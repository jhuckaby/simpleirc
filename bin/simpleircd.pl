#!/usr/bin/perl

##
# IRCSimple v1.0
# A simple IRC server implementation with built-in NickServ and ChanServ
# Copyright (c) 2013 Joseph Huckaby and EffectSoftware.com
# Released under the MIT License.
##

use strict;
use warnings;
use File::Basename;
use Cwd qw/abs_path/;
use HTTP::Date;
use URI::Escape;
use Scalar::Util qw/reftype/;
use Carp ();
use Data::Dumper;
use POSIX qw/:sys_wait_h setsid/;

use POE;
use POE::Component::Server::TCP;
use POE::Filter::HTTPD;
use POE::Component::Server::IRC;
use POE::Component::IRC;
use POE::Component::Server::IRC::Plugin::OperServ;
 
our $GOT_SSL;

BEGIN {
	push @INC, dirname(dirname(abs_path($0))) . "/lib";
	eval {
		require POE::Component::SSLify;
		import POE::Component::SSLify qw( Server_SSLify SSLify_Options Client_SSLify );
		$GOT_SSL = 1;
	};
	if ($@) { die $@; }
}

use Tools;
use Simple;
use VersionInfo;

$| = 1;

$SIG{'__DIE__'} = sub { Carp::cluck("Stack Trace: "); };

my $args = new Args( @ARGV );

my $base_dir = dirname(dirname(abs_path($0)));
chdir( $base_dir );

my $config = eval { json_parse(load_file('conf/config-defaults.json')); };
if (!$config) { die "Failed to parse config-defaults.json: $@\n"; }

# merge in web config
if (-e 'conf/config-web.json') {
	my $temp_config = eval { json_parse(load_file('conf/config-web.json')); };
	if (!$temp_config) { die "Failed to parse config-web.json: $@\n"; }
	merge_hashes( $config, $temp_config, 1 );
}

# merge in user config
if (-e 'conf/config.json') {
	my $temp_config = eval { json_parse(load_file('conf/config.json')); };
	if (!$temp_config) { die "Failed to parse config.json: $@\n"; }
	merge_hashes( $config, $temp_config, 1 );
}

# remove "comments" from json
remove_key_recursive( $config, '//' );

# check for command-line debug mode
if ($args->{debug}) {
	$config->{Logging}->{EchoToConsole} = 1;
}
else {
	# otherwise become daemon
	become_daemon();
	
	# write pid file
	save_file( 'logs/pid.txt', $$ );
	
	# cleanup after upgrade
	unlink('logs/upgrade.lock');
}

# create main engine object
my $resident = Simple->new( config => $config );

# capture warn calls to redirect to log file (and for capturing raw irc network bytes)
$SIG{'__WARN__'} = sub {
	my ($package_name, undef, undef) = caller();
	$resident->warn_handler( $package_name, $_[0] );
};

# if ssl is enabled, make sure cert files are present
if ($config->{SSL}->{Enabled}) {
	if (!(-e $config->{SSL}->{CertFile})) { die "SSL: Cannot locate certificate file: " . $config->{SSL}->{CertFile} . "\n"; }
	if (!(-e $config->{SSL}->{KeyFile})) { die "SSL: Cannot locate certificate key file: " . $config->{SSL}->{KeyFile} . "\n"; }
	if (!$GOT_SSL) { die "SSL: Could not be initialized, POE::Component::SSLify did not load properly.\n"; }
}

# get our version info
my $version = get_version();
$resident->log_debug(1, 'SimpleIRC v' . $version->{Major} . '-' . $version->{Minor} . ' (' . $version->{Branch} . ') starting up');

# construct IRC daemon object
my $pocosi = POE::Component::Server::IRC::Simple->spawn(
	resident => $resident,
	config => {
		servername => $config->{ServerName}, 
		serverdesc => $config->{ServerDesc},
		nicklen	=> $config->{MaxNickLength},
		network	=> $config->{ServerName},
		version	=> 'SimpleIRC v' . $version->{Major} . '-' . $version->{Minor} . ' (' . $version->{Branch} . ')',
		admin => [ split(/\n/, trim(load_file('conf/admin.txt'))) ],
		info => [ split(/\n/, trim(load_file('conf/info.txt'))) ],
		motd => [ split(/\n/, trim(load_file('conf/motd.txt'))) ],
		whoisactually => 0, # only ops can see true ips
		maskips => $config->{MaskIPs}->{Enabled}, # custom config param
		ipsecretkey => $config->{SecretKey} # custom config param
	},
	sslify_options => $config->{SSL}->{Enabled} ? [$config->{SSL}->{KeyFile}, $config->{SSL}->{CertFile}] : 0,
	auth		  => 0,
	# antiflood	 => 0,
	# plugin_debug   => 1
	debug => 1 # REQUIRED for capturing raw IRC input/output (for calculating bandwidth)
);
$resident->{ircd} = $pocosi;
$pocosi->{resident} = $resident;

# Web server
if ($config->{WebServer}->{Enabled}) {
	my $extra_opts = {};
	if ($config->{WebServer}->{SSL}) {
		# Set the key + certificate file
		eval { SSLify_Options( $config->{SSL}->{KeyFile}, $config->{SSL}->{CertFile} ) };
		if ( $@ ) { die "SSLify: $@"; }
		
		$extra_opts->{ClientPreConnect} = sub {
			# SSLify the socket, which is in $_[ARG0].
			my $socket = eval { Server_SSLify($_[ARG0]) };
			return undef if $@;

			# Return the SSL-ified socket.
			return $socket;
		};
	}
	
	$resident->log_debug(3, "Opening HTTP".($config->{WebServer}->{SSL} ? 'S (SSL)' : '')." socket listener on port " . $config->{WebServer}->{Port});
	
	POE::Component::Server::TCP->new(
		Alias => "httpd",
		Port => $config->{WebServer}->{Port},
		ClientFilter => 'POE::Filter::HTTPD',
		
		ClientInput => sub {
			my ($kernel, $heap, $request) = @_[KERNEL, HEAP, ARG0];
			
			if ($request->isa("HTTP::Response")) {
				# request parse error
				$heap->{client}->put($request);
				$kernel->yield("shutdown");
				return;
			}
			
			my $response = HTTP::Response->new(200);
			$response->header( Connection => 'close' );
			$response->header( Server => 'SimpleIRC Web v' . $version->{Major} . '-' . $version->{Minor} . ' (' . $version->{Branch} . ')' );
			$response->header( Date => time2str( time() ) );
			
			$resident->handle_web_request(
				request => $request, 
				response => $response,
				ip => $heap->{remote_ip},
				client => $heap->{client},
				heap => $heap
			);
			
			$heap->{client}->put($response);
			$kernel->yield("shutdown");
		},
		
		%$extra_opts
	);
	
	if ($config->{WebServer}->{RedirectNonSSLPort}) {
		$resident->log_debug(3, "Opening HTTP socket listener for non-SSL redirects on port " . $config->{WebServer}->{RedirectNonSSLPort});
		
		POE::Component::Server::TCP->new(
			Alias => "httpd_nonssl_redirect",
			Port => $config->{WebServer}->{RedirectNonSSLPort},
			ClientFilter => 'POE::Filter::HTTPD',
			ClientInput => sub {
				my ($kernel, $heap, $request) = @_[KERNEL, HEAP, ARG0];
				
				if ($request->isa("HTTP::Response")) {
					# request parse error
					$heap->{client}->put($request);
					$kernel->yield("shutdown");
					return;
				}
				
				my $redirect_url = 'https://' . $request->header('Host');
				$redirect_url =~ s/\:\d+$//;
				if ($config->{WebServer}->{Port} != 443) { $redirect_url .= ':' . $config->{WebServer}->{Port}; }
				$redirect_url .= $request->uri();
				
				$resident->log_debug(7, "Caught non-SSL request, redirecting to: $redirect_url");
				
				my $response = HTTP::Response->new(302);
				$response->header( Connection => 'close' );
				$response->header( Server => 'SimpleIRCWeb v1.0' );
				$response->header( Location => $redirect_url );
				$heap->{client}->put($response);
				$kernel->yield("shutdown");
			}
		);
	}
} # httpd enabled

POE::Session->create(
	package_states => [
		'main' => [qw(_start _default _stop)],
	],
	heap => { ircd => $pocosi },
	object_states => [
		$pocosi => {
			tick => "tick_state"
		}
	],
	inline_states => {
		got_sig_int => \&listener_got_sig_int,
		got_sig_term => \&listener_got_sig_term
	}
);

# block until exit
$poe_kernel->run();

$SIG{'__DIE__'} = undef;

# exiting
unlink('logs/pid.txt');
$resident->log_debug(1, "Exiting");

exit();

sub become_daemon {
	##
	# Fork daemon process and disassociate from terminal
	##
	my $pid = fork();
	if (!defined($pid)) { die "Error: Cannot fork daemon process: $!\n"; }
	if ($pid) { exit(0); }
	
	setsid();
	open( STDIN, "</dev/null" );
	open( STDOUT, ">/dev/null" );
	umask( 0 );
	
	return $$;
}

sub _start {
	my ($kernel, $heap) = @_[KERNEL, HEAP];
	
	$resident->log_debug(1, "IRC server starting up");
	
	$kernel->sig(INT => "got_sig_int");
	$kernel->sig(TERM => "got_sig_term");
	
	$heap->{ircd}->yield('register', 'all');
	
	# init engine
	$resident->init( $heap->{ircd} );
		
	# Anyone connecting from the loopback gets spoofed hostname
	#$heap->{ircd}->add_auth(
	#	mask	=> '*@*',
	#	spoof	=> 'm33p.com',
	#	no_tilde => 1,
	#);

	# We have to add an auth as we have specified one above.
	# $heap->{ircd}->add_auth(mask => '*@*');

	# Start a listener on the 'standard' IRC port.
	if ($config->{Port}) {
		$resident->log_debug(3, "Opening IRC socket listener on port " . $config->{Port});
		$heap->{ircd}->add_listener( port => $config->{Port} ); # standard port
	}
	
	if ($config->{SSL}->{Enabled}) {
		$resident->log_debug(3, "Activating IRC SSL on port " . $config->{SSL}->{Port});
		$heap->{ircd}->add_listener( port => $config->{SSL}->{Port}, usessl => 1 ); # for ssl
	}
	
	if ($config->{BotAccess}->{Enabled}) {
		$resident->log_debug(3, "Activating IRC bot access on port " . $config->{BotAccess}->{Port});
		$heap->{ircd}->add_listener(
			port => $config->{BotAccess}->{Port}, 
			bindaddr => $config->{BotAccess}->{IP}, 
			antiflood => 0
		); # for bots only
	}
	
	$resident->log_debug(3, "Initializing OperServ bot");
	$heap->{ircd}->plugin_add(
		'OperServ',
		POE::Component::Server::IRC::Plugin::OperServ->new(),
	);
	
	# load all enabled plugins
	foreach my $plugin_name (keys %{$config->{Plugins}}) {
		my $plugin_config = $config->{Plugins}->{$plugin_name};
		if ($plugin_config->{Enabled}) {
			$resident->log_debug(3, "Loading Plugin: $plugin_name");
			eval "use Plugins::$plugin_name;";
			if ($@) {
				die "Failed to load Plugin: $plugin_name: $@\n";
			}
			my $class_name = "POE::Component::Server::IRC::Plugin::$plugin_name";
			$heap->{ircd}->plugin_add(
				$plugin_name,
				$class_name->new( config => $plugin_config, resident => $resident ),
			);
		} # plugin is enabled
	} # foreach plugin
	
	# start tick heartbeat
	$resident->log_debug(3, "Scheduling heartbeat");
	$heap->{ircd}->schedule_tick(1);
	
	# restore server bans
	if ($resident->{data}->{Bans} && @{$resident->{data}->{Bans}}) {
		$heap->{ircd}->{state}{klines} ||= [];
		
		foreach my $ban (@{$resident->{data}->{Bans}}) {
			$resident->log_debug(4, "Restoring server-wide ban: " . $ban->{TargetUser} . '@' . $ban->{TargetIP});
			
			push @{ $heap->{ircd}->{state}{klines} }, {
				setby	=> $ban->{AddedBy},
				setat	=> $ban->{Created},
				target   => $config->{ServerName},
				duration => 0,
				user	 => $ban->{TargetUser},
				host	 => $ban->{TargetIP},
				reason   => $ban->{Reason} || '',
			};
		} # foreach ban
	} # bans
 }

sub _default {
	# default catch-all for events
	# log transactions as necessary, and manage klines
	my ($kernel, $heap, $event, $args) = @_[KERNEL, HEAP, ARG0 .. $#_];
	# local $Data::Dumper::Maxdepth = 1;
	# local $Data::Dumper::Indent = 0;
	
	# Event: ircd_daemon_privmsg: jhuckabynick!~jhuckabyuser@c9ed02581a4ce137, NickServ, IDENTIFY 12345
	if ($config->{Logging}->{LogPrivateMessages} || ($event ne 'ircd_daemon_privmsg')) {
		$resident->log_debug(9, "Event: $event: " . join(', ', @$args));
	}
	
	# $VAR1 = ['testnick',1,1365391392,'+i','~testuser','c9ed02581a4ce137','sample.irc.local','testuser'];
	if ($event eq 'ircd_daemon_nick') {
		if (@$args == 2) {
			# nick change
			my $old_nick = (split /!/, $args->[0])[0];
			my $new_nick = $args->[1];
			
			my $route_id = $heap->{ircd}->_state_user_route($new_nick);
			if ($route_id ne 'spoofed') {
				my $record = $heap->{ircd}->{state}{conns}{$route_id};
				
				$resident->log_event(
					log => 'transcript',
					package => $record->{socket}[0],
					level => $record->{auth}{hostname},
					msg => "(Nick Change: $old_nick --> $new_nick)"
				);
			} # not spoofed
		}
		else {
			# login
			my $nick = $args->[0];
			
			my $route_id = $heap->{ircd}->_state_user_route($nick);
			if ($route_id ne 'spoofed') {
				my $record = $heap->{ircd}->{state}{conns}{$route_id};
				
				$resident->log_event(
					log => 'transcript',
					package => $record->{socket}[0],
					level => $record->{auth}{hostname},
					msg => "NICK $nick"
				);
			} # not spoofed
		} # nick login
	} # ircd_daemon_nick
	elsif ($event eq 'ircd_daemon_quit') {
		my $nick = (split /!/, $args->[0])[0];
		my $masked_ip = (split /\@/, $args->[0])[1];
		
		$resident->log_event(
			log => 'transcript',
			package => $masked_ip,
			level => $nick,
			msg => "(Client disconnected)"
		);
	}
	elsif ($event eq 'ircd_daemon_kline') {
		# add server-wide ban
		# $VAR1 = ['jhuckabynick!~jhuckabyuser@c9ed02581a4ce137','sample.irc.local',0,'~testuser','*','JoeFuck'];
		my $nick = (split /!/, $args->[0])[0];
		# my $masked_ip = (split /\@/, $args->[0])[1];
		my $user_mask = $args->[3];
		my $ip_mask = $args->[4];
		my $reason = $args->[5];
		my $now = time();
		
		$resident->{data}->{Bans} ||= [];
		
		if (!find_object($resident->{data}->{Bans}, { TargetUser => $user_mask, TargetIP => $ip_mask })) {
			$resident->log_debug(3, "Adding server wide ban: $user_mask\@$ip_mask");
			push @{$resident->{data}->{Bans}}, {
				TargetUser => $user_mask,
				TargetIP => $ip_mask,
				AddedBy => $args->[0],
				Reason => $reason,
				Created => $now,
				Expires => $now + (86400 * $resident->{config}->{ServerBanDays})
			};
			$resident->save_data();
			
			$heap->{ircd}->_send_output_to_client( $heap->{ircd}->_state_user_route($nick), {
				prefix  => 'Server', command => 'NOTICE',
				params  => [ $nick, "Added new server-wide ban for: $user_mask\@$ip_mask" ]
			});
		}
		else {
			$resident->log_debug(3, "Server ban already exists: $user_mask\@$ip_mask");
			
			$heap->{ircd}->_send_output_to_client( $heap->{ircd}->_state_user_route($nick), {
				prefix  => 'Server', command => 'NOTICE',
				params  => [ $nick, "Error: Server-wide ban already exists for: $user_mask\@$ip_mask" ]
			});
		}
	} # kline
	elsif ($event eq 'ircd_daemon_unkline') {
		# jhuckabynick!~jhuckabyuser@c9ed02581a4ce137, sample.irc.local, *, 1.2.3.4
		my $nick = (split /!/, $args->[0])[0];
		my $user_mask = $args->[2];
		my $ip_mask = $args->[3];
		
		$resident->{data}->{Bans} ||= [];
		
		if (delete_object($resident->{data}->{Bans}, { TargetUser => $user_mask, TargetIP => $ip_mask })) {
			$resident->log_debug(3, "Removing server wide ban: $user_mask\@$ip_mask");
			$resident->save_data();
			
			$heap->{ircd}->_send_output_to_client( $heap->{ircd}->_state_user_route($nick), {
				prefix  => 'Server', command => 'NOTICE',
				params  => [ $nick, "Removed server-wide ban for: $user_mask\@$ip_mask" ]
			});
		}
		else {
			$resident->log_debug(3, "Server ban not found: $user_mask\@$ip_mask");
			
			$heap->{ircd}->_send_output_to_client( $heap->{ircd}->_state_user_route($nick), {
				prefix  => 'Server', command => 'NOTICE',
				params  => [ $nick, "Error: Server-wide ban not found: $user_mask\@$ip_mask" ]
			});
		}
	} # unkline
}

sub _stop {
	my ($kernel, $heap) = @_[KERNEL, HEAP];
	$resident->shutdown();
}

sub listener_got_sig_int {
	$resident->log_debug(2, "Received SIGINT");
	# delete $_[HEAP]->{ircd};
	# $_[KERNEL]->sig_handled();
}

sub listener_got_sig_term {
	$resident->log_debug(2, "Received SIGTERM");
	# delete $_[HEAP]->{ircd};
	# $_[KERNEL]->sig_handled();
}

1;

##
# Subclass POE::Component::Server::IRC so we can customize behavior
##

package POE::Component::Server::IRC::Simple;

use strict;
use Digest::MD5 qw/md5_hex/;
use Data::Dumper;
use POE;
use POE::Component::Server::IRC;
use POE::Component::Server::IRC::Common qw(chkpasswd);
use POE::Component::Server::IRC::Plugin qw(:ALL);
use base qw( POE::Component::Server::IRC );

use Tools;
use VersionInfo;

sub _state_register_client {
	# overriding POE::Component::Server::IRC::_state_register_client
	# so we can mask user IPs properly
	my $self	= shift;
	my $conn_id = shift || return;
	return if !$self->_connection_exists($conn_id);

	my $record = $self->{state}{conns}{$conn_id};
	
	if (!$record->{auth}{hostname}) {
		if ($self->server_config('maskips') eq 1) {
			$record->{auth}{hostname} = $self->mask_ip_address($record->{socket}[0], 16);
		}
		else {
			$record->{auth}{hostname} = $record->{socket}[0];
		}
	}
	
	$self->{resident}->log_event(
		log => 'transcript',
		package => $record->{socket}[0],
		level => $record->{auth}{hostname},
		msg => "(New client connection)"
	);
	
	# invoke parent function
	return POE::Component::Server::IRC::_state_register_client($self, $conn_id, @_);
}

sub mask_ip_address {
	my ($self, $octet, $len) = @_;
	return substr( md5_hex($octet . $self->server_config('ipsecretkey')), 0, $len );
}

sub tick_state {
	my ($self, $kernel, $heap) = @_[OBJECT, KERNEL, HEAP];
	my $delay = $self->tick();
	$self->schedule_tick($delay) if $delay;
	return;
}

sub schedule_tick {
	my $self = shift;
	my $time = shift || 5;
	$poe_kernel->delay('tick', $time);
	return;
}

sub tick {
	# called every second
	my $self = shift;
	# print "in tick()\n";
	
	# pass tick to engine
	$self->{resident}->tick();
	
	# pass tick along to all plugins (i.e. NickServ)
	my $plugins = $self->plugin_list();
	foreach my $plugin_name (keys %$plugins) {
		my $plugin = $plugins->{$plugin_name};
		if ($plugin->can('tick')) { $plugin->tick(); }
	}
	
	# daily maintenance check
	my $day_code = yyyy_mm_dd();
	if (!$self->{resident}->{data}->{LastMaint} || ($day_code ne $self->{resident}->{data}->{LastMaint})) {
		$self->run_daily_maintenance();
		
		$self->{resident}->{data}->{LastMaint} = $day_code;
		$self->{resident}->save_data();
	}
	
	# check for restart / stop
	if ($self->{resident}->{ctl_cmd_at_next_tick}) {
		my $cmd = $self->{resident}->{ctl_cmd_at_next_tick};
		delete $self->{resident}->{ctl_cmd_at_next_tick};
		
		if ($cmd =~ /^upgrade(.*)$/) {
			# upgrade
			my $current_version = get_version();
			my $branch = trim($1 || '') || $current_version->{Branch};
			
			# make sure branch exists
			my $version_url = "http://effectsoftware.com/software/simpleirc/version-$branch.json";
			my $resp = wget( $version_url );
			if (!$resp->is_success()) {
				$self->{resdident}->log_debug(1, "Could not fetch version information file for branch: $branch: $version_url");
				return 1;
			}
			
			# make sure only one upgrade is happening at a time
			my $upgrade_lock_file = 'logs/upgrade.lock';
			if (-e $upgrade_lock_file) {
				$self->{resident}->log_debug(1, "ERROR: An upgrade operation is already in progress."); 
				return 1;
			}
			touch($upgrade_lock_file);
			
			my $shell_cmd = "install/bkgnd-upgrade.pl $branch >/dev/null 2>&1 &";
			$self->{resident}->log_debug(1, "Executing upgrade script now: $shell_cmd");
			`$shell_cmd`;
		} # upgrade
		else {
			# restart / stop
			my $shell_cmd = "bin/bkgnd-cmd.pl $cmd >/dev/null 2>&1 &";
			$self->{resident}->log_debug(1, "Executing $cmd script now: $shell_cmd");
			`$shell_cmd`;
		}
	}
	
	return 1;
}

sub run_daily_maintenance {
	# expire old nicks, remove expired bans, reset daily stats, etc.
	my $self = shift;
	my $now = time();
	
	$self->{resident}->log_maint("Starting daily maintenance run");
	
	# pass maint event along to all plugins (i.e. NickServ)
	my $plugins = $self->plugin_list();
	foreach my $plugin_name (keys %$plugins) {
		my $plugin = $plugins->{$plugin_name};
		if ($plugin->can('run_daily_maintenance')) { $plugin->run_daily_maintenance(); }
	}
	
	# remove expired server bans
	my $data = $self->{resident}->get_data();
	if ($data->{Bans} && ref($data->{Bans})) {
		$self->{resident}->log_maint("Checking server bans for expiration");
		
		# check each ban to see if it has expired
		foreach my $ban (@{$data->{Bans}}) {
			if ($ban->{Expires} <= $now) {
				$self->{resident}->log_maint("Removing expired server ban: " . $ban->{TargetUser} . '@' . $ban->{TargetIP});
				delete_object( $data->{Bans}, {
					TargetUser => $ban->{TargetUser},
					TargetIP => $ban->{TargetIP}
				} );
				delete_object( $self->{ircd}->{state}{klines}, {
					user => $ban->{TargetUser},
					host => $ban->{TargetIP}
				} );
			} # expired ban
		} # foreach ban
		
		# Note: data is auto-saved at end of daily maint run
		
	} # has bans
	
	# rotate logs into daily gzip archives
	$self->{resident}->log_maint("Rotating logs");
	$self->{resident}->rotate_logs();
	
	# maintain web sessions (discard old ones)
	$self->{resident}->web_session_maint();
	
	# reset byte counts and messages
	$self->{total_bytes_in} = 0;
	$self->{total_bytes_out} = 0;
	$self->{total_messages_sent} = 0;
	
	$self->{resident}->log_maint("Daily maintenance complete");
}

sub _state_o_line {
	# overriding POE::Component::Server::IRC::_state_o_line
	# return true if user is an oper (server admin), false otherwise
	my $self = shift;
	my $nick = shift || return;
	my ($username, $password) = @_;
	
	return $self->{resident}->is_admin($nick) ? 1 : 0;
}

sub _daemon_cmd_names {
	# overriding POE::Component::Server::IRC::_daemon_cmd_names
	# ugly hack to hide ChanServ from cilent user lists
	my $self = shift;
	my $ref = POE::Component::Server::IRC::_daemon_cmd_names($self, @_);
		
	if ($self->{resident}->{config}->{Plugins}->{ChanServ}->{Hide}) {
		$ref->[0]->{params}->[3] = join(' ', grep { $_ !~ /^\@ChanServ$/; } split(/\s+/, $ref->[0]->{params}->[3]));
	}
		
	return @$ref if wantarray;
	return $ref;
}

sub _daemon_cmd_who {
	# overriding POE::Component::Server::IRC::_daemon_cmd_who
	# ugly hack to hide ChanServ from cilent user lists
	my $self = shift;
	my $ref = POE::Component::Server::IRC::_daemon_cmd_who($self, @_);
		
	if ($self->{resident}->{config}->{Plugins}->{ChanServ}->{Hide}) {
		my $new_ref = [];
		foreach my $elem (@$ref) {
			if (!ref($elem) || !$elem->{params} || !ref($elem->{params}) || !$elem->{params}->[2] || ($elem->{params}->[2] ne 'ChanServ')) {
				push @$new_ref, $elem;
			}
		}
		$ref = $new_ref;
	}
		
	return @$ref if wantarray;
	return $ref;
}

sub _daemon_cmd_topic {
	# overriding POE::Component::Server::IRC::_daemon_cmd_topic
	# ugly hack to fix format of '333' command for apps like KiwiIRC
	# Adding 'FIX' param to force it to become the "trailing" text (after the colon)
	# and the actual epoch date to come before it, like this:
	#   :sample.irc.local 333 jhuckabynick #myroom ChanServ!ChanServ@sample.irc.local 1374122157 :FIX
    my $self   = shift;
    my $nick   = shift || return;
    my $server = $self->server_name();
    my $ref    = [ ];
    my $args   = [@_];
    my $count  = @$args;

    SWITCH:{
        if (!$count) {
            push @$ref, ['461', 'TOPIC'];
            last SWITCH;
        }
        if (!$self->state_chan_exists($args->[0])) {
            push @$ref, ['403', $args->[0]];
            last SWITCH;
        }
        if ($self->state_chan_mode_set($args->[0], 's')
            && !$self->state_is_chan_member($nick, $args->[0])) {
            push @$ref, ['442', $args->[0]];
            last SWITCH;
        }
        my $chan_name = $self->_state_chan_name($args->[0]);
        if ($count == 1
                and my $topic = $self->state_chan_topic($args->[0])) {
            push @$ref, {
                prefix  => $server,
                command => '332',
                params  => [$nick, $chan_name, $topic->[0]],
            };
            push @$ref, {
                prefix  => $server,
                command => '333',
                params  => [$nick, $chan_name, @{ $topic }[1..2], "FIX"], # ADDED 'FIX' HERE
            };
            last SWITCH;
        }
        if ($count == 1) {
            push @$ref, {
                prefix  => $server,
                command => '331',
                params  => [$nick, $chan_name, 'No topic is set'],
            };
            last SWITCH;
        }
        if (!$self->state_is_chan_member($nick, $args->[0])) {
            push @$ref, ['442', $args->[0]];
            last SWITCH;
        }
        if ($self->state_chan_mode_set($args->[0], 't')
        && !$self->state_is_chan_op($nick, $args->[0])) {
            push @$ref, ['482', $args->[0]];
            last SWITCH;
        }
        my $record = $self->{state}{chans}{uc_irc($args->[0])};
        my $topic_length = $self->server_config('TOPICLEN');
        if (length $args->[0] > $topic_length) {
            $args->[1] = substr $args->[0], 0, $topic_length;
        }
        if ($args->[1] eq '') {
            delete $record->{topic};
        }
        else {
            $record->{topic} = [
                $args->[1],
                $self->state_user_full($nick),
                time,
            ];
        }
        $self->_send_output_to_channel(
            $args->[0],
            {
                prefix  => $self->state_user_full($nick),
                command => 'TOPIC',
                params  => [$chan_name, $args->[1]],
            },
        );
    }

    return @$ref if wantarray;
    return $ref;
}

sub _daemon_cmd_help {
	# custom command, returns generic help text to user
	my $ircd = shift;
	my $nick = shift;
	my $value = join(' ', @_);
	
	my $help_content = '';
	my $help_file = "conf/help/general.txt";
	if (-e $help_file) { $help_content = load_file($help_file); }
	else { $help_content = "Sorry, there is no help available for the IRC server."; }
	
	foreach my $line (split(/\n/, $help_content)) {
		if ($line =~ /\S/) {
			my $route_id = $ircd->_state_user_route($nick);
			if (!$route_id) { return; }
							
			$ircd->_send_output_to_client( $route_id, {
				prefix  => 'Server',
				command => 'NOTICE',
				params  => [ $nick, $line ]
			});
		} # line has non-whitespace
	} # foreach help line
	
	return () if wantarray;
	return [];
};

sub _daemon_cmd_restart {
	# custom command, restarts whole server (admin only)
	my $ircd = shift;
	my $nick = shift;
	my $custom_msg = join(' ', @_);
	
	if ($ircd->{resident}->is_admin($nick)) {
		$ircd->{resident}->log_debug(1, "Server restart initiated by $nick");
		
		$ircd->{resident}->log_event(
			log => 'transcript',
			package => $ircd->_state_user_ip($nick) || '',
			level => $nick,
			msg => "(Server restart)"
		);
		
		$ircd->_daemon_cmd_broadcast( $nick, "Server is being restarted.  Please try to reconnect in a few moments.  $custom_msg" );
		
		$ircd->{resident}->{ctl_cmd_at_next_tick} = 'restart';
	}
	
	return () if wantarray;
	return [];
}

sub _daemon_cmd_shutdown {
	# custom command, stops whole server (admin only)
	my $ircd = shift;
	my $nick = shift;
	my $custom_msg = join(' ', @_);
	
	if ($ircd->{resident}->is_admin($nick)) {
		$ircd->{resident}->log_debug(1, "Server shutdown initiated by $nick");
		
		$ircd->{resident}->log_event(
			log => 'transcript',
			package => $ircd->_state_user_ip($nick) || '',
			level => $nick,
			msg => "(Server shutdown)"
		);
		
		$ircd->_daemon_cmd_broadcast( $nick, "Server is being shut down immediately.  You will be disconnected.  $custom_msg" );
		
		$ircd->{resident}->{ctl_cmd_at_next_tick} = 'stop';
	}
	
	return () if wantarray;
	return [];
}

sub _daemon_cmd_upgrade {
	# custom command, upgrades whole server (admin only)
	my $ircd = shift;
	my $nick = shift;
	my $branch = join(' ', @_);
	
	if ($ircd->{resident}->is_admin($nick)) {
		$ircd->{resident}->log_debug(1, "Server upgrade initiated by $nick");
		
		$ircd->{resident}->log_event(
			log => 'transcript',
			package => $ircd->_state_user_ip($nick) || '',
			level => $nick,
			msg => "(Server upgrade)"
		);
		
		$ircd->_daemon_cmd_broadcast( $nick, "Server is being shut down immediately for upgrade.  Please try to reconnect in a few minutes." );
		
		$ircd->{resident}->{ctl_cmd_at_next_tick} = "upgrade $branch";
	}
	
	return () if wantarray;
	return [];
}

sub _daemon_cmd_reloadconfig {
	# custom command, reloads configuration live (admin only)
	my $ircd = shift;
	my $nick = shift;
	
	if ($ircd->{resident}->is_admin($nick)) {
		$ircd->{resident}->log_debug(1, "Server config reload initiated by $nick");
				
		eval { $ircd->{resident}->reload_config(); };
		my $msg = '';
		if ($@) {
			$msg = "ERROR: Failed to reload configuration: $@";
		}
		else {
			$msg = "Server configuration reloaded successfully.";
			
			$ircd->{resident}->log_event(
				log => 'transcript',
				package => $ircd->_state_user_ip($nick) || '',
				level => $nick,
				msg => "(Server config reloaded)"
			);
		}
		
		my $route_id = $ircd->_state_user_route($nick);
		if ($route_id) {
			$ircd->_send_output_to_client( $route_id, {
				prefix  => 'Server',
				command => 'NOTICE',
				params  => [ $nick, $msg ]
			});
		}
	}
	
	return () if wantarray;
	return [];
}

sub _daemon_cmd_broadcast {
	# custom command, broadcast notice to all channels (admin only)
	my $ircd = shift;
	my $nick = shift;
	my $custom_msg = join(' ', @_);
	
	if ($ircd->{resident}->is_admin($nick) && ($custom_msg =~ /\S/)) {
		$ircd->{resident}->log_event(
			log => 'transcript',
			package => $ircd->_state_user_ip($nick) || '',
			level => $nick,
			msg => "(Broadcast message: $custom_msg)"
		);
		
		foreach my $chan (@{$ircd->{resident}->get_all_channel_ids()}) {
			$chan = nch($chan);
			$ircd->_send_output_to_channel( $chan, { 
				prefix => 'Server', 
				command => 'NOTICE', 
				params => [$chan, trim($custom_msg)] 
			} );
		}
	}
	
	return () if wantarray;
	return [];
}

sub _daemon_cmd_userinfo {
	# custom command, outputs detailed information about a user
	my $ircd = shift;
	my $nick = shift;
	my $is_admin = $ircd->{resident}->is_admin($nick);
	my $target_nick = lc(join('', @_));
	my $lines = [];
	
	push @$lines, "Information for user: $target_nick";
	
	my $full = $ircd->state_user_full($target_nick);
	if ($full) { push @$lines, "Identification: $full"; }
	
	if ($is_admin) {
		my $ip = $ircd->_state_user_ip($target_nick);
		if ($ip) { push @$lines, "Real IP: $ip"; }
	}
	
	my $user = $ircd->{resident}->get_user($target_nick);
	
	if ($user && $user->{Registered}) {
		if ($is_admin) { push @$lines, "User '$target_nick' is registered to: " . $user->{FullName} . " <" . $user->{Email} . ">"; }
		else { push @$lines, "User '$target_nick' is registered."; }
		
		# identified
		if ($user->{_identified}) { push @$lines, "User is currently logged in."; }
		else { push @$lines, "User is not logged in."; }
		
		# created, modified
		push @$lines, "Account created on " . yyyy_mm_dd($user->{Created}) . ", last modified on " . yyyy_mm_dd($user->{Modified}) . ".";
		
		# all channel modes
		my $chan_info = [];
		foreach my $chan (@{$ircd->{resident}->get_all_channel_ids()}) {
			my $channel = $ircd->{resident}->get_channel($chan);
			if ($channel->{Users}->{$target_nick}) {
				my $info = '#' . $chan;
				my $flags = $channel->{Users}->{$target_nick}->{Flags} || '';
				if ($channel->{Founder} eq $target_nick) { $flags .= 'f'; }
				if ($flags) {
					$info .= ' (+' . $flags . ')';
				}
				push @$chan_info, $info;
			}
		} # foreach channel
		push @$lines, "Channels: " . (join(', ', @$chan_info) || '(None)');
		
		# last seen
		if ($user->{LastCmd}) {
			my $nice_date_time = scalar localtime $user->{LastCmd}->{When};
			my $seen = "Last Seen: " . $nice_date_time;
			if ($user->{LastCmd}->{Raw} =~ /^PRIVMSG\s+(\#\w+)/) { $seen .= ' in ' . $1; }
			push @$lines, $seen;
			
			if ($is_admin) { push @$lines, 'Last Command: ' . $user->{LastCmd}->{Raw}; }
		}
		
		# channel bans
		my $ban_info = [];
		foreach my $chan (@{$ircd->{resident}->get_all_channel_ids()}) {
			if ($ircd->_state_user_banned($target_nick, nch($chan))) {
				push @$ban_info, nch($chan);
			}
		} # foreach channel
		if (scalar @$ban_info) {
			push @$lines, "User is banned from: " . join(', ', @$ban_info);
		}
		
	} # nick is reg
	else {
		push @$lines, "User '$target_nick' is not registered.";
	}
	
	# send output to user
	foreach my $line (@$lines) {
		if ($line =~ /\S/) {
			my $route_id = $ircd->_state_user_route($nick);
			if (!$route_id) { return; }
							
			$ircd->_send_output_to_client( $route_id, {
				prefix  => 'Server',
				command => 'NOTICE',
				params  => [ $nick, $line ]
			});
		} # line has non-whitespace
	} # foreach line
	
	return () if wantarray;
	return [];
};

sub _daemon_cmd_register {
	# custom command, shortcut for:
	#	/msg nickserv register PASSWORD EMAIL
	#	/msg chanserv register CHANNEL
	my $ircd = shift;
	my $nick = shift;
	my $msg = 'REGISTER ' . join(' ', @_);
	
	if ($msg =~ /^register\s+([\'\"])([^\1]+)(\1)\s+(\S+)$/i) {
		# ($password, $email) = ($2, $4);
		# nickserv format A
		my $nickserv = $ircd->plugin_get( 'NickServ' );
		$nickserv->IRCD_daemon_privmsg( $ircd, \$nick, \"NickServ", \$msg, [] );
	}
	elsif ($msg =~ /^register\s+(\S+)\s+(\S+)$/i) {
		# ($password, $email) = ($1, $2);
		# nickserv format B
		my $nickserv = $ircd->plugin_get( 'NickServ' );
		$nickserv->IRCD_daemon_privmsg( $ircd, \$nick, \"NickServ", \$msg, [] );
	}
	elsif ($msg =~ /^register\s+\#(\S+)$/i) {
		# chanserv
		my $chanserv = $ircd->plugin_get( 'ChanServ' );
		$chanserv->IRCD_daemon_privmsg( $ircd, \$nick, \"ChanServ", \$msg, [] );
	}
	
	return () if wantarray;
	return [];
}

sub _state_user_invited {
	# overriding POE::Component::Server::IRC::_state_user_invited
	# so we can deal with 'private' channels
	my $self = shift;
	my $nick = shift || return;
	my $chan = shift || return;
	
	my $user = $self->{resident}->get_user($nick, 0) || {};
	my $channel = $self->{resident}->get_channel( $chan );
	
	if ($channel->{Private} && $channel->{Users}->{lc($nick)} && $user->{Registered} && $user->{_identified}) {
		# perma-invite for members
		return 1; 
	}
	if ($channel->{Private} && ($channel->{Founder} eq lc($nick)) && $user->{Registered} && $user->{_identified}) {
		# perma-invite for founder
		return 1; 
	}
	if ($channel->{Private} && $user->{Administrator} && $user->{Registered} && $user->{_identified}) {
		# perma-invite for admins
		return 1; 
	}
	
	return POE::Component::Server::IRC::_state_user_invited($self, $nick, $chan);
}

sub _cmd_from_client {
	# overriding POE::Component::Server::IRC::_cmd_from_client
	# so we can log everything, and for plugins to hook it
	my ($self, $wheel_id, $input) = @_;
	my $result = POE::Component::Server::IRC::_cmd_from_client(@_);
	
	if ($input->{raw_line}) {
		my $nick = $self->_client_nickname($wheel_id);
		
		if ($input->{command} ne 'PING') {
			
			if ($self->{resident}->{config}->{Logging}->{LogPrivateMessages} || ($input->{raw_line} !~ /^(PRIVMSG|NS|CS|IDENTIFY|REGISTER)\s+\w+/)) {
				my $record = $self->{state}{conns}{$wheel_id};
				$self->{resident}->log_event(
					log => 'transcript',
					package => ($record && $record->{socket}) ? $record->{socket}->[0] : '',
					# level => $self->state_user_full($nick),
					level => $nick,
					msg => $input->{raw_line}
				);
				
				my $user = $self->{resident}->get_user($nick, 0);
				if ($user) {
					$user->{LastCmd} = {
						When => time(),
						Raw => $input->{raw_line}
					};
				}
				
				$self->{total_messages_sent}++;
			} # okay to log
		} # not a ping
		
		# pass command along to all plugins (i.e. NickServ)
		my $plugins = $self->plugin_list();
		foreach my $plugin_name (keys %$plugins) {
			my $plugin = $plugins->{$plugin_name};
			if ($plugin->can('cmd_from_client')) {
				eval { $plugin->cmd_from_client($nick, $input); };
				if ($@) { $self->{resident}->log_error( "$plugin_name Crash in cmd_from_client: $@" ); }
			}
		}
	} # raw_line
	
	return $result;
}

#	sub IRCD_raw_input {
#		# overriding POE::Component::Server::IRC::IRCD_raw_input
#		# to count total bytes in
#		my ($self, $ircd) = splice @_, 0, 2;
#		my $conn_id = ${ $_[0] };
#		my $input   = ${ $_[1] };
#		
#		$self->{total_bytes_in} += length($input);
#		
#		# return PCSI_EAT_CLIENT if !$self->{debug};
#		warn "<<< $conn_id: $input\n";
#		return PCSI_EAT_CLIENT;
#	}
#
#	sub IRCD_raw_output {
#		# overriding POE::Component::Server::IRC::IRCD_raw_output
#		# to count total bytes out
#		my ($self, $ircd) = splice @_, 0, 2;
#		my $conn_id = ${ $_[0] };
#		my $output  = ${ $_[1] };
#		
#		$self->{total_bytes_out} += length($output);
#		
#		# return PCSI_EAT_CLIENT if !$self->{debug};
#		warn ">>> $conn_id: $output\n";
#		return PCSI_EAT_CLIENT;
#	}

1;

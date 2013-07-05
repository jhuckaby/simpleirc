package Simple;

##
# SimpleIRC Main Engine
##

use strict;
use warnings;
use FileHandle;
use File::Basename;
use Time::HiRes qw/time/;
use Digest::MD5 qw/md5_hex/;
use URI::Escape;
use JSON;
use MIME::Lite;
use IRC::Utils ':ALL';
use Tools;
use VersionInfo;

require 'WebServer.pm';

sub new {
	# class constructor
	my $class = shift;
	my $self = bless {@_}, $class;
	
	$self->{log_columns} = {
		transcript => ['Epoch', 'Date/Time', 'PID', 'Category', 'IP', 'Host/Nick', 'Message'],
		debug => ['Epoch', 'Date/Time', 'PID', 'Category', 'Package', 'Level', 'Message'],
		error => ['Epoch', 'Date/Time', 'PID', 'Category', 'Package', 'Code', 'Message'],
		maint => ['Epoch', 'Date/Time', 'PID', 'Category', 'Package', 'Code', 'Message']
	};
	
	return $self;
}

sub init {
	# startup
	my ($self, $ircd) = @_;
	$self->{ircd} = $ircd;
	
	# setup nick management system
	$self->{users} = {};
	$self->{user_dir} = 'data/users';
	make_dirs_for( $self->{user_dir} . '/' );
	
	# setup channel management system
	$self->{channels} = {};
	$self->{channel_dir} = 'data/channels';
	make_dirs_for( $self->{channel_dir} . '/' );
	
	# server-wide persistent data
	$self->{data_dir} = 'data';
	$self->get_data();
	
	# sessions for web server
	$self->{sessions} = {};
	if (-e 'data/web-sessions.json') {
		$self->{sessions} = eval { json_parse( load_file('data/web-sessions.json') ); } || {};
	}
	
	# server management
	$self->{hostname} = get_hostname();
	$self->{time_start} = time();
}

sub tick {
	# called once every second
	my $self = shift;
}

sub get_all_user_ids {
	# scan dir for all users, return id list as arr ref
	my $self = shift;
	my $files = [ glob($self->{user_dir} . '/*.json') ];
	my $nicks = [];
	
	foreach my $file (@$files) {
		my $filename = basename($file);
		my $nick = $filename; $nick =~ s/\.\w+$//;
		push @$nicks, $nick;
	}
	
	return $nicks;
}

sub get_user {
	# get user record
	my $self = shift;
	my $nick = shift;
	my $do_create = shift || 0;
	$nick = lc($nick);
	
	# check cache first
	if ($self->{users}->{$nick}) { return $self->{users}->{$nick}; }
	
	# nope, load from disk
	my $user_file = $self->{user_dir} . '/' . $nick . '.json';
	my $user_raw = load_file($user_file);
	
	# if no exist and no create flag, return 0 now
	if (!$user_raw && !$do_create) { return 0; }
	
	my $user = { Username => $nick };
	if ($user_raw) {
		eval { $user = json_parse($user_raw); };
		if ($@) {
			$self->log_error( "Failed to parse user file: $user_file: $@" );
			return 0;
		}
	}
	
	$self->{users}->{$nick} = $user;
	return $user;
}

sub save_user {
	# save user to disk
	my ($self, $nick) = @_;
	$nick = lc($nick);
	
	my $user = $self->{users}->{$nick};
	if (!$user || !$user->{Registered}) { return 0; }
	
	my $now = time();
	$user->{Created} ||= $now;
	$user->{Modified} = $now;
	
	# remove session keys
	$user = deep_copy($user);
	foreach my $key (keys %$user) {
		if ($key =~ /^_/) { delete $user->{$key}; }
	}
	
	my $user_file = $self->{user_dir} . '/' . $nick . '.json';
	if (!save_file_atomic( $user_file, json_compose_pretty($user) )) {
		$self->log_error( "Failed to save user file: $user_file: $!" );
		return 0;
	}
	
	return 1;
}

sub unload_user {
	# free memory used by user
	my ($self, $nick) = @_;
	$nick = lc($nick);
	
	$self->save_user($nick);
	delete $self->{users}->{$nick};
}

sub is_admin {
	# return true if user is an admin, false otherwise
	my ($self, $nick) = @_;
	my $user = $self->get_user($nick, 0);
	return ($user && $user->{Administrator});
}

sub is_op {
	# return true if user is an effective op in channel, false otherwise
	my ($self, $chan, $nick) = @_;
	my $flags = $self->get_channel_user_flags($chan, $nick);
	return ($flags =~ /o/i) ? 1 : 0;
}

sub get_channel_user_flags {
	# get EFFECTIVE channel user flags, modified by admin / founder status
	my ($self, $chan, $nick) = @_;
	
	my $channel = $self->get_channel($chan, 0);
	if (!$channel) { return ''; }
	
	my $flags = '';
	if ($channel->{Users}->{$nick}) {
		$flags = $channel->{Users}->{$nick}->{Flags} || '';
	}
	if ($channel->{Founder} eq $nick) { $flags = 'of'; }
	if ($self->is_admin($nick) && ($flags !~ /o/i)) { $flags = 'o'; }
	
	return $flags;
}

sub send_user_password_reset_email {
	# send email to user with instructions for resetting password
	my ($self, $nick) = @_;
	my $user = $self->get_user($nick, 0);
	if (!$user) { return 0; }
	
	my $secret = generate_unique_id(16);
	my $from = 'irc@' . $self->{config}->{ServerName};
	my $subject = $self->{config}->{ServerName} . " IRC Password Recovery for '$nick'";
	
	my $body = "";
	$body .= "Hello " . ($user->{FullName} || $nick) . ",\n\n";
	$body .= "It looks like you may have forgotten your IRC password for nickname '$nick' on " . $self->{config}->{ServerName} . ".\n";
	$body .= "If this was you, please type the following command into the IRC console:\n\n";
	$body .= "\t/msg nickserv confirm $secret NEWPASSWORD\n\n";
	$body .= "Replace NEWPASSWORD with a newly created password for your account.\n";
	$body .= "If you did not initiate this process, please ignore this e-mail.\n\n";
	$body .= "Thanks!\n\n";
	$body .= $self->{config}->{ServerDesc} . "\n";
	$body .= load_file('conf/admin.txt') . "\n";
	
	my $msg = MIME::Lite->new(
		To => $user->{Email},
		From => $from,
		Subject => $subject,
		Data => $body
	);
	# MIME::Lite->send('sendmail', "sendmail -t -oi -oem");
	if (!$msg->send()) {
		my $error_msg = "Failed to send mail to ".$user->{Email}.": " . ($! || "Unknown Error");
		$self->log_error($error_msg);
		return 0;
	}
	
	$user->{TempPasswordResetHash} = $secret;
	$self->save_user($nick);
	
	return 1;
}

sub get_all_channel_ids {
	# scan dir for all channels, return id list as arr ref
	my $self = shift;
	my $files = [ glob($self->{channel_dir} . '/*.json') ];
	my $chan_ids = [];
	
	foreach my $file (sort @$files) {
		my $filename = basename($file);
		my $chan = $filename; $chan =~ s/\.\w+$//;
		push @$chan_ids, $chan;
	}
	
	return $chan_ids;
}

sub get_channel {
	# get channel record
	my $self = shift;
	my $chan = shift;
	my $do_create = shift || 0;
	$chan = lc(sch($chan));
	
	# check cache first
	if ($self->{channels}->{$chan}) { return $self->{channels}->{$chan}; }
	
	# nope, load from disk
	my $channel_file = $self->{channel_dir} . '/' . $chan . '.json';
	my $channel_raw = load_file($channel_file);
	
	# if no exist and no create flag, return 0 now
	if (!$channel_raw && !$do_create) { return 0; }
	
	my $channel = { Name => $chan };
	if ($channel_raw) {
		eval { $channel = json_parse($channel_raw); };
		if ($@) {
			$self->log_error( "Failed to parse channel file: $channel_file: $@" );
			return 0;
		}
	}
	
	$self->{channels}->{$chan} = $channel;
	return $channel;
}

sub save_channel {
	# save channel to disk
	my ($self, $chan) = @_;
	$chan = lc(sch($chan));
	
	my $channel = $self->{channels}->{$chan};
	if (!$channel) { return 0; }
	
	my $now = time();
	$channel->{Created} ||= $now;
	$channel->{Modified} = $now;
	$channel->{Name} = $chan;
	
	# remove session keys
	$channel = deep_copy($channel);
	foreach my $key (keys %$channel) {
		if ($key =~ /^_/) { delete $channel->{$key}; }
	}
	
	my $channel_file = $self->{channel_dir} . '/' . $chan . '.json';
	if (!save_file_atomic( $channel_file, json_compose_pretty($channel) )) {
		$self->log_error( "Failed to save channel file: $channel_file: $!" );
		return 0;
	}
	
	return 1;
}

sub unload_channel {
	# free memory used by channel
	my ($self, $chan) = @_;
	$chan = lc(sch($chan));
	
	$self->save_channel($chan);
	delete $self->{channels}->{$chan};
}

sub get_data {
	# get global server-wide data record
	my $self = shift;
	
	# check cache first
	if ($self->{data}) { return $self->{data}; }
	
	# nope, load from disk
	my $data_file = $self->{data_dir} . '/server.json';
	my $data_raw = load_file($data_file);
	
	my $data = {};
	if ($data_raw) {
		eval { $data = json_parse($data_raw); };
		if ($@) {
			$self->log_error( "Failed to parse server data file: $data_file: $@" );
			return 0;
		}
	}
	
	$self->{data} = $data;
	return $data;
}

sub save_data {
	# save global server data to disk
	my $self = shift;
	
	my $data = $self->{data};
	if (!$data) { return 0; }
	
	my $now = time();
	$data->{Created} ||= $now;
	$data->{Modified} = $now;
	
	# remove session keys
	$data = deep_copy($data);
	foreach my $key (keys %$data) {
		if ($key =~ /^_/) { delete $data->{$key}; }
	}
	
	my $data_file = $self->{data_dir} . '/server.json';
	if (!save_file_atomic( $data_file, json_compose_pretty($data) )) {
		$self->log_error( "Failed to save server data file: $data_file: $!" );
		return 0;
	}
	
	return 1;
}

sub rotate_logs {
	# rotate and archive daily logs
	my $self = shift;
	my $yyyy_mm_dd = yyyy_mm_dd( normalize_midnight( normalize_midnight(time()) - 43200 ), '/' );
	my $archive_dir = $self->{config}->{Logging}->{LogDir} . '/archive';
	my $logs = [ glob($self->{config}->{Logging}->{LogDir} . '/*.log') ];
	my $gzip_bin = find_bin('gzip');
	
	foreach my $log_file (@$logs) {
		my $log_category = basename($log_file); $log_category =~ s/\.\w+$//;
		my $log_archive = $archive_dir . '/' . $log_category . '/' . $yyyy_mm_dd . '.log';
		
		$self->log_maint("Archiving log: $log_file to $log_archive.gz");
		
		# add a message at the bottom of the log, in case someone is live tailing it.
		my $fh = FileHandle->new( ">>$log_file" );
		if ($fh) {
			my $nice_time = scalar localtime;
			$fh->print("\n# Rotating log to $log_archive.gz at $nice_time\n");
		}
		$fh->close();
		
		if (make_dirs_for( $log_archive )) {
			if (rename($log_file, $log_archive)) {
				my $output = `$gzip_bin $log_archive 2>&1`;
				if ($output =~ /\S/) {
					$self->log_maint("ERROR: Failed to gzip file: $log_archive: $output");
				}
			}
			else {
				$self->log_maint("ERROR: Failed to move file: $log_file --> $log_archive: $!");
			}
		}
		else {
			$self->log_maint("ERROR: Failed to create directories for: $log_archive: $!");
		}
	} # foreach log
}

sub web_session_maint {
	# discard old web sessions
	my $self = shift;
	my $now = time();
	my $lifetime_secs = $self->{config}->{WebServer}->{SessionExpireDays} * 86400;
	
	foreach my $session_id (keys %{$self->{sessions}}) {
		my $session = $self->{sessions}->{$session_id};
		if ($now - $session->{Modified} >= $lifetime_secs) {
			$self->log_maint("Expiring old web session: $session_id: " . json_compose($session));
			delete $self->{sessions}->{$session_id};
		}
	}
}

sub warn_handler {
	# catch warn calls, log them or count bytes if coming from IRC
	my ($self, $package_name, $msg) = @_;
	
	# <<< 6: WHO #test
	# >>> 6: :sample.irc.local 324 jhuckabynick #test +int
	if (($package_name eq 'POE::Component::Server::IRC') && ($msg =~ m@(>>>|<<<)\s+(\d+)\:\s*(.+)$@s)) {
		# captured data in/out of IRC via 'debug' flag (VERY MESSY, TODO: Find a better way)
		# log number of bytes
		my ($direction, $conn_id, $data) = ($1, $2, $3);
		if ($self->{ircd}) {
			if ($direction =~ m@<@) { $self->{ircd}->{total_bytes_in} += length($data); }
			else { $self->{ircd}->{total_bytes_out} += length($data); }
		}
	}
	elsif ($self->{config}->{Logging}->{DebugLevel} >= 9) {
		$self->log_event(
			log => 'debug',
			package => $package_name,
			level => 9,
			msg => $msg
		);
	}	
}

sub log_event {
	# log generic event to log
	my $self = shift;
	my $args = {@_};
	my $log = $args->{log} || 'debug';
	my $log_config = $self->{config}->{Logging};
	
	if (!$log_config->{Enabled}) { return; }
	if (!$log_config->{ActiveLogs}->{$log}) { return; }
	
	my $fh = FileHandle->new( ">>" . $log_config->{LogDir} . '/' . $log . '.log' );
	
	# $args->{msg} =~ s/\n/ /g;
	# $args->{msg} =~ s/\s+/ /g;
	
	my $now = time();
	my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime($now);
	my $nice_date = sprintf("%0004d-%02d-%02d %02d:%02d:%02d", $year + 1900, $mon + 1, $mday, $hour, $min, $sec);
	
	my $line = '[' . join('][', 
		$now,
		$nice_date,
		$$,
		$log,
		$args->{package} || 'main',
		$args->{code} || $args->{level} || ''
	) . "] " . trim($args->{msg}) . "\n";
	
	$fh->print( $line );
	$fh->close();
	
	if ($log_config->{EchoToConsole}) { print "$line"; }
}

sub log_debug {
	# log debug message
	my ($self, $level, $msg) = @_;
	
	if ($level > $self->{config}->{Logging}->{DebugLevel}) { return; }
	
	my ($package, undef, undef) = caller();
	$package =~ s/^(.+)::(\w+)$/$2/;
	
	$self->log_event(
		log => 'debug',
		package => $package,
		level => $level,
		msg => $msg
	);
}

sub log_error {
	# log error
	my ($self, $msg) = @_;
	
	my ($package, undef, undef) = caller();
	$package =~ s/^(.+)::(\w+)$/$2/;
	
	$self->log_event(
		log => 'error',
		package => $package,
		code => 1,
		msg => $msg
	);
}

sub log_maint {
	# log maintenance message
	my ($self, $msg) = @_;
		
	my ($package, undef, undef) = caller();
	$package =~ s/^(.+)::(\w+)$/$2/;
	
	$self->log_event(
		log => 'maint',
		package => $package,
		level => '',
		msg => $msg
	);
}

sub reload_config {
	# reload and re-merge config, just like at startup
	my $self = shift;
	my $config = eval { json_parse(load_file('conf/config-defaults.json')); };
	if (!$config) { return { Code => 1, Description => "Failed to parse config-defaults.json: $@" }; }
	
	# merge in web config
	if (-e 'conf/config-web.json') {
		my $temp_config = eval { json_parse(load_file('conf/config-web.json')); };
		if (!$temp_config) { die "Failed to parse config-web.json: $@\n"; }
		merge_hashes( $config, $temp_config, 1 );
	}
	
	# merge in user config (always takes precedence)
	if (-e 'conf/config.json') {
		my $temp_config = eval { json_parse(load_file('conf/config.json')); };
		if (!$temp_config) { die "Failed to parse config.json: $@\n"; }
		merge_hashes( $config, $temp_config, 1 );
	}
	
	# remove "comments" from json
	remove_key_recursive( $config, '//' );
	
	# infuse elements back into their respective homes
	$self->{config} = $config;
	
	# $self->{ircd}->{config}->{SERVERNAME} = $config->{ServerName};
	$self->{ircd}->{config}->{SERVERDESC} = $config->{ServerDesc};
	$self->{ircd}->{config}->{NICKLEN} = $config->{MaxNickLength};
	# $self->{ircd}->{config}->{NETWORK} = $config->{ServerName};
	# $self->{ircd}->{config}->{MASKIPS} = $config->{MaskIPs}->{Enabled};
	
	# pass new config to plugins
	my $plugins = $self->{ircd}->plugin_list();
	foreach my $plugin_name (keys %$plugins) {
		my $plugin = $plugins->{$plugin_name};
		my $plugin_config = $config->{Plugins}->{$plugin_name};
		if ($plugin_config->{Enabled}) {
			$plugin->{config} = $plugin_config;
			if ($plugin->can('reload_config')) { $plugin->reload_config($plugin_config); }
		}
	}
	
	# infuse text files back into live ircd server
	foreach my $key ('motd', 'admin', 'info') {
		my $lines = [ split(/\n/, trim(load_file("conf/$key.txt"))) ];
		$self->{ircd}->{config}->{uc($key)} = $lines;
	}
	
	return 1;
}

sub shutdown {
	# receive shutdown signal (int / term)
	my $self = shift;
	$self->log_debug(1, "Shutting down");
	
	# commit web sessions to disk
	save_file_atomic( 'data/web-sessions.json', json_compose_pretty($self->{sessions}) );
}

1;

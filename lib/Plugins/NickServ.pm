##
# NickServ Bot for SimpleIRC 1.0
# Copyright (c) 2013 Joseph Huckaby and EffectSoftware.com
##

package POE::Component::Server::IRC::Plugin::NickServ;

use strict;
use warnings;
use POE::Component::Server::IRC::Plugin qw(:ALL);
use IRC::Utils qw/uc_irc/;
use Data::Dumper;
use Digest::MD5 qw/md5_hex/;
use Tools;

use Plugin;
use base qw/Plugin/;

sub new {
	my ($package, %args) = @_;
	return bless \%args, $package;
}

sub PCSI_register {
	my ($self, $ircd) = splice @_, 0, 2;
	$self->log_debug(3, "NickServ starting up");
	
	# setup
	$self->{ircd} = $ircd;
	$self->{schedule} = {};

	$ircd->plugin_register($self, 'SERVER', qw(daemon_privmsg daemon_nick daemon_quit daemon_join));
	$ircd->yield(
		'add_spoofed_nick',
		{
			nick	=> 'NickServ',
			umode   => 'Doi',
			ircname => 'The NickServ bot',
		},
	);
	
	# add /ns shortcut to /msg NickServ
	$self->add_custom_command( 'ns', sub {
		my ($this, $nick, $cmd) = @_;
		$self->IRCD_daemon_privmsg( $ircd, \$nick, \"NickServ", \$cmd, [] );
	} );
	
	$self->add_custom_command( 'identify', sub {
		my ($this, $nick, $cmd) = @_;
		$cmd = "IDENTIFY " . $cmd;
		$self->IRCD_daemon_privmsg( $ircd, \$nick, \"NickServ", \$cmd, [] );
	} );
	
	return 1;
}

sub PCSI_unregister {
	return 1;
}

sub IRCD_daemon_privmsg {
	my ($self, $ircd) = splice @_, 0, 2;
	my $nick = (split /!/, ${ $_[0] })[0];
	my $msg = ${ $_[2] };
	my $ns_config = $self->{config};
	
	if (${ $_[1] } ne 'NickServ') { return PCSI_EAT_NONE; } # not meant for us
	
	# $self->log_debug(9, "IRCD_daemon_privmsg: " . Dumper(\@_));
	
	if ($msg =~ /^register/i) {
		# register nick
		my $password = '';
		my $email = '';
		
		if ($msg =~ /^register\s+([\'\"])([^\1]+)(\1)\s+(\S+)$/i) {
			($password, $email) = ($2, $4);
		}
		elsif ($msg =~ /^register\s+(\S+)\s+(\S+)$/i) {
			($password, $email) = ($1, $2);
		}
		else {
			# bad format
			$self->send_msg_to_user($nick, 'NOTICE', "Error: Bad syntax for 'register' command. Please use: /msg nickserv register PASSWORD EMAIL");
			return PCSI_EAT_NONE;
		}
		if ($email !~ /^.+\@.+$/) {
			$self->send_msg_to_user($nick, 'NOTICE', "Error: Incorrectly formatted email address: $email");
			return PCSI_EAT_NONE;
		}
		
		my $nick_exclude_re = $ns_config->{RegExclude} || '';
		if ($nick_exclude_re && ($nick =~ m@$nick_exclude_re@i)) {
			$self->send_msg_to_user($nick, 'NOTICE', "Please change your nickname before registering. Type: /nick NEWNICK");
			return PCSI_EAT_NONE;
		}
		
		my $user = $self->{resident}->get_user($nick, 1);
		
		if ($user->{Registered}) {
			$self->send_msg_to_user($nick, 'NOTICE', "Nick '$nick' is already registered.  If you have forgotten your password, please type: /msg nickserv recover EMAIL");
			return PCSI_EAT_NONE;
		}
		if ($user->{_identified}) {
			$self->send_msg_to_user($nick, 'NOTICE', "Nick '$nick' is already registered and you have identified.");
			return PCSI_EAT_NONE;
		}
		
		$user->{Username} = lc($nick);
		$user->{DisplayUsername} = $nick;
		$user->{Email} = $email;
		$user->{ID} = generate_unique_id();
		$user->{Password} = md5_hex( $password . $user->{ID} );
		$user->{Registered} = 1;
		$user->{Status} = 'Active';
		$user->{LastLogin} = time();
		$user->{_identified} = 1; # underscore prefix = ram only (session variable, not permanent)
		
		# grab some additional user information from IRC
		my $unick = uc_irc($nick);
		my $record = $ircd->{state}{users}{$unick};
		if ($record) {
			if ($record->{ircname}) { $user->{FullName} = $record->{ircname}; }
			if ($record->{socket} && $record->{socket}->[0]) { $user->{IP} = $record->{socket}->[0]; }
		}
		
		$self->{resident}->save_user($nick);
		
		$self->send_msg_to_user($nick, 'NOTICE', "Nick '$nick' has been successfully registered and identified.");
		
		# auto-oper check
		$self->auto_oper_check($nick, 1, 1);
		
		# auto-set modes if user is already in channels
		my $chanserv = $self->{ircd}->plugin_get( 'ChanServ' );
		$chanserv->sync_all_user_modes( '', $nick );
		
		# cleanup old schedule entries for nick reg
		delete $self->{schedule}->{lc($nick)};
	} # register
	
	elsif ($msg =~ /^recover\s+(\S+)$/i) {
		# recover password
		my $email = $1;
		
		if ($email !~ /^.+\@.+$/) {
			$self->send_msg_to_user($nick, 'NOTICE', "Error: Incorrectly formatted email address: $email");
			return PCSI_EAT_NONE;
		}
		
		my $user = $self->{resident}->get_user($nick, 1);
		
		if (!$user->{Registered}) {
			$self->send_msg_to_user($nick, 'NOTICE', "Nick '$nick' has not yet been registered. Please type: /msg nickserv register PASSWORD EMAIL");
			return PCSI_EAT_NONE;
		}
		if (lc($email) ne lc($user->{Email})) {
			$self->send_msg_to_user($nick, 'NOTICE', "Error: The email address you provided does not match our records: $email");
			return PCSI_EAT_NONE;
		}
		
		if (!$self->{resident}->send_user_password_reset_email($nick)) {
			$self->send_msg_to_user($nick, 'NOTICE', "Error: Could not send e-mail. Please try again later.");
			return PCSI_EAT_NONE;
		}
		
		$self->send_msg_to_user($nick, 'NOTICE', "Instructions for resetting your password have been sent to you via e-mail.");
	} # recover
	
	elsif ($msg =~ /^confirm/i) {
		# confirm password reset
		my $secret = '';
		my $new_password = '';
		
		if ($msg =~ /^confirm\s+(\S+)\s+([\'\"])([^\1]+)(\1)$/i) {
			($secret, $new_password) = ($2, $4);
		}
		elsif ($msg =~ /^confirm\s+(\S+)\s+(\S+)$/i) {
			($secret, $new_password) = ($1, $2);
		}
		else {
			# bad format
			$self->send_msg_to_user($nick, 'NOTICE', "Error: Bad syntax for 'confirm' command. Please use: /msg nickserv confirm SECRETKEY PASSWORD");
			return PCSI_EAT_NONE;
		}
		
		my $user = $self->{resident}->get_user($nick, 1);
		
		if (!$user->{TempPasswordResetHash} && $user->{_old_nick}) {
			my $old_nick = $user->{_old_nick};
			$self->send_msg_to_user($nick, 'NOTICE', "Error: Your nick was changed to '$nick'. Please type: /nick $old_nick, then enter the confirm command again.");
			return PCSI_EAT_NONE;
		}
		if ($secret ne $user->{TempPasswordResetHash}) {
			$self->send_msg_to_user($nick, 'NOTICE', "Error: Secret key does not match. Please copy the command from your confirmation e-mail.");
			return PCSI_EAT_NONE;
		}
		
		# success!
		delete $user->{TempPasswordResetHash};
		$user->{DisplayUsername} = $nick;
		$user->{Password} = md5_hex( $new_password . $user->{ID} );
		$user->{Registered} = 1;
		$user->{LastLogin} = time();
		$user->{_identified} = 1; # underscore prefix = ram only (session variable, not permanent)
		
		# grab some additional user information from IRC
		my $unick = uc_irc($nick);
		my $record = $ircd->{state}{users}{$unick};
		if ($record) {
			if ($record->{ircname}) { $user->{FullName} = $record->{ircname}; }
			if ($record->{socket} && $record->{socket}->[0]) { $user->{IP} = $record->{socket}->[0]; }
		}
		
		$self->{resident}->save_user($nick);
		
		$self->send_msg_to_user($nick, 'NOTICE', "Your password for nickname '$nick' has been reset successfully.");
		
		# auto-oper check
		$self->auto_oper_check($nick, 1, 1);
		
		# auto-set modes if user is already in channels
		my $chanserv = $self->{ircd}->plugin_get( 'ChanServ' );
		$chanserv->sync_all_user_modes( '', $nick );
		
		# cleanup old schedule entries for nick reg
		delete $self->{schedule}->{lc($nick)};
	} # confirm password reset
	
	elsif ($msg =~ /^(identify|login)\s+(.+)$/i) {
		# identify nick
		my $password = $2;
		my $user = $self->{resident}->get_user($nick, 1);
		
		if (!$user->{Registered}) {
			$self->send_msg_to_user($nick, 'NOTICE', "Nick '$nick' has not yet been registered. Please type: /msg nickserv register PASSWORD EMAIL");
			return PCSI_EAT_NONE;
		}
		if ($user->{_identified}) {
			$self->send_msg_to_user($nick, 'NOTICE', "Nick '$nick' is already identified.");
			return PCSI_EAT_NONE;
		}
		if ($user->{Status} =~ /suspended/i) {
			$self->send_msg_to_user($nick, 'NOTICE', "The '$nick' user account is suspended, and cannot be accessed at this time.");
			return PCSI_EAT_NONE;
		}
		
		if (md5_hex($password . $user->{ID}) ne $user->{Password}) {
			$self->send_msg_to_user($nick, 'NOTICE', "Error: Incorrect password for '$nick'. If you have forgotten your password, please type: /msg nickserv recover EMAIL");
			return PCSI_EAT_NONE;
		}
		
		$user->{DisplayUsername} = $nick;
		$user->{LastLogin} = time();
		$user->{_identified} = 1; # underscore prefix = ram only (session variable, not permanent)
		
		# grab some additional user information from IRC (may change between sessions)
		my $unick = uc_irc($nick);
		my $record = $ircd->{state}{users}{$unick};
		if ($record) {
			if ($record->{auth}) { $user->{Ident} = $nick . '!' . $record->{auth}->{ident} . '@' . $record->{auth}->{hostname}; }
			if ($record->{ircname}) { $user->{FullName} = $record->{ircname}; }
			if ($record->{socket} && $record->{socket}->[0]) { $user->{IP} = $record->{socket}->[0]; }
		}
		
		$self->{resident}->save_user($nick);
		
		$self->send_msg_to_user($nick, 'NOTICE', "Password accepted. Nick '$nick' has been successfully identified.");
		
		# auto-oper check
		$self->auto_oper_check($nick, 1, 1);
		
		# auto-set modes if user is already in channels
		my $chanserv = $self->{ircd}->plugin_get( 'ChanServ' );
		$chanserv->sync_all_user_modes( '', $nick );
		
		# cleanup old schedule entries for nick reg
		delete $self->{schedule}->{lc($nick)};
	} # identify
	
	elsif ($msg =~ /^(drop|delete)\s+(\S+)$/i) {
		# drop nick (delete account)
		my $thingy = $2;
		my $user = $self->{resident}->get_user($nick);
		my $target_user = $self->{resident}->get_user($thingy);
		my $target_nick = '';
		
		# if thingy is our password, then delete our own account
		if ($user && $user->{Registered} && !$target_user) {
			# delete self
			if (md5_hex($thingy . $user->{ID}) eq $user->{Password}) {
				# password matches
				$target_nick = $nick;
				$target_user = $user;
				$self->log_debug(3, "User $target_nick is deleting their own account.");
			} # password matches
			else {
				$self->send_msg_to_user($nick, 'NOTICE', "Error: Your password is incorrect.");
				return PCSI_EAT_NONE;
			}
		} # delete self
		
		# otherwise, admin must be trying to delete a nick
		elsif ($user && $user->{Administrator} && $user->{_identified} && $target_user) {
			# delete any target nick / user (admin only)
			$target_nick = $thingy;
			$self->log_debug(3, "Administrator $nick is deleting user account: $target_nick");
		} # admin drop any nick
		
		if ($target_nick) {
			# okay, we have a target nick, proceed with drop operation
			# cleanup old schedule entries for old nick reg
			delete $self->{schedule}->{lc($target_nick)};
			
			# if user is a server administrator, remove that too
			if ($target_user->{Administrator}) {
				delete $target_user->{Administrator};
				
				if ($target_user->{_identified}) {
					$self->schedule_event( '', {
						action => sub {
							my $route_id = $self->{ircd}->_state_user_route($target_nick);
							if ($route_id) {
								$self->{ircd}->_send_output_to_client($route_id, $_)
									for $self->{ircd}->_daemon_cmd_umode($target_nick, '-o');
							}
						}
					} );
				} # identified
			} # user is admin
			
			# delete all privs in all channels
			foreach my $temp_chan (@{$self->{resident}->get_all_channel_ids()}) {
				my $temp_channel = $self->{resident}->get_channel($temp_chan);
				if ($temp_channel && $temp_channel->{Users} && $temp_channel->{Users}->{lc($target_nick)}) {
					delete $temp_channel->{Users}->{lc($target_nick)};
					$self->{resident}->save_channel($temp_chan);
				}
			} # foreach channel
			
			# sync all privs
			my $chanserv = $self->{ircd}->plugin_get( 'ChanServ' );
			$chanserv->sync_all_user_modes( '', $target_nick );
			
			# free up memory from old nick
			$self->{resident}->unload_user($target_nick);
			
			# delete user record from disk
			unlink( $self->{resident}->{user_dir} . '/' . lc($target_nick) . '.json' );
			
			# change user nick if required
			my $unick = uc_irc($target_nick);
			my $record = $ircd->{state}{users}{$unick} || 0;
			
			if ($ns_config->{RegForce} && $record) {
				my $nick_exclude_re = $ns_config->{RegExclude} || '';
				if (!$nick_exclude_re || ($target_nick !~ m@$nick_exclude_re@i)) {
					$self->schedule_event( '', {
						when => time() + 1,
						action => 'evt_change_nick',
						old_nick => $target_nick,
						new_nick => $self->get_rand_nick(),
						msg => "Your nick was changed because your account was deleted."
					} );
				}
			} # force register new nicks
			
			if ($nick eq $target_nick) {
				# deleted our own account
				$self->send_msg_to_user($nick, 'NOTICE', "Your user account was successfully deleted.");
			}
			else {
				# deleted a nick other than ourselves, inform admin
				$self->send_msg_to_user($nick, 'NOTICE', "The user account '$target_nick' was successfully deleted.");
			}
		} # proceed with drop
	} # drop
	
	elsif ($msg =~ /^logout/i) {
		# log user out
		my $user = $self->{resident}->get_user($nick);
		if ($user && $user->{_identified}) {
			# remove _identified flag (in ram)
			delete $user->{_identified};
			
			# cleanup old schedule entries for old nick reg
			delete $self->{schedule}->{lc($nick)};
			
			# if user is admin, remove the global 'o' priv
			if ($user->{Administrator}) {
				$self->schedule_event( '', {
					action => sub {
						my $route_id = $self->{ircd}->_state_user_route($nick);
						if ($route_id) {
							$self->{ircd}->_send_output_to_client($route_id, $_)
								for $self->{ircd}->_daemon_cmd_umode($nick, '-o');
						}
					}
				} );
			} # unadmin
			
			# sync all privs in all channels
			my $chanserv = $self->{ircd}->plugin_get( 'ChanServ' );
			$chanserv->sync_all_user_modes( '', $nick );
			
			# free up memory, etc.
			$self->{resident}->unload_user($nick);
			
			# inform user they were logged out
			$self->send_msg_to_user($nick, 'NOTICE', "You were successfully logged out.");
			
			# schedule event to rename nick if user doesn't re-log-in
			$self->schedule_event( $nick, {
				when => time() + $ns_config->{RegTimeout},
				action => 'evt_change_nick',
				old_nick => $nick,
				new_nick => $self->get_rand_nick(),
				msg => "Your nick was changed because '$nick' is registered, and you did not identify."
			} );
		}
		else {
			$self->send_msg_to_user($nick, 'NOTICE', "You are not logged in.");
		}
	} # logout
	
	elsif ($msg =~ /^help/i) {
		$self->do_plugin_help($nick, $msg);
	} # help

	return PCSI_EAT_NONE;
}

sub IRCD_daemon_nick {
	my ($self, $ircd) = splice @_, 0, 2;
	my $nick = (split /!/, ${ $_[0] })[0];
	my $ns_config = $self->{config};
	my $now = time();
		
	# $self->log_debug(9, "IRCD_daemon_nick: " . Dumper(\@_) );
	
	my $new_nick = $nick;
	
	if (@_ == 3) {
		# nick change
		$new_nick = ${ $_[1] };
		$self->log_debug(9, "Nick change: $nick --> $new_nick");
	}
	
	# only manage nick if not spoofed
	my $route_id = $ircd->_state_user_route($new_nick);
	if ($route_id ne 'spoofed') {
		my $old_user = undef;
		if (lc($new_nick) ne lc($nick)) {
			# load old user and UNidentify him
			$old_user = $self->{resident}->get_user($nick);
			delete $old_user->{_identified};
			
			# cleanup old schedule entries for both nicks
			delete $self->{schedule}->{lc($nick)};
			delete $self->{schedule}->{lc($new_nick)};
			
			# free up memory from old nick
			$self->{resident}->unload_user($nick);
		}
		# load or create user record
		my $user = $self->{resident}->get_user($new_nick, 1);
		
		if (!$user->{Registered} && $ns_config->{RegForce}) {
			# user has not yet registered
			my $nick_exclude_re = $ns_config->{RegExclude} || '';
			if (!$nick_exclude_re || ($new_nick !~ m@$nick_exclude_re@i)) {
				# nick requires reg
				$self->send_msg_to_user($new_nick, 'NOTICE', "Please register your nickname by typing: /msg nickserv register PASSWORD EMAIL");
				
				$self->schedule_event( $new_nick, {
					when => $now + $ns_config->{RegTimeout},
					action => 'evt_change_nick',
					old_nick => $new_nick,
					new_nick => ($new_nick eq $nick) ? $self->get_rand_nick() : $nick,
					msg => "Your nick was changed because you did not register '$new_nick'."
				} );
			}
		}
		elsif ($user->{Registered} && !$user->{_identified}) {
			$self->send_msg_to_user($new_nick, 'NOTICE', "This nickname is registered. Please identify by typing: /msg nickserv identify PASSWORD");
			
			$self->schedule_event( $new_nick, {
				when => $now + $ns_config->{RegTimeout},
				action => 'evt_change_nick',
				old_nick => $new_nick,
				new_nick => ($new_nick eq $nick) ? $self->get_rand_nick() : $nick,
				msg => "Your nick was changed because '$new_nick' is registered, and you did not identify."
			} );
		}
		
		if ($old_user && $old_user->{Administrator} && !$user->{Administrator}) {
			my $route_id = $self->{ircd}->_state_user_route($new_nick);
			if ($route_id) {
				$self->{ircd}->_send_output_to_client($route_id, $_)
					for $self->{ircd}->_daemon_cmd_umode($new_nick, '-o');
			}
		} # taketh away admin
		
		# update display nick if user is ident and reg
		if ($user->{Registered} && $user->{_identified}) {
			$user->{DisplayUsername} = $new_nick;
			$self->{resident}->save_user($new_nick);
		}
		
		my $chanserv = $self->{ircd}->plugin_get( 'ChanServ' );
		$chanserv->sync_all_user_modes( '', $new_nick );
		
	} # not spoofed
	
	return PCSI_EAT_NONE;
}

sub IRCD_daemon_quit {
	my ($self, $ircd) = splice @_, 0, 2;
	my $nick = (split /!/, ${ $_[0] })[0];
	# $self->log_debug(9, "IRCD_daemon_quit: " . Dumper(\@_) );
	
	# cleanup old schedule entries for nick reg
	delete $self->{schedule}->{lc($nick)};
	
	# free up memory from old nick
	$self->{resident}->unload_user($nick);
	
	return PCSI_EAT_NONE;
}

sub IRCD_daemon_join {
    my ($self, $ircd) = splice @_, 0, 2;
    my $nick = (split /!/, ${ $_[0] })[0];
    my $chan = ${ $_[1] };
    
    # my $unick = uc_irc($nick);
    # my $record = $ircd->{state}{users}{$unick};
    # $record->{auth}->{hostname} = 'elksoft.com';
    
    return PCSI_EAT_NONE;
}

sub tick {
	# called every second
	my $self = shift;
	$self->schedule_idle();
}

sub evt_change_nick {
	# auto change nick after reg time period expires
	my ($self, $event) = @_;
	$self->log_debug(6, "Changing nick " . $event->{old_nick} . " to " . $event->{new_nick});
	
	$self->{ircd}->_daemon_cmd_nick( $event->{old_nick}, $event->{new_nick} );
	
	# save old nick in new nick's hash (in memory), so we can tell the user how to get back
	my $user = $self->{resident}->get_user($event->{new_nick}, 1);
	$user->{_old_nick} = $event->{old_nick};
	
	if ($event->{msg}) {
		# send notice in next tick
		$self->schedule_event( '', {
			action => 'evt_send_msg',
			type => 'NOTICE',
			nick => $event->{new_nick},
			msg => $event->{msg}
		} );
	}
}

sub evt_send_msg {
	# send delayed message to user
	my ($self, $event) = @_;
	$self->send_msg_to_user( $event->{nick}, $event->{type} || 'PRIVMSG', $event->{msg} );
}

sub get_rand_nick {
	# get random unique nick, for reg timeouts
	my $self = shift;
	my $nick = '';
	my $max = 99;
	
	do {
		$max *= 10;
		$nick = $self->{config}->{UnregPrefix} . int(rand($max));
	} 
	while ($self->{resident}->get_user($nick, 0));
	
	return $nick;
}

sub auto_oper_check {
	# check if user is supposed to be an oper, and if so, oper right away
	my ($self, $nick, $username, $password) = @_;
	
	if ($self->{ircd}->_state_o_line($nick, $username, $password)) {
		my $route_id = $self->{ircd}->_state_user_route($nick);
		return 0 unless $route_id;
		$self->{ircd}->_send_output_to_client(
			$route_id,
			(ref $_ eq 'ARRAY' ? @{ $_ } : $_),
		) for $self->{ircd}->_daemon_cmd_oper( $nick, $username, $password );
		
		return 1;
	}
	
	return 0;
}

sub run_daily_maintenance {
	# expire old nicks (admins excluded)
	my $self = shift;
	
	if ($self->{config}->{NickExpireDays}) {
		$self->log_maint("Checking nicks for expiration (" . $self->{config}->{NickExpireDays} . " days)");
		my $ago = time() - ($self->{config}->{NickExpireDays} * 86400);
		
		foreach my $nick (@{$self->{resident}->get_all_user_ids()}) {
			my $user = $self->{resident}->get_user($nick);
			if ($user && !$user->{_identified} && !$user->{Administrator}) {
				# exclude admins, and users who are actually logged in
				if ($user->{Modified} < $ago) {
					$self->log_maint("Deleting user: $nick (last activity " . yyyy_mm_dd($user->{Modified}) . ")");
					$self->{resident}->unload_user($nick);
					unlink( $self->{resident}->{user_dir} . '/' . $nick . '.json' );
				} # expired
			} # good user
		} # foreach nick
	} # nick expire set
}

1;

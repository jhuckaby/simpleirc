##
# ChanServ Bot
##

package POE::Component::Server::IRC::Plugin::ChanServ;

use strict;
use warnings;
use POE::Component::Server::IRC::Plugin qw(:ALL);
use IRC::Utils ':ALL';
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
	$self->log_debug(3, "ChanServ starting up");
	
	# setup
	$self->{ircd} = $ircd;
	$self->{schedule} = {};
	
	$self->{mode_map} = {
		v => 'voice',
		h => 'half-op',
		o => 'operator'
	};

	$ircd->plugin_register($self, 'SERVER', qw(daemon_privmsg daemon_join daemon_nick daemon_mode daemon_topic));
	$ircd->yield(
		'add_spoofed_nick',
		{
			nick	=> 'ChanServ',
			umode   => 'Doi',
			ircname => 'The ChanServ bot',
		},
	);
	
	# add /cs shortcut to /msg ChanServ
	$self->add_custom_command( 'cs', sub {
		my ($this, $nick, $cmd) = @_;
		$self->IRCD_daemon_privmsg( $ircd, \$nick, \"ChanServ", \$cmd, [] );
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
	
	if (${ $_[1] } ne 'ChanServ') { return PCSI_EAT_NONE; } # not meant for us
	
	# $self->log_debug(9, "IRCD_daemon_privmsg: " . Dumper(\@_));
	
	if ($msg =~ /^register/i) {
		my $chan = '';
		
		if ($msg =~ /^register\s+(\S+)$/i) {
			$chan = sch(lc($1));
		}
		else {
			# bad format
			$self->send_msg_to_user($nick, 'NOTICE', "Error: Bad syntax for 'register' command. Please use: /msg chanserv register #MYCHANNEL");
			return PCSI_EAT_NONE;
		}
		
		# make sure user is registered and identified
		my $user = $self->{resident}->get_user($nick, 0);
		if (!$user || !$user->{Registered}) {
			$self->send_msg_to_user($nick, 'NOTICE', "Error: You must register your user account before you can register channels.  Please type: /msg nickserv register PASSWORD EMAIL");
			return PCSI_EAT_NONE;
		}
		if (!$user->{_identified}) {
			$self->send_msg_to_user($nick, 'NOTICE', "Error: You must login (identify) before you can register channels.  Please type: /msg nickserv identify PASSWORD");
			return PCSI_EAT_NONE;
		}
		
		# create channel record
		my $channel = $self->{resident}->get_channel($chan, 1);
		
		if ($channel->{Registered}) {
			$self->send_msg_to_user($nick, 'NOTICE', "Channel \#$chan is already registered.");
			return PCSI_EAT_NONE;
		}
		
		# Check user access level needed to register channel
		if (!$self->{config}->{FreeChannels} && !$user->{Administrator}) {
			$self->send_msg_to_user($nick, 'NOTICE', "Error: Only server administrators can register channels.");
			return PCSI_EAT_NONE;
		}
		
		# register it!
		$channel->{ID} = generate_unique_id();
		$channel->{Registered} = 1;
		$channel->{Founder} = lc($nick);
		$channel->{Users} = { lc($nick) => { Flags => 'o' } };
		
		$self->{resident}->save_channel($chan);
		
		$self->send_msg_to_user($nick, 'NOTICE', "Channel \#$chan has been successfully registered.");
		
		$ircd->yield('daemon_cmd_join', 'ChanServ', nch($chan));
	} # register
	
	elsif ($msg =~ /^drop\s+(\S+)$/i) {
		# drop channel
		my $chan = sch(lc($1));
		my $user = $self->{resident}->get_user($nick, 0);
		my $channel = $self->{resident}->get_channel($chan, 0);
		
		if (!$user || !$user->{Registered}) {
			$self->send_msg_to_user($nick, 'NOTICE', "Error: You must register your user account before you can manage channels.  Please type: /msg nickserv register PASSWORD EMAIL");
			return PCSI_EAT_NONE;
		}
		if (!$user->{_identified}) {
			$self->send_msg_to_user($nick, 'NOTICE', "Error: You must login (identify) before you can manage channels.  Please type: /msg nickserv identify PASSWORD");
			return PCSI_EAT_NONE;
		}
		
		if (!$channel || !$channel->{Registered}) {
			$self->send_msg_to_user($nick, 'NOTICE', "Channel \#$chan is not registered.");
			return PCSI_EAT_NONE;
		}
		
		if ($user->{Administrator} || ($channel->{Founder} eq lc($nick))) {
			# okay to delete
			$self->delete_channel($chan);
			
			# inform user
			$self->send_msg_to_user($nick, 'NOTICE', "Channel \#$chan has been successfully deleted.");
			
		} # user has perms
		else {
			$self->send_msg_to_user($nick, 'NOTICE', "Error: You do not have sufficient access privileges to drop this channel.");
			return PCSI_EAT_NONE;
		}
	} # drop channel
	
	elsif ($msg =~ /^access\s+(\S+)\s+(private|public)$/i) {
		# set channel access
		my $chan = sch(lc($1));
		my $access = lc($2);
		my $user = $self->{resident}->get_user($nick, 0);
		my $channel = $self->{resident}->get_channel($chan, 0);
		
		if (!$user || !$user->{Registered}) {
			$self->send_msg_to_user($nick, 'NOTICE', "Error: You must register your user account before you can manage channels.  Please type: /msg nickserv register PASSWORD EMAIL");
			return PCSI_EAT_NONE;
		}
		if (!$user->{_identified}) {
			$self->send_msg_to_user($nick, 'NOTICE', "Error: You must login (identify) before you can manage channels.  Please type: /msg nickserv identify PASSWORD");
			return PCSI_EAT_NONE;
		}
		
		if (!$channel || !$channel->{Registered}) {
			$self->send_msg_to_user($nick, 'NOTICE', "Channel \#$chan is not registered.");
			return PCSI_EAT_NONE;
		}
		
		if ($user->{Administrator} || ($channel->{Founder} eq lc($nick))) {
			# set access level
			$channel->{Private} = ($access eq 'private') ? 1 : 0;
			$self->{resident}->save_channel($chan);
			
			# set channel invite flag accordingly
			$ircd->daemon_server_mode($chan, ($channel->{Private} ? '+' : '-') . 'i');
			
			# sync user modes (kick the uninvited)
			$self->sync_all_user_modes($chan, '');
			
			# inform user
			$self->send_msg_to_user($nick, 'NOTICE', "Channel \#$chan access has been set to: " . uc($access));
			
		} # user has perms
		else {
			$self->send_msg_to_user($nick, 'NOTICE', "Error: You do not have sufficient access privileges to manage this channel.");
			return PCSI_EAT_NONE;
		}
		
	} # access
	
	elsif ($msg =~ /^help/i) {
		$self->do_plugin_help($nick, $msg);
	} # help
	
	return PCSI_EAT_NONE;
}

sub IRCD_daemon_join {
	my ($self, $ircd) = splice @_, 0, 2;
	my $nick = (split /!/, ${ $_[0] })[0];
	my $chan = ${ $_[1] };
	
	# $self->log_debug(9, "IRCD_daemon_join: " . Dumper(\@_));
	
	my $channel = $self->{resident}->get_channel($chan);
	if ($channel) {
		my $user_stub = $channel->{Users}->{ lc($nick) } || 0;
		my $user = $self->{resident}->get_user($nick) || 0;
		
		# private channel and user not on list?  kick!
		#if (($nick ne 'ChanServ') && $channel->{Private} && !$user_stub) {
		#	$ircd->daemon_server_kick($chan, $nick, "Private Channel");
		#	return PCSI_EAT_NONE;
		#}
		
		if ($user_stub && $user_stub->{Flags} && $user && $user->{_identified} && !$user->{Administrator}) { # operserv handles admins
			$ircd->daemon_server_mode($chan, '+'.$user_stub->{Flags}, $nick);
		}
		elsif (($channel->{Founder} eq lc($nick)) && $user && $user->{_identified} && !$user->{Administrator}) {
			# channel founder
			$ircd->daemon_server_mode($chan, '+o', $nick);
		}
		
		# set topic if user is first in the channel
		my $uchan = uc_irc( nch($chan) );
		my $record = $ircd->{state}{chans}{$uchan};
		if ($record && $record->{users} && (scalar keys %{$record->{users}} == 1)) {
			# $ircd->yield('daemon_cmd_topic', 'ChanServ', $chan, $channel->{Topic});
			# $ircd->_daemon_cmd_topic('ChanServ', $chan, $channel->{Topic});
			
			# my $route_id = $self->{ircd}->_state_user_route($nick);
			# die unless $route_id;
			# $self->{ircd}->_send_output_to_client(
			#	$route_id,
			#	(ref $_ eq 'ARRAY' ? @{ $_ } : $_),
			# ) for $self->{ircd}->_daemon_cmd_topic( 'ChanServ', $chan, $channel->{Topic} );
			
			my $crecord = $ircd->{state}{chans}{uc_irc($chan)};
			
			if ($channel->{Topic}) {
				$self->set_channel_topic($chan, $channel->{Topic});
			} # restore topic
			
			if ($channel->{Bans} && scalar @{$channel->{Bans}}) {
				$crecord->{bans} ||= {};
				
				foreach my $ban (@{$channel->{Bans}}) {
					my $ban_target = $ban->{TargetUser} . '@' . $ban->{TargetIP};
					$crecord->{bans}->{ uc($ban_target) } = [
						$ban_target,
						$ban->{AddedBy},
						$ban->{Created}
					];
				} # foreach ban
			} # restore bans
			
			# special channel modes (private, user limit)
			if ($channel->{Private}) {
				$ircd->daemon_server_mode($chan, '+i');
			}
			if ($channel->{UserLimit}) {
				$ircd->daemon_server_mode($chan, '+l', $channel->{UserLimit});
			}
			
		} # first user entering channel
	} # found channel
	elsif ($self->{config}->{RegForce}) {
		# force user to register channel before joining
		$self->{ircd}->daemon_server_kick( $chan, $nick, "Please register the channel before joining." );
		$self->send_msg_to_user($nick, 'NOTICE', "To register your channel, please type: /msg chanserv register " . nch($chan));
	}
	
	return PCSI_EAT_NONE;
}

sub IRCD_daemon_nick {
	my ($self, $ircd) = splice @_, 0, 2;
	my $nick = (split /!/, ${ $_[0] })[0];
	
	# use our own nick cmd as a init hook for joining channels
	if ($nick eq 'ChanServ') {
		foreach my $chan (@{$self->{resident}->get_all_channel_ids()}) {
			my $channel = $self->{resident}->get_channel($chan);
			if ($channel->{Registered}) {
				$ircd->yield('daemon_cmd_join', 'ChanServ', nch($chan));
				
				if ($channel->{Topic}) {
					# $ircd->yield('daemon_cmd_topic', 'ChanServ', $chan, $channel->{Topic});
				}
			}
		}
	}
	
	return PCSI_EAT_NONE;
}

sub IRCD_daemon_mode {
	my ($self, $ircd) = splice @_, 0, 2;
	
	$self->log_debug(9, "IRCD_daemon_mode: " . Dumper(\@_));
	
	my $nick = (split /!/, ${ $_[0] })[0];
	my $chan = ${ $_[1] };
	my $mode = ${ $_[2] };
		
	if (ref($_[3]) eq 'ARRAY') { return PCSI_EAT_NONE; } # channel mode, not user mode
	
	my $target_nick = ${ $_[3] };
	
	my $channel = $self->{resident}->get_channel($chan);
	if ($channel) {
		if ($mode eq '+b') {
			# add ban
			my $ban_target = lc($target_nick);
			$channel->{Bans} ||= [];
			
			$ban_target =~ /^(.+)\@(.+)$/;
			my ($ban_target_user, $ban_target_ip) = ($1, $2);
			
			if (!find_object( $channel->{Bans}, { TargetUser => $ban_target_user, TargetIP => $ban_target_ip } )) {
				my $now = time();
				push @{$channel->{Bans}}, {
					TargetUser => $ban_target_user,
					TargetIP => $ban_target_ip,
					AddedBy => ${ $_[0] },
					Created => $now,
					Expires => $now + (86400 * $self->{config}->{ChannelBanDays})
				};
				$self->{resident}->save_channel($chan);
			} # new ban
		} # add ban
		elsif ($mode eq '-b') {
			# remove ban
			my $ban_target = lc($target_nick);
			$channel->{Bans} ||= [];
			
			$ban_target =~ /^(.+)\@(.+)$/;
			my ($ban_target_user, $ban_target_ip) = ($1, $2);
			
			if (delete_object( $channel->{Bans}, { TargetUser => $ban_target_user, TargetIP => $ban_target_ip } )) {
				$self->{resident}->save_channel($chan);
			} # found ban
		} # remove ban
		elsif ($self->{resident}->get_user($target_nick, 0)) {
			# set user mode and remember it, but ONLY if nick is registered and identified
			my $user = $self->{resident}->get_user( $target_nick );
			my $cuser = $channel->{Users}->{ lc($target_nick) } ||= { Flags => '' };
			
			my $unick = uc_irc($target_nick);
			my $record = $ircd->{state}{users}{$unick};
			
			my $uchan = uc( nch($chan) );
			if ($record && $record->{chans} && $user && $user->{Registered} && $user->{_identified}) {
				$cuser->{Flags} = $record->{chans}->{$uchan} || '';
				$self->{resident}->log_debug(4, "Permanently setting user $target_nick flags in channel $chan: " . ($cuser->{Flags} || 'n/a'));
				if (!$cuser->{Flags}) { delete $channel->{Users}->{ lc($target_nick) }; }
				$self->{resident}->save_channel($chan);
			}
		} # user mode
	} # got channel
	
	return PCSI_EAT_NONE;
}

sub IRCD_daemon_topic {
	my ($self, $ircd) = splice @_, 0, 2;
	my $nick = (split /!/, ${ $_[0] })[0];
	my $chan = ${ $_[1] };
	my $topic = ${ $_[2] };
	
	# $self->log_debug(9, "IRCD_daemon_topic: " . Dumper(\@_));
	
	# ignore topics we set ourselves
	if ($nick eq 'ChanServ') { return PCSI_EAT_NONE; }
	
	my $channel = $self->{resident}->get_channel($chan);
	if ($channel) {
		$channel->{Topic} = $topic;
		$self->{resident}->save_channel($chan);
	}
	
	return PCSI_EAT_NONE;
}

sub tick {
	# called every second
	my $self = shift;
	$self->schedule_idle();
}

sub cmd_from_client {
	# called for every command entered by every user
	my ($self, $nick, $input) = @_;
	
	# print "ChanServ cmd_from_client: " . Dumper($input);
	
	if (($input->{command} eq 'PRIVMSG') && ($input->{params}->[0] =~ /^\#\w+/) && ($input->{params}->[1] =~ /^\!(([vhas]op)|sync)/i)) {
		my ($chan, $msg) = @{$input->{params}};
		
		my $channel = $self->{resident}->get_channel($chan) || 0;
		if (!$channel || !$channel->{Registered}) {
			$self->send_msg_to_channel($chan, 'NOTICE', "Error: Can only use ChanServ commands in registered channels.");
			return;
		}
		
		# make sure calling user is op or higher
		my $is_op = 0;
		my $user_stub = $channel->{Users}->{lc($nick)} || {};
		$user_stub->{Flags} ||= '';
		if ($user_stub->{Flags} =~ /o/) { $is_op = 1; }
		if (!$is_op && $self->{resident}->is_admin($nick)) { $is_op = 1; }
		
		# special-case: hops can manipulate the vop
		if (($user_stub->{Flags} =~ /h/) && ($msg =~ /^\!vop\s+/i)) { $is_op = 1; }
		
		if (!$is_op) {
			$self->send_msg_to_channel($chan, 'NOTICE', "Error: You are not an op in $chan, so you cannot use ChanServ commands.");
			return;
		}
		
		if ($msg =~ /^\!([vhas])op\s+(add|remove|del)\s+(\w+)/i) {
			my ($flag, $cmd, $target_nick) = ($1, $2, $3);
			$flag = lc($flag);
			$cmd = lc($cmd); $cmd =~ s/del/remove/;
			
			my $user = $self->{resident}->get_user($target_nick) || 0;
			if (!$user || !$user->{Registered}) {
				$self->send_msg_to_channel($chan, 'NOTICE', "Error: Can only use xOP commands on registered users.");
				return;
			}
			
			# 'aop' just means 'op'
			if ($flag eq 'a') { $flag = 'o'; }
			
			# special handling for 's' mode (admin)
			if ($flag eq 's') {
				# super-admin
				if (!$self->{resident}->is_admin($nick)) {
					$self->send_msg_to_channel($chan, 'NOTICE', "Error: Only administrators may use the SOP command.");
					return;
				}
				if ($cmd eq 'add') {
					if (!$user->{Administrator}) {
						$user->{Administrator} = 1;
						$self->{resident}->save_user($target_nick);
						$self->send_msg_to_channel($chan, 'NOTICE', "User '$target_nick' is now a server administrator.");
						
						if ($user->{_identified}) {
							$self->schedule_event( '', {
								action => sub {
									my $nickserv = $self->{ircd}->plugin_get( 'NickServ' );
									$nickserv->auto_oper_check( $target_nick, 'username-unused', 'password-unused' );
									$self->sync_all_user_modes('', $target_nick);
								}
							} );
						} # identified
					}
					else {
						$self->send_msg_to_channel($chan, 'NOTICE', "User '$target_nick' is already a server administrator.");
					}
				}
				else {
					if ($user->{Administrator}) {
						delete $user->{Administrator};
						$self->{resident}->save_user($target_nick);
						
						foreach my $temp_chan (@{$self->{resident}->get_all_channel_ids()}) {
							my $temp_channel = $self->{resident}->get_channel($temp_chan);
							if ($temp_channel && $temp_channel->{Users} && $temp_channel->{Users}->{lc($target_nick)}) {
								delete $temp_channel->{Users}->{lc($target_nick)};
								$self->{resident}->save_channel($temp_chan);
							}
						} # foreach channel
						
						if ($user->{_identified}) {
							$self->schedule_event( '', {
								action => sub {
									my $route_id = $self->{ircd}->_state_user_route($target_nick);
									if ($route_id) {
										$self->{ircd}->_send_output_to_client($route_id, $_)
											for $self->{ircd}->_daemon_cmd_umode($target_nick, '-o');
									}
									$self->sync_all_user_modes('', $target_nick);
								}
							} );
						} # identified
						
						$self->send_msg_to_channel($chan, 'NOTICE', "User '$target_nick' is no longer a server administrator.");
					}
					else {
						$self->send_msg_to_channel($chan, 'NOTICE', "User '$target_nick' is not a server administrator.");
					}
				}
			} # sop
			else {
				# voice, half or op in this channel
				if ($cmd eq 'add') {
					$channel->{Users}->{lc($target_nick)} ||= { Flags => '' };
					$channel->{Users}->{lc($target_nick)}->{Flags} = $flag;
					
					$self->send_msg_to_channel( $chan, 'PRIVMSG', 
						"User '$target_nick' added to the ".nch($chan)." Auto-".ucfirst($self->{mode_map}->{$flag})." list."
					);
				}
				else {
					delete $channel->{Users}->{lc($target_nick)};
					
					$self->send_msg_to_channel( $chan, 'PRIVMSG', 
						"User '$target_nick' removed from the ".nch($chan)." Auto-".ucfirst($self->{mode_map}->{$flag})." list." 
					);
				}
				$self->{resident}->save_channel($chan);
				
				$self->sync_all_user_modes($chan, $target_nick);
			}
		} # xOP add/remove
		
		elsif ($msg =~ /^\!([vhas])op\s+list$/i) {
			my $flag = lc($1);
			
			# 'aop' just means 'op'
			if ($flag eq 'a') { $flag = 'o'; }
			
			# special handling for 's' mode (admin)
			if ($flag eq 's') {
				# super-admin
				my $ulist = [];
				foreach my $temp_nick (@{$self->{resident}->get_all_user_ids()}) {
					my $temp_user = $self->{resident}->get_user($temp_nick);
					if ($temp_user->{Administrator}) { push @$ulist, $temp_nick; }
				}
				my $msg = '';
				if (scalar @$ulist) {
					$msg .= "The following users are server administrators: " . join(', ', @$ulist);
				}
				else {
					$msg = "There are no server administrators listed.";
				}
				$self->send_msg_to_channel( $chan, 'PRIVMSG', $msg );
			}
			else {
				my $ulist = [];
				foreach my $temp_nick (sort keys %{$channel->{Users}}) {
					my $temp_user = $channel->{Users}->{$temp_nick};
					if ($temp_user->{Flags} && ($temp_user->{Flags} =~ /$flag/i)) { push @$ulist, $temp_nick; }
				}
				my $msg = '';
				if (scalar @$ulist) {
					$msg .= "The following users are on the ".nch($chan)." Auto-".ucfirst($self->{mode_map}->{$flag})." list: " . join(', ', @$ulist);
				}
				else {
					$msg = "There are no users on the ".nch($chan)." Auto-".ucfirst($self->{mode_map}->{$flag})." list.";
				}
				$self->send_msg_to_channel( $chan, 'PRIVMSG', $msg );
			} # not sop
		} # xOP list
		
		elsif ($msg =~ /^\!sync$/i) {
			# sync all users in current channel
			$self->sync_all_user_modes($chan, '');
		} # sync
		
	} # privmsg
}

sub sync_all_user_modes {
	# make sure all users in all channels have the correct modes
	my $self = shift;
	my $single_chan = shift || '';
	my $single_nick = shift || '';
	$single_nick = lc($single_nick);
	
	my $chans = $single_chan ? [lc(sch($single_chan))] : [keys %{$self->{resident}->{channels}}];
	$self->log_debug(5, "Syncronizing ".($single_nick ? $single_nick : 'all')." user modes in channels: " . join(', ', @$chans));
	
	foreach my $chan (@$chans) {
		my $uchan = uc_irc( nch($chan) );
		my $record = $self->{ircd}->{state}{chans}{$uchan} || 0;
		
		if ($record && $record->{users}) {
			my $channel = $self->{resident}->get_channel($chan);
			
			if ($channel && $channel->{Registered}) {
				foreach my $unick (keys %{$record->{users}}) {
					my $nick = $self->{ircd}->{state}->{users}->{$unick}->{nick};
					next if $nick =~ /^ChanServ$/i;
					next if $single_nick && ($single_nick ne lc($nick));
					
					my $cur_mode = $record->{users}->{$unick};
					
					# private channel and user not in list?  kick!
					if ($channel->{Private} && !$channel->{Users}->{lc($nick)}) {
						$self->log_debug(4, "Kicking user '$nick' out of private channel \#$chan");
						$self->{ircd}->daemon_server_kick( nch($chan), $nick, "Private Channel" );
					}
					elsif ($self->{ircd}->_state_user_banned($nick, nch($chan))) {
						$self->log_debug(4, "Kicking banned user '$nick' out of channel \#$chan");
						$self->{ircd}->daemon_server_kick( nch($chan), $nick, "Banned" );
					}
					else {
						my $target_mode = $channel->{Users}->{lc($nick)} ? ($channel->{Users}->{lc($nick)}->{Flags} || '') : '';
						
						my $user = $self->{resident}->get_user($nick);
						if ($user && $user->{Administrator}) { $target_mode = 'o'; }
						if (!$user || !$user->{_identified}) { $target_mode = ''; }
						
						if ($cur_mode ne $target_mode) {
							# my $mode_change = gen_mode_change($cur_mode, $target_mode);
							$self->log_debug(4, "Changing user mode for '$nick' in channel \#$chan from '$cur_mode' to '$target_mode'");
							
							# $self->{ircd}->daemon_server_mode(nch($chan), $mode_change, $nick);
							
							if (length($cur_mode)) {
								foreach my $ch (split(//, $cur_mode)) {
									if ($target_mode !~ /$ch/) {
										$self->{ircd}->daemon_server_mode(nch($chan), '-'.$ch, $nick);
										$cur_mode =~ s/$ch//;
									}
								}
							}
							if (length($target_mode)) {
								foreach my $ch (split(//, $target_mode)) {
									if ($cur_mode !~ /$ch/) {
										$self->{ircd}->daemon_server_mode(nch($chan), '+'.$ch, $nick);
									}
								}
							}
							
						} # need mode change
					} # non-private
				} # foreach nick in chan
			} # registered chan
		} # found chan, has users
	} # foreach chan
}

sub run_daily_maintenance {
	# remove expired bans
	my $self = shift;
	my $now = time();
	
	$self->log_maint("Checking channel bans for expiration");
	
	foreach my $chan (@{$self->{resident}->get_all_channel_ids()}) {
		my $channel = $self->{resident}->get_channel($chan);
		
		if ($channel && $channel->{Bans} && ref($channel->{Bans})) {
			my $crecord = $self->{ircd}->{state}{chans}{uc_irc($chan)} || 0;
			my $need_save = 0;
			
			foreach my $ban (@{$channel->{Bans}}) {
				if ($ban->{Expires} <= $now) {
					$self->{resident}->log_maint("Removing expired \#$chan channel ban: " . json_compose($ban));
					
					delete_object( $channel->{Bans}, { TargetUser => $ban->{TargetUser}, TargetIP => $ban->{TargetIP} } );
					$need_save = 1;
					
					if ($crecord && ref($crecord) && $crecord->{bans} && ref($crecord->{bans})) {
						# also remove it from active irc channel data structure in memory
						delete $crecord->{bans}->{ uc($ban->{TargetUser} . '@' . $ban->{TargetIP}) };
					}
				} # expired ban
			} # foreach ban
			
			if ($need_save) {
				$self->{resident}->save_channel($chan);
			}
		} # good channel
	} # foreach channel
}

sub set_channel_topic {
	# set topic in channel
	my ($self, $chan, $topic) = @_;
	
	my $crecord = $self->{ircd}->{state}{chans}{uc_irc(nch($chan))};
	if (!$crecord) { return 0; }
	
	$crecord->{topic} = [
	    $topic,
	    $self->{ircd}->state_user_full('ChanServ'),
	    time,
	];
	
	$self->send_msg_to_channel( $chan, 'TOPIC', $topic );
	return 1;
}

sub delete_channel {
	# delete (drop) channel
	my ($self, $chan) = @_;
	
	my $channel = $self->{resident}->get_channel($chan);
	if (!$channel) { return 0; }
	
	# if force-reg is enabled, kick everyone out of room
	if ($self->{config}->{RegForce}) {
		my $uchan = uc_irc( nch($chan) );
		my $record = $self->{ircd}->{state}{chans}{$uchan} || 0;
		if ($record && $record->{users}) {
			foreach my $cnick (keys %{$record->{users}}) {
				$cnick = lc($cnick);
				$self->log_debug(9, "Kicking $cnick out of \#$chan");
				$self->{ircd}->daemon_server_kick( nch($chan), $cnick, "Channel has been deleted." );
			}
		}
	}
	else {
		# otherwise, just drop everyone's privs incl. founder (except sops)
		$channel->{Users} = {};
		$self->sync_all_user_modes($chan, '');
		
		# always have chanserv leave tho
		my $cnick = 'chanserv';
		$self->log_debug(9, "Kicking $cnick out of \#$chan");
		$self->{ircd}->daemon_server_kick( nch($chan), $cnick, "Channel has been deleted." );
	}
	
	# release channel
	$self->{resident}->unload_channel($chan);
	
	# delete channel data file
	unlink( $self->{resident}->{channel_dir} . '/' . sch(lc($chan)) . '.json' );
	
	return 1;
}

1;

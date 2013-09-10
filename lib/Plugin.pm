package Plugin;

use strict;
use warnings;
use Tools;

##
# Base class for SimpleIRC Plugins
##

sub add_custom_command{
	# add custom IRC command like /ns
	my ($self, $cmd, $code) = @_;
	
	$self->log_debug(4, "Adding custom command: /".uc($cmd));
	
	my $wrapper = sub {
		my $ircd = shift;
		my $nick = shift;
		my $value = join(' ', @_);
		
		$code->( $self, $nick, $value );
		
		return () if wantarray;
		return [];
	};
	
	my $func_name = '_daemon_cmd_' . $cmd;
	eval '*POE::Component::Server::IRC::Simple::'.$func_name.' = $wrapper;';
}

sub send_msg_to_user {
	# send message or notice to user
	my ($self, $nick, $type, $msg) = @_;
	
	my ($package, undef, undef) = caller();
	$package =~ s/^(.+)::(\w+)$/$2/;
	
	my $route_id = $self->{ircd}->_state_user_route($nick);
	if (!$route_id) {
		my $unick = $self->{resident}->get_irc_username( $nick );
		if ($unick) { $route_id = $self->{ircd}->_state_user_route($unick); }
		if (!$route_id) { return; }
	}
	
	$self->log_debug(9, "Sending $type to $nick: $msg");
	
	foreach my $line (split(/\n/, $msg)) {
		next unless $line =~ /\S/;
		$self->{ircd}->_send_output_to_client( $route_id, {
			prefix  => $package,
			command => $type,
			params  => [ $nick, $line ]
		});
	}
	
	$self->{resident}->log_event(
		log => 'transcript',
		package => '0.0.0.0',
		level => $package,
		msg => "$type $nick $msg"
	);
}

sub send_msg_to_channel_user {
	# send message or notice to user inside channel
	# but don't broadcast to any other users in the channel (NEAT TRICK!)
	my ($self, $nick, $chan, $type, $msg) = @_;
	
	my ($package, undef, undef) = caller();
	$package =~ s/^(.+)::(\w+)$/$2/;
	
	my $route_id = $self->{ircd}->_state_user_route($nick);
	if (!$route_id) {
		my $unick = $self->{resident}->get_irc_username( $nick );
		if ($unick) { $route_id = $self->{ircd}->_state_user_route($unick); }
		if (!$route_id) { return; }
	}
	
	$self->log_debug(9, "Sending $type to $nick in $chan: $msg");
	
	foreach my $line (split(/\n/, $msg)) {
		next unless $line =~ /\S/;
		$self->{ircd}->_send_output_to_client( $route_id, {
			prefix  => $self->{ircd}->state_user_full($package),
			command => $type,
			params  => [ nch($chan), $line ]
		});
	}
	
	$self->{resident}->log_event(
		log => 'transcript',
		package => '0.0.0.0',
		level => $package,
		msg => "$type $nick $chan $msg"
	);
}

sub send_msg_to_channel {
	# send message to everyone in channel
	my ($self, $chan, $type, $msg) = @_;
	$chan = nch($chan);
	
	my ($package, undef, undef) = caller();
	$package =~ s/^(.+)::(\w+)$/$2/;
	
	$self->log_debug(9, "Sending $type to $chan: $msg");
	
	$self->{ircd}->_send_output_to_channel( $chan, { 
		prefix => $package, 
		command => $type, 
		params => [$chan, $msg] 
	} );
	
	$self->{resident}->log_event(
		log => 'transcript',
		package => '', # usually source ip
		level => $package,
		msg => "$type $chan $msg"
	);
}

sub do_plugin_help {
	# display help for plugin or specific command
	my ($self, $nick, $msg) = @_;
	
	my ($package, undef, undef) = caller();
	$package =~ s/^(.+)::(\w+)$/$2/;
	
	my $help_content = '';
	
	if ($msg =~ /^help$/i) {
		# general help for plugin
		my $help_file = "conf/help/Plugins/$package.txt";
		if (-e $help_file) { $help_content = load_file($help_file); }
		else { $help_content = "Sorry, there is no help available for $package."; }
	}
	elsif ($msg =~ /^help\s+(\w+)$/i) {
		# help for a specific command
		my $cmd = lc($1);
		my $help_file = "conf/help/Plugins/$package/$cmd.txt";
		if (-e $help_file) { $help_content = load_file($help_file); }
		else { $help_content = "Sorry, there is no help available for the ".uc($cmd)." command."; }
	}
	
	foreach my $line (split(/\n/, $help_content)) {
		if ($line =~ /\S/) {
			my $route_id = $self->{ircd}->_state_user_route($nick);
			if (!$route_id) { return; }
							
			$self->{ircd}->_send_output_to_client( $route_id, {
				prefix  => $package,
				command => 'PRIVMSG',
				params  => [ $nick, $line ]
			});
		} # line has non-whitespace
	} # foreach help line
}

sub schedule_idle {
	# run any schedudle items that are due
	my $self = shift;
	my $now = time();
	
	foreach my $id (keys %{$self->{schedule}}) {
		my $event = $self->{schedule}->{$id};
		
		if (!$event->{when} || !$event->{action}) {
			$self->log_debug(9, "Warning: Bad schedule entry, removing it: " . json_compose($event));
			delete $self->{schedule}->{$id};
			next;
		}
		
		if ($now >= $event->{when}) {
			my $func = $event->{action};
			
			if (ref($func)) { $func->( $event ); }
			else { $self->$func( $event ); }
			
			delete $self->{schedule}->{$id};
		}
	}
}

sub schedule_event {
	# schedule future event
	my ($self, $id, $event) = @_;
	if (!$id) { $id = generate_unique_id(); }
	$event->{when} ||= time();
	$self->{schedule}->{nnick($id)} = $event;
}

sub log_debug {
	# log debug message
	my ($self, $level, $msg) = @_;
	
	if ($level > $self->{resident}->{config}->{Logging}->{DebugLevel}) { return; }
	
	my ($package, undef, undef) = caller();
	$package =~ s/^(.+)::(\w+)$/$2/;
	
	$self->{resident}->log_event(
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
	
	$self->{resident}->log_event(
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
	
	$self->{resident}->log_event(
		log => 'maint',
		package => $package,
		code => '',
		msg => $msg
	);
}

1;

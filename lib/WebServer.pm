# Continuation of Simple.pm
# Web server functions

use strict;
use File::Basename;
use Time::Local;
use HTTP::Date;
use Digest::MD5 qw(md5_hex);
use VersionInfo;
use IRC::Utils ':ALL';

my $nice_log_cat_names = {
	transcript => 'Chat Transcript',
	debug => 'Debug Log',
	error => 'Error Log',
	maint => 'Maintenance Log'
};

sub handle_web_request {
	# handle incoming http request
	my $self = shift;
	my $args = {@_};
	my $request = $args->{request};
	my $response = $args->{response};
	my $ip = $args->{ip};
	
	my $uri = $request->uri();
	$uri =~ s@^\w+\:\/\/[\w\-\.\:]+@@;
	$self->log_debug(6, "Incoming HTTP request from $ip: " . $request->method() . " $uri");
	
	my $headers_raw = $request->headers()->as_string();
	$headers_raw =~ s/\r?\n/, /g;
	$self->log_debug(8, "Incoming HTTP headers: " . $headers_raw );
	
	if ($uri =~ m@^/api/(\w+)@) {
		# API Call
		my $func = 'api_' . $1;
		if ($self->can($func)) {
			my $query = parse_query($uri);
			my $post = {};
			my $files = {};
			
			if (($request->method() eq 'POST') && $request->content()) {
				my $content_type = $request->header('Content-Type');
				if ($content_type =~ /(javascript|json)/i) {
					# pure json post
					eval { $post = json_parse($request->content()); };
					if ($@) {
						my $error_msg = "Failed to parse JSON POST: $@";
						$self->log_error($error_msg);
						$response->code( 400 );
						$response->content( $error_msg );
						return;
					}
				}
				elsif ($content_type =~ /urlencoded/i) {
					# standard form post, x-www-form-urlcoded
					$post = parse_query( $request->content() );
				}
				elsif ($content_type =~ /multipart\/form-data\;\s*boundary\=(.+)$/) {
					# multipart form post (file uploads)
					my $boundary = trim($1); $boundary =~ s/(\W)/\\$1/g;
					my $body = $request->content();
					# $body =~ s/\r\n/\n/sg;
					# $body =~ s/\r/\n/sg;
					
					foreach my $chunk_raw (split(/$boundary/, $body)) {
						chomp $chunk_raw;
						if ($chunk_raw =~ /^(.+?)\r\n\r\n(.+)$/s) {
							my ($chunk_headers_raw, $chunk_body) = ($1, $2);
							
							$chunk_body =~ s/\r\n\-+$//;
							my $chunk_headers = {};
							foreach my $chunk_header_raw (split(/\r\n/, $chunk_headers_raw)) {
								if ($chunk_header_raw =~ /([\w\-]+)\:\s*(.+)$/) { $chunk_headers->{$1} = $2; }
							}
							my $cont_disp = $chunk_headers->{'Content-Disposition'} || '';
							if ($cont_disp && ($cont_disp =~ /\bname\=\"([^\"]+)\"/)) {
								my $chunk_id = $1;
								my $chunk = {
									id => $chunk_id,
									headers => $chunk_headers,
									content => $chunk_body
								};
								if ($cont_disp =~ /\bfilename\=\"([^\"]+)\"/) { 
									$chunk->{filename} = $1;
									$self->log_debug(7, "Received file upload: $chunk_id: " . $chunk->{filename} . ": " . length($chunk_body) . " bytes");
									$files->{$chunk_id} = $chunk;
								}
								else {
									# standard post key/value (not a file)
									$post->{$chunk_id} = $chunk_body;
								}
								# $post->{$chunk_id} = $chunk;
							}
						} # good chunk
					} # foreach multipart chunk
				} # multipart/form-data
				else {
					# unsupported content-type, just pass string
					$post = $request->content();
				}
			} # has POST content
			
			$self->log_debug(8, "Calling API: $func with: " . json_compose($post));
			
			my $resp_json = $self->$func(
				request => $request,
				response => $response,
				query => $query,
				post => $post,
				files => $files,
				uri => $uri,
				ip => $ip,
				client => $args->{client},
				heap => $args->{heap}
			);
			
			if ($resp_json) {
				if (!$resp_json->{Code}) { $resp_json->{Code} = 0; }
				my $content = json_compose_pretty($resp_json);
				my $content_type = 'text/json';
				
				if ($query->{callback}) {
					$content = $query->{callback} . '(' . $content . ');';
					$content_type = 'application/javascript';
				}
				
				$response->code( 200 );
				$response->header( 'Content-Type' => $content_type );
				$response->header( 'Content-Length' => length($content) );
				$response->content( $content );
				$self->log_debug(7, "JSON Response: HTTP " . $response->as_string());
			}
			else {
				# api handled response by itself, just echo headers
				$self->log_debug(7, "Custom API Response: HTTP " . $response->code() . ": " . $response->headers()->as_string());
			}
		} # supported api
		else {
			my $error_msg = "Unknown API Call: $uri";
			$self->log_error($error_msg);
			$response->code( 400 );
			$response->content( $error_msg );
		}
	}
	else {
		# send back static file		
		my $partial_path = $uri;
		$partial_path =~ s/\?.*$//; # strip query
		$partial_path =~ s/\.\.//g; # strip parent directory shortcuts
		$partial_path =~ s@//@/@g; # normalize double-slashes
		
		if ($partial_path !~ m@^/@) { $partial_path = '/' . $partial_path; }
		if ($partial_path =~ m@/$@) { $partial_path .= 'index.html'; }
		
		my $doc_root = $self->{config}->{WebServer}->{DocumentRoot};
		my $file_path = $doc_root . $partial_path;
		
		if (-e $file_path) {
			# found file, send back to client
			my $content = load_file($file_path);
			$response->code(200);
			$response->header( 'Content-Type' => guess_content_type($file_path) );
			$response->header( 'Content-Length' => length($content) );
			$response->header( 'Cache-Control' => 'max-age=86400' );
			$response->header( 'Last-Modified' => time2str( (stat($file_path))[9] ) );
			$response->content($content);
			
			my $out_headers_raw = $response->headers()->as_string();
			$out_headers_raw =~ s/\r?\n/, /g;
			$self->log_debug(7, "Outgoing HTTP Response: HTTP " . $response->code() . ": " . $out_headers_raw);
		}
		else {
			# file not found
			my $error_msg = "File not found: $uri";
			$self->log_error($error_msg);
			$response->code( 404 );
			$response->content( $error_msg );
		}
	}
}

sub api_echo {
	# just echo query back to client, for testing
	my $self = shift;
	my $args = {@_};
	
	return {
		Code => 0,
		Query => $args->{query}
	};
}

sub api_config {
	# send config object tree to client
	my $self = shift;
	my $args = {@_};
	my $query = $args->{query};
	
	my $config = deep_copy( $self->{config} );
	delete $config->{SecretKey};
		
	return {
		Code => 0,
		Config => $config,
		Version => get_version()
	};
}

sub api_config_for_edit {
	# send config object tree to client
	my $self = shift;
	my $args = {@_};
	my $query = $args->{query};
	
	# must be admin and logged in for this
	my $session = $self->require_session($args) or return { Code => 'session' };
	my $username = $session->{Username};
	
	if (!$self->is_admin($username)) {
		return { Code => 1, Description => "You must be a server administrator to edit the configuration." };
	}
	
	return {
		Code => 0,
		Config => $self->{config},
		Version => get_version()
	};
}

sub api_check_version {
	# call home to get latest version for our branch
	my $self = shift;
	my $args = {@_};
	my $query = $args->{query};
	my $branch = $query->{branch};
	
	my $resp = wget("http://effectsoftware.com/software/simpleirc/version-$branch.json", 5);
	if ($resp->is_success()) {
		my $json_raw = $resp->content();
		my $json = undef;
		eval { $json = json_parse($json_raw); };
		if ($json) {
			return {
				Code => 0,
				Version => {
					Major => $json->{version},
					Minor => $json->{build},
					BuildDate => $json->{date},
					BuildID => $json->{id}
				}
			};
		}
		else {
			return {
				Code => 1,
				Description => "Failed to fetch version information from update server: " . ($@ || "Unknown Error")
			};
		}
	}
	else {
		return {
			Code => $resp->code(), 
			Description => "Failed to fetch version information from update server: " . $resp->status_line() 
		};
	}
}

sub get_server_status {
	# get current server status
	my $self = shift;
	my $status = {};
	
	# hostname
	$status->{Hostname} = $self->{hostname};
	
	# uptime
	$status->{Now} = time();
	$status->{ServerStarted} = $self->{time_start};
	
	# total users online
	my $num_users_online = 0;
	foreach my $unick (keys %{$self->{ircd}->{state}->{users}}) {
		my $user = $self->{ircd}->{state}->{users}->{$unick};
		if ($user->{route_id} ne 'spoofed') { $num_users_online++; }
	}
	$status->{NumUsersOnline} = $num_users_online;
	
	# total registered users
	my $all_user_ids = $self->get_all_user_ids();
	$status->{TotalRegisteredUsers} = scalar @$all_user_ids;
	
	# total registered channels
	my $all_channel_ids = $self->get_all_channel_ids();
	$status->{TotalRegisteredChannels} = scalar @$all_channel_ids;
	
	# total messages sent for the day
	$status->{TotalMessagesSent} = $self->{ircd}->{total_messages_sent} || 0;
	
	# total bytes transferred for the day
	$status->{TotalBytesIn} = $self->{ircd}->{total_bytes_in} || 0;
	$status->{TotalBytesOut} = $self->{ircd}->{total_bytes_out} || 0;
	
	# cpu
	# memory
	my $total_cpu = 0;
	my $total_mem = 0;
	my $ps_bin = find_bin('ps');
	if ($ps_bin) {
		foreach my $line (split(/\n/, `$ps_bin -eo "pid \%cpu rss"`)) {
			# 95666   0.0   2168
			if ($line =~ /(\d+)\s+([\d\.]+)\s+(\d+)/) {
				my ($pid, $cpu, $mem) = ($1, $2, $3);
				if ($pid == $$) {
					$total_cpu += $cpu;
					$total_mem += $mem;					
				}
			}
		}
	}
	$total_mem *= 1024; # comes as K, we want bytes
	$status->{TotalCPUPct} = $total_cpu;
	$status->{TotalMemBytes} = $total_mem;
	
	# disk usage
	my $total_disk_usage = 0;
	my $du_bin = find_bin('du');
	if ($du_bin) {
		my $du_raw = `$du_bin -sk .`;
		if ($du_raw =~ /(\d+)/) {
			my $disk_kbytes = int($1);
			$total_disk_usage = $disk_kbytes * 1024;
		}
	}
	$status->{TotalDiskUsage} = $total_disk_usage;
	
	return $status;
}

sub api_get_server_status {
	# get current server status, uptime, etc.
	my $self = shift;
	my $args = {@_};
	my $query = $args->{query};
	my $session = $self->require_session($args) or return { Code => 'session' };
	my $username = $session->{Username};
	
	if (!$self->is_admin($username)) {
		return { Code => 1, Description => "You must be a server administrator to view the server status." };
	}
	
	my $status = $self->get_server_status();
	
	return {
		Code => 0,
		Status => $status
	};
}

sub get_user_info {
	# get info about user from irc server
	my ($self, $nick) = @_;
	my $info = {};
	$nick = nnick($nick);
	
	$info->{Channels} = {};
	foreach my $chan (@{$self->get_all_channel_ids()}) {
		my $channel = $self->get_channel($chan);
		next if $channel->{Private} && !$channel->{Users}->{$nick};
		next if !$channel->{Users}->{$nick};
		
		my $chan_info = {
			Founder => $channel->{Founder},
			Topic => $channel->{Topic},
			Created => $channel->{Created},
			Modified => $channel->{Modified},
			Private => $channel->{Private} || 0
		};
		
		my $flags = $channel->{Users}->{$nick}->{Flags} || '';
		if ($channel->{Founder} eq $nick) { $flags .= 'f'; }
		$chan_info->{Flags} = $flags;
		
		if ($self->{ircd}->_state_user_banned($nick, nch($chan))) {
			$chan_info->{Banned} = 1;
		}
		my $irc_chan = $self->{ircd}->{state}->{chans}->{uc(nch($chan))} || 0;
		if ($irc_chan && $irc_chan->{users}) {
			if ($irc_chan->{users}->{uc($nick)}) {
				$chan_info->{Live} = 1;
			}
			$chan_info->{NumLiveUsers} = scalar keys %{$irc_chan->{users}};
			if ($channel->{Registered} && $self->{config}->{Plugins}->{ChanServ}->{Hide}) { $chan_info->{NumLiveUsers}--; } # chanserv
		}
		
		$info->{Channels}->{$chan} = $chan_info;
	} # foreach channel
	
	return $info;
}

sub api_login {
	# log user in, create new session
	my $self = shift;
	my $args = {@_};
	my $json = $args->{post};
	my $username = nnick($json->{Username});
	my $password = $json->{Password};
	
	$self->log_debug(6, "User logging in: $username");
	
	my $user = $self->get_user($username, 0);
	if (!$user) { return { Code => 1, Description => "The username / password combination you entered is incorrect." }; }
	
	if (md5_hex($password . $user->{ID}) ne $user->{Password}) {
		return { Code => 1, Description => "The username / password combination you entered is incorrect." };
	}
	
	my $session_id = generate_unique_id();
	my $session = {
		Username => $username,
		Created => time(),
		Modified => time()
	};
	$self->{sessions}->{$session_id} = $session;
	
	return {
		Code => 0,
		Username => $username,
		User => $user,
		SessionID => $session_id,
		Info => $self->get_user_info($username)
	};
}

sub api_resume_session {
	# log user in, resume existing session
	my $self = shift;
	my $args = {@_};
	my $json = $args->{post};
	my $session_id = $json->{SessionID};
	
	$self->log_debug(6, "Resuming session: $session_id");
	
	my $session = $self->{sessions}->{$session_id} || undef;
	if (!$session) {
		# return non-error error, so UI can redirect without showing error
		return { Code => 0, Description => "Session not found, please re-login." };
	}
	
	my $username = $session->{Username};
	my $user = $self->get_user($username, 0);
	if (!$user) { return { Code => 1, Description => "User not found: $username" }; }
	
	$session->{Modified} = time();
	
	return {
		Code => 0,
		Username => $username,
		User => $user,
		SessionID => $session_id,
		Info => $self->get_user_info($username)
	};
}

sub api_get_user_info {
	# return info about user
	my $self = shift;
	my $args = {@_};
	my $json = $args->{post};
	my $session = $self->require_session($args) or return { Code => 'session' };
	my $username = $session->{Username};
	$json->{Username} = nnick($json->{Username});
	
	if ($json->{Username} && ($json->{Username} ne $username)) {
		# trying to edit someone else's account -- must be admin to continue
		if (!$self->is_admin($username)) {
			return { Code => 1, Description => "You must be a server administrator to edit user accounts." };
		}
		$username = $json->{Username};
	}
	
	my $user = $self->get_user($username, 0);
	if (!$user) { 
		return { Code => 1, Description => "User not found: $username" }; 
	}
	
	my $status = 0;
	if ($self->is_admin($username)) {
		$status = $self->get_server_status();
	}
	
	return {
		Code => 0,
		User => $user,
		Info => $self->get_user_info($username),
		Status => $status
	};
}

sub api_logout {
	# log user out, destroy session
	my $self = shift;
	my $args = {@_};
	my $session_id = $args->{SessionID};
	
	#if (!$self->{sessions}->{$session_id}) {
	#	return { Code => 1, Description => "Session not found: $session_id" };
	#}
	
	delete $self->{sessions}->{$session_id};
	
	return {
		Code => 0
	};
}

sub require_session {
	# extract session id from cookie and make sure it is valid
	my ($self, $args) = @_;
	
	my $cookie_raw = $args->{request}->header('Cookie') || '';
	if (!$cookie_raw) { return 0; }
	
	my $cookie = {};
	if ($cookie_raw =~ /CookieTree\=([^\;]+)/) {
		my $json_raw = uri_unescape($1);
		eval { $cookie = json_parse($json_raw); };
		if ($@) {
			$self->log_debug(2, "Warning: Corrupted JSON in cookie: $cookie_raw: $@");
			return 0;
		}
	}
	if (!$cookie->{session_id}) { return 0; }
	my $session_id = $cookie->{session_id};
	my $session = $self->{sessions}->{$session_id} || 0;
	
	if ($session) { $session->{Modified} = time(); }
	
	return $session;
}

sub api_forgot_password {
	# send e-mail to user with instructions for resetting password
	my $self = shift;
	my $args = {@_};
	my $json = $args->{post};
	my $username = nnick($json->{Username});
	
	my $user = $self->get_user($username, 0);
	if (!$user) { 
		return { Code => 1, Description => "User not found: $username" }; 
	}
	
	if (lc($json->{Email}) ne lc($user->{Email})) { 
		return { Code => 1, Description => "The e-mail address you entered does not match our records." }; 
	}
	
	if (!$self->send_user_password_reset_email($username)) {
		return { Code => 1, Description => "Could not send e-mail. Please try again later." };
	}
	
	return {
		Code => 0
	};
}

sub api_get_all_users {
	# get list of all users
	my $self = shift;
	my $args = {@_};
	my $query = $args->{query};
	my $session = $self->require_session($args) or return { Code => 'session' };
	my $username = $session->{Username};
	my $self_admin = $self->is_admin($username);
	
	if (!$self->is_admin($username)) {
		return { Code => 1, Description => "You must be a server administrator to view the full user list." };
	}
	
	$query->{offset} ||= 0;
	$query->{limit} ||= 20;
	
	my $irc_users = $self->{ircd}->{state}->{users} || {};
	my $user_ids = {};
	
	foreach my $temp_nick (@{$self->get_all_user_ids()}) {
		$user_ids->{$temp_nick} = $temp_nick;
	}
	
	foreach my $temp_nick (keys %$irc_users) {
		if ($irc_users->{$temp_nick}->{route_id} ne 'spoofed') {
			$user_ids->{nnick($temp_nick)} = $temp_nick;
		}
	}
	
	# sort by username
	my $sorted_user_ids = [ sort keys %$user_ids ];
	my $total_users = scalar @$sorted_user_ids;
	my $rows = [];
	
	foreach my $temp_nick (splice(@$sorted_user_ids, $query->{offset}, $query->{limit})) {
		my $temp_irc_nick = $user_ids->{$temp_nick};
		my $row = {
			Username => $temp_nick,
			Live => defined($irc_users->{uc_irc($temp_irc_nick)}) ? 1 : 0
		};
		
		if ($query->{filter} && ($query->{filter} =~ /online/i) && !$row->{Live}) {
			$total_users--;
			next;
		}
		if ($query->{keyword} && ($temp_nick !~ /$query->{keyword}/i)) {
			$total_users--;
			next;
		}
		
		my $unick = uc_irc($temp_irc_nick);
		my $crecord = $self->get_irc_user_record($unick);
		if ($crecord) {
			$row->{Ident} = $crecord->{auth}->{ident};
			$row->{Host} = $crecord->{auth}->{hostname};
			$row->{FullIdent} = $crecord->{nick} . '!' . $crecord->{auth}->{ident} . '@' . $crecord->{auth}->{hostname};
			if ($self_admin) { $row->{IP} = $crecord->{socket}->[0]; }
		}
		
		my $temp_user = $self->get_user($temp_nick) || {};
		foreach my $key (keys %$temp_user) {
			if (!defined($row->{$key}) && ($key ne 'Password')) { $row->{$key} = $temp_user->{$key}; }
		}
		$row->{FullName} ||= '';
		$row->{Registered} ||= 0;
		
		push @$rows, $row;
	} # foreach user
	
	return {
		Code => 0,
		List => { length => $total_users },
		Rows => { Row => $rows }
	};
}

sub api_user_create {
	# create new user
	my $self = shift;
	my $args = {@_};
	my $json = $args->{post};
	my $session = $self->require_session($args) or return { Code => 'session' };
	my $username = $session->{Username};
	
	if (!$self->is_admin($username)) {
		return { Code => 1, Description => "You must be a server administrator to create new users." };
	}
	
	if (!is_valid_nick_name($json->{Username})) {
		return { Code => 1, Description => "The username you entered is not a valid IRC nickname." };
	}
	
	my $disp_username = $json->{Username};
	$json->{Username} = nnick($json->{Username});
	if (!length($json->{Username})) {
		return { Code => 1, Description => "The username you entered is invalid (must contain alphanumerics, not in brackets)" };
	}
	
	if (length($json->{Username}) > $self->{config}->{MaxNickLength}) {
		return { Code => 1, Description => "Usernames must be " . $self->{config}->{MaxNickLength} . " characters or less." };
	}
	
	my $user = $self->get_user($json->{Username}, 0);
	if ($user) {
		return { Code => 1, Description => "User already exists: " . $json->{Username} }; 
	}
	
	if ($json->{Aliases}) {
		my $err_msg = $self->validate_user_aliases($json->{Username}, $json->{Aliases});
		if ($err_msg) { return { Code => 1, Description => $err_msg }; }
	}
	
	$user = $self->get_user($json->{Username}, 1);
	
	$user->{DisplayUsername} = $disp_username;
	$user->{FullName} = $json->{FullName};
	$user->{Email} = $json->{Email};
	$user->{ID} = generate_unique_id();
	$user->{Password} = md5_hex( $json->{Password} . $user->{ID} );
	$user->{Registered} = 1;
	$user->{Status} = $json->{Status};
	$user->{Administrator} = $json->{Administrator} || 0;
	$user->{Aliases} = $json->{Aliases} || [];
	
	$self->save_user($json->{Username});
	
	return {
		Code => 0,
		User => $user
	};
}

sub api_user_update {
	# update user info
	my $self = shift;
	my $args = {@_};
	my $json = $args->{post};
	my $session = $self->require_session($args) or return { Code => 'session' };
	my $username = $session->{Username};
	my $self_admin = $self->is_admin($username);
	
	$json->{Username} = nnick($json->{Username});
	
	if ($json->{Username} && ($json->{Username} ne $username)) {
		# trying to update someone else's account -- must be admin to continue
		if (!$self_admin) {
			return { Code => 1, Description => "You must be a server administrator to update user accounts." };
		}
		$username = $json->{Username};
	}
	
	my $user = $self->get_user($username, 0);
	if (!$user) { 
		return { Code => 1, Description => "User not found: $username" }; 
	}
	my $old_user = { %$user }; # shallow copy
	
	if ($json->{Aliases}) {
		my $err_msg = $self->validate_user_aliases($json->{Username}, $json->{Aliases});
		if ($err_msg) { return { Code => 1, Description => $err_msg }; }
		$user->{Aliases} = $json->{Aliases};
		
		if (!$self_admin && $user->{_identified}) {
			# auto-set modes if user is already in channels
			my $chanserv = $self->{ircd}->plugin_get( 'ChanServ' );
			$chanserv->sync_all_user_modes( '', $username );
		}
	} # aliases
	
	$user->{FullName} = $json->{FullName};
	$user->{Email} = $json->{Email};
	
	if ($json->{Password}) {
		# changing password
		$user->{Password} = md5_hex( $json->{Password} . $user->{ID} );
	}
	
	if ($self_admin) {
		if (defined($json->{Administrator})) { $user->{Administrator} = $json->{Administrator}; }
		if (!$user->{Administrator}) { delete $user->{Administrator}; }
		
		if (defined($json->{Status})) { $user->{Status} = $json->{Status}; }
		
		# if user is suspended, see if we have to kick out a live user	
		if ($user->{_identified}) {
			my $unick = $self->get_irc_username($username);
			
			if (($user->{Status} =~ /suspended/i)) {
				$self->{ircd}->daemon_server_kill( $unick, "Account suspended" );
			}
			else {
				if ($user->{Administrator} && !$old_user->{Administrator}) {
					my $nickserv = $self->{ircd}->plugin_get( 'NickServ' );
					$nickserv->auto_oper_check($username, 1, 1);
				} # giveth admin
				elsif (!$user->{Administrator} && $old_user->{Administrator}) {
					my $route_id = $self->{ircd}->_state_user_route($unick);
					if ($route_id) {
						$self->{ircd}->_send_output_to_client($route_id, $_)
							for $self->{ircd}->_daemon_cmd_umode($unick, '-o');
					}
				} # taketh away admin
				
				# auto-set modes if user is already in channels
				my $chanserv = $self->{ircd}->plugin_get( 'ChanServ' );
				$chanserv->sync_all_user_modes( '', $username );
			}
		} # _identified
	}
	
	$self->save_user($username);
	
	return {
		Code => 0,
		User => $user
	};
}

sub api_user_delete {
	# delete user account (drop nick)
	my $self = shift;
	my $args = {@_};
	my $json = $args->{post};
	my $session = $self->require_session($args) or return { Code => 'session' };
	my $username = $session->{Username};
	
	$json->{Username} = nnick($json->{Username});
	
	if ($json->{Username} && ($json->{Username} ne $username)) {
		# trying to delete someone else's account -- must be admin to continue
		if (!$self->is_admin($username)) {
			return { Code => 1, Description => "You must be a server administrator to delete user accounts." };
		}
		$username = $json->{Username};
	}
	
	my $user = $self->get_user($username, 0);
	if (!$user) { 
		return { Code => 1, Description => "User not found: $username" }; 
	}
	delete $user->{Administrator};
	
	# delete all privs in all channels
	foreach my $temp_chan (@{$self->get_all_channel_ids()}) {
		my $temp_channel = $self->get_channel($temp_chan);
		if ($temp_channel && $temp_channel->{Users} && $temp_channel->{Users}->{lc($username)}) {
			delete $temp_channel->{Users}->{lc($username)};
			$self->save_channel($temp_chan);
		}
	} # foreach channel
	
	# sync all privs
	my $chanserv = $self->{ircd}->plugin_get( 'ChanServ' );
	$chanserv->sync_all_user_modes( '', $username );
	
	# free up memory from old nick
	$self->unload_user($username);
	
	# delete user record from disk
	unlink( $self->{user_dir} . '/' . lc($username) . '.json' );
	
	# boot user from irc
	if ($user->{_identified}) {
		my $unick = $self->get_irc_username($username);
		$self->{ircd}->daemon_server_kill( $unick, "Account deleted" );
	}
	
	# remove any aliases associated with account
	update_user_aliases( $username, [], 1 );
	
	return {
		Code => 0
	};
}

sub api_channel_create {
	# create new channel
	my $self = shift;
	my $args = {@_};
	my $json = $args->{post};
	my $session = $self->require_session($args) or return { Code => 'session' };
	my $username = $session->{Username};
	
	# make sure user has permission to create channels
	if (!$self->{config}->{Plugins}->{ChanServ}->{FreeChannels} && !$self->is_admin($username)) {
		return { Code => 1, Description => "You must be a server administrator to create channels." };
	}
	
	my $chan = lc(sch($json->{Name}));
	
	# create channel record
	my $channel = $self->get_channel($chan, 1);
	
	if ($channel->{Registered}) {
		return { Code => 1, Description => "Channel \#$chan is already registered." };
	}
	
	# register it!
	$channel->{ID} = generate_unique_id();
	$channel->{Registered} = 1;
	$channel->{Founder} = nnick($json->{Founder});
	$channel->{Users} = { lc($username) => { Flags => 'o' } };
	$channel->{Topic} = $json->{Topic} || '';
	$channel->{Private} = $json->{Private} || 0;
	$channel->{URL} = $json->{URL} || '';
	$channel->{JoinNotice} = $json->{JoinNotice} || '';
	
	foreach my $key (keys %$json) {
		if ($key =~ /^Guest\w+$/) { $channel->{$key} = $json->{$key}; }
	}
	
	$self->save_channel($chan);
		
	$self->{ircd}->yield('daemon_cmd_join', 'ChanServ', nch($chan));
	
	return {
		Code => 0
	};
}

sub api_channel_get {
	# get channel record for editing
	my $self = shift;
	my $args = {@_};
	my $json = $args->{post};
	my $session = $self->require_session($args) or return { Code => 'session' };
	my $username = $session->{Username};
	
	my $chan = lc(sch($json->{Name}));
	
	# get channel record
	my $channel = $self->get_channel($chan, 0);
	if (!$channel) {
		return { Code => 1, Description => "Channel not found: \#$chan" };
	}
	
	return {
		Code => 0,
		Channel => $channel
	};
}

sub api_get_all_channels {
	# get full list of all channels
	my $self = shift;
	my $args = {@_};
	my $query = $args->{query};
	my $session = $self->require_session($args) or return { Code => 'session' };
	my $username = $session->{Username};
	my $self_admin = $self->is_admin($username);
	
	$query->{offset} ||= 0;
	$query->{limit} ||= 20;
	
	my $all_channel_ids = $self->get_all_channel_ids();
	my $total_channels = scalar @$all_channel_ids;
	my $rows = [];
	
	foreach my $chan (splice(@$all_channel_ids, $query->{offset}, $query->{limit})) {
		my $channel = $self->get_channel($chan);
		# next if $channel->{Private} && !$channel->{Users}->{$username};
		if ($channel->{Private} && (!$channel->{Users}->{$username} && !$self->is_admin($username))) {
			$total_channels--;
			next;
		}
		
		my $chan_info = {
			Name => $chan,
			Founder => $channel->{Founder},
			Topic => $channel->{Topic},
			Created => $channel->{Created},
			Modified => $channel->{Modified},
			Private => $channel->{Private} || 0
		};
		
		my $flags = '';
		if ($channel->{Users}->{$username}) {
			$flags = $channel->{Users}->{$username}->{Flags} || '';
		}
		if ($channel->{Founder} eq $username) { $flags .= 'f'; }
		$chan_info->{Flags} = $flags;
		
		my $irc_chan = $self->{ircd}->{state}->{chans}->{uc(nch($chan))} || 0;
		if ($irc_chan && $irc_chan->{users}) {
			if ($irc_chan->{users}->{uc($username)}) {
				$chan_info->{Live} = 1;
			}
			$chan_info->{NumLiveUsers} = scalar keys %{$irc_chan->{users}};
			if ($channel->{Registered} && $self->{config}->{Plugins}->{ChanServ}->{Hide}) { $chan_info->{NumLiveUsers}--; } # chanserv
		}
		
		if ($self_admin || ($channel->{Founder} eq nnick($username)) || ($flags =~ /[ho]/i)) {
			$chan_info->{CanOp} = 1;
		}
		
		push @$rows, $chan_info;
	} # foreach channel
	
	return {
		Code => 0,
		List => { length => $total_channels },
		Rows => { Row => $rows }
	};
}

sub api_channel_update {
	# save changes to channel
	my $self = shift;
	my $args = {@_};
	my $json = $args->{post};
	my $session = $self->require_session($args) or return { Code => 'session' };
	my $username = $session->{Username};
	
	my $chan = lc(sch($json->{Name}));
	
	# get channel record
	my $channel = $self->get_channel($chan, 0);
	if (!$channel || !$channel->{Registered}) {
		return { Code => 1, Description => "Channel not found: \#$chan" };
	}
	
	# make sure user has permission (channel founder or admin)
	if (!$self->is_admin($username) && ($channel->{Founder} ne $username)) {
		return { Code => 1, Description => "You do not have sufficient access privileges to make changes to this channel." };
	}
	
	# change founder?
	if (nnick($json->{Founder}) ne $channel->{Founder}) {
		my $new_founder = $self->get_user($json->{Founder}, 0);
		if (!$new_founder) {
			return { Code => 1, Description => "User not found: " . $json->{Founder} };
		}
		$channel->{Founder} = nnick($json->{Founder});
	}
	
	my $chanserv = $self->{ircd}->plugin_get( 'ChanServ' );
	
	# update topic?  have chanserv fix it
	if ($json->{Topic} ne $channel->{Topic}) {
		$channel->{Topic} = $json->{Topic};
		$chanserv->set_channel_topic( $chan, $channel->{Topic} );
	}
	
	# change from private/public?  sync things, kick
	if ($json->{Private} ne $channel->{Private}) {
		$channel->{Private} = $json->{Private};
		
		# reset channel invite flag accordingly
		$self->{ircd}->daemon_server_mode($chan, ($channel->{Private} ? '+' : '-') . 'ip');
	}
	
	# other channel params
	$channel->{URL} = $json->{URL};
	$channel->{JoinNotice} = $json->{JoinNotice};
	
	foreach my $key (keys %$json) {
		if ($key =~ /^Guest\w+$/) { $channel->{$key} = $json->{$key}; }
	}
	
	# sync all user modes
	$chanserv->sync_all_user_modes( $chan, '' );
	
	# save channel to disk
	$self->save_channel($chan);
	
	return {
		Code => 0
	};
}

sub api_channel_delete {
	# delete (drop) channel
	my $self = shift;
	my $args = {@_};
	my $json = $args->{post};
	my $session = $self->require_session($args) or return { Code => 'session' };
	my $username = $session->{Username};
	
	my $chan = lc(sch($json->{Name}));
	
	# get channel record
	my $channel = $self->get_channel($chan, 0);
	if (!$channel || !$channel->{Registered}) {
		return { Code => 1, Description => "Channel not found: \#$chan" };
	}
	
	# make sure user has permission (channel founder or admin)
	if (!$self->is_admin($username) && ($channel->{Founder} ne $username)) {
		return { Code => 1, Description => "You do not have sufficient access privileges to delete this channel." };
	}
	
	my $chanserv = $self->{ircd}->plugin_get( 'ChanServ' );
	$chanserv->delete_channel( $chan );
	
	return {
		Code => 0
	};
}

sub api_channel_get_users {
	# get channel users (with limit/offset)
	# sorted by user mode, then by alphabetical
	# query: channel, offset, limit
	my $self = shift;
	my $args = {@_};
	my $query = $args->{query};
	my $session = $self->require_session($args) or return { Code => 'session' };
	my $username = $session->{Username};
	my $chan = lc(sch($query->{channel}));
	
	$query->{offset} ||= 0;
	$query->{limit} ||= 50;
	
	# get channel record
	my $channel = $self->get_channel($chan, 0);
	if (!$channel || !$channel->{Registered}) {
		return { Code => 1, Description => "Channel not found: \#$chan" };
	}
	
	# make sure user has permission (channel founder, hop, op or admin)
	my $self_flags = $self->get_channel_user_flags($chan, $username);
	if (!$self->is_admin($username) && ($channel->{Founder} ne $username) && ($self_flags !~ /[ho]/i)) {
		return { Code => 1, Description => "You do not have sufficient access privileges to administer this channel." };
	}
	
	my $uchan = uc_irc( nch($chan) );
	my $record = $self->{ircd}->{state}{chans}{$uchan} || {};
	my $cusers = $record->{users} || {};
	
	my $user_ids = {};
	foreach my $temp_nick (keys %{$channel->{Users}}) {
		if (($channel->{Users}->{$temp_nick} && $channel->{Users}->{$temp_nick}->{Flags}) || $channel->{Private}) {
			$user_ids->{nnick($temp_nick)} ||= 1;
		}
	}
	foreach my $temp_nick (keys %$cusers) {
		$user_ids->{nnick($temp_nick)} ||= 1;
	}
	if ($self->{config}->{Plugins}->{ChanServ}->{Hide}) {
		delete $user_ids->{chanserv};
	}
	
	my $users = {};
	foreach my $temp_nick (keys %$user_ids) {
		my $sort_level = 0;
		
		my $flags = '';
		my $unick = $self->get_irc_username( $temp_nick );
		if ($unick) { $flags = $cusers->{$unick} || ''; }
		
		if (!$flags && $channel->{Users}->{$temp_nick} && $channel->{Users}->{$temp_nick}->{Flags}) {
			$flags = $channel->{Users}->{$temp_nick}->{Flags};
		}
		if ($channel->{Founder} eq $temp_nick) { $sort_level = 4; }
		elsif ($flags =~ /o/i) { $sort_level = 3; }
		elsif ($flags =~ /h/i) { $sort_level = 2; }
		elsif ($flags =~ /v/i) { $sort_level = 1; }
		$users->{$temp_nick} = $sort_level;
	}
	
	# sort by value descending (user mode $sort_level), and then by alphabetic ascending (username ascending)
	my $sorted_user_ids = [ sort { ($users->{$a} != $users->{$b}) ? ($users->{$b} <=> $users->{$a}) : ($a cmp $b); } keys %$users ];
	
	my $total_users = scalar @$sorted_user_ids;
	my $rows = [];
	
	foreach my $temp_nick (splice(@$sorted_user_ids, $query->{offset}, $query->{limit})) {
		my $unick = $self->get_irc_username( $temp_nick );
		my $row = {
			Username => $temp_nick,
			Live => $unick && defined($cusers->{$unick}) ? 1 : 0
		};
		
		if ($query->{filter} && ($query->{filter} =~ /online/i) && !$row->{Live}) {
			$total_users--;
			next;
		}
		if ($query->{keyword} && ($temp_nick !~ /$query->{keyword}/i)) {
			$total_users--;
			next;
		}
		
		my $crecord = $self->get_irc_user_record($temp_nick);
		if ($crecord) {
			$row->{Ident} = $crecord->{auth}->{ident};
			$row->{Host} = $crecord->{auth}->{hostname};
			$row->{FullIdent} = $crecord->{nick} . '!' . $crecord->{auth}->{ident} . '@' . $crecord->{auth}->{hostname};
			if ($self->is_admin($username)) { $row->{IP} = $crecord->{socket}->[0]; }
		}
		
		my $flags = '';
		if ($unick) { $flags = $cusers->{$unick} || ''; }
		
		if (!$flags && $channel->{Users}->{$temp_nick} && $channel->{Users}->{$temp_nick}->{Flags}) {
			$flags = $channel->{Users}->{$temp_nick}->{Flags};
		}
		if ($channel->{Founder} eq $temp_nick) { $flags .= 'f'; }
		$row->{Flags} = $flags;
		
		my $temp_user = $self->get_user($temp_nick) || {};
		$row->{DisplayUsername} = $temp_user->{DisplayUsername} || $temp_nick;
		$row->{FullName} = $temp_user->{FullName} || '';
		$row->{Registered} = $temp_user->{Registered} || 0;
		if ($temp_user->{LastCmd}) { $row->{LastCmd} = $temp_user->{LastCmd}; }
		
		push @$rows, $row;
	} # foreach user
	
	return {
		Code => 0,
		Channel => $channel,
		List => { length => $total_users },
		Rows => { Row => $rows }
	};
}

sub api_channel_get_bans {
	# get channel bans (with limit/offset)
	# query: channel, offset, limit
	my $self = shift;
	my $args = {@_};
	my $query = $args->{query};
	my $session = $self->require_session($args) or return { Code => 'session' };
	my $username = $session->{Username};
	my $chan = lc(sch($query->{channel}));
	
	$query->{offset} ||= 0;
	$query->{limit} ||= 50;
	
	# get channel record
	my $channel = $self->get_channel($chan, 0);
	if (!$channel || !$channel->{Registered}) {
		return { Code => 1, Description => "Channel not found: \#$chan" };
	}
	
	# make sure user has permission (channel founder, hop, op or admin)
	my $self_flags = $self->get_channel_user_flags($chan, $username);
	if (!$self->is_admin($username) && ($channel->{Founder} ne $username) && ($self_flags !~ /[ho]/i)) {
		return { Code => 1, Description => "You do not have sufficient access privileges to administer this channel." };
	}
	
	my $bans = [ @{$channel->{Bans} || []} ];
	my $total_bans = scalar @$bans;
	my $rows = [ splice( @$bans, $query->{offset}, $query->{limit} ) ];
	
	return {
		Code => 0,
		Channel => $channel,
		List => { length => $total_bans },
		Rows => { Row => $rows }
	};
}

sub api_channel_add_user {
	# add user to channel
	my $self = shift;
	my $args = {@_};
	my $json = $args->{post};
	my $session = $self->require_session($args) or return { Code => 'session' };
	my $username = $session->{Username};
	
	my $chan = lc(sch($json->{Channel}));
	my $target_nick = nnick($json->{Username});
	
	# get channel record
	my $channel = $self->get_channel($chan, 0);
	if (!$channel || !$channel->{Registered}) {
		return { Code => 1, Description => "Channel not found: \#$chan" };
	}
	
	# make sure user has permission (channel founder, hop, op or admin)
	my $self_flags = $self->get_channel_user_flags($chan, $username);
	if (!$self->is_admin($username) && ($channel->{Founder} ne $username) && ($self_flags !~ /[ho]/i)) {
		return { Code => 1, Description => "You do not have sufficient access privileges to add users to this channel." };
	}
	
	# make sure user is registered
	my $user = $self->get_user($target_nick, 0);
	if (!$user || !$user->{Registered}) {
		return { Code => 1, Description => "The username you entered is not registered: $target_nick" };
	}
	
	# make sure user isn't already in channel
	if ($channel->{Users}->{$target_nick}) {
		return { Code => 1, Description => "The username you entered is already a member of the channel." };
	}
	
	# add user to channel (voice list)
	$channel->{Users}->{$target_nick} = { Flags => 'v' };
	
	# save channel
	$self->save_channel($chan);
	
	# sync modes, in case user is in channel
	my $chanserv = $self->{ircd}->plugin_get( 'ChanServ' );
	$chanserv->sync_all_user_modes( $chan, $target_nick );
	
	return {
		Code => 0
	};
}

sub api_channel_set_user_mode {
	# set user mode in channel
	my $self = shift;
	my $args = {@_};
	my $json = $args->{post};
	my $session = $self->require_session($args) or return { Code => 'session' };
	my $username = $session->{Username};
	
	my $chan = lc(sch($json->{Channel}));
	my $target_nick = nnick($json->{Username});
	my $flags = $json->{Flags};
	
	# get channel record
	my $channel = $self->get_channel($chan, 0);
	if (!$channel || !$channel->{Registered}) {
		return { Code => 1, Description => "Channel not found: \#$chan" };
	}
	
	# make sure user has permission (channel founder, hop, op or admin)
	my $self_flags = $self->get_channel_user_flags($chan, $username);
	my $self_admin = $self->is_admin($username);
	
	if (!$self_admin && ($channel->{Founder} ne $username) && ($self_flags !~ /[ho]/i)) {
		return { Code => 1, Description => "You do not have sufficient access privileges to set user modes in this channel." };
	}
	if (($self_flags =~ /h/i) && ($flags =~ /[ho]/i)) {
		return { Code => 1, Description => "You do not have sufficient access privileges to set user modes to half-op or higher in this channel." };
	}
	
	# make sure user is registered
	if ($self->{config}->{Plugins}->{NickServ}->{RegForce}) {
		my $user = $self->get_user($target_nick, 0);
		if (!$user || !$user->{Registered}) {
			return { Code => 1, Description => "User is not registered: $target_nick" };
		}
	}
		
	# set user mode in channel
	$channel->{Users}->{$target_nick} ||= { Flags => '' };
	$channel->{Users}->{$target_nick}->{Flags} = $flags;
	
	# save channel
	$self->save_channel($chan);
	
	# sync modes, in case user is in channel
	my $chanserv = $self->{ircd}->plugin_get( 'ChanServ' );
	$chanserv->sync_all_user_modes( $chan, $target_nick );
	
	return {
		Code => 0
	};
}

sub api_channel_delete_user {
	# remove user from channel
	my $self = shift;
	my $args = {@_};
	my $json = $args->{post};
	my $session = $self->require_session($args) or return { Code => 'session' };
	my $username = $session->{Username};
	
	my $chan = lc(sch($json->{Channel}));
	my $target_nick = nnick($json->{Username});
	
	# get channel record
	my $channel = $self->get_channel($chan, 0);
	if (!$channel || !$channel->{Registered}) {
		return { Code => 1, Description => "Channel not found: \#$chan" };
	}
	
	# make sure user has permission (channel founder, hop, op or admin)
	my $self_admin = $self->is_admin($username);
	my $self_flags = $self->get_channel_user_flags($chan, $username);
	my $flags = $self->get_channel_user_flags($chan, $target_nick);
	
	if (!$self_admin && ($channel->{Founder} ne $username) && ($self_flags !~ /[ho]/i)) {
		return { Code => 1, Description => "You do not have sufficient access privileges to delete users from this channel." };
	}
	if (($self_flags =~ /h/i) && ($flags =~ /[ho]/i)) {
		return { Code => 1, Description => "You do not have sufficient access privileges to delete half-ops or higher in this channel." };
	}
	if ($channel->{Founder} eq $target_nick) {
		return { Code => 1, Description => "You cannot delete the channel founder from the channel." };
	}
	if ($self->is_admin($target_nick) && !$self_admin) {
		return { Code => 1, Description => "You cannot delete server administrators from the channel." };
	}
	
	# remove user from channel
	delete $channel->{Users}->{$target_nick};
	
	# save channel
	$self->save_channel($chan);
	
	# sync modes, in case user is in channel
	my $chanserv = $self->{ircd}->plugin_get( 'ChanServ' );
	$chanserv->sync_all_user_modes( $chan, $target_nick );
	
	return {
		Code => 0
	};
}

sub api_channel_kick_user {
	# kick user out of channel
	my $self = shift;
	my $args = {@_};
	my $json = $args->{post};
	my $session = $self->require_session($args) or return { Code => 'session' };
	my $username = $session->{Username};
	
	my $chan = lc(sch($json->{Channel}));
	my $target_nick = nnick($json->{Username});
	
	# get channel record
	my $channel = $self->get_channel($chan, 0);
	if (!$channel || !$channel->{Registered}) {
		return { Code => 1, Description => "Channel not found: \#$chan" };
	}
	
	# make sure user has permission (channel founder, hop, op or admin)
	my $self_admin = $self->is_admin($username);
	my $self_flags = $self->get_channel_user_flags($chan, $username);
	my $flags = $self->get_channel_user_flags($chan, $target_nick);
	
	if (!$self_admin && ($channel->{Founder} ne $username) && ($self_flags !~ /[ho]/i)) {
		return { Code => 1, Description => "You do not have sufficient access privileges to kick users from this channel." };
	}
	if (($self_flags =~ /h/i) && ($flags =~ /[ho]/i)) {
		return { Code => 1, Description => "You do not have sufficient access privileges to kick ops in this channel." };
	}
	if ($channel->{Founder} eq $target_nick) {
		return { Code => 1, Description => "You cannot kick the channel founder from the channel." };
	}
	if ($self->is_admin($target_nick) && !$self_admin) {
		return { Code => 1, Description => "You cannot kick server administrators from the channel." };
	}
	
	# kick
	$self->log_debug(4, "Kicking user '$target_nick' out of channel \#$chan");
	my $unick = $self->get_irc_username( $target_nick );
	$self->{ircd}->daemon_server_kick( nch($chan), $unick, $self->{config}->{WebServer}->{KickMessage} );
	
	return {
		Code => 0
	};
}

sub api_channel_add_ban {
	# add ban to channel
	my $self = shift;
	my $args = {@_};
	my $json = $args->{post};
	my $session = $self->require_session($args) or return { Code => 'session' };
	my $username = $session->{Username};
	
	my $chan = lc(sch($json->{Channel}));
	my $target_user = lc($json->{TargetUser} || '*'); if ($target_user !~ /\!/) { $target_user .= '!*'; }
	my $target_ip = lc($json->{TargetIP} || '*');
	my $expires = $json->{Expires};
	
	# get channel record
	my $channel = $self->get_channel($chan, 0);
	if (!$channel || !$channel->{Registered}) {
		return { Code => 1, Description => "Channel not found: \#$chan" };
	}
	
	# make sure user has permission (channel founder, hop, op or admin)
	my $self_admin = $self->is_admin($username);
	my $self_flags = $self->get_channel_user_flags($chan, $username);
	
	if (!$self_admin && ($channel->{Founder} ne $username) && ($self_flags !~ /[o]/i)) {
		return { Code => 1, Description => "You do not have sufficient access privileges to add bans to this channel." };
	}
	
	$channel->{Bans} ||= [];
	if (find_object( $channel->{Bans}, { TargetUser => $target_user, TargetIP => $target_ip } )) {
		return { Code => 1, Description => "The ban target you entered is already in effect on the channel." };
	}
	
	# add ban
	$self->log_debug(4, "Adding ban '$target_user\@$target_ip' to channel \#$chan");
	my $now = time();
	
	# get full username (if not logged in, make one up)
	my $username_full = $self->{ircd}->state_user_full($username);
	if (!$username_full) {
		$username_full = $username . '!~' . $username . '@' . $self->{config}->{ServerName};
	}
	
	push @{$channel->{Bans}}, {
		TargetUser => $target_user,
		TargetIP => $target_ip,
		AddedBy => $username_full,
		Created => $now,
		Expires => $expires
	};
	$self->save_channel($chan);
	
	# jhuckabynick!~jhuckabyuser@c9ed02581a4ce137
	my $ban_target = $target_user . '@' . $target_ip;
	
	my $crecord = $self->{ircd}->{state}{chans}{uc_irc(nch($chan))};
	$crecord->{bans} ||= {};
	$crecord->{bans}->{ uc($ban_target) } = [
		$ban_target,
		$username_full,
		$now
	];
	
	# kick any users affected by ban
	my $chanserv = $self->{ircd}->plugin_get( 'ChanServ' );
	$chanserv->sync_all_user_modes( $chan, '' );
	
	return {
		Code => 0
	};
}

sub api_channel_update_ban {
	# update existing channel ban
	my $self = shift;
	my $args = {@_};
	my $json = $args->{post};
	my $session = $self->require_session($args) or return { Code => 'session' };
	my $username = $session->{Username};
	
	my $chan = lc(sch($json->{Channel}));
		
	my $old_target_user = lc($json->{OldTargetUser} || '*'); if ($old_target_user !~ /\!/) { $old_target_user .= '!*'; }
	my $old_target_ip = lc($json->{OldTargetIP} || '*');
		
	my $new_target_user = lc($json->{TargetUser} || '*'); if ($new_target_user !~ /\!/) { $new_target_user .= '!*'; }
	my $new_target_ip = lc($json->{TargetIP} || '*');
	
	my $expires = $json->{Expires};
	
	# get channel record
	my $channel = $self->get_channel($chan, 0);
	if (!$channel || !$channel->{Registered}) {
		return { Code => 1, Description => "Channel not found: \#$chan" };
	}
	
	# make sure user has permission (channel founder, hop, op or admin)
	my $self_admin = $self->is_admin($username);
	my $self_flags = $self->get_channel_user_flags($chan, $username);
	
	if (!$self_admin && ($channel->{Founder} ne $username) && ($self_flags !~ /[o]/i)) {
		return { Code => 1, Description => "You do not have sufficient access privileges to add bans to this channel." };
	}
	
	$channel->{Bans} ||= [];
	my $ban = find_object( $channel->{Bans}, { TargetUser => $old_target_user, TargetIP => $old_target_ip } );
	if (!$ban) {
		return { Code => 1, Description => "Ban not found: $old_target_user\@$old_target_ip" };
	}
	
	# apply changes to ban
	$self->log_debug(4, "Updating ban '$old_target_user\@$old_target_ip' to '$new_target_user\@$new_target_ip' in channel \#$chan");
	$ban->{TargetUser} = $new_target_user;
	$ban->{TargetIP} = $new_target_ip;
	$ban->{Expires} = $expires;
	my $now = time();
	
	# get full username (if not logged in, make one up)
	my $username_full = $self->{ircd}->state_user_full($username);
	if (!$username_full) {
		$username_full = $username . '!~' . $username . '@' . $self->{config}->{ServerName};
	}
	
	$self->save_channel($chan);
	
	# jhuckabynick!~jhuckabyuser@c9ed02581a4ce137
	my $old_ban_target = $old_target_user . '@' . $old_target_ip;
	my $new_ban_target = $new_target_user . '@' . $new_target_ip;
	
	my $crecord = $self->{ircd}->{state}{chans}{uc_irc(nch($chan))};
	$crecord->{bans} ||= {};
	delete $crecord->{bans}->{ uc($old_ban_target) };
	$crecord->{bans}->{ uc($new_ban_target) } = [
		$new_ban_target,
		$username_full,
		$now
	];
	
	# kick any users affected by ban
	my $chanserv = $self->{ircd}->plugin_get( 'ChanServ' );
	$chanserv->sync_all_user_modes( $chan, '' );
	
	return {
		Code => 0
	};
}

sub api_channel_delete_ban {
	# remove ban from channel
	my $self = shift;
	my $args = {@_};
	my $json = $args->{post};
	my $session = $self->require_session($args) or return { Code => 'session' };
	my $username = $session->{Username};
	
	my $chan = lc(sch($json->{Channel}));
	my $target_user = lc($json->{TargetUser} || '*'); if ($target_user !~ /\!/) { $target_user .= '!*'; }
	my $target_ip = lc($json->{TargetIP} || '*');
	
	# get channel record
	my $channel = $self->get_channel($chan, 0);
	if (!$channel || !$channel->{Registered}) {
		return { Code => 1, Description => "Channel not found: \#$chan" };
	}
	
	# make sure user has permission (channel founder, hop, op or admin)
	my $self_admin = $self->is_admin($username);
	my $self_flags = $self->get_channel_user_flags($chan, $username);
	
	if (!$self_admin && ($channel->{Founder} ne $username) && ($self_flags !~ /[o]/i)) {
		return { Code => 1, Description => "You do not have sufficient access privileges to delete bans on this channel." };
	}
	
	$channel->{Bans} ||= [];
	if (!find_object( $channel->{Bans}, { TargetUser => $target_user, TargetIP => $target_ip } )) {
		return { Code => 1, Description => "Channel ban not found: $target_user\@$target_ip" };
	}
	
	# delete ban
	$self->log_debug(4, "Deleting ban '$target_user\@$target_ip' from channel \#$chan");
	
	delete_object( $channel->{Bans}, { TargetUser => $target_user, TargetIP => $target_ip } );
	$self->save_channel($chan);
	
	# jhuckabynick!~jhuckabyuser@c9ed02581a4ce137
	my $ban_target = $target_user . '@' . $target_ip;
	
	my $crecord = $self->{ircd}->{state}{chans}{uc_irc(nch($chan))};
	$crecord->{bans} ||= {};
	delete $crecord->{bans}->{ uc($ban_target) };
	
	return {
		Code => 0
	};
}

sub api_logs {
	# fetch logs from live or archives, with search criteria
	# return as HTML or raw text
	# Shortcut URI for channel transcript: /api/logs/transcript/myroom/10000
	my $self = shift;
	my $args = {@_};
	my $query = $args->{query};
	my $session = $self->require_session($args) or return { Code => 'session', Description => 'Your session is invalid or has timed out.  Please return to the main site, log in, then try your log search again.' };
	my $username = $session->{Username};
	
	if ($args->{uri} =~ m@/api/logs/(\w+)/(\w+)/(\w+)@) {
		$query->{cat} = $1;
		$query->{chan} = $2;
		$query->{recent} = $3;
		$query->{format} = 'html';
	}
	
	if ($query->{chan}) {
		my $flags = $self->get_channel_user_flags( $query->{chan}, $username );
		if ($flags !~ /[ho]/) {
			return { Code => 1, Description => "You do not have sufficient access privileges to view the ".nch($query->{chan})." transcript." };
		}
		$query->{cat} = 'transcript';
		$query->{filter} = "PRIVMSG " . nch($query->{chan});
	}
	elsif (!$self->is_admin($username)) {
		return { Code => 1, Description => "You must be a server administrator to view the logs." };
	}
	
	my $cat = lc($query->{cat}); $cat =~ s/\W+//g; # alphanum only
	my $log_file = '';
	my $log_fh = undef;
	my $col_headers = $self->{log_columns}->{$cat} || [];
	my $rows = [];
	my $content_type = '';
	my $content = '';
	
	if ($query->{recent}) {
		$query->{date} = yyyy_mm_dd(time(), '/');
	}
	
	if ($query->{date} eq yyyy_mm_dd(time(), '/')) {
		# today's log, pull from live location, no gunzip needed
		$log_file = $self->{config}->{Logging}->{LogDir} . '/' . $cat . '.log';
		if (-e $log_file) { $log_fh = FileHandle->new("<$log_file"); }
	}
	else {
		# log archive, must decompress using gzip pipe
		$query->{date} =~ s/[^\d\/]+//g; # only allow digits and slashes
		$log_file = $self->{config}->{Logging}->{LogDir} . '/archive/' . $cat . '/' . $query->{date} . '.log.gz';
		$log_file =~ s/\.\.//g; # strip parent directory shortcuts
		$log_file =~ s@//@/@g; # normalize double-slashes
		if (-e $log_file) { $log_fh = FileHandle->new( find_bin('gzip') . ' -cd ' . $log_file . ' |' ); }
	}
	
	$query->{date} =~ /(\d{4})\D+(\d{2})\D+(\d{2})/;
	my ($yyyy, $mm, $dd) = ($1, $2, $3);
	my $midnight = timelocal( 0, 0, 0, int($dd), int($mm) - 1, int($yyyy) - 1900 );
	my $start_epoch = $midnight + ($query->{time_start} || 0);
	my $end_epoch = $midnight + ($query->{time_end} || 0);
	
	if ($query->{recent}) {
		$start_epoch = time() - $query->{recent};
		$end_epoch = time();
	}
	
	if ($log_fh) {
		my $regex = $query->{filter} || '.+';
		my $buffer = '';
		
		while (my $line = <$log_fh>) {
			next if $line =~ /^\#/; # comment
			
			if ($line =~ /^\[([\d\.]+)\]/) {
				if ($buffer =~ /^\[([\d\.]+)\]/) {
					my $epoch = $1;
					# this is a new row, so flush previous buffer
					if (($epoch >= $start_epoch) && ($epoch < $end_epoch) && ($buffer =~ m@$regex@)) {
						push @$rows, $buffer;
					}
				} # flush buffer
				$buffer = $line;
			}
			elsif ($line =~ /\S/) {
				# continuation of prev line, append to buffer
				$buffer .= $line;
			}
		} # foreach line
		
		if ($buffer =~ /^\[([\d\.]+)\]/) {
			my $epoch = $1;
			if (($epoch >= $start_epoch) && ($epoch < $end_epoch) && ($buffer =~ m@$regex@)) {
				push @$rows, $buffer;
			}
		} # final buffer flush
		
		my $len = 0;
		for (my $idx = 0, $len = scalar @$rows; $idx < $len; $idx++) {
			my $cols = [ split(/\]\[/, $rows->[$idx], 6) ];
			$cols->[0] =~ s/^\[//;
			$cols->[5] =~ s/^(.*?)\](.*)$/$1/s;
			my $msg = $2;
			push @$cols, trim($msg);
			$rows->[$idx] = $cols;
		}
		
		undef $log_fh;
	} # good log fh
	
	if ($query->{format} =~ /html/i) {
		$content_type = 'text/html';
		my $data = '';
		
		$data .= '<tr>';
		foreach my $col (@$col_headers) {
			next if $col =~ /^(PID|Category)$/;
			$data .= '<th>' . $col . '</th>';
		}
		$data .= '</tr>' . "\n";
		
		foreach my $row (@$rows) {
			$data .= '<tr>';
			my $idx = 0;
			foreach my $col (@$row) {
				if (($idx == 2) || ($idx == 3)) { $idx++; next; }
				$data .= ($idx < 6) ? '<td style="white-space:nowrap;">' : '<td>';
				
				my $closer = '';
				if ($idx == 5) { 
					$data .= '<b>'; $closer = '</b>';
					if ($query->{chan}) { $col =~ s/\!.+$//; }
				}
				elsif ($idx == 6) {
					$data .= '<span style="font-family:monospace;">'; $closer = '</span>'; 
					if ($query->{chan}) { $col =~ s/^PRIVMSG\s+\#\S+\s+\://; }
				}
				
				$data .= encode_entities($col);
				$data .= $closer;
				$data .= '</td>';
				$idx++;
			}
			$data .= '</tr>' . "\n";
		} # foreach row
		if (!@$rows) {
			$data .= '<tr><td colspan="7" align="center" style="padding:10px 0px 10px 0px; font-weight:bold;">No rows found.</td></tr>';
		}
		
		my $nice_filter = $query->{filter} || '(None)';
		if ($query->{chan}) { $nice_filter = "Channel " . nch($query->{chan}); }
		
		my $args = {
			%$query,
			cat => $nice_log_cat_names->{$query->{cat}},
			title => $self->{config}->{ServerDesc},
			date => get_nice_date( $midnight ),
			time => get_nice_time($start_epoch, 1) . ' to ' . get_nice_time($end_epoch - 1, 1),
			filter => $nice_filter,
			data => $data
		};
		
		$content = memory_substitute(load_file('htdocs/log_template.html'), $args);
	} # html
	else {
		$content_type = 'text/plain';
		$content = '';
		
		unshift @$rows, [ @$col_headers ];
		
		foreach my $row (@$rows) {
			my $msg = pop @$row;
			$content .= '[' . join('][', @$row) . '] ' . $msg . "\n";
		}
		
		if (scalar @$rows == 1) {
			$content .= "\n(No rows found)\n";
		}
	} # raw
	
	my $response = $args->{response};
	$response->code( 200 );
	$response->header( 'Content-Type' => $content_type );
	$response->header( 'Content-Length' => length($content) );
	$response->content( $content );
	
	return 0; # custom response
}

sub api_upload_logo {
	# upload custom logo
	my $self = shift;
	my $args = {@_};
	my $session = $self->require_session($args) or return { Code => 'session' };
	my $username = $session->{Username};
	
	if (!$self->is_admin($username)) {
		return { Code => 1, Description => "You must be a server administrator to change the server logo image." };
	}
	if (!$args->{files} || !$args->{files}->{file1} || !$args->{files}->{file1}->{filename} || !$args->{files}->{file1}->{content}) {
		return { Code => 1, Description => "File upload data not found. Please try your upload again." };
	}
	
	my $file = $args->{files}->{file1};
	my $ext = '';
	if ($file->{filename} =~ /\.(\w+)$/) { $ext = lc($1); }
	elsif ($file->{headers}->{'Content-Type'} && ($file->{headers}->{'Content-Type'} =~ m@image/(\w+)$@)) { $ext = lc($1); }
	else { return { Code => 1, Description => "Unable to determine file format.  Please upload a different image." }; }
	
	$ext =~ s/jpeg/jpg/;
	if ($ext !~ /^(jpg|gif|png)$/) { return { Code => 1, Description => "Unsupported file format.  Please upload a JPEG, GIF or PNG image." }; }
	
	my $logo_filename = "logo.$ext";
	$self->log_debug(4, "Saving new custom logo image: data/$logo_filename (".length($file->{content})." bytes)");
	
	my $server_data = $self->get_data();
	if ($server_data->{CustomLogoFilename}) { unlink('data/' . $server_data->{CustomLogoFilename}); }
	
	if (!save_file( "data/$logo_filename", $file->{content} )) {
		return { Code => 1, Description => "Unable to save logo: data/$logo_filename: $!" };
	}
	
	$server_data->{CustomLogoFilename} = $logo_filename;
	$self->save_data();
	
	return {
		Code => 0
	};
}

sub api_get_logo {
	# return raw logo image
	my $self = shift;
	my $args = {@_};
	my $content_type = '';
	my $content = '';
	my $server_data = $self->get_data();
	
	if ($server_data->{CustomLogoFilename} && ($server_data->{CustomLogoFilename} =~ /\.(\w+)$/)) {
		# custom logo
		my $fmt = $1; $fmt =~ s/jpg/jpeg/;
		$content_type = "image/$fmt";
		$content = load_file( "data/" . $server_data->{CustomLogoFilename} );
	}
	else {
		# standard simpleirc logo
		$content_type = 'image/png';
		$content = load_file( 'htdocs/images/logo-128.png' );
	}
	
	my $response = $args->{response};
	$response->code( 200 );
	$response->header( 'Content-Type' => $content_type );
	$response->header( 'Cache-Control' => 'no-cache' );
	$response->header( 'Content-Length' => length($content) );
	$response->content( $content );
	
	return 0; # custom response
}

sub api_upload_file {
	# upload file, API designed for '/upload' (upload.scpt) Textual IRC Script
	my $self = shift;
	my $args = {@_};
	my $query = $args->{query};
	
	if (!$self->{config}->{WebServer}->{FileUploadKey}) {
		return { Code => 1, Description => "No file upload key found in web server configuration." };
	}
	if ($query->{key} ne $self->{config}->{WebServer}->{FileUploadKey}) {
		return { Code => 1, Description => "File upload key does not match." };
	}
	if (!$args->{files} || !$args->{files}->{file1} || !$args->{files}->{file1}->{filename} || !$args->{files}->{file1}->{content}) {
		return { Code => 1, Description => "File upload data not found. Please try your upload again." };
	}
	
	my $file = $args->{files}->{file1};
	my $filename = basename( $file->{filename} );
	$filename =~ s/[^\w\-\.]+//g;
	
	my $sub_path = yyyy_mm_dd(time(), '/') . '/' . $filename;
	my $dest_file = 'htdocs/files/' . $sub_path;
	make_dirs_for( $dest_file );
	if (!save_file( $dest_file, $file->{content} )) {
		return { Code => 1, Description => "Failed to upload file: $filename: $!" };
	}
	
	my $url = $self->{config}->{WebServer}->{SSL} ? 'https://' : 'http://';
	$url .= $args->{request}->header('Host');
	$url .= '/files/' . $sub_path;
	
	my $content = "$url\n";
	
	my $response = $args->{response};
	$response->code( 200 );
	$response->header( 'Content-Type' => 'text/plain' );
	$response->header( 'Cache-Control' => 'no-cache' );
	$response->header( 'Content-Length' => length($content) );
	$response->content( $content );
	
	return 0; # custom response
}

sub api_broadcast_message {
	# broadcast message to all channels
	my $self = shift;
	my $args = {@_};
	my $json = $args->{post};
	my $session = $self->require_session($args) or return { Code => 'session' };
	my $username = $session->{Username};
	
	if (!$self->is_admin($username)) {
		return { Code => 1, Description => "You must be a server administrator to broadcast messages." };
	}
	
	$self->{ircd}->_daemon_cmd_broadcast( $username, $json->{Message} );
	
	return {
		Code => 0
	};
}

sub api_server_restart {
	# restart server in background
	my $self = shift;
	my $args = {@_};
	my $session = $self->require_session($args) or return { Code => 'session' };
	my $username = $session->{Username};
	
	if (!$self->is_admin($username)) {
		return { Code => 1, Description => "You must be a server administrator to restart the server." };
	}
	
	$self->{ircd}->_daemon_cmd_restart( $username, "" );
	
	return {
		Code => 0
	};
}

sub api_server_stop {
	# shut down server
	my $self = shift;
	my $args = {@_};
	my $session = $self->require_session($args) or return { Code => 'session' };
	my $username = $session->{Username};
	
	if (!$self->is_admin($username)) {
		return { Code => 1, Description => "You must be a server administrator to shut down the server." };
	}
	
	$self->{ircd}->_daemon_cmd_shutdown( $username, "" );
	
	return {
		Code => 0
	};
}

sub api_server_upgrade {
	# upgrade server and/or switch branch
	my $self = shift;
	my $args = {@_};
	my $json = $args->{post};
	my $session = $self->require_session($args) or return { Code => 'session' };
	my $username = $session->{Username};
	
	if (!$self->is_admin($username)) {
		return { Code => 1, Description => "You must be a server administrator to upgrade the server." };
	}
	
	my $current_version = get_version();
	my $branch = $json->{branch} || $current_version->{Branch};
	
	# make sure branch exists
	my $version_url = "http://effectsoftware.com/software/simpleirc/version-$branch.json";
	my $resp = wget( $version_url );
	if (!$resp->is_success()) { return { Code => 1, Description => "Could not fetch version information file for branch: $branch" }; }
	
	$self->{ircd}->_daemon_cmd_upgrade( $username, $branch );
	
	return {
		Code => 0
	};
}

sub api_save_config {
	# save server configuration
	my $self = shift;
	my $args = {@_};
	my $json = $args->{post};
	my $session = $self->require_session($args) or return { Code => 'session' };
	my $username = $session->{Username};
	
	if (!$self->is_admin($username)) {
		return { Code => 1, Description => "You must be a server administrator to make configuration changes." };
	}
	
	my $new_config = $json->{Config};
	
	$self->log_debug(3, "Saving new configuration from web UI ($username): " . json_compose_pretty($new_config));
	
	my $web_config_file = 'conf/config-web.json';
	if (!save_file_atomic($web_config_file, json_compose_pretty($new_config))) {
		return { Code => 1, Description => "Failed to save server configuration: $!" };
	}
	
	# reload new config live
	eval { $self->reload_config(); };
	if ($@) { return { Code => 1, Description => "Failed to reload configuration: $@" }; }
	
	$self->log_event(
		log => 'transcript',
		package => $args->{ip},
		level => $username,
		msg => "(Server config reload)"
	);
	
	return {
		Code => 0,
		Config => $self->{config}
	};
}

sub api_get_config_texts {
	# get server config text files, i.e. info.txt, admin.txt, motd.txt
	my $self = shift;
	my $args = {@_};
	my $session = $self->require_session($args) or return { Code => 'session' };
	my $username = $session->{Username};
	
	if (!$self->is_admin($username)) {
		return { Code => 1, Description => "You must be a server administrator to make configuration changes." };
	}
	
	return {
		Code => 0,
		Texts => {
			motd => join("\n", @{$self->{ircd}->{config}->{MOTD}}),
			admin => join("\n", @{$self->{ircd}->{config}->{ADMIN}}),
			info => join("\n", @{$self->{ircd}->{config}->{INFO}})
		}
	};
}

sub api_save_config_texts {
	# save server config text files, i.e. info.txt, admin.txt, motd.txt
	my $self = shift;
	my $args = {@_};
	my $json = $args->{post};
	my $session = $self->require_session($args) or return { Code => 'session' };
	my $username = $session->{Username};
	
	if (!$self->is_admin($username)) {
		return { Code => 1, Description => "You must be a server administrator to make configuration changes." };
	}
	
	my $texts = $json->{Texts};
	$self->log_debug(3, "Saving new server config text files from web UI ($username): " . json_compose_pretty($texts));
	
	# clean up texts
	foreach my $key (keys %$texts) {
		my $value = trim($texts->{$key});
		$value =~ s/\r\n/\n/sg;
		$value =~ s/\r/\n/sg;
		if ($value !~ /\S/) { $value = '-'; }
		$texts->{$key} = [ split(/\n/, $value) ];
	}
	
	# admin and info must be exactly 3 lines each
	foreach my $key ('admin', 'info') {
		my $lines = $texts->{$key};
		while (scalar @$lines < 3) { push @$lines, '-'; }
		while (scalar @$lines > 3) { pop @$lines; }
		$texts->{$key} = $lines;
	}
	
	# save files to disk and
	# infuse data back into live ircd server
	foreach my $key (keys %$texts) {
		my $lines = $texts->{$key};
		if (!save_file( "conf/$key.txt", join("\n", @$lines) . "\n" )) {
			return { Code => 1, Description => "Failed to save config text file: $key: $!" };
		}
		$self->{ircd}->{config}->{uc($key)} = $lines;
	}
	
	$self->log_event(
		log => 'transcript',
		package => $args->{ip},
		level => $username,
		msg => "(Server config text file reload)"
	);
	
	return {
		Code => 0
	};
}

sub api_server_get_bans {
	# get server bans (with limit/offset)
	# query: server, offset, limit
	my $self = shift;
	my $args = {@_};
	my $query = $args->{query};
	my $session = $self->require_session($args) or return { Code => 'session' };
	my $username = $session->{Username};
	
	if (!$self->is_admin($username)) {
		return { Code => 1, Description => "You must be a server administrator to manage server-wide bans." };
	}
	
	$query->{offset} ||= 0;
	$query->{limit} ||= 50;
	
	my $bans = [ @{$self->{data}->{Bans} || []} ];
	my $total_bans = scalar @$bans;
	my $rows = [ splice( @$bans, $query->{offset}, $query->{limit} ) ];
	
	return {
		Code => 0,
		List => { length => $total_bans },
		Rows => { Row => $rows }
	};
}

sub api_server_add_ban {
	# add ban to server
	my $self = shift;
	my $args = {@_};
	my $json = $args->{post};
	my $session = $self->require_session($args) or return { Code => 'session' };
	my $username = $session->{Username};
	
	if (!$self->is_admin($username)) {
		return { Code => 1, Description => "You must be a server administrator to manage server-wide bans." };
	}
	
	my $user_mask = lc($json->{TargetUser} || '*');
	my $ip_mask = $json->{TargetIP} || '*';
	
	$self->{data}->{Bans} ||= [];
	
	if (find_object($self->{data}->{Bans}, { TargetUser => $user_mask, TargetIP => $ip_mask })) {
		return { Code => 1, Description => "Server ban already exists: $user_mask\@$ip_mask" };
	}
	
	$self->log_debug(3, "Adding server wide ban: $user_mask\@$ip_mask");
	
	# get full username (if not logged in, make one up)
	my $username_full = $self->{ircd}->state_user_full($username);
	if (!$username_full) {
		$username_full = $username . '!~' . $username . '@' . $self->{config}->{ServerName};
	}
	
	my $ban = {
		TargetUser => $user_mask,
		TargetIP => $ip_mask,
		AddedBy => $username_full,
		Reason => "No reason",
		Created => time(),
		Expires => $json->{Expires}
	};
	
	push @{$self->{data}->{Bans}}, $ban;
	$self->save_data();
	
	# add server ban to ircd
	$self->{ircd}->{state}{klines} ||= [];
	push @{ $self->{ircd}->{state}{klines} }, {
		setby	=> $ban->{AddedBy},
		setat	=> $ban->{Created},
		target   => $self->{config}->{ServerName},
		duration => 0,
		user	 => $ban->{TargetUser},
		host	 => $ban->{TargetIP},
		reason   => $ban->{Reason} || ''
	};
	
	# terminate affected users now
	for ($self->{ircd}->_state_local_users_match_gline($ban->{TargetUser}, $ban->{TargetIP})) {
		$self->log_debug(4, "Terminating user due to server-wide ban: $_ (" . $ban->{TargetUser} . '@' . $ban->{TargetIP} . ")");
	    $self->{ircd}->_terminate_conn_error($_, 'K-Lined');
	}
	
	$self->log_event(
		log => 'transcript',
		package => $args->{ip},
		level => $username,
		msg => "(Server ban added: $user_mask\@$ip_mask)"
	);
	
	return {
		Code => 0
	};
}

sub api_server_update_ban {
	# update existing server ban
	my $self = shift;
	my $args = {@_};
	my $json = $args->{post};
	my $session = $self->require_session($args) or return { Code => 'session' };
	my $username = $session->{Username};
	
	if (!$self->is_admin($username)) {
		return { Code => 1, Description => "You must be a server administrator to manage server-wide bans." };
	}
	
	my $old_user_mask = lc($json->{OldTargetUser} || '*');
	my $old_ip_mask = $json->{OldTargetIP} || '*';
	
	$self->{data}->{Bans} ||= [];
	
	my $ban = find_object($self->{data}->{Bans}, { TargetUser => $old_user_mask, TargetIP => $old_ip_mask });
	if (!$ban) {
		return { Code => 1, Description => "Server ban not found: $old_user_mask\@$old_ip_mask" };
	}
	
	my $user_mask = lc($json->{TargetUser} || '*');
	my $ip_mask = $json->{TargetIP} || '*';
	
	$self->log_debug(3, "Updating server wide ban: $old_user_mask\@$old_ip_mask to: $user_mask\@$ip_mask");
	
	$ban->{TargetUser} = $user_mask;
	$ban->{TargetIP} = $ip_mask;
	$ban->{Expires} = $json->{Expires};
	$self->save_data();
	
	$self->{ircd}->{state}{klines} ||= [];
	my $cban = find_object($self->{ircd}->{state}{klines}, { user => $old_user_mask, host => $old_ip_mask });
	if ($cban) {
		$cban->{user} = $user_mask;
		$cban->{host} = $ip_mask;
	}
	
	# terminate affected users now
	for ($self->{ircd}->_state_local_users_match_gline($ban->{TargetUser}, $ban->{TargetIP})) {
		$self->log_debug(4, "Terminating user due to server-wide ban: $_ (" . $ban->{TargetUser} . '@' . $ban->{TargetIP} . ")");
	    $self->{ircd}->_terminate_conn_error($_, 'K-Lined');
	}
	
	$self->log_event(
		log => 'transcript',
		package => $args->{ip},
		level => $username,
		msg => "(Server ban updated: $old_user_mask\@$old_ip_mask to: $user_mask\@$ip_mask)"
	);
	
	return {
		Code => 0
	};
}

sub api_server_delete_ban {
	# remove ban from server
	my $self = shift;
	my $args = {@_};
	my $json = $args->{post};
	my $session = $self->require_session($args) or return { Code => 'session' };
	my $username = $session->{Username};
	
	if (!$self->is_admin($username)) {
		return { Code => 1, Description => "You must be a server administrator to manage server-wide bans." };
	}
	
	my $user_mask = lc($json->{TargetUser} || '*');
	my $ip_mask = $json->{TargetIP} || '*';
	
	$self->log_debug(3, "Deleting server wide ban: $user_mask\@$ip_mask");
	
	$self->{data}->{Bans} ||= [];
	
	if (!delete_object($self->{data}->{Bans}, { TargetUser => $user_mask, TargetIP => $ip_mask })) {
		return { Code => 1, Description => "Server ban not found: $user_mask\@$ip_mask" };
	}
	$self->save_data();
	
	$self->{ircd}->{state}{klines} ||= [];
	delete_object($self->{ircd}->{state}{klines}, { user => $user_mask, host => $ip_mask });
	
	$self->log_event(
		log => 'transcript',
		package => $args->{ip},
		level => $username,
		msg => "(Server ban deleted: $user_mask\@$ip_mask)"
	);
	
	return {
		Code => 0
	};
}

sub api_server_boot_user {
	# force disconnect user from server
	my $self = shift;
	my $args = {@_};
	my $json = $args->{post};
	my $session = $self->require_session($args) or return { Code => 'session' };
	my $username = $session->{Username};
	
	if (!$self->is_admin($username)) {
		return { Code => 1, Description => "You must be a server administrator to boot users." };
	}
	
	my $target_nick = nnick($json->{Username});
	my $unick = $self->get_irc_username( $target_nick );
	if (!$unick) {
		return { Code => 1, Description => "User $target_nick is no longer connected to the IRC server." };
	}
	
	my $route_id = $self->{ircd}->_state_user_route( $unick );
	if (!$route_id || ($route_id eq 'spoofed')) {
		return { Code => 1, Description => "User $target_nick is no longer connected to the IRC server." };
	}
	
	$self->log_debug(3, "Booting user from server: $target_nick" );
	
	$self->{ircd}->daemon_server_kill( $unick, "Booted" );
	
	$self->log_event(
		log => 'transcript',
		package => $args->{ip},
		level => $username,
		msg => "(User booted: $target_nick)"
	);
	
	return {
		Code => 0
	};
}

sub api_talk {
	# send text to any channel, uses secret key auth token system
	my $self = shift;
	my $args = {@_};
	my $query = $args->{query};
	
	my $msg = trim( $query->{msg} || $args->{post}->{msg} || '' );
	my $package = $query->{who} || 'Server';
	my $type = $query->{type} || 'PRIVMSG';
	
	if ($package !~ /\!/) { $package = $package . '!~' . $package . '@' . $self->{config}->{ServerName}; }
	
	if (!$msg || ($msg !~ /\S/)) {
		return { Code => 1, Description => "No message text (msg) was specified." };
	}
	if (!$query->{auth}) {
		return { Code => 1, Description => "No authentication token (auth) was specified." };
	}
	if (!$query->{chan}) {
		return { Code => 1, Description => "No channel (chan) was specified." };
	}
	if ($query->{auth} ne md5_hex($query->{msg} . $self->{config}->{SecretKey})) {
		return { Code => 1, Description => "Authentication token is incorrect." };
	}
	
	my $chan = nch($query->{chan});
	$self->log_debug(9, "Sending $type to $chan: $msg");
	
	foreach my $line (split(/\n/, $msg)) {
		$line = trim($line);
		if ($line =~ /\S/) {
			$self->{ircd}->_send_output_to_channel( $chan, { 
				prefix => $package, 
				command => $type, 
				params => [$chan, $line] 
			} );
		}
	}
	
	$self->log_event(
		log => 'transcript',
		package => $args->{ip},
		level => $package,
		msg => "$type $chan $msg"
	);
	
	return {
		Code => 0,
		Description => "Success"
	};
}

1;

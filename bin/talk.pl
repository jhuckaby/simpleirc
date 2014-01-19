#!/usr/bin/perl

##
# talk.pl
# IRCSimple v1.0 Command-line IRC message post tool
# Posts any text to your running SimpleIRC server (requires web interface)
# Copyright (c) 2013 Joseph Huckaby and PixlCore.com
# Released under the MIT License.
# 
# Usage:
#	./talk.pl --chan CHANNEL --msg "Hello there." [--who NICKNAME --type PRIVMSG]
##

use strict;
use warnings;
use File::Basename;
use Cwd qw/abs_path/;
use URI::Escape;
use Digest::MD5 qw(md5_hex);

BEGIN {
	push @INC, dirname(dirname(abs_path($0))) . "/lib";
}
use Tools;

$ENV{'PERL_LWP_SSL_VERIFY_HOSTNAMES'} = 0;
$ENV{'PERL_LWP_SSL_VERIFY_HOSTNAME'} = 0;

$| = 1;

my $usage = "Usage: ./talk.pl --chan CHANNEL --msg \"Hello there.\" [--who NICKNAME --type PRIVMSG]\n";

my $args = new Args( @ARGV );
if (!$args->{msg} || !$args->{chan}) { die $usage; }
$args->{msg} = trim($args->{msg});
$args->{who} ||= 'Server';
$args->{type} ||= 'PRIVMSG';

if ($args->{msg} eq 'STDIN') {
	# special shortcut to read from stdin
	$args->{msg} = '';
	while (my $line = <STDIN>) { $args->{msg} .= $line; }
	$args->{msg} = trim($args->{msg});
}

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

if (!$config->{SecretKey}) { die "SimpleIRC has no secret key in config.\n"; }
if (!$config->{WebServer}->{Enabled}) { die "SimpleIRC web server is not enabled.\n"; }

my $auth_token = md5_hex( $args->{msg} . $config->{SecretKey} );
$args->{auth} = $auth_token;
$args->{format} = 'json';
$args->{pure} = 1;

my $url = $config->{WebServer}->{SSL} ? 'https://' : 'http://';
$url .= '127.0.0.1:' . $config->{WebServer}->{Port} . '/api/talk';
$url .= compose_query( $args );

if ($args->{debug}) { print "URL: $url\n\n"; }

my $resp = wget( $url );
if ($resp->is_success()) { print $resp->content() . "\n"; }
else { die "Failed to fetch URL: $url: " . $resp->status_line() . "\n"; }

exit();

1;

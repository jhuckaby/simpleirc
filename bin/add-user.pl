#!/usr/bin/perl

##
# add-user.pl
# IRCSimple v1.0 Command-line IRC user creation tool.
# Copyright (c) 2013 Joseph Huckaby and EffectSoftware.com
# Released under the MIT License.
# 
# Usage:
#	./add-user.pl --Username bob --Password 12345 --FullName "Bob" --Email "a@b.com" --Administrator 1
##

use strict;
use warnings;
use File::Basename;
use Cwd qw/abs_path/;
use URI::Escape;
use Digest::MD5 qw(md5_hex);
use English qw( -no_match_vars ) ;
use IRC::Utils ':ALL';

BEGIN {
	push @INC, dirname(dirname(abs_path($0))) . "/lib";
}
use Tools;

$| = 1;

if ($UID != 0) { die "Error: Must be root to add SimpleIRC users.  Exiting.\n"; }

my $usage = "Usage: ./add-user.pl --Username USERNAME --Password PASSWORD --FullName \"REAL NAME\" --Email \"EMAIL\@ADDRESS\" [--Administrator 1]\n";

my $cmdline_args = new Args( @ARGV );
my $args = { %$cmdline_args }; # unbless
if (!$args->{Username} || !$args->{Password} || !$args->{FullName} || !$args->{Email}) { die $usage; }

if (!is_valid_nick_name($args->{Username})) { die "ERROR: Username '".$args->{Username}."' is not a valid IRC nickname.\n"; }
$args->{Username} = nnick( $args->{Username} );
if (!length($args->{Username})) { die "ERROR: That nickname cannot be registered, as it is invalid (must contain alphanumerics, not in brackets)\n"; }

my $base_dir = dirname(dirname(abs_path($0)));
chdir( $base_dir );

print "\n";

my $config = eval { json_parse(load_file('conf/config-defaults.json')); };
if (!$config) { die "Failed to parse config-defaults.json: $@\n\n"; }

# merge in web config
if (-e 'conf/config-web.json') {
	my $temp_config = eval { json_parse(load_file('conf/config-web.json')); };
	if (!$temp_config) { die "Failed to parse config-web.json: $@\n\n"; }
	merge_hashes( $config, $temp_config, 1 );
}

# merge in user config
if (-e 'conf/config.json') {
	my $temp_config = eval { json_parse(load_file('conf/config.json')); };
	if (!$temp_config) { die "Failed to parse config.json: $@\n\n"; }
	merge_hashes( $config, $temp_config, 1 );
}

# remove "comments" from json
remove_key_recursive( $config, '//' );

my $now = time();

$args->{Username} = lc($args->{Username});
my $username = $args->{Username};
my $user = $args;

$user->{Registered} = 1;
$user->{Status} = 'Active';
$user->{Modified} = $now;

my $user_file = "data/users/$username.json";
if (-e $user_file) {
	# user exists, merge in keys
	
	my $pid_file = 'logs/pid.txt';
	if (-e $pid_file) {
		my $pid = trim( load_file($pid_file) );
		if ($pid && kill(0, $pid)) {
			die "ERROR: User '$username' already exists.  Please stop the SimpleIRC service before modifying existing users, e.g. /etc/init.d/simpleircd stop\n\n";
		}
	}
	
	print "User $username already exists, merging in your parameters...\n";
	my $user_raw = load_file($user_file);
	my $old_user = undef;
	eval { $old_user = json_parse($user_raw); };
	if ($@) {
		die( "Failed to parse user file: $user_file: $@\n\n" );
	}
	merge_hashes( $old_user, $user, 1 );
	$user = $old_user;
}
else {
	# create new user
	print "Creating new user: $username...\n";
	$user->{ID} = generate_unique_id();
	$user->{Created} = $now;
	make_dirs_for( $user_file );
}

$user->{Password} = md5_hex( $user->{Password} . $user->{ID} );

if (!save_file_atomic( $user_file, json_compose_pretty($user) )) {
	die( "Failed to save user file: $user_file: $!\n\n" );
}

print "User $username saved successfully.\n";

print "\n";
exit();

1;

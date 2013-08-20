#!/usr/bin/perl

# SimpleIRC Installer Phase 2
# Invoked by install-latest-BRANCH.txt (remote-install.sh)
# by Joseph Huckaby
# Copyright (c) 2012-2013 EffectSoftware.com

use strict;
use FileHandle;
use File::Basename;
use DirHandle;
use Cwd 'abs_path';
use English qw( -no_match_vars ) ;
use Digest::MD5 qw/md5_hex/;
use Time::HiRes qw/time/;
use IO::Socket::INET;

BEGIN {
	push @INC, dirname(dirname(abs_path($0))) . "/lib";
}
use VersionInfo;

if ($UID != 0) { die "Error: Must be root to install SimpleIRC.  Exiting.\n"; }

my $base_dir = abs_path( dirname( dirname($0) ) );
chdir( $base_dir );

my $version = get_version();

my $standard_binary_paths = {
	'/bin' => 1,
	'/usr/bin' => 1,
	'/usr/local/bin' => 1,
	'/sbin' => 1,
	'/usr/sbin' => 1,
	'/usr/local/sbin' => 1,
	'/opt/bin' => 1,
	'/opt/local/bin' => 1
};
foreach my $temp_bin_path (split(/\:/, $ENV{'PATH'} || '')) {
	if ($temp_bin_path) { $standard_binary_paths->{$temp_bin_path} = 1; }
}

print "\nInstalling SimpleIRC " . $version->{Major} . '-' . $version->{Minor} . " (" . $version->{Branch} . ")...\n\n";

# Have cpanm install all our required modules, if we need them
foreach my $module (split(/\n/, load_file("$base_dir/install/perl-modules.txt"))) {
	if ($module =~ /\S/) {
		my $cmd = "/usr/bin/perl -M$module -e ';' >/dev/null 2>\&1";
		my $result = system($cmd);
		if ($result == 0) {
			print "Perl module $module is installed.\n";
		}
		else {
			my $cpanm_bin = find_bin("cpanm");
			if (!$cpanm_bin) {
				die "\nERROR: Could not locate 'cpanm' binary in the usual places.  Installer cannot continue.\n\n";
			}
			system("$cpanm_bin -n --configure-timeout=3600 $module");
			my $result = system($cmd);
			if ($result != 0) {
				die "\nERROR: Failed to install Perl module: $module.  Please try to install it manually, then run this installer again.\n\n";
			}
		}
	}
}

# JH 2013-08-19 Special patch for POE::Component::Server::TCP 1.354
# https://rt.cpan.org/Public/Bug/Display.html?id=87922
my $poe_tcp_version = trim(`/usr/bin/perl -MPOE::Component::Server::TCP -e 'print \$POE::Component::Server::TCP::VERSION;`);
if ($poe_tcp_version eq '1.354') {
	my $poe_tcp_patch_file = "$base_dir/install/patches/TCP.pm";
	my $poe_tcp_patch_size = (stat($poe_tcp_patch_file))[7];
	
	my $poe_tcp_dest_file = trim(`/usr/bin/perl -MPOE::Component::Server::TCP -e 'print \$INC{"POE/Component/Server/TCP.pm"};'`);
	my $poe_tcp_dest_size = (stat($poe_tcp_dest_file))[7];
	
	if ($poe_tcp_dest_size != $poe_tcp_patch_size) {
		print "Patching POE::Component::Server::TCP v1.354...\n";
		chmod 0644, $poe_tcp_dest_file;
		exec_shell( "cp -v $poe_tcp_patch_file $poe_tcp_dest_file");
		chmod 0444, $poe_tcp_dest_file;
	}
}

exec_shell( "chmod 775 $base_dir/bin/*" );

# detect first install
my $config_file = "$base_dir/conf/config-defaults.json";
my $first_install = (-e $config_file) ? 0 : 1;

# preserve old secret key, if upgrading
my $old_secret = '';
if (!$first_install) {
	my $temp = load_file($config_file);
	# "SecretKey" : "djhdkjfhdkj",
	if ($temp =~ m@\"SecretKey\"\s*\:\s*\"([^\"]*)\"@) { $old_secret = $1; }
}

# safe copy sample_conf to conf -- only if files don't already exist
exec_shell( "mkdir -p $base_dir/conf", 'quiet' );
safe_copy_dir( "$base_dir/sample_conf", "$base_dir/conf" );

# always copy over latest config-defaults.json (user config should be in config.json)
exec_shell( "cp $base_dir/sample_conf/config-defaults.json $base_dir/conf/config-defaults.json", 'quiet' );

# set config.json/SecretKey
my $secret_key = $old_secret || md5_hex( time() . $$ . rand() );
my $temp = load_file($config_file);
$temp =~ s@(\"SecretKey\"\s*\:\s*\")([^\"]*)(\")@ $1 . $secret_key . $3; @e;
save_file( $config_file, $temp );

# init.d script (+perms)
exec_shell( "cp $base_dir/install/simpleircd.init /etc/init.d/simpleircd" );
exec_shell( "chmod 775 /etc/init.d/simpleircd" );

if ($first_install) {
	# activate service for startup
	if (system("which chkconfig >/dev/null 2>\&1") == 0) {
		# redhat
		exec_shell( "chkconfig simpleircd on" );
	}
	elsif (system("which update-rc.d >/dev/null 2>\&1") == 0) {
		# ubuntu
		exec_shell( "update-rc.d simpleircd defaults" );
	}
	
	# find available port to use
	my $best_port = 8080;
	foreach my $port (80, 8080..8100) {
		if (!is_tcp_port_used($port)) { $best_port = $port; last; }
	}
	$temp = load_file($config_file);
	$temp =~ s@\b8080\b@$best_port@;
	save_file( $config_file, $temp );
	
	# bootstrap admin account
	my $admin_username = 'admin';
	my $admin_password = substr( md5_hex(time() . $$ . rand()), 0, 8 );
	exec_shell( "$base_dir/bin/add-user.pl --Username $admin_username --Password $admin_password --FullName \"Administrator\" --Email \"your\@email.com\" --Administrator 1", 'quiet' );
	
	print "\n";
	print ascii_box( "NEW ADMINISTRATOR LOGIN INFO:\n     Username: $admin_username\n     Password: $admin_password", "*", "     ", "     " );
	
	# print info on ports, url for web interface
	my $real_ip = trim(`curl -s http://effectsoftware.com/software/tools/remote_ip.php`) || '127.0.0.1';
	print "\nYour IRC server can be reached on port: 6667\n";
	print "The web admin UI URL is: http://$real_ip" . (($best_port ne 80) ? ":$best_port" : "") . "/\n";
	
} # first install

print "\nSimpleIRC Installation complete.\n\n";

exit();

sub is_tcp_port_used {
	# check if a tcp port is in use by an existing socket listener
	my $port = shift;
	my $socket = undef;
	
	local $SIG{ALRM} = sub { die "ALRM\n" };
	alarm 5;
	eval {
		$socket = new IO::Socket::INET(
			PeerAddr => '127.0.0.1',
			PeerPort => $port,
			Proto => "tcp",
			Type => SOCK_STREAM,
			Timeout => 5
		);
	};
	alarm 0;
	
	return !!$socket;
}

sub trim {
	##
	# Trim whitespace from beginning and end of string
	##
	my $text = shift;
	
	$text =~ s@^\s+@@; # beginning of string
	$text =~ s@\s+$@@; # end of string
	
	return $text;
}

sub ascii_box {
	# simple ascii box
	my $text = shift;
	my $border = shift || '*';
	my $indent = shift || '';
	my $horiz_space = shift || '';
	
	my $output = '';
	my $lines = [];
	my $longest_line = 0;
	
	foreach my $line (split("\n", $text)) {
		$line = $horiz_space . $line . $horiz_space;
		if (length($line) > $longest_line) { $longest_line = length($line); }
		push @$lines, $line;
	}
	
	$output .= $indent . ($border x ($longest_line + 4)) . "\n";
	$output .= $indent . $border . (' ' x ($longest_line + 2)) . $border . "\n";
	
	foreach my $line (@$lines) {
		$output .= $indent . $border . ' ' . $line . (' ' x ($longest_line - length($line))) . ' ' . $border . "\n";
	}
	
	$output .= $indent . $border . (' ' x ($longest_line + 2)) . $border . "\n";
	$output .= $indent . ($border x ($longest_line + 4)) . "\n";
	
	return $output;
}

sub safe_copy_dir {
	# recursively copy dir and files, but only if they don't already exist in the destination
	my ($source_dir, $dest_dir) = @_;
	
	my $dirh = new DirHandle $source_dir;
	unless (defined($dirh)) { return; }
	
	my $filename;
	while (defined($filename = $dirh->read())) {
		if (($filename ne '.') && ($filename ne '..')) {
			if (-d "$source_dir/$filename") {
				if (!(-d "$dest_dir/$filename")) { mkdir "$dest_dir/$filename", 0775; }
				safe_copy_dir( "$source_dir/$filename", "$dest_dir/$filename" );
			}
			elsif (!(-e "$dest_dir/$filename")) {
				exec_shell( "cp $source_dir/$filename $dest_dir/$filename", 'quiet' );
			}
		} # don't process . and ..
	}
	undef $dirh;
}

sub exec_shell {
	my $cmd = shift;
	my $quiet = shift || 0;
	if (!$quiet) { print "Executing command: $cmd\n"; }
	print `$cmd 2>&1`;
}

sub find_bin {
	# locate binary executable on filesystem
	# look in the usual places, also PATH
	my $bin_name = shift;
	
	foreach my $parent_path (keys %$standard_binary_paths) {
		my $bin_path = $parent_path . '/' . $bin_name;
		if ((-e $bin_path) && (-x $bin_path)) {
			return $bin_path;
		}
	}
	
	return '';
}

sub load_file {
	##
	# Loads file into memory and returns contents as scalar.
	##
	my $file = shift;
	my $contents = undef;
	
	my $fh = new FileHandle "<$file";
	if (defined($fh)) {
		$fh->read( $contents, (stat($fh))[7] );
		$fh->close();
	}
	
	##
	# Return contents of file as scalar.
	##
	return $contents;
}

sub save_file {
	my $file = shift;
	my $contents = shift;

	my $fh = new FileHandle ">$file";
	if (defined($fh)) {
		$fh->print( $contents );
		$fh->close();
		return 1;
	}
	
	return 0;
}

1;

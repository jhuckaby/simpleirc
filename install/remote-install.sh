#!/bin/bash

##
# Remote Installer script for SimpleIRC 1.0
# Copyright (c) 2012-2013 Joseph Huckaby and PixlCore.com
# Released under the MIT License: http://opensource.org/licenses/MIT
#
# To install or upgrade, issue this command as root:
#
#	curl -s "http://pixlcore.com/software/simpleirc/install-latest-_BRANCH_.txt" | bash
#
# Or, if you don't have curl, you can use wget:
#
#	wget -O - "http://pixlcore.com/software/simpleirc/install-latest-_BRANCH_.txt" | bash
##

SIMPLEIRC_TARBALL="latest-_BRANCH_.tar.gz"

if [[ $EUID -ne 0 ]]; then
   echo "ERROR: The SimpleIRC remote installer script must be run as root." 1>&2
   exit 1
fi

echo ""
echo "Installing latest _BRANCH_ SimpleIRC build..."
echo ""

# Stop services, if they are running
/etc/init.d/simpleircd stop >/dev/null 2>&1

# Only run yum/apt-get on first install
if [ ! -f /opt/simpleirc/conf/config-defaults.json ]; then
	if which yum >/dev/null 2>&1 ; then 
		# Linux prereq install
		yum -y install perl wget gzip zip gcc gcc-c++ libstdc++-devel pkgconfig curl make openssl openssl-devel openssl-perl perl-libwww-perl perl-Time-HiRes perl-JSON perl-ExtUtils-MakeMaker perl-TimeDate perl-MailTools perl-MIME-Types perl-MIME-Lite || exit 1
	else
		if which apt-get >/dev/null 2>&1 ; then
			# Ubuntu prereq install
			apt-get -y install perl wget gzip zip build-essential libssl-dev pkg-config libwww-perl libjson-perl || exit 1
		else
			echo ""
			echo "ERROR: This server is not supported by the SimpleIRC auto-installer, as it does not have 'yum' nor 'apt-get'."
			echo "Please see the manual installation instructions at: http://effectgames.com/software/simpleirc/"
			echo ""
			exit 1
		fi
	fi

	if which cpanm >/dev/null 2>&1 ; then 
		echo "cpanm is already installed, good."
	else
		export PERL_CPANM_OPT="--notest --configure-timeout=3600"
		if which curl >/dev/null 2>&1 ; then 
			curl -L https://raw.githubusercontent.com/miyagawa/cpanminus/master/cpanm | perl - App::cpanminus
		else
			wget -O - https://raw.githubusercontent.com/miyagawa/cpanminus/master/cpanm | perl - App::cpanminus
		fi
	fi
fi

mkdir -p /opt
cd /opt
if which curl >/dev/null 2>&1 ; then 
	curl -O "http://pixlcore.com/software/simpleirc/$SIMPLEIRC_TARBALL" || exit 1
else
	wget "http://pixlcore.com/software/simpleirc/$SIMPLEIRC_TARBALL" || exit 1
fi
tar zxf $SIMPLEIRC_TARBALL || exit 1
rm -f $SIMPLEIRC_TARBALL

chmod 775 /opt/simpleirc/install/*
/opt/simpleirc/install/install.pl || exit 1

# Start service
/etc/init.d/simpleircd start || exit 1

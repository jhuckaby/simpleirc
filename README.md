SimpleIRC
=========

SimpleIRC is an easy-to-install and easy-to-use IRC server, written in Perl.  It was designed around the idea that setting up and running an IRC server should be simple.  SimpleIRC should run on any modern Linux server, and comes with a full web interface for administration (although you can also admin the server from the IRC console if you want).  SimpleIRC is built on the awesome [POE::Component::Server::IRC](http://search.cpan.org/dist/POE-Component-Server-IRC/) framework.

Features at a glance:

* Single-command install on most flavors of Linux.
* Built-in web interface for administration.
* Full SSL support, in both the IRC and embedded web server.
* Easy upgrades, from the Web UI or within IRC.
* Log archival and retrieval system.
* User modes are auto-remembered for registered users.
* Public or private channels (with invites and permanent users).
* Administrators can broadcast notices to all channels.
* NickServ and ChanServ service bots included.
* Supports both channel and server-wide bans.
* Database implemented with simple JSON files on disk.

## Single-Command Install

To install SimpleIRC, execute this command as root on your server:

    curl -s "http://effectsoftware.com/software/simpleirc/install-latest-stable.txt" | bash

Or, if you don't have curl, you can use wget:

    wget -O - "http://effectsoftware.com/software/simpleirc/install-latest-stable.txt" | bash

This will install the latest stable version of SimpleIRC.  Change the word "stable" to "dev" to install the development branch.  This single command installer should work fine on any modern Linux RedHat (RHEL, Fedora, CentOS) or Debian (Ubuntu) operating system.  Basically, anything that has "yum" or "apt-get" should be happy.  See the [manual installation instructions](https://github.com/jhuckaby/simpleirc/wiki/Manual-Installation) for other OSes, or if the single-command installer doesn't work for you.

After installation, you will be provided instructions for logging in as an administrator.

## Differences from "Standard" IRC

If you have used IRC before, then you may notice that SimpleIRC does things a little bit differently.  While it still supports the IRC protocol, and should work with nearly all IRC client applications, there are indeed some key differences from "standard" IRC.

The most important difference is, _your nickname is your identity_.  SimpleIRC completely ignores the IRC "username" you log in with, and relies solely on your nickname for identification.  If you change your nick while logged in, you have effectively logged out and logged in as a new user, and all your privileges (modes) are instantly changed to reflect that.  If you have Ops in a channel and change your nick, your Ops are taken away.  If you nick back and re-identify, your original modes are restored.

SimpleIRC only implements a few select user modes, to keep things simple.  Voice (+v), Half-Op (+h), and Op (+o) are the only modes supported in channels.  There is the concept of a server administrator, which gets server-wide +o (O-Line) and +o in all channels too, but appears to others as a standard Op.

You can optionally configure your server to require nicks and/or channels to be registered.  You can also lock it down so only server administrators can create new channels, and even make them private (invite only).  Users added to channels (given a mode, or added in the web UI) are permanently invited.

## Copyright and Legal

SimpleIRC is copyright (c) 2013 by Joseph Huckaby and EffectSoftware.com.  It is released under the MIT License (see below).

Note that this software ships with some bundled 3rd party software libraries which have different licenses:

> Contains a bundled copy of jQuery:
> http://jquery.org/license

> Also contains a bundled copy of md5.js:
> Version 2.0 Copyright (C) Paul Johnston 1999 - 2002.
> Distributed under the BSD License
> See http://pajhome.org.uk/crypt/md5 for more info.

SimpleIRC relies on the following non-core Perl modules, which are automatically installed, along with their prerequisites, using [cpanm](http://cpanmin.us):

* POE
* POE::Component::Server::IRC
* POE::Component::SSLify
* JSON
* JSON::XS
* MIME::Lite
* MIME::Types
* LWP::UserAgent
* URI::Escape
* HTTP::Date
* IRC::Utils

### MIT License

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in
all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
THE SOFTWARE.


Class.subclass( AppStr.Page.Base, "AppStr.Page.Settings", {	
		
	onInit: function() {
		// called once at page load
		var html = '';
		this.div.html( html );
	},
	
	onActivate: function(args) {
		// page activation
		if (!this.requireLogin(args)) return true;
		
		if (!args) args = {};
		this.args = args;
		
		app.showTabBar(true);
		Uploader.init();
		
		var sub = args.sub || 'config';
		this['gosub_'+sub](args);
		
		return true;
	},
	
	gosub_config: function(args) {
		// edit config subpage
		// this.div.addClass('loading');
		app.api.post( 'config', {}, [this, 'receive_config'] );
	},
	
	receive_config: function(resp, tx) {
		var html = '';
		var config = this.config = resp.Config;
		var version = this.version = resp.Version;
		// this.div.removeClass('loading');
		
		app.setWindowTitle( "Server Configuration" );
		
		html += this.getSidebarTabs( 'config',
			[
				['config', "Configuration"],
				['text', "Info Text Files"],
				['bans', "Server IP Bans"]
			]
		);
		
		html += '<div style="padding:20px;"><div class="subtitle">Server Configuration</div></div>';
		
		html += '<div style="padding:0px 20px 50px 20px; margin-right:200px; position:relative;">';
		
		// right sidebar
		html += '<div style="position:absolute; width:180px; left:100%; margin-right:200px;">';
		
			// server restart, shutdown, broadcast (btn --> dialog)
			html += '<fieldset style="padding-top:12px; padding-bottom:12px;"><legend>Server Control</legend>';
				html += '<div class="button center" style="margin-bottom:10px" onMouseUp="$P().ask_restart_server()">Restart Server</div>';
				html += '<div class="button center" style="margin-bottom:10px" onMouseUp="$P().ask_stop_server()">Stop Server</div>';
				html += '<div class="button center" onMouseUp="$P().ask_broadcast()">Broadcast...</div>';
			html += '</fieldset>';
			
			// simpleirc version check, upgrade button
			html += '<fieldset style="margin-top:12px; padding-top:12px; padding-bottom:12px;"><legend>Version Check</legend>';
				html += '<div class="info_label">LOCAL ' + this.version.Branch.toUpperCase() + ' VERSION</div>';
				html += '<div class="info_value">v' + this.version.Major + '-' + this.version.Minor + ' (' + this.version.BuildID.substring(0,8) + ')</div>';
				
				html += '<div id="d_version_check" class="loading"></div>';
				
				html += '<hr/>';
				html += '<div class="info_label">SWITCH BRANCH</div>';
				var branch_items = [ ['dev', "Development"], ['stable', "Stable"] ];
				html += '<select id="fe_es_branch" onChange="$P().ask_switch_branch(this.options[this.selectedIndex].value)">' + render_menu_options(branch_items, this.version.Branch) + '</select>';
			html += '</fieldset>';
			
			// logo uploader
			html += '<fieldset style="margin-top:12px; padding-top:12px; padding-bottom:12px;"><legend>Custom Logo</legend>';
				html += '<div id="d_logo_upload" onMouseUp="Uploader.chooseFiles()"></div>';
				html += '<div class="caption" style="">Drag and drop a custom logo into the image slot above, or click to upload one.  Please use only JPEG, PNG or GIF images, 45x45 pixels.</div>';
			html += '</fieldset>';
		
		html += '</div>';
		
		// main configuration form
		
		// html += '<center>';
		html += '<table style="margin:0;">';
		
		// server hostname
		html += get_form_table_row( 'Hostname', '<input type="text" id="fe_es_servername" size="20" placeholder="irc.myserver.com" value="'+escape_text_field_value(config.ServerName)+'"/>' );
		html += get_form_table_caption( "Enter the hostname for your IRC server, e.g. \"irc.myserver.com\".  This is used to identify the server when users connect.  If you don't have a hostname, you can make one up, or just use the IP address.");
		html += get_form_table_spacer('short transparent');
		
		// server title
		html += get_form_table_row( 'Server Title', '<input type="text" id="fe_es_serverdesc" size="40" value="'+escape_text_field_value(config.ServerDesc)+'"/>' );
		html += get_form_table_caption( "Enter a title for your IRC server, which is shown here on the web interface, as well as in e-mails to users.");
		
		html += get_form_table_spacer();
		
		// insecure irc port, checkbox
		// ssl irc port, checkbox
		html += get_form_table_row( 'Standard IRC', '<table cellspacing="0" cellpadding="0"><tr><td><input type="checkbox" id="fe_es_portchecked" value="1" '+(config.Port ? 'checked="checked"' : '')+'/></td><td><label for="fe_es_portchecked" style="font-size:13px;">Enable standard IRC on port:</label>&nbsp;</td><td><input type="text" id="fe_es_port" size="6" placeholder="6667" value="'+escape_text_field_value(config.Port)+'"/></td></tr></table>' );
		html += get_form_table_row( 'Secure IRC', '<table cellspacing="0" cellpadding="0"><tr><td><input type="checkbox" id="fe_es_sslchecked" value="1" '+(config.SSL.Enabled ? 'checked="checked"' : '')+'/></td><td><label for="fe_es_sslchecked" style="font-size:13px;">Enable secure SSL IRC on port:</label>&nbsp;</td><td><input type="text" id="fe_es_sslport" size="6" placeholder="6697" value="'+escape_text_field_value(config.SSL.Port)+'"/></td></tr></table>' );
		html += get_form_table_caption( "Choose how you want your IRC service implemented, using standard (insecure) and/or SSL encrypted modes.  Note that SSL requires a certificate (an example one is provided for testing, but shouldn't be used for production)." );
		html += get_form_table_spacer();
		
		// NickServ Enabled
		html += get_form_table_row( 'Manage Nicknames', '<input type="checkbox" id="fe_es_ns_enabled" value="1" '+(config.Plugins.NickServ.Enabled ? 'checked="checked"' : '')+' onChange="$P().setGroupVisible(\'nick\',this.checked)"/><label for="fe_es_ns_enabled">Enable IRC nickname management</label>' );
		html += get_form_table_caption( "This enables nickname registration and management on the IRC server, commonly known as 'NickServ'.");
		html += get_form_table_spacer('nickgroup', 'short transparent');
		
		// NickServ RegForce
		html += get_form_table_row( 'nickgroup', 'Enforcement', '<input type="checkbox" id="fe_es_ns_regforce" value="1" '+(config.Plugins.NickServ.RegForce ? 'checked="checked"' : '')+'/><label for="fe_es_ns_regforce">Force nickname registration</label>' );
		html += get_form_table_caption( 'nickgroup', "This forces users to register their nicknames.  If they do not register within the timeout (see below), their nickname will be changed.");
		html += get_form_table_spacer('nickgroup', 'short transparent');
		
		// NickServ RegTimeout
		html += get_form_table_row( 'nickgroup', 'Nick Time Limit', '<input type="text" id="fe_es_ns_regtimeout" size="3" placeholder="60" value="'+escape_text_field_value(config.Plugins.NickServ.RegTimeout)+'"/>&nbsp;(seconds)' );
		html += get_form_table_caption( 'nickgroup', "Enter the number of seconds users are given to register or identify nicknames, before timing out and changing their name.");
		html += get_form_table_spacer('nickgroup', 'short transparent');
		
		// NickServ RegExclude
		/* html += get_form_table_row( 'nickgroup', 'Nick Exclusions', '<input type="text" id="fe_es_ns_regexclude" size="20" placeholder="^(Web|Unidentified)\\d+$" value="'+escape_text_field_value(config.Plugins.NickServ.RegExclude)+'"/>' );
		html += get_form_table_caption( 'nickgroup', "If nickname registration enforcement is enabled, names that match this regular expression pattern are excluded from registration.  For example, this can be used to allow anonymous web visitors, if you use a web IRC client.");
		html += get_form_table_spacer('nickgroup', 'short transparent'); */
		
		// NickServ UnregPrefix
		/* html += get_form_table_row( 'nickgroup', 'Unreg Prefix', '<input type="text" id="fe_es_ns_unregprefix" size="10" placeholder="Unidentified" value="'+escape_text_field_value(config.Plugins.NickServ.UnregPrefix)+'"/>' );
		html += get_form_table_caption( 'nickgroup', "If nickname registration enforcement is enabled, users who do not register within the time limit are given a new nickname with this prefix, and a random number added to the end.  Make sure this prefix is also in the exclusion pattern above.");
		html += get_form_table_spacer('nickgroup', 'short transparent'); */
		
		// NickServ NickExpireDays
		html += get_form_table_row( 'nickgroup', 'Nick Expiration', '<input type="text" id="fe_es_ns_expiredays" size="3" placeholder="360" value="'+escape_text_field_value(config.Plugins.NickServ.NickExpireDays)+'"/>&nbsp;(days)' );
		html += get_form_table_caption( 'nickgroup', "Enter the number of days before abandoned nicknames will expire and be deleted from the server.  Server administrators are excluded from this.");
		html += get_form_table_spacer('nickgroup', 'short transparent');
		
		// max nick length
		html += get_form_table_row( 'nickgroup', 'Max Nick Length', '<input type="text" id="fe_es_ns_nicklength" size="3" placeholder="32" value="'+escape_text_field_value(config.MaxNickLength)+'"/>&nbsp;(chars)' );
		html += get_form_table_caption( 'nickgroup', "Enter the maximum nickname length allowed on the server.");
		
		html += get_form_table_spacer();
		
		// ChanServ Enabled
		html += get_form_table_row( 'Manage Channels', '<input type="checkbox" id="fe_es_cs_enabled" value="1" '+(config.Plugins.ChanServ.Enabled ? 'checked="checked"' : '')+' onChange="$P().setGroupVisible(\'chan\',this.checked)"/><label for="fe_es_cs_enabled">Enable IRC channel management</label>' );
		html += get_form_table_caption( "This enables channel registration and management on the IRC server, commonly known as 'ChanServ'.");
		html += get_form_table_spacer('changroup', 'short transparent');
		
		// ChanServ RegForce
		html += get_form_table_row( 'changroup', 'Enforcement', '<input type="checkbox" id="fe_es_cs_regforce" value="1" '+(config.Plugins.ChanServ.RegForce ? 'checked="checked"' : '')+'/><label for="fe_es_cs_regforce">Force channel registration</label>' );
		html += get_form_table_caption( 'changroup', "This forces users to register new channels before they are allowed to join them.");
		html += get_form_table_spacer('changroup', 'short transparent');
		
		// ChanServ ChannelBanDays
		html += get_form_table_row( 'changroup', 'Channel Bans', '<input type="text" id="fe_es_cs_bandays" size="3" placeholder="90" value="'+escape_text_field_value(config.Plugins.ChanServ.ChannelBanDays)+'"/>&nbsp;(days)' );
		html += get_form_table_caption( 'changroup', "Enter the default number of days that channel bans should last (this is also configurable per ban).");
		html += get_form_table_spacer('changroup', 'short transparent');
		
		// ChanServ FreeChannels
		html += get_form_table_row( 'changroup', 'Free Channels', '<input type="checkbox" id="fe_es_cs_freechannels" value="1" '+(config.Plugins.ChanServ.FreeChannels ? 'checked="checked"' : '')+'/><label for="fe_es_cs_freechannels">Allow all users to create channels</label>' );
		html += get_form_table_caption( 'changroup', "This allows any user to create and register a new channel on the server.  If disabled, only server administrators may do so.");
		
		html += get_form_table_spacer();
		
		// Logging Enabled
		html += get_form_table_row( 'Logging', '<input type="checkbox" id="fe_es_log_enabled" value="1" '+(config.Logging.Enabled ? 'checked="checked"' : '')+' onChange="$P().setGroupVisible(\'log\',this.checked)"/><label for="fe_es_log_enabled">Enable server logging</label>' );
		html += get_form_table_caption( "This enables logging on the server.");
		html += get_form_table_spacer('loggroup', 'short transparent');
		
		// Logging ActiveLogs
		html += get_form_table_row( 'loggroup', 'Active Logs', '<input type="checkbox" id="fe_es_log_transcript" value="1" '+(config.Logging.ActiveLogs.transcript ? 'checked="checked"' : '')+'/><label for="fe_es_log_transcript">IRC Transcript</label>&nbsp;&nbsp;&nbsp;<input type="checkbox" id="fe_es_log_error" value="1" '+(config.Logging.ActiveLogs.error ? 'checked="checked"' : '')+'/><label for="fe_es_log_error">Errors</label>&nbsp;&nbsp;&nbsp;<input type="checkbox" id="fe_es_log_debug" value="1" '+(config.Logging.ActiveLogs.debug ? 'checked="checked"' : '')+'/><label for="fe_es_log_debug">Debug</label>&nbsp;&nbsp;&nbsp;<input type="checkbox" id="fe_es_log_maint" value="1" '+(config.Logging.ActiveLogs.maint ? 'checked="checked"' : '')+'/><label for="fe_es_log_maint">Maintenance</label>' );
		html += get_form_table_caption( 'loggroup', "Choose which logs you want to enable here.");
		html += get_form_table_spacer('loggroup', 'short transparent');
		
		// Logging LogPrivateMessages
		html += get_form_table_row( 'loggroup', 'Privacy', '<input type="checkbox" id="fe_es_log_private" value="1" '+(config.Logging.LogPrivateMessages ? 'checked="checked"' : '')+'/><label for="fe_es_log_private">Log private messages</label>' );
		html += get_form_table_caption( 'loggroup', "Enable this if you want private messages logged to the transcript and debug log.");
		html += get_form_table_spacer('loggroup', 'short transparent');
		
		// Logging DebugLevel
		var debug_level_items = [
			[1, '1 (Quietest)'], [2, '2'], [3, '3'], [4, '4'], [5, '5'], [6, '6'], [7, '7'], [8, '8'], [9, '9 (Loudest)']
		];
		html += get_form_table_row( 'loggroup', 'Debug Level', '<select id="fe_es_log_debuglevel">' + render_menu_options(debug_level_items, config.Logging.DebugLevel) + '</select>' );
		html += get_form_table_caption( 'loggroup', "Select the debug log verbosity, from 1 to 9.");
		
		html += get_form_table_spacer();
		
		// WebServer Enabled
		html += get_form_table_row( 'Web Server', '<input type="checkbox" id="fe_es_web_enabled" value="1" '+(config.WebServer.Enabled ? 'checked="checked"' : '')+' onChange="$P().setGroupVisible(\'web\',this.checked)"/><label for="fe_es_web_enabled">Enable web server</label>' );
		html += get_form_table_caption( "This enables the web server you are using now, which drives this user interface.");
		html += get_form_table_spacer('webgroup', 'short transparent');
		
		// WebServer Port
		html += get_form_table_row( 'webgroup', 'Port Number', '<input type="text" id="fe_es_web_port" size="4" placeholder="80" value="'+escape_text_field_value(config.WebServer.Port)+'"/>' );
		html += get_form_table_caption( 'webgroup', "Enter the port number the web server should listen on.  Standard ports are 80 for HTTP and 443 for HTTPS.");
		html += get_form_table_spacer('webgroup', 'short transparent');
		
		// WebServer SSL
		html += get_form_table_row( 'webgroup', 'Secure HTTPS', '<input type="checkbox" id="fe_es_web_ssl" value="1" '+(config.WebServer.SSL ? 'checked="checked"' : '')+' onChange="$P().setWebServerSSL(this.checked)"/><label for="fe_es_web_ssl">Enable SSL (HTTPS)</label>' );
		html += get_form_table_caption( 'webgroup', "This enables SSL (HTTPS) encryption on the web server.  This requires a SSL certificate (an example one is provided for testing, but shouldn't be used for production).");
		html += get_form_table_spacer('webgroup', 'short transparent');
		
		// WebServer RedirectNonSSLPort
		html += get_form_table_row( 'webgroup', 'Non-SSL Redirect', '<table cellspacing="0" cellpadding="0"><tr><td><input type="checkbox" id="fe_es_web_nsr_enabled" value="1" '+(config.WebServer.RedirectNonSSLPort ? 'checked="checked"' : '')+'/></td><td><label for="fe_es_web_nsr_enabled" style="font-size:13px;">Enable non-ssl HTTP redirects on port:</label>&nbsp;</td><td><input type="text" id="fe_es_web_nsr_port" size="6" placeholder="80" value="'+escape_text_field_value(config.WebServer.RedirectNonSSLPort)+'"/></td></tr></table>' );
		html += get_form_table_caption( 'webgroup', "If HTTPS is enabled, you can optionally have the web server also listen on a standard HTTP port such as 80, and redirect all traffic to HTTPS.");
		
		html += get_form_table_spacer();
		
		// server ban days
		html += get_form_table_row( 'Server Bans', '<input type="text" id="fe_es_bandays" size="3" placeholder="90" value="'+escape_text_field_value(config.ServerBanDays)+'"/>&nbsp;(days)' );
		html += get_form_table_caption( "Enter the default number of days that server-wide bans should last (this is also configurable per ban).");
		html += get_form_table_spacer();
		
		// MaskIPs
		html += get_form_table_row( 'Hide IPs', '<input type="checkbox" id="fe_es_maskips" value="1" '+(config.MaskIPs.Enabled ? 'checked="checked"' : '')+'/><label for="fe_es_maskips">Hide user IPs from non-administrators</label>' );
		html += get_form_table_caption( "When this feature is enabled, user IP addresses are hidden (masked) and not shown to others on the server (except for server administrators).  Channel Ops can still ban users by their IP mask.");
		html += get_form_table_spacer();
		
		html += '<tr><td colspan="2" align="center">';
			html += '<div style="height:30px;"></div>';
			
			html += '<table><tr>';
				html += '<td><div class="button" style="width:115px;" onMouseUp="$P().do_save_config()">Save Changes</div></td>';
			html += '</tr></table>';
			
		html += '</td></tr>';
		
		html += '</table>';
		// html += '</center>';
		html += '</div>'; // table wrapper div
		
		html += '</div>'; // sidebar tabs
		
		this.div.html( html );
		
		if (!config.Plugins.NickServ.Enabled) $('tr.nickgroup').hide();
		if (!config.Plugins.ChanServ.Enabled) $('tr.changroup').hide();
		if (!config.Logging.Enabled) $('tr.loggroup').hide();
		if (!config.WebServer.Enabled) $('tr.webgroup').hide();
		
		var self = this;
		setTimeout( function() {
			if (!config.Plugins.NickServ.Enabled) $('tr.nickgroup').hide();
			if (!config.Plugins.ChanServ.Enabled) $('tr.changroup').hide();
			if (!config.Logging.Enabled) $('tr.loggroup').hide();
			if (!config.WebServer.Enabled) $('tr.webgroup').hide();
			
			// version check (call home)
			app.api.get( 'check_version', { branch: version.Branch }, function(resp, tx) {
				self.receive_remote_version(resp, tx);
			} );
			
			// setup uploader
			$('#d_logo_upload').css({ 'background-image':"url(/api/get_logo?random="+Math.random()+")" });
			Uploader.setURL( '/api/upload_logo?format=json&pure=1' );
			Uploader.setMaxFiles( 1 );
			Uploader.setTypes( 'image/*' );
			Uploader.addDropTarget( '#d_logo_upload' );
			Uploader.onStart = function(files) {
				$('#d_logo_upload').css({ 'background-image':"url(/images/loading.gif)" });
			};
			Uploader.onComplete = function(args) {
				self.receive_upload_response(args);
			};
			Uploader.onError = function(msg) {
				app.doError( "Upload Error: " + msg );
			};
		}, 1 );
	},
	
	receive_upload_response: function(response) {
		// receive response from server after uploading new logo
		var json = null;
		try { json = JSON.parse( response.data ); }
		catch (e) {
			return app.doError("JSON Parser Error: " + e.toString());
		}
		var tree = json;
		
		if ((typeof(tree.Code) != 'undefined') && (tree.Code != 0)) {
			// special handling for session errors, logout right away
			if (tree.Code == 'session') {
				Debug.trace("User session cookie is invalid, forcing logout");
				app.doUserLogout(true);
				return;
			}
			
			// non-session error, show alert
			if (!tree.Description) tree.Description = "Unknown Network Error";
			return app.doError( "Error: " + tree.Description, tree.ErrorDetails );
		}
		
		$('#d_logo_upload, #d_header_logo').css({ 'background-image':"url(/api/get_logo?random="+Math.random()+")" });
		
		app.showMessage('success', "Your logo was changed successfully.");
	},
	
	receive_remote_version: function(resp, tx) {
		var remote_version = this.remote_version = resp.Version;
		var html = '';
		
		html += '<div class="info_label">LATEST ' + this.version.Branch.toUpperCase() + ' VERSION</div>';
		
		if (remote_version.BuildID != this.version.BuildID) {
			html += '<div class="info_value" style="color:red;">v' + remote_version.Major + '-' + remote_version.Minor + ' (' + remote_version.BuildID.substring(0,8) + ')</div>';
			html += '<div class="button center" style="margin-bottom:8px" onMouseUp="$P().ask_upgrade()">Upgrade...</div>';
		}
		else {
			html += '<div class="info_value" style="color:green;">v' + remote_version.Major + '-' + remote_version.Minor + ' (' + remote_version.BuildID.substring(0,8) + ')</div>';
			html += '<div>Your software is up to date.</div>';
		}
		
		$('#d_version_check').html( html ).removeClass('loading');
	},
	
	setGroupVisible: function(group, visible) {
		// set the nick, chan, log or web groups of form fields visible or invisible, 
		// according to master checkbox for each section
		var selector = 'tr.' + group + 'group';
		if (visible) $(selector).show(250);
		else $(selector).hide(250);
	},
	
	setWebServerSSL: function(enabled) {
		// set web server SSL enabled or disabled
		// set ports and features accordingly
		if (enabled) {
			if ($('#fe_es_web_port').val() == 80) {
				$('#fe_es_web_port').val( 443 );
				$('#fe_es_web_nsr_enabled').prop('checked', true);
				$('#fe_es_web_nsr_port').val( 80 );
			}
		}
		else {
			if ($('#fe_es_web_port').val() == 443) {
				$('#fe_es_web_port').val( 80 );
				$('#fe_es_web_nsr_enabled').prop('checked', false);
				$('#fe_es_web_nsr_port').val( '' );
			}
		}
	},
	
	ask_restart_server: function() {
		// confirm server restart command
		var self = this;
		app.confirm( '<span style="color:red">Restart Server</span>', "Are you sure you want to restart the server?  All current IRC users will be notified and disconnected.", "Restart", function(result) {
			if (result) {
				app.showProgress( 1.0, "Restarting server..." );
				app.api.post( 'server_restart', {}, function(resp, tx) {
					app.hideProgress();
					app.showMessage('success', "The server is restarting in the background.");
				} );
			}
		} );
	},
	
	ask_stop_server: function() {
		// confirm server stop command
		var self = this;
		app.confirm( '<span style="color:red">Stop Server</span>', "Are you sure you want to shut down server?  All IRC users will be disconnected, and this also shuts down the web server.", "Shutdown", function(result) {
			if (result) {
				app.showProgress( 1.0, "Shutting down server..." );
				app.api.post( 'server_stop', {}, function(resp, tx) {
					app.hideProgress();
					app.showMessage('success', "The server is shutting down in the background.");
				} );
			}
		} );
	},
	
	ask_broadcast: function() {
		// show dialog to gather custom broadcast message, then send it
		var self = this;
		var html = '';
		html += '<table>' + get_form_table_row('Message:', '<input type="text" id="fe_es_broadcast_msg" style="width:350px" value=""/>') + '</table>';
		html += '<div class="caption">Please enter your custom message to broadcast to all IRC channels.</div>';
		
		app.confirm( "Broadcast Message", html, "Send", function(result) {
			if (result) {
				var msg = trim($('#fe_es_broadcast_msg').val());
				Dialog.hide();
				if (msg.match(/\S/)) {
					app.showProgress( 1.0, "Sending message..." );
					app.api.post( 'broadcast_message', {
						Message: msg
					}, 
					function(resp, tx) {
						app.hideProgress();
						app.showMessage('success', "Your message was successfully sent to all IRC channels.");
					} ); // api.post
				} // good message
			} // user clicked add
		} ); // app.confirm
		
		setTimeout( function() { 
			$('#fe_es_broadcast_msg').focus().keypress( function(event) {
				if (event.keyCode == '13') { // enter key
					event.preventDefault();
					app.confirm_click(true);
				}
			} );
		}, 1 );
	},
	
	ask_upgrade: function() {
		// show dialog confirming server upgrade action
		var self = this;
		var remote_version = this.remote_version;
		
		app.confirm( '<span style="color:red">Upgrade Server</span>', 'Are you sure you want to upgrade SimpleIRC to v' + remote_version.Major + '-' + remote_version.Minor + ' (' + remote_version.BuildID.substring(0,8) + ')?  All current IRC users will be disconnected.', "Upgrade", function(result) {
			if (result) {
				app.showProgress( 1.0, "Starting upgrade..." );
				app.api.post( 'server_upgrade', {}, function(resp, tx) {
					app.hideProgress();
					app.showMessage('success', "The server is upgrading in the background.  Please refresh in a few minutes.");
				} );
			}
		} );
	},
	
	ask_switch_branch: function(new_branch) {
		// show dialog confirming branch change action
		var self = this;
		
		app.confirm( '<span style="color:red">Switch Branch</span>', 'Are you sure you want to switch to the SimpleIRC "'+ucfirst(new_branch)+'" branch?  This will also upgrade to the latest '+new_branch+' version, and all current IRC users will be disconnected.', "Upgrade", function(result) {
			if (result) {
				app.showProgress( 1.0, "Starting upgrade..." );
				app.api.post( 'server_upgrade', { branch: new_branch }, function(resp, tx) {
					app.hideProgress();
					app.showMessage('success', "The server is upgrading in the background.  Please refresh in a few minutes.");
				} );
			}
			else {
				// user cancelled, reset menu back to old value
				$('#fe_es_branch').val( app.version.Branch );
			}
		} );
	},
	
	do_save_config: function() {
		// save config to server
		app.hideMessage();
		
		var new_config = {
			ServerName: $('#fe_es_servername').val(),
			ServerDesc: $('#fe_es_serverdesc').val(),
			Port: trim($('#fe_es_portchecked').is(':checked') ? $('#fe_es_port').val() : ''),
			SSL: {
				Enabled: $('#fe_es_sslchecked').is(':checked') ? 1 : 0,
				Port: trim($('#fe_es_sslport').val())
			},
			Plugins: {
				NickServ: {
					Enabled: $('#fe_es_ns_enabled').is(':checked') ? 1 : 0,
					RegForce: $('#fe_es_ns_regforce').is(':checked') ? 1 : 0,
					RegTimeout: trim($('#fe_es_ns_regtimeout').val()),
					NickExpireDays: trim($('#fe_es_ns_expiredays').val())
				},
				ChanServ: {
					Enabled: $('#fe_es_cs_enabled').is(':checked') ? 1 : 0,
					RegForce: $('#fe_es_cs_regforce').is(':checked') ? 1 : 0,
					ChannelBanDays: trim($('#fe_es_cs_bandays').val()),
					FreeChannels: $('#fe_es_cs_freechannels').is(':checked') ? 1 : 0
				}
			},
			Logging: {
				Enabled: $('#fe_es_log_enabled').is(':checked') ? 1 : 0,
				LogPrivateMessages: $('#fe_es_log_private').is(':checked') ? 1 : 0,
				DebugLevel: $('#fe_es_log_debuglevel').val(),
				ActiveLogs: {
					error: $('#fe_es_log_error').is(':checked') ? 1 : 0,
					debug: $('#fe_es_log_debug').is(':checked') ? 1 : 0,
					transcript: $('#fe_es_log_transcript').is(':checked') ? 1 : 0,
					maint: $('#fe_es_log_maint').is(':checked') ? 1 : 0
				}
			},
			WebServer: {
				Enabled: $('#fe_es_web_enabled').is(':checked') ? 1 : 0,
				Port: trim($('#fe_es_web_port').val()),
				SSL: $('#fe_es_web_ssl').is(':checked') ? 1 : 0,
				RedirectNonSSLPort: trim($('#fe_es_web_nsr_enabled').is(':checked') ? $('#fe_es_web_nsr_port').val() : '')
			},
			MaskIPs: {
				Enabled: $('#fe_es_maskips').is(':checked') ? 1 : 0
			},
			MaxNickLength: trim($('#fe_es_ns_nicklength').val()),
			ServerBanDays: trim($('#fe_es_bandays').val())
		};
		
		// validation
		if (!new_config.ServerName.length) return app.badField('fe_es_servername', "You must enter a hostname for your server.  If you don't have one, just use the IP address.");
		if (!new_config.ServerName.match(/^[\w\-\.]+$/)) return app.badField('fe_es_servername', "Your server hostname appears to be invalid.  Please use alphanumerics, dashes and periods only.");
		
		if (!new_config.ServerDesc.length) return app.badField('fe_es_serverdesc', "You must enter a title for your server.  If you don't have one, just set it to something generic like 'IRC Server'.");
		
		if (new_config.Port && (!new_config.Port.match(/^\d+$/) || (parseInt(new_config.Port, 10) < 1) || (parseInt(new_config.Port, 10) > 65535))) return app.badField('fe_es_port', "The port number you entered appears to be invalid.  It must be a positive integer number between 1 - 65535.");
		
		if (new_config.SSL.Port && (!new_config.SSL.Port.match(/^\d+$/) || (parseInt(new_config.SSL.Port, 10) < 1) || (parseInt(new_config.SSL.Port, 10) > 65535))) return app.badField('fe_es_sslport', "The SSL port number you entered appears to be invalid.  It must be a positive integer number between 1 - 65535.");
		
		if (!new_config.Port && !new_config.SSL.Enabled) return app.doError("You must enable either the standard IRC or secure SSL IRC services.  They cannot both be disabled.");
		
		if (!new_config.Plugins.NickServ.RegTimeout) return app.badField('fe_es_ns_regtimeout', "You must enter the number of seconds for the nickname management registration / identification time limit.");
		if (!new_config.Plugins.NickServ.RegTimeout.match(/^\d+$/)) return app.badField('fe_es_ns_regtimeout', "The time limit you entered appears to be invalid.  Please enter a positive number of seconds.");
		
		if (!new_config.Plugins.NickServ.NickExpireDays) return app.badField('fe_es_ns_expiredays', "You must enter the number of days for abandoned nickname expiration.  If you don't want nicknames to ever expire, just enter an extremely large amount, like 36500 (100 years).");
		if (!new_config.Plugins.NickServ.NickExpireDays.match(/^\d+$/)) return app.badField('fe_es_ns_expiredays', "The nickname expiration you entered appears to be invalid.  Please enter a positive number of days.");
		
		if (!new_config.Plugins.ChanServ.ChannelBanDays) return app.badField('fe_es_cs_bandays', "You must enter the default number of days for channel bans.");
		if (!new_config.Plugins.ChanServ.ChannelBanDays.match(/^\d+$/)) return app.badField('fe_es_cs_bandays', "The channel ban days you entered appears to be invalid.  Please enter a positive number of days.");
		
		if (new_config.WebServer.Port && (!new_config.WebServer.Port.match(/^\d+$/) || (parseInt(new_config.WebServer.Port, 10) < 1) || (parseInt(new_config.WebServer.Port, 10) > 65535))) return app.badField('fe_es_web_port', "The web server port number you entered appears to be invalid.  It must be a positive integer number between 1 - 65535.");
		
		if (new_config.WebServer.Enabled && !new_config.WebServer.Port) return app.badField('fe_es_web_port', "You must enter a web server port number if the web server is enabled.");
		
		if (new_config.WebServer.RedirectNonSSLPort && (!new_config.WebServer.RedirectNonSSLPort.match(/^\d+$/) || (parseInt(new_config.WebServer.RedirectNonSSLPort, 10) < 1) || (parseInt(new_config.WebServer.RedirectNonSSLPort, 10) > 65535))) return app.badField('fe_es_web_nsr_port', "The web server non-ssl redirect port number you entered appears to be invalid.  It must be a positive integer number between 1 - 65535.");
		
		if (!new_config.MaxNickLength) return app.badField('fe_es_ns_nicklength', "You must enter the maximum number of characters allowed for IRC nicknames.");
		if (!new_config.MaxNickLength.match(/^\d+$/)) return app.badField('fe_es_ns_nicklength', "The maximum nickname length you entered appears to be invalid.  Please enter a positive number.");
		
		if (!new_config.ServerBanDays) return app.badField('fe_es_bandays', "You must enter the default number of days for server-wide bans.");
		if (!new_config.ServerBanDays.match(/^\d+$/)) return app.badField('fe_es_bandays', "The server ban days you entered appears to be invalid.  Please enter a positive number of days.");
		
		// save config now
		var self = this;
		// app.showProgress( 1.0, "Saving configuration..." );
		app.api.post( 'save_config', {
			Config: new_config
		}, 
		function(resp, tx) {
			var save_config_resp = resp;
			
			if (self.check_restart_needed(new_config)) {
				app.confirm( '<span style="color:red">Restart Required</span>', "You have made configuration changes that require a server restart.  Do you want to restart it now?  All IRC users will be notified and disconnected.", "Restart", function(result) {
					if (result) {
						app.showProgress( 1.0, "Restarting server..." );
						app.api.post( 'server_restart', {}, function(resp, tx) {
							app.hideProgress();
							
							// update local client config
							app.receiveConfig( save_config_resp );
							app.updateFromConfig();
							self.config = save_config_resp.Config;
							app.showMessage('success', "Configuration saved successfully.  The server is restarting in the background.");
						} );
					}
					else {
						// user cancelled server restart, but we still successfully saved the config
						// update local client config
						app.hideProgress();
						window.scrollTo( 0, 0 );
						app.receiveConfig( save_config_resp );
						app.updateFromConfig();
						self.config = save_config_resp.Config;
						app.showMessage('success', "Configuration saved successfully.");
					}
				} );
			}
			else {
				// no server restart necessary
				// update local client config
				app.hideProgress();
				window.scrollTo( 0, 0 );
				app.receiveConfig( save_config_resp );
				app.updateFromConfig();
				self.config = save_config_resp.Config;
				app.showMessage('success', "Configuration saved successfully.");
			}
		} ); // api.post
	},
	
	check_restart_needed: function(nc) {
		// check if a restart is needed based on the config changes
		var oc = this.config;
		
		if (nc.ServerName != oc.ServerName) return true;
		if (nc.Port != oc.Port) return true;
		if (nc.SSL.Enabled != oc.SSL.Enabled) return true;
		if (nc.SSL.Port != oc.SSL.Port) return true;
		if (nc.Plugins.NickServ.Enabled != oc.Plugins.NickServ.Enabled) return true;
		if (nc.Plugins.ChanServ.Enabled != oc.Plugins.ChanServ.Enabled) return true;
		if (nc.WebServer.Enabled != oc.WebServer.Enabled) return true;
		if (nc.WebServer.Port != oc.WebServer.Port) return true;
		if (nc.WebServer.SSL != oc.WebServer.SSL) return true;
		if (nc.WebServer.RedirectNonSSLPort != oc.WebServer.RedirectNonSSLPort) return true;
		if (nc.MaskIPs.Enabled != oc.MaskIPs.Enabled) return true;
		
		return false;
	},
	
	gosub_text: function(args) {
		// edit text files subpage
		// this.div.addClass('loading');
		app.api.post( 'get_config_texts', {}, [this, 'receive_texts'] );
	},
	
	receive_texts: function(resp, tx) {
		var html = '';
		var texts = this.texts = resp.Texts;
		// this.div.removeClass('loading');
		
		app.setWindowTitle( "Informational Text Files" );
		
		html += this.getSidebarTabs( 'text',
			[
				['config', "Configuration"],
				['text', "Info Text Files"],
				['bans', "Server IP Bans"]
			]
		);
		
		html += '<div style="padding:20px;"><div class="subtitle">Informational Text Files</div></div>';
				
		html += '<center>';
		html += '<table style="margin:0;">';
		
		// motd.txt
		html += get_form_table_row( 'Message of the Day', '<textarea id="fe_et_motd" style="width:600px; height:150px;">'+escape_textarea_field_value(texts.motd)+'</textarea>' );
		html += get_form_table_caption( "<div style=\"width:600px;\">This is the 'Message of the Day' or 'MOTD' for short, which typically contains a welcome message for new users.  Any user can retrieve the text by entering the '<b>/motd</b>' IRC command, and also, most IRC apps request the MOTD on connect.  This can be as many lines as you want.</div>");
		html += get_form_table_spacer();
		
		// info.txt
		html += get_form_table_row( 'Server Information', '<textarea id="fe_et_info" style="width:600px; height:150px;">'+escape_textarea_field_value(texts.info)+'</textarea>' );
		html += get_form_table_caption( "<div style=\"width:600px;\">This is the informational file (info.txt), which typically contains general information about the IRC server.  Any user can retrieve this text by entering the '<b>/info</b>' IRC command.  This can be as many lines as you want.</div>");
		html += get_form_table_spacer();
		
		// admin.txt
		html += get_form_table_row( 'Administrator', '<textarea id="fe_et_admin" style="width:600px;" rows="3">'+escape_textarea_field_value(texts.admin)+'</textarea>' );
		html += get_form_table_caption( "<div style=\"width:600px;\">This is the adminstrator info file (admin.txt), which typically contains information on how to contact a server administrator.  Any user can retrieve this text by entering the '<b>/admin</b>' IRC command.  This must be exactly 3 lines long.</div>");
		html += get_form_table_spacer();
		
		html += '<tr><td colspan="2" align="center">';
			html += '<div style="height:30px;"></div>';
			
			html += '<table><tr>';
				html += '<td><div class="button" style="width:115px;" onMouseUp="$P().do_save_config_texts()">Save Changes</div></td>';
			html += '</tr></table>';
			
			html += '<div style="height:30px;"></div>';
		html += '</td></tr>';
		
		html += '</table>';
		html += '</center>';
		html += '</div>'; // table wrapper div
		
		html += '</div>'; // sidebar tabs
		
		this.div.html( html );
	},
	
	do_save_config_texts: function() {
		// save text files back to server
		var texts = {
			admin: $('#fe_et_admin').val(),
			info: $('#fe_et_info').val(),
			motd: $('#fe_et_motd').val()
		};
		
		app.showProgress( 1.0, "Saving text files..." );
		app.api.post( 'save_config_texts', {
			Texts: texts
		}, 
		function(resp, tx) {
			app.hideProgress();
			window.scrollTo( 0, 0 );
			app.showMessage('success', "Text files saved successfully.");
		} );
	},
	
	gosub_bans: function(args) {
		// view / edit bans for channel
		// this.div.addClass('loading');
		if (!args.offset) args.offset = 0;
		if (!args.limit) args.limit = 50;
		app.api.get( 'server_get_bans', copy_object(args), [this, 'receive_server_bans'] );
	},
	
	receive_server_bans: function(resp, tx) {
		// receive page of server bans, render it
		var html = '';
		// this.div.removeClass('loading');
		
		app.setWindowTitle( "Server IP Bans" );
		
		this.bans = [];
		if (resp.Rows && resp.Rows.Row) this.bans = resp.Rows.Row;
		
		html += this.getSidebarTabs( 'bans',
			[
				['config', "Configuration"],
				['text', "Info Text Files"],
				['bans', "Server IP Bans"]
			]
		);
		
		var cols = ['Target Host/IP', 'Added By', 'Created', 'Expires', 'Actions'];
		
		// html += '<div style="padding:10px 20px 20px 20px;">';
		html += '<div style="padding:20px 20px 30px 20px">';
		// html += '<div class="subtitle">Server IP Bans</div>';
		
		html += '<div class="subtitle">';
			html += 'Server IP Bans';
			html += '<div class="subtitle_widget"><span class="link" onMouseUp="$P().refresh_server_bans()"><b>Refresh List</b></span></div>';
			html += '<div class="clear"></div>';
		html += '</div>';
		
		html += this.getPaginatedTable( resp, cols, 'ban', function(ban, idx) {
			var actions = [];
			actions.push( '<span class="link" onMouseUp="$P().edit_server_ban('+idx+')"><b>Edit</b></span>' );
			actions.push( '<span class="link" onMouseUp="$P().delete_server_ban('+idx+')"><b>Delete</b></span>' );
			
			return [
				'<div class="td_big">' + ban.TargetIP + '</div>',
				ban.AddedBy.replace(/\!.+$/, ''),
				get_short_date_time( ban.Created ),
				get_short_date_time( ban.Expires ),
				actions.join(' | ')
			];
		} );
		html += '</div>';
		
		// add ban button
		html += '<div class="button center" style="width:120px; margin-bottom:10px;" onMouseUp="$P().edit_server_ban(-1)">Add IP Ban...</div>';
		
		html += '</div>'; // sidebar tabs
		
		this.div.html( html );
	},
	
	refresh_server_bans: function() {
		// refresh user list
		app.api.mod_touch( 'server_get_bans' );
		this.gosub_bans(this.args);
	},
	
	edit_server_ban: function(idx, default_ip, callback) {
		// show dialog prompting for editing server ban (or adding one)
		var self = this;
		var ban = (idx > -1) ? this.bans[idx] : {
			TargetIP: default_ip || '',
			Expires: time_now() + (86400 * config.ServerBanDays)
		};
		var edit = (idx > -1) ? true : false;
		var html = '';
		
		html += '<table>' + 
			get_form_table_row('Target Host/IP:', '<input type="text" id="fe_es_ban_target_ip" size="20" value="'+escape_text_field_value(ban.TargetIP)+'"/>') + 
			get_form_table_caption("Enter the target user host or IP address here.  You may also use wildcards (*).") + 
			get_form_table_spacer() + 
			get_form_table_row('Ban Expires:', get_date_selector('fe_es_ban_expires', ban.Expires, 0, 10)) + 
			get_form_table_caption("Select the date when the ban should expire.  Bans are checked for expiration daily at midnight (local server time).") + 
		'</table>';
		
		app.confirm( edit ? "Edit Server Ban" : "Add Server Ban", html, edit ? "Save Changes" : "Add Ban", function(result) {
			if (result) {
				var ban_target_ip = trim($('#fe_es_ban_target_ip').val());
				var ban_expires = get_date_menu_value('fe_es_ban_expires');
				Dialog.hide();
				
				if (ban_target_ip) {
					app.showProgress( 1.0, edit ? "Saving ban..." : "Adding ban..." );
					app.api.post( edit ? 'server_update_ban' : 'server_add_ban', {
						OldTargetIP: edit ? ban.TargetIP : '',
						TargetIP: ban_target_ip,
						Expires: ban_expires
					}, 
					function(resp, tx) {
						app.hideProgress();
						app.showMessage('success', "Server ban was successfully " + (edit ? "saved" : "added") + ".");
						app.api.mod_touch('server_get_bans');
						if (callback) callback();
						else self.gosub_bans(self.args);
					} ); // api.post
				} // good username/ip
				else app.doError("You did not enter a target IP address for the ban.");
			} // user clicked add
		} ); // app.confirm
		
		setTimeout( function() { 
			$('#fe_es_ban_target_user, #fe_es_ban_target_ip').keypress( function(event) {
				if (event.keyCode == '13') { // enter key
					event.preventDefault();
					app.confirm_click(true);
				}
			} );
			$('#fe_es_ban_target_user').focus();
		}, 1 );
	},
	
	delete_server_ban: function(idx) {
		// delete server ban
		var self = this;
		var ban = this.bans[idx];
		
		app.api.post( 'server_delete_ban', {
			TargetUser: ban.TargetUser,
			TargetIP: ban.TargetIP
		}, 
		function(resp, tx) {
			app.showMessage('success', "Server ban was successfully removed.");
			
			app.api.mod_touch('server_get_bans');
			self.gosub_bans(self.args);
		} ); // api.post
	},
	
	onDeactivate: function() {
		// called when page is deactivated
		// this.div.html( '' );
		if ($('#d_logo_upload').length) {
			Uploader.removeDropTarget( '#d_logo_upload' );
		}
		return true;
	}
	
} );

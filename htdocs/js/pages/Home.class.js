Class.subclass( AppStr.Page.Base, "AppStr.Page.Home", {	
	
	onInit: function() {
		// called once at page load
		// var html = 'Now is the time (HOME)';
		// this.div.html( html );
	},
	
	onActivate: function(args) {
		// page activation
		if (!this.requireLogin(args)) return true;
		
		if (!args) args = {};
		this.args = args;
		
		app.setWindowTitle('Home');
		app.showTabBar(true);
		
		// this.div.addClass('loading');
		app.api.post( 'get_user_info', {}, [this, 'receive_user_info'] );
		
		return true;
	},
	
	receive_user_info: function(resp, tx) {
		// receive user info from server
		var html = '';
		// this.div.removeClass('loading');
		
		app.user = resp.User;
		app.user_info = resp.Info;
		
		// wrapper div
		html += '<div style="padding:6px;">';
		
		if (resp.Status) {
			var status = resp.Status;
			html += '<div style="width:100%; margin-bottom:15px;">';
				html += '<fieldset style="margin-right:0px; padding-top:10px;"><legend>Server Status</legend>';
					
					html += '<div style="float:left; width:25%;">';
						html += '<div class="info_label">SERVER HOSTNAME</div>';
						html += '<div class="info_value">' + status.Hostname + '</div>';
						
						html += '<div class="info_label">SIMPLEIRC VERSION</div>';
						html += '<div class="info_value">' + app.version.Major + '-' + app.version.Minor + ' (' + app.version.Branch + ')' + '</div>';
						
						html += '<div class="info_label">SERVICE UPTIME</div>';
						html += '<div class="info_value">' + get_text_from_seconds(status.Now - status.ServerStarted, false, true) + '</div>';
					html += '</div>';
					
					html += '<div style="float:left; width:25%;">';
						html += '<div class="info_label">USERS ONLINE</div>';
						html += '<div class="info_value">' + commify(status.NumUsersOnline) + '</div>';
						
						html += '<div class="info_label">REGISTERED USERS</div>';
						html += '<div class="info_value">' + commify(status.TotalRegisteredUsers) + '</div>';
						
						html += '<div class="info_label">REGISTERED CHANNELS</div>';
						html += '<div class="info_value">' + commify(status.TotalRegisteredChannels) + '</div>';
					html += '</div>';
					
					html += '<div style="float:left; width:25%;">';
						html += '<div class="info_label">MESSAGES SENT (TODAY)</div>';
						html += '<div class="info_value">' + commify(status.TotalMessagesSent) + '</div>';
						
						html += '<div class="info_label">TOTAL BYTES IN (TODAY)</div>';
						html += '<div class="info_value">' + get_text_from_bytes(status.TotalBytesIn) + '</div>';
						
						html += '<div class="info_label">TOTAL BYTES OUT (TODAY)</div>';
						html += '<div class="info_value">' + get_text_from_bytes(status.TotalBytesOut) + '</div>';
					html += '</div>';
									
					html += '<div style="float:left; width:25%;">';
						html += '<div class="info_label">MEMORY IN USE</div>';
						html += '<div class="info_value">' + get_text_from_bytes(status.TotalMemBytes) + '</div>';
						
						html += '<div class="info_label">CPU IN USE</div>';
						html += '<div class="info_value">' + status.TotalCPUPct + '%</div>';
						
						html += '<div class="info_label">DISK SPACE USED</div>';
						html += '<div class="info_value">' + get_text_from_bytes(status.TotalDiskUsage) + '</div>';
					html += '</div>';
					
					html += '<div class="clear"></div>';
					
				html += '</fieldset>';
			html += '</div>';
		} // full server status
		
		// basic info, admin or no, created / modified
		html += '<div style="float:left; width:50%;">';
			html += '<fieldset style="margin-right:8px; padding-top:10px;"><legend>My Account Info</legend>';
				
				html += '<div style="float:left; width:50%;">';
					html += '<div class="info_label">IRC NICKNAME</div>';
					html += '<div class="info_value">' + app.username + '</div>';
					
					html += '<div class="info_label">REAL NAME</div>';
					html += '<div class="info_value">' + app.user.FullName + '</div>';
					
					html += '<div class="info_label">EMAIL ADDRESS</div>';
					html += '<div class="info_value">' + app.user.Email + '</div>';
				html += '</div>';
				
				html += '<div style="float:right; width:50%;">';
					html += '<div class="info_label">ACCOUNT TYPE</div>';
					html += '<div class="info_value">' + (app.user.Administrator ? '<span class="color_label admin">Administrator</span>' : '<span class="color_label" style="background:gray;">Standard</span>') + '</div>';
					
					html += '<div class="info_label">REGISTERED</div>';
					html += '<div class="info_value">' + get_nice_date_time(app.user.Created) + '</div>';
					
					html += '<div class="info_label">LAST MODIFIED</div>';
					html += '<div class="info_value">' + get_nice_date_time(app.user.Modified) + '</div>';
				html += '</div>';
				
				html += '<div class="clear"></div>';
				
			html += '</fieldset>';
		html += '</div>';
		
		// current irc login or last login
		// last command, when
		html += '<div style="float:right; width:50%;">';
			html += '<fieldset style="margin-left:8px; padding-top:10px;"><legend>My IRC Info</legend>';
				
				html += '<div style="float:left; width:50%;">';
					html += '<div class="info_label">STATUS</div>';
					html += '<div class="info_value">' + (app.user._identified ? '<span class="color_label online">Connected</span>' : '<span class="color_label offline">Disconnected</span>') + '</div>';
					
					html += '<div class="info_label">' + (app.user._identified ? 'LOGGED IN' : 'LAST LOGIN') + '</div>';
					html += '<div class="info_value">' + (app.user.LastLogin ? get_nice_date_time(app.user.LastLogin) : 'n/a') + '</div>';
					
					html += '<div class="info_label">' + (app.user._identified ? 'IP ADDRESS' : 'LAST IP ADDRESS') + '</div>';
					html += '<div class="info_value">' + (app.user.IP ? app.user.IP : 'n/a') + '</div>';
				html += '</div>';
								
				html += '<div style="float:right; width:50%;">';
					html += '<div class="info_label">LAST ACTIVITY</div>';
					html += '<div class="info_value">' + (app.user.LastCmd ? get_nice_date_time(app.user.LastCmd.When) : 'n/a') + '</div>';
					
					html += '<div class="info_label">LAST COMMAND</div>';
					html += '<div class="info_value" style="line-height:14px; max-height:42px; overflow:hidden;">' + (app.user.LastCmd ? app.user.LastCmd.Raw : 'n/a') + '</div>';
				html += '</div>';
				
				html += '<div class="clear"></div>';
				
			html += '</fieldset>';
		html += '</div>';
		
		html += '<div class="clear"></div>';
		
		// my channels
		if (config.Plugins.ChanServ.Enabled) {
			html += '<div class="subtitle" style="margin-top:20px; margin-bottom:4px;">My Channels</div>';
			if (!this.args.offset) this.args.offset = 0;
			if (!this.args.limit) this.args.limit = 9999;
			
			var rows = [];
			var sorted_chans = hash_keys_to_array( app.user_info.Channels ).sort();
			for (var idx = 0, len = sorted_chans.length; idx < len; idx++) {
				var chan = sorted_chans[idx];
				var channel = app.user_info.Channels[chan];
				channel.Name = chan;
				rows.push( channel );
			}
			
			var cols = ['Channel', 'Users Online', 'My Status', 'Founder', 'Access', 'Created', 'Topic'];
			var list_resp = {
				List: { length: rows.length },
				Rows: { Row: rows }
			};
			html += this.getPaginatedTable( list_resp, cols, 'channel', function(channel, idx) {
				var status = '(None)';
				if (channel.Flags.match(/f/)) status = '<span class="color_label founder">Founder</span>';
				else if (channel.Flags.match(/o/)) status = '<span class="color_label op">Operator</span>';
				else if (channel.Flags.match(/h/)) status = '<span class="color_label halfop">Half-Op</span>';
				else if (channel.Flags.match(/v/)) status = '<span class="color_label voice">Voice</span>';
				return [
					'<div class="td_big"><a href="#Channels?sub=edit&channel='+channel.Name+'">#' + channel.Name + '</a></div>',
					commify( channel.NumLiveUsers  ),
					status,
					channel.Founder,
					(channel.Private == 1) ? '<span class="color_label private">Private</span>' : '<span class="color_label public">Public</span>',
					get_nice_date( channel.Created ),
					expando_text( channel.Topic || '(None)', 80 )
				];
			} );
		}
		
		html += '</div>'; // wrapper
		
		this.div.html( html );
	},
	
	onDeactivate: function() {
		// called when page is deactivated
		// this.div.html( '' );
		return true;
	}
	
} );

Class.subclass( AppStr.Page.Base, "AppStr.Page.Channels", {	
		
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
		
		var sub = args.sub || 'list';
		this['gosub_'+sub](args);
		
		return true;
	},
	
	gosub_new: function(args) {
		// create new channel
		var html = '';
		app.setWindowTitle( "Add New Channel" );
		
		html += this.getSidebarTabs( 'new',
			[
				['list', "Channel List"],
				['new', "Add New Channel"]
			]
		);
		
		html += '<div style="padding:20px;"><div class="subtitle">Add New Channel</div></div>';
		
		html += '<div style="padding:0px 20px 50px 20px">';
		html += '<center><table style="margin:0;">';
		
		this.channel = {
			Founder: app.username
		};
		
		html += this.get_channel_edit_html();
		
		html += '<tr><td colspan="2" align="center">';
			html += '<div style="height:30px;"></div>';
			
			html += '<table><tr>';
				html += '<td><div class="button" style="width:120px;" onMouseUp="$P().do_new_channel()">Add Channel</div></td>';
			html += '</tr></table>';
			
		html += '</td></tr>';
		
		html += '</table></center>';
		html += '</div>'; // table wrapper div
		
		html += '</div>'; // sidebar tabs
		
		this.div.html( html );
		
		setTimeout( function() {
			$('#fe_ec_name').focus();
		}, 1 );
	},
	
	do_new_channel: function() {
		// create new channel
		app.clearError();
		var channel = this.get_channel_form_xml();
		if (!channel) return; // error
		
		this.channel = channel;
		
		app.showProgress( 1.0, "Creating channel..." );
		app.api.post( 'channel_create', channel, [this, 'new_channel_finish'] );
	},
	
	new_channel_finish: function(resp, tx) {
		// new channel created successfully
		app.hideProgress();
		app.api.mod_touch( 'channel_get', 'get_all_channels' );
		
		Nav.go('Channels?sub=list');
		
		setTimeout( function() {
			app.showMessage('success', "The new channel was added successfully.");
		}, 150 );
	},
	
	gosub_edit: function(args) {
		// edit channel subpage
		this.div.addClass('loading');
		app.api.post( 'channel_get', { Name: args.channel }, [this, 'receive_channel'] );
	},
	
	receive_channel: function(resp, tx) {
		// edit existing channel
		var html = '';
		this.channel = resp.Channel;
		this.div.removeClass('loading');
		app.setWindowTitle( "Editing Channel \""+this.channel.Name+"\"" );
		
		html += this.getSidebarTabs( 'edit',
			[
				['list', "Channel List"],
				['new', "Add New Channel"],
				['edit', "Edit Channel"],
				['users&channel=' + resp.Channel.Name, "Channel Users"],
				['bans&channel=' + resp.Channel.Name, "Channel Bans"]
			]
		);
		
		html += '<div style="padding:20px;"><div class="subtitle">Editing Channel ' + nch(this.channel.Name) + '</div></div>';
		
		html += '<div style="padding:0px 20px 50px 20px">';
		html += '<center>';
		html += '<table style="margin:0;">';
		
		html += this.get_channel_edit_html();
		
		html += '<tr><td colspan="2" align="center">';
			html += '<div style="height:30px;"></div>';
			
			html += '<table><tr>';
				html += '<td><div class="button" style="width:115px; font-weight:normal;" onMouseUp="$P().show_delete_channel_dialog()">Delete Channel...</div></td>';
				html += '<td width="50">&nbsp;</td>';
				html += '<td><div class="button" style="width:115px;" onMouseUp="$P().do_save_channel()">Save Changes</div></td>';
			html += '</tr></table>';
			
		html += '</td></tr>';
		
		html += '</table>';
		html += '</center>';
		html += '</div>'; // table wrapper div
		
		html += '</div>'; // sidebar tabs
		
		this.div.html( html );
		
		setTimeout( function() {
			$('#fe_ec_name').attr('disabled', true);
		}, 1 );
	},
	
	do_save_channel: function() {
		// create new channel
		app.clearError();
		var channel = this.get_channel_form_xml();
		if (!channel) return; // error
		
		this.channel = channel;
		
		app.showProgress( 1.0, "Saving channel..." );
		app.api.post( 'channel_update', channel, [this, 'save_channel_finish'] );
	},
	
	save_channel_finish: function(resp, tx) {
		// new channel created successfully
		app.hideProgress();
		window.scrollTo( 0, 0 );
		app.showMessage('success', "The channel was saved successfully.");
		app.api.mod_touch( 'channel_get', 'get_all_channels' );
	},
	
	show_delete_channel_dialog: function() {
		// show dialog confirming channel delete action
		var self = this;
		app.confirm( '<span style="color:red">Delete Channel</span>', "Are you sure you want to delete the channel <b>"+nch(this.channel.Name)+"</b>?  There is no way to undo this action.", "Delete", function(result) {
			if (result) {
				app.showProgress( 1.0, "Deleting Channel..." );
				app.api.post( 'channel_delete', {
					Name: self.channel.Name
				}, [self, 'delete_finish'] );
			}
		} );
	},
	
	delete_finish: function(resp, tx) {
		// finished deleting, immediately log channel out
		app.hideProgress();
		app.api.mod_touch( 'channel_get', 'get_all_channels' );
		
		Nav.go('Channels');
		
		setTimeout( function() {
			app.showMessage('success', "The channel was deleted successfully.");
		}, 150 );
	},
	
	get_channel_edit_html: function() {
		// get html for editing a channel (or creating a new one)
		var html = '';
		var channel = this.channel;
		
		var channel_name = channel.Name || '';
		if (channel_name && !channel_name.match(/^\#/)) channel_name = '#' + channel_name;
		
		// id
		html += get_form_table_row( 'Channel ID', '<input type="text" id="fe_ec_name" size="20" placeholder="#mychannel" value="'+escape_text_field_value(channel_name)+'"/>' );
		html += get_form_table_caption( "Enter an identifer for the channel, e.g. \"#mychannel\".  After creating the channel this cannot be changed.  Case insensitive.");
		html += get_form_table_spacer();
		
		// founder
		html += get_form_table_row( 'Founder', '<input type="text" id="fe_ec_founder" size="20" value="'+escape_text_field_value(channel.Founder)+'"/>' );
		html += get_form_table_caption( "Specify the nickname of the channel's 'founder' (i.e. owner), who will always have op privileges and can manage/delete the channel.");
		html += get_form_table_spacer();
		
		// url
		html += get_form_table_row( 'URL', '<input type="text" id="fe_ec_url" size="50" value="'+escape_text_field_value(channel.URL)+'"/>' );
		html += get_form_table_caption( "Optionally enter a URL for the channel.  Some IRC clients show this to users who join.");
		html += get_form_table_spacer();
		
		// access
		html += get_form_table_row( 'Access', '<select id="fe_ec_access">' + render_menu_options([['0','Public'], ['1','Private']], (channel.Private == 1) ? 1 : 0) + '</select>' );
		html += get_form_table_caption( "Select either 'Public' (all users can join), or 'Private' (users must be added manually).");
		html += get_form_table_spacer();
		
		// topic
		html += get_form_table_row( 'Topic', '<textarea id="fe_ec_topic" style="width:600px;" rows="3">'+escape_textarea_field_value(channel.Topic)+'</textarea>' );
		html += get_form_table_caption( "Optionally enter a topic (description) for the channel.  This can also be changed in IRC by channel ops.");
		html += get_form_table_spacer();
		
		// join notice
		html += get_form_table_row( 'Join Notice', '<textarea id="fe_ec_joinnotice" style="width:600px;" rows="3">'+escape_textarea_field_value(channel.JoinNotice)+'</textarea>' );
		html += get_form_table_caption( "Optionally enter a join notice for the channel.  The ChanServ bot will send this to all users who join the channel.");
		html += get_form_table_spacer();
		
		return html;
	},
	
	get_channel_form_xml: function() {
		// get channel xml elements from form, used for new or edit
		var channel = {
			Name: trim($('#fe_ec_name').val().toLowerCase().replace(/\W+/g, '')),
			Topic: trim($('#fe_ec_topic').val()),
			URL: trim($('#fe_ec_url').val()),
			JoinNotice: trim($('#fe_ec_joinnotice').val()),
			Private: parseInt( $('#fe_ec_access').val(), 10 ),
			Founder: $('#fe_ec_founder').val()
		};
		
		if (!channel.Name) return app.badField('fe_ec_name', "Please enter an ID for the channel.");
		if (!channel.Founder) return app.badField('fe_ec_founder', "Please enter a founder (owner) for the channel.");
		
		return channel;
	},
	
	gosub_list: function(args) {
		// show channel list
		app.setWindowTitle( "Channel List" );
		this.div.addClass('loading');
		if (!args.offset) args.offset = 0;
		if (!args.limit) args.limit = 50;
		app.api.get( 'get_all_channels', copy_object(args), [this, 'receive_channels'] );
	},
	
	receive_channels: function(resp, tx) {
		// receive page of channels from server, render it
		var html = '';
		this.div.removeClass('loading');
		
		html += this.getSidebarTabs( 'list',
			[
				['list', "Channel List"],
				['new', "Add New Channel"]
			]
		);
		
		var cols = ['Channel', 'Users Online', 'My Status', 'Founder', 'Access', 'Created', 'Topic'];
		
		// html += '<div style="padding:5px 15px 15px 15px;">';
		html += '<div style="padding:20px 20px 30px 20px">';
		
		html += '<div class="subtitle">';
			html += 'Channel List';
			html += '<div class="subtitle_widget"><span class="link" onMouseUp="$P().refresh_channel_list()"><b>Refresh List</b></span></div>';
			html += '<div class="clear"></div>';
		html += '</div>';
		
		html += this.getPaginatedTable( resp, cols, 'channel', function(channel, idx) {
			var status = '(None)';
			if (channel.Flags.match(/f/)) status = '<span class="color_label founder">Founder</span>';
			else if (channel.Flags.match(/o/)) status = '<span class="color_label op">Operator</span>';
			else if (channel.Flags.match(/h/)) status = '<span class="color_label halfop">Half-Op</span>';
			else if (channel.Flags.match(/v/)) status = '<span class="color_label voice">Voice</span>';
			
			var chan_html = '';
			if (channel.CanOp) {
				chan_html = '<div class="td_big"><a href="#Channels?sub=edit&channel='+channel.Name+'">#' + channel.Name + '</a></div>';
			}
			else {
				chan_html = '<div class="td_big">#' + channel.Name + '</div>';
			}
			
			return [
				chan_html,
				commify( channel.NumLiveUsers  ),
				status,
				channel.Founder,
				(channel.Private == 1) ? '<span class="color_label private">Private</span>' : '<span class="color_label public">Public</span>',
				get_nice_date( channel.Created ),
				expando_text( channel.Topic || '(None)', 80 )
			];
		} );
		html += '</div>';
		
		html += '</div>'; // sidebar tabs
		
		this.div.html( html );
	},
	
	refresh_channel_list: function() {
		// refresh user list
		app.api.mod_touch( 'get_all_channels' );
		this.gosub_list(this.args);
	},
	
	gosub_users: function(args) {
		// view / edit users for channel
		this.div.addClass('loading');
		if (!args.offset) args.offset = 0;
		if (!args.limit) args.limit = 50;
		app.api.get( 'channel_get_users', copy_object(args), [this, 'receive_channel_users'] );
	},
	
	receive_channel_users: function(resp, tx) {
		// receive page of users from server, render it
		var html = '';
		this.div.removeClass('loading');
		
		this.channel = resp.Channel;
		app.setWindowTitle( "Users for Channel " + nch(this.channel.Name) );
		
		this.users = [];
		if (resp.Rows && resp.Rows.Row) this.users = resp.Rows.Row;
		
		html += this.getSidebarTabs( 'users',
			[
				['list', "Channel List"],
				['new', "Add New Channel"],
				['edit&channel=' + this.args.channel, "Edit Channel"],
				['users', "Channel Users"],
				['bans&channel=' + this.args.channel, "Channel Bans"]
			]
		);
		
		var cols = ['Nickname', 'Full Name', 'Online', 'Host', 'IP', 'Status', 'Last Seen', 'Actions'];
		var user_modes = [ ['','None'], ['v','Voice'], ['h','Half-Op'], ['o','Operator'] ];
		
		// html += '<div style="padding:10px 10px 20px 10px;">';
		html += '<div style="padding:20px 20px 30px 20px">';
		// html += '<div class="subtitle">Users for Channel ' + nch(this.channel.Name) + '</div>';
		
		html += '<div class="subtitle">';
			html += 'Users for Channel ' + nch(this.channel.Name);
			html += '<div class="subtitle_widget"><span class="link" onMouseUp="$P().refresh_channel_users()"><b>Refresh List</b></span></div>';
			html += '<div class="subtitle_widget">Filter: ';
				if (!this.args.filter || (this.args.filter == 'all')) html += '<b>All</b>';
				else html += '<span class="link" onMouseUp="$P().set_channel_user_filter(\'all\')">All</span>';
				html += ' - ';
				if (this.args.filter && (this.args.filter == 'online')) html += '<b>Online</b>';
				else html += '<span class="link" onMouseUp="$P().set_channel_user_filter(\'online\')">Online</span>';
			html += '</div>';
			html += '<div class="clear"></div>';
		html += '</div>';
		
		html += this.getPaginatedTable( resp, cols, 'user', function(user, idx) {
			var actions = [];
			if (user.Live) {
				actions.push( '<span class="link" onMouseUp="$P().kick_channel_user('+idx+')"><b>Kick</b></span>' );
			}
			actions.push( '<span class="link" onMouseUp="$P().ban_channel_user('+idx+')"><b>Ban</b></span>' );
			if (user.Registered) {
				actions.push( '<span class="link" onMouseUp="$P().delete_channel_user('+idx+')"><b>Remove</b></span>' );
			}
			
			var username_open = '';
			var username_close = '';
			if (user.Registered && app.user.Administrator) {
				username_open = '<div class="td_big"><a href="#Users?sub=edit&username='+user.Username+'">';
				username_close = '</a></div>';
			}
			else if (user.Registered) {
				username_open = '<div class="td_big">';
				username_close = '</div>';
			}
			else {
				username_open = '<div class="td_big" style="font-weight:normal;">';
				username_close = '</div>';
			}
			
			return [
				username_open + (user.DisplayUsername || user.Username) + username_close,
				user.FullName || 'n/a',
				user.Live ? '<span class="color_label online">Yes</span>' : '<span class="color_label offline">No</span>',
				user.Host || 'n/a',
				user.IP || 'n/a',
				'<select class="small" onChange="$P().set_channel_user_mode('+idx+',this.options[this.selectedIndex].value)">' + render_menu_options(user_modes, user.Flags.replace(/f/i, '')) + '</select>',
				user.LastCmd ? get_short_date_time( user.LastCmd.When ) : 'n/a',
				actions.join(' | ')
			];
		} );
		html += '</div>';
		
		// add user button
		html += '<div class="button center" style="width:120px; margin-bottom:10px;" onMouseUp="$P().add_channel_user()">Add User...</div>';
		
		html += '</div>'; // sidebar tabs
		
		this.div.html( html );
	},
	
	set_channel_user_filter: function(filter) {
		// filter user list and refresh
		this.args.filter = filter;
		this.args.offset = 0;
		this.refresh_channel_users();
	},
	
	refresh_channel_users: function() {
		// refresh user list
		app.api.mod_touch( 'channel_get_users' );
		this.gosub_users(this.args);
	},
	
	add_channel_user: function() {
		// show dialog prompting for new user to add to channel
		var self = this;
		var html = '';
		html += '<table>' + get_form_table_row('Nickname:', '<input type="text" id="fe_ec_username" size="30" value=""/>') + '</table>';
		html += '<div class="caption">Please enter the registered IRC nickname of the user to add to the channel.</div>';
		
		app.confirm( "Add User to " + nch(this.channel.Name), html, "Add User", function(result) {
			if (result) {
				var username = trim($('#fe_ec_username').val());
				Dialog.hide();
				if (username.match(/^\w+$/)) {
					app.showProgress( 1.0, "Adding user..." );
					app.api.post( 'channel_add_user', {
						Channel: self.channel.Name,
						Username: username
					}, 
					function(resp, tx) {
						app.hideProgress();
						app.showMessage('success', "User '"+username+"' was successfully added to " + nch(self.channel.Name));
						
						app.api.mod_touch('channel_get_users');
						self.gosub_users(self.args);
					} ); // api.post
				} // good username
				else app.doError("The username you entered is invalid (alphanumerics only please).");
			} // user clicked add
		} ); // app.confirm
		
		setTimeout( function() { 
			$('#fe_ec_username').focus().keypress( function(event) {
				if (event.keyCode == '13') { // enter key
					event.preventDefault();
					app.confirm_click(true);
				}
			} );
		}, 1 );
	},
	
	set_channel_user_mode: function(idx, flags) {
		// set user mode for channel
		var self = this;
		var user = this.users[idx];
		
		app.api.post( 'channel_set_user_mode', {
			Channel: self.channel.Name,
			Username: user.Username,
			Flags: flags
		}, 
		function(resp, tx) {
			app.showMessage('success', "User mode for '"+user.Username+"' was set successfully.");
			
			app.api.mod_touch('channel_get_users');
			self.gosub_users(self.args);
		} ); // api.post
	},
	
	delete_channel_user: function(idx) {
		// remove user from channel
		var self = this;
		var user = this.users[idx];
		
		app.api.post( 'channel_delete_user', {
			Channel: self.channel.Name,
			Username: user.Username
		}, 
		function(resp, tx) {
			app.showMessage('success', "User '"+user.Username+"' was successfully removed from " + nch(self.channel.Name) + ".");
			
			app.api.mod_touch('channel_get_users');
			self.gosub_users(self.args);
		} ); // api.post
	},
	
	kick_channel_user: function(idx) {
		// kick user out of channel
		var self = this;
		var user = this.users[idx];
		
		app.api.post( 'channel_kick_user', {
			Channel: self.channel.Name,
			Username: user.Username
		}, 
		function(resp, tx) {
			app.showMessage('success', "User '"+user.Username+"' was successfully kicked from " + nch(self.channel.Name) + ".");
			
			app.api.mod_touch('channel_get_users');
			self.gosub_users(self.args);
		} ); // api.post
	},
	
	ban_channel_user: function(idx) {
		// add quick ban for user
		var self = this;
		var user = this.users[idx];
		// this.edit_channel_ban( -1, '*!' + user.Ident + '@' + user.Host );
		
		// if username is part of NickServ.RegExclude, set to '*' instead
		// (useless to ban 'web756' or 'unidentified343' by username)
		var target_user = user.Username;
		if (target_user.match( new RegExp(config.Plugins.NickServ.RegExclude, 'i') )) target_user = '*';
		
		this.edit_channel_ban( -1, target_user, user.Host || '*' );
	},
	
	gosub_bans: function(args) {
		// view / edit bans for channel
		this.div.addClass('loading');
		if (!args.offset) args.offset = 0;
		if (!args.limit) args.limit = 50;
		app.api.get( 'channel_get_bans', copy_object(args), [this, 'receive_channel_bans'] );
	},
	
	receive_channel_bans: function(resp, tx) {
		// receive page of channel bans from server, render it
		var html = '';
		this.div.removeClass('loading');
		
		this.channel = resp.Channel;
		app.setWindowTitle( "Bans for Channel " + nch(this.channel.Name) );
		
		this.bans = [];
		if (resp.Rows && resp.Rows.Row) this.bans = resp.Rows.Row;
		
		html += this.getSidebarTabs( 'bans',
			[
				['list', "Channel List"],
				['new', "Add New Channel"],
				['edit&channel=' + this.args.channel, "Edit Channel"],
				['users&channel=' + this.args.channel, "Channel Users"],
				['bans', "Channel Bans"]
			]
		);
		
		var cols = ['Target User', 'Target Host/IP', 'Added By', 'Created', 'Expires', 'Actions'];
		
		// html += '<div style="padding:10px 20px 20px 20px;">';
		html += '<div style="padding:20px 20px 30px 20px">';
		html += '<div class="subtitle">Bans for Channel ' + nch(this.channel.Name) + '</div>';
		
		html += this.getPaginatedTable( resp, cols, 'ban', function(ban, idx) {
			var actions = [];
			actions.push( '<span class="link" onMouseUp="$P().edit_channel_ban('+idx+')"><b>Edit</b></span>' );
			actions.push( '<span class="link" onMouseUp="$P().delete_channel_ban('+idx+')"><b>Delete</b></span>' );
			
			return [
			'<div class="td_big">' + ban.TargetUser.replace(/\!.+$/, '') + '</div>',
			'<div class="td_big">' + ban.TargetIP + '</div>',
				ban.AddedBy.replace(/\!.+$/, ''),
				get_short_date_time( ban.Created ),
				get_short_date_time( ban.Expires ),
				actions.join(' | ')
			];
		} );
		html += '</div>';
		
		// add ban button
		html += '<div class="button center" style="width:120px; margin-bottom:10px;" onMouseUp="$P().edit_channel_ban(-1)">Add Ban...</div>';
		
		html += '</div>'; // sidebar tabs
		
		this.div.html( html );
	},
	
	edit_channel_ban: function(idx, default_nick, default_ip) {
		// show dialog prompting for editing channel ban (or adding one)
		var self = this;
		var ban = (idx > -1) ? this.bans[idx] : {
			TargetUser: default_nick || '',
			TargetIP: default_ip || '',
			Expires: time_now() + (86400 * config.Plugins.ChanServ.ChannelBanDays)
		};
		var edit = (idx > -1) ? true : false;
		var html = '';
		
		html += '<table>' + 
			get_form_table_row('Target Nickname:', '<input type="text" id="fe_ec_ban_target_user" size="20" value="'+escape_text_field_value(ban.TargetUser.replace(/\!\*$/, ''))+'"/>') + 
			get_form_table_caption("If you want your ban to target a specific user, enter their nickname/username here.  You may also use wildcards (*).") + 
			get_form_table_spacer() + 
			get_form_table_row('Target Host/IP:', '<input type="text" id="fe_ec_ban_target_ip" size="20" value="'+escape_text_field_value(ban.TargetIP)+'"/>') + 
			get_form_table_caption("If you want your ban to target a specific user host or IP address, enter it here.  You may also use wildcards (*).") + 
			get_form_table_spacer() + 
			get_form_table_row('Expires:', get_date_selector('fe_ec_ban_expires', ban.Expires, 0, 10)) + 
			get_form_table_caption("Select the date when the ban should expire.  Bans are checked for expiration daily at midnight (local server time).") + 
		'</table>';
		
		app.confirm( edit ? "Edit Channel Ban" : "Add Channel Ban", html, edit ? "Save Changes" : "Add Ban", function(result) {
			if (result) {
				var ban_target_user = trim($('#fe_ec_ban_target_user').val());
				var ban_target_ip = trim($('#fe_ec_ban_target_ip').val());
				var ban_expires = get_date_menu_value('fe_ec_ban_expires');
				Dialog.hide();
				
				if (ban_target_user || ban_target_ip) {
					app.showProgress( 1.0, edit ? "Saving ban..." : "Adding ban..." );
					app.api.post( edit ? 'channel_update_ban' : 'channel_add_ban', {
						Channel: self.channel.Name,
						OldTargetUser: edit ? ban.TargetUser : '',
						OldTargetIP: edit ? ban.TargetIP : '',
						TargetUser: ban_target_user || '*',
						TargetIP: ban_target_ip || '*',
						Expires: ban_expires
					}, 
					function(resp, tx) {
						app.hideProgress();
						app.showMessage('success', "Ban was successfully " + (edit ? "saved in " : "added to ") + nch(self.channel.Name) + ".");
						
						// support refreshing channel users OR channel bans sub-page
						app.api.mod_touch('channel_get_bans', 'channel_get_users');
						var sub = self.args.sub || 'list';
						self['gosub_'+sub](self.args);
					} ); // api.post
				} // good username/ip
				else app.doError("The ban target you entered is invalid.");
			} // user clicked add
		} ); // app.confirm
		
		setTimeout( function() { 
			$('#fe_ec_ban_target_user, #fe_ec_ban_target_ip').keypress( function(event) {
				if (event.keyCode == '13') { // enter key
					event.preventDefault();
					app.confirm_click(true);
				}
			} );
			if (!$('#fe_ec_ban_target_user').val()) $('#fe_ec_ban_target_user').focus();
		}, 1 );
	},
	
	delete_channel_ban: function(idx) {
		// delete ban on channel
		var self = this;
		var ban = this.bans[idx];
		
		app.api.post( 'channel_delete_ban', {
			Channel: self.channel.Name,
			TargetUser: ban.TargetUser,
			TargetIP: ban.TargetIP
		}, 
		function(resp, tx) {
			app.showMessage('success', "Ban was successfully removed from " + nch(self.channel.Name) + ".");
			
			app.api.mod_touch('channel_get_bans');
			self.gosub_bans(self.args);
		} ); // api.post
	},
	
	onDeactivate: function() {
		// called when page is deactivated
		return true;
	}
	
} );

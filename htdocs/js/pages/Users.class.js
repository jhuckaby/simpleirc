Class.subclass( AppStr.Page.Base, "AppStr.Page.Users", {	
		
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
		
		app.setWindowTitle('Users');
		app.showTabBar(true);
		
		var sub = args.sub || 'list';
		this['gosub_'+sub](args);
		
		return true;
	},
	
	gosub_new: function(args) {
		// create new user
		var html = '';
		app.setWindowTitle( "Add New User" );
		
		html += this.getSidebarTabs( 'new',
			[
				['list', "User List"],
				['new', "Add New User"]
			]
		);
		
		html += '<div style="padding:20px;"><div class="subtitle">Add New User</div></div>';
		
		html += '<div style="padding:0px 20px 50px 20px">';
		html += '<center><table style="margin:0;">';
		
		this.user = {};
		
		html += this.get_user_edit_html();
		
		html += '<tr><td colspan="2" align="center">';
			html += '<div style="height:30px;"></div>';
			
			html += '<table><tr>';
				html += '<td><div class="button" style="width:120px;" onMouseUp="$P().do_new_user()">Create User</div></td>';
			html += '</tr></table>';
			
		html += '</td></tr>';
		
		html += '</table></center>';
		html += '</div>'; // table wrapper div
		
		html += '</div>'; // sidebar tabs
		
		this.div.html( html );
		
		setTimeout( function() {
			$('#fe_eu_username').focus();
		}, 1 );
	},
	
	do_new_user: function() {
		// create new user
		app.clearError();
		var user = this.get_user_form_xml();
		if (!user) return; // error
		
		if (!user.Username) return app.badField('fe_eu_username', "You must enter a username to create a user account.");
		if (!user.Username.match(/^\w+$/)) return app.badField('fe_eu_username', "Usernames must only consist of letters, numbers and underscores.");
		if (!user.Password) return app.badField('fe_eu_password', "You must enter a password for the account.");
		
		this.user = user;
		
		app.showProgress( 1.0, "Creating user..." );
		app.api.post( 'user_create', user, [this, 'new_user_finish'] );
	},
	
	new_user_finish: function(resp, tx) {
		// new user created successfully
		app.hideProgress();
		app.api.mod_touch( 'get_user_info', 'get_all_users' );
		
		Nav.go('Users?sub=edit&username=' + this.user.Username);
		
		setTimeout( function() {
			app.showMessage('success', "The new user account was created successfully.");
		}, 150 );
	},
	
	gosub_edit: function(args) {
		// edit user subpage
		this.div.addClass('loading');
		app.api.post( 'get_user_info', { Username: args.username }, [this, 'receive_user'] );
	},
	
	receive_user: function(resp, tx) {
		// edit existing user
		var html = '';
		app.setWindowTitle( "Editing User \"" + (resp.User.DisplayUsername || this.args.username) + "\"" );
		this.div.removeClass('loading');
		
		html += this.getSidebarTabs( 'edit',
			[
				['list', "User List"],
				['new', "Add New User"],
				['edit', "Edit User"]
			]
		);
		
		html += '<div style="padding:20px;"><div class="subtitle">Editing User "' + (resp.User.DisplayUsername || this.args.username) + '"</div></div>';
		
		html += '<div style="padding:0px 20px 50px 20px">';
		html += '<center>';
		html += '<table style="margin:0;">';
		
		this.user = resp.User;
		
		html += this.get_user_edit_html();
		
		html += get_form_table_row( 'IRC Status', 
			'<fieldset style="margin-left:8px; padding-top:10px;"><legend>IRC Info</legend>' + 
				'<div style="float:left; width:50%;">' + 
					'<div class="info_label">STATUS</div>' + 
					'<div class="info_value">' + (this.user._identified ? '<span class="color_label online">Connected</span>' : '<span class="color_label offline">Disconnected</span>') + '</div>' + 
					'<div class="info_label">' + (this.user._identified ? 'LOGGED IN' : 'LAST LOGIN') + '</div>' + 
					'<div class="info_value">' + (this.user.LastLogin ? get_nice_date_time(this.user.LastLogin) : 'n/a') + '</div>' + 
					'<div class="info_label">' + (this.user._identified ? 'IP ADDRESS' : 'LAST IP ADDRESS') + '</div>' + 
					'<div class="info_value">' + (this.user.IP || 'n/a') + '</div>' + 
				'</div>' + 
				'<div style="float:right; width:50%;">' + 
					'<div class="info_label">LAST ACTIVITY</div>' + 
					'<div class="info_value">' + (this.user.LastCmd ? get_nice_date_time(this.user.LastCmd.When) : 'n/a') + '</div>' + 
					'<div class="info_label">LAST COMMAND</div>' + 
					'<div class="info_value" style="line-height:14px; max-height:42px; overflow:hidden;">' + (this.user.LastCmd ? this.user.LastCmd.Raw : 'n/a') + '</div>' + 
				'</div>' + 
				'<div class="clear"></div>' + 
			'</fieldset>'
		);
		html += get_form_table_spacer();
		
		html += '<tr><td colspan="2" align="center">';
			html += '<div style="height:30px;"></div>';
			
			html += '<table><tr>';
				html += '<td><div class="button" style="width:115px; font-weight:normal;" onMouseUp="$P().show_delete_account_dialog()">Delete Account...</div></td>';
				html += '<td width="50">&nbsp;</td>';
				html += '<td><div class="button" style="width:115px;" onMouseUp="$P().do_save_user()">Save Changes</div></td>';
			html += '</tr></table>';
			
		html += '</td></tr>';
		
		html += '</table>';
		html += '</center>';
		html += '</div>'; // table wrapper div
		
		html += '</div>'; // sidebar tabs
		
		this.div.html( html );
		
		setTimeout( function() {
			$('#fe_eu_username').attr('disabled', true);
		}, 1 );
	},
	
	do_save_user: function() {
		// create new user
		app.clearError();
		var user = this.get_user_form_xml();
		if (!user) return; // error
		
		this.user = user;
		
		app.showProgress( 1.0, "Saving user account..." );
		app.api.post( 'user_update', user, [this, 'save_user_finish'] );
	},
	
	save_user_finish: function(resp, tx) {
		// new user created successfully
		app.hideProgress();
		app.showMessage('success', "The user was saved successfully.");
		app.api.mod_touch( 'get_user_info', 'get_all_users' );
		window.scrollTo( 0, 0 );
		
		// if we edited ourself, update header
		if (this.args.username == app.username) {
			app.user = resp.User;
			app.updateHeaderInfo();
		}
		
		$('#fe_eu_password').val('');
	},
	
	show_delete_account_dialog: function() {
		// show dialog confirming account delete action
		var self = this;
		app.confirm( '<span style="color:red">Delete Account</span>', "Are you sure you want to <b>permanently delete</b> the user account \""+this.user.Username+"\"?  There is no way to undo this action, and no way to recover the data.", 'Delete', function(result) {
			if (result) {
				app.showProgress( 1.0, "Deleting Account..." );
				app.api.post( 'user_delete', {
					Username: self.user.Username
				}, [self, 'delete_finish'] );
			}
		} );
	},
	
	delete_finish: function(resp, tx) {
		// finished deleting, immediately log user out
		app.hideProgress();
		app.api.mod_touch( 'get_user_info', 'get_users' );
		
		Nav.go('Users');
		
		setTimeout( function() {
			app.showMessage('success', "The user account was deleted successfully.");
		}, 150 );
	},
	
	get_user_edit_html: function() {
		// get html for editing a user (or creating a new one)
		var html = '';
		var user = this.user;
		
		// user id
		html += get_form_table_row( 'Nickname', '<input type="text" id="fe_eu_username" size="20" value="'+escape_text_field_value(user.DisplayUsername || user.Username)+'"/>' );
		html += get_form_table_caption( "Enter the IRC nickname which identifies this account.  Once entered, it cannot be changed. " );
		html += get_form_table_spacer();
		
		// account status
		html += get_form_table_row( 'Account Status', '<select id="fe_eu_status">' + render_menu_options(['Active', 'Suspended'], user.Status) + '</select>' );
		html += get_form_table_caption( "'Suspended' means that the account remains in the system, but the user cannot log in." );
		html += get_form_table_spacer();
		
		// account type
		html += get_form_table_row( 'Account Type', '<select id="fe_eu_type">' + render_menu_options([[0,'Standard'], [1,'Administrator']], user.Administrator ? 1 : 0) + '</select>' );
		html += get_form_table_caption( "'Administrator' users are full server administrators, can manage all channels and users, and have auto-ops in every channel." );
		html += get_form_table_spacer();
		
		// full name
		html += get_form_table_row( 'Full Name', '<input type="text" id="fe_eu_fullname" size="30" value="'+escape_text_field_value(user.FullName)+'"/>' );
		html += get_form_table_caption( "Optional first and last name.  They will not be shared with anyone outside the server.");
		html += get_form_table_spacer();
		
		// email
		html += get_form_table_row( 'Email Address', '<input type="text" id="fe_eu_email" size="30" value="'+escape_text_field_value(user.Email)+'"/>' );
		html += get_form_table_caption( "This can be used to recover the password if the user forgets.  It will not be shared with anyone outside the server." );
		html += get_form_table_spacer();
		
		// password
		html += get_form_table_row( user.Password ? 'Change Password' : 'Password', '<input type="text" id="fe_eu_password" size="20" value=""/>&nbsp;<input type="button" value="&laquo; Generate Random" onClick="$P().generate_password()"/>' );
		html += get_form_table_caption( user.Password ? "Optionally enter a new password here to reset it.  Please make it secure." : "Enter a password for the account.  Please make it secure." );
		html += get_form_table_spacer();
		
		// user aliases
		html += get_form_table_row( 'User Aliases', '<textarea id="fe_eu_aliases" style="width:300px;" rows="5">'+escape_textarea_field_value( (user.Aliases || []).join("\n") )+'</textarea>' );
		html += get_form_table_caption( "<div style=\"width:600px;\">Optionally enter one or more username aliases, one per line, to use as alternate nicknames in IRC.  The user can switch to any of these nicks and retain all their privileges.  Case insensitive.</div>");
		html += get_form_table_spacer();
		
		return html;
	},
	
	get_user_form_xml: function() {
		// get user xml elements from form, used for new or edit
		var aliases = [];
		if ($('#fe_eu_aliases').val().match(/\S/)) {
			aliases = trim($('#fe_eu_aliases').val()).split(/\s+/);
		}
		
		var user = {
			Username: trim($('#fe_eu_username').val().toLowerCase()),
			Status: $('#fe_eu_status').val(),
			FullName: trim($('#fe_eu_fullname').val()),
			Email: trim($('#fe_eu_email').val()),
			Password: $('#fe_eu_password').val(),
			Administrator: parseInt( $('#fe_eu_type').val(), 10 ),
			Aliases: aliases
		};
		
		return user;
	},
	
	generate_password: function() {
		// generate random password
		$('#fe_eu_password').val( b64_md5(get_unique_id()).substring(0, 8) );
	},
	
	gosub_list: function(args) {
		// show user list
		app.setWindowTitle( "User List" );
		this.div.addClass('loading');
		if (!args.offset) args.offset = 0;
		if (!args.limit) args.limit = 50;
		app.api.get( 'get_all_users', copy_object(args), [this, 'receive_users'] );
	},
	
	receive_users: function(resp, tx) {
		// receive page of users from server, render it
		var html = '';
		this.div.removeClass('loading');
		
		this.users = [];
		if (resp.Rows && resp.Rows.Row) this.users = resp.Rows.Row;
		
		html += this.getSidebarTabs( 'list',
			[
				['list', "User List"],
				['new', "Add New User"]
			]
		);
		
		var cols = ['Nickname', 'Full Name', 'Online', 'IP Address', 'Account Type', 'Account Status', 'User Created', 'Last Login', 'Actions'];
		
		// html += '<div style="padding:5px 15px 15px 15px;">';
		html += '<div style="padding:20px 20px 30px 20px">';
		
		html += '<div class="subtitle">';
			html += 'User List';
			html += '<div class="subtitle_widget"><span class="link" onMouseUp="$P().refresh_user_list()"><b>Refresh List</b></span></div>';
			html += '<div class="subtitle_widget">Filter: ';
				if (!this.args.filter || (this.args.filter == 'all')) html += '<b>All</b>';
				else html += '<span class="link" onMouseUp="$P().set_user_list_filter(\'all\')">All</span>';
				html += ' - ';
				if (this.args.filter && (this.args.filter == 'online')) html += '<b>Online</b>';
				else html += '<span class="link" onMouseUp="$P().set_user_list_filter(\'online\')">Online</span>';
			html += '</div>';
			html += '<div class="clear"></div>';
		html += '</div>';
		
		html += this.getPaginatedTable( resp, cols, 'user', function(user, idx) {
			var actions = [];
			if (user.IP) actions.push( '<span class="link" onMouseUp="$P().ban_user('+idx+')"><b>Ban</b></span>' );
			if (user.Live) actions.push( '<span class="link" onMouseUp="$P().boot_user('+idx+')"><b>Boot</b></span>' );
			if (user.Registered) {
				return [
					'<div class="td_big"><a href="#Users?sub=edit&username='+user.Username+'">' + (user.DisplayUsername || user.Username) + '</a></div>',
					user.FullName,
					user.Live ? '<span class="color_label online">Yes</span>' : '<span class="color_label offline">No</span>',
					user.IP ? user.IP : 'n/a',
					user.Administrator ? '<span class="color_label admin">Administrator</span>' : '<span class="color_label standard">Standard</span>',
					'<span class="color_label '+user.Status.toLowerCase()+'">' + user.Status + '</span>',
					'<span title="'+get_nice_date_time(user.Created, true)+'">'+get_nice_date(user.Created, true)+'</span>',
					user.LastLogin ? ('<span title="'+get_nice_date_time(user.LastLogin, true)+'">'+get_nice_date(user.LastLogin, true)+'</span>') : 'n/a',
					actions.join(' | ')
				];
			}
			else {
				return [
					'<div class="td_big">' + user.Username + '</div>',
					'n/a',
					user.Live ? '<span class="color_label online">Yes</span>' : '<span class="color_label offline">No</span>',
					(user.Live && user.IP) ? user.IP : 'n/a',
					'n/a',
					'n/a',
					'n/a',
					'n/a',
					actions.join(' | ')
				];
			}
		} );
		html += '</div>';
		
		html += '</div>'; // sidebar tabs
		
		this.div.html( html );
	},
	
	set_user_list_filter: function(filter) {
		// filter user list and refresh
		this.args.filter = filter;
		this.args.offset = 0;
		this.refresh_user_list();
	},
	
	refresh_user_list: function() {
		// refresh user list
		app.api.mod_touch( 'get_all_users' );
		this.gosub_list(this.args);
	},
	
	ban_user: function(idx) {
		// add server ban
		var user = this.users[idx];
		var self = this;
		$P('Settings').edit_server_ban(-1, user.IP, function() {
			self.refresh_user_list();
		} );
	},
	
	boot_user: function(idx) {
		// boot user from server
		var self = this;
		var user = this.users[idx];
		
		app.api.post( 'server_boot_user', {
			Username: user.Username
		}, 
		function(resp, tx) {
			app.showMessage('success', "User '"+user.Username+"' was successfully booted off the server.");
			self.refresh_user_list();
		} ); // api.post
	},
	
	onDeactivate: function() {
		// called when page is deactivated
		// this.div.html( '' );
		return true;
	}
	
} );

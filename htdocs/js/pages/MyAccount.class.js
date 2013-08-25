Class.subclass( AppStr.Page.Base, "AppStr.Page.MyAccount", {	
		
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
		
		app.setWindowTitle('My Account');
		app.showTabBar(true);
		
		this.receive_user({ User: app.user });
		
		return true;
	},
	
	receive_user: function(resp, tx) {
		var html = '';
		var user = resp.User;
				
		html += '<div style="padding:50px 20px 50px 20px">';
		html += '<center>';
		html += '<table style="margin:0;">';
		
		// user id
		html += get_form_table_row( 'Username', '<div style="font-size: 14px;"><b>' + app.username + '</b></div>' );
		html += get_form_table_caption( "Your username (which is also your IRC nickname) cannot be changed." );
		html += get_form_table_spacer();
		
		// acct type
		html += get_form_table_row( 'Account Type', (app.user.Administrator ? '<span class="color_label" style="background:#5b9bd1;">Administrator</span>' : '<span class="color_label" style="background:gray;">Standard</span>') );
		html += get_form_table_caption( "Only an administrator may change your account type." );
		html += get_form_table_spacer();
		
		// full name
		html += get_form_table_row( 'Full Name', '<input type="text" id="fe_ma_fullname" size="30" value="'+escape_text_field_value(user.FullName)+'"/>' );
		html += get_form_table_caption( "Optional first and last name.  These are typically sent to the server by your IRC client.");
		html += get_form_table_spacer();
		
		// email
		html += get_form_table_row( 'Email Address', '<input type="text" id="fe_ma_email" size="30" value="'+escape_text_field_value(user.Email)+'"/>' );
		html += get_form_table_caption( "This can be used to recover your password if you forget it." );
		html += get_form_table_spacer();
		
		// reset password
		html += get_form_table_row( 'Change Password', '<input type="password" id="fe_ma_password" size="20" value=""/>' );
		html += get_form_table_caption( "Need to change your password?  Enter a new one here.  Please make it secure." );
		html += get_form_table_spacer();
		
		// user aliases
		html += get_form_table_row( 'User Aliases', '<textarea id="fe_ma_aliases" style="width:300px;" rows="5">'+escape_textarea_field_value( (user.Aliases || []).join("\n") )+'</textarea>' );
		html += get_form_table_caption( "<div style=\"width:400px;\">Optionally enter one or more username aliases, one per line, to use as alternate nicknames in IRC.  You can switch to any of these nicks and retain all your user privileges.  Case insensitive.</div>");
		html += get_form_table_spacer();
		
		html += '<tr><td colspan="2" align="center">';
			html += '<div style="height:30px;"></div>';
			
			html += '<table><tr>';
				html += '<td><div class="button" style="width:120px; font-weight:normal;" onMouseUp="$P().show_delete_account_dialog()">Delete Account...</div></td>';
				html += '<td width="50">&nbsp;</td>';
				html += '<td><div class="button" style="width:120px;" onMouseUp="$P().save_changes()">Save Changes</div></td>';
			html += '</tr></table>';
			
		html += '</td></tr>';
		
		html += '</table>';
		html += '</center>';
		html += '</div>'; // table wrapper div
				
		this.div.html( html );
	},
	
	save_changes: function() {
		// save changes to user info
		app.showProgress( 1.0, "Saving user info..." );
		
		var aliases = [];
		if ($('#fe_ma_aliases').val().match(/\S/)) {
			aliases = trim($('#fe_ma_aliases').val()).split(/\s+/);
		}
		
		app.api.post( 'user_update', {
			Username: app.username,
			FullName: trim($('#fe_ma_fullname').val()),
			Email: trim($('#fe_ma_email').val()),
			Password: $('#fe_ma_password').val(),
			Aliases: aliases
		}, [this, 'save_finish'] );
	},
	
	save_finish: function(resp, tx) {
		// save complete
		app.hideProgress();
		app.showMessage('success', "Your account settings were updated successfully.");
		$('#fe_ma_password').val('');
		window.scrollTo( 0, 0 );
		
		app.user = resp.User;
		app.updateHeaderInfo();
		
		app.api.mod_touch( 'get_users' );
	},
	
	show_delete_account_dialog: function() {
		// show dialog confirming account delete action
		var self = this;
		app.confirm( "Delete My Account", "Are you sure you want to <b>permanently delete</b> your user account?  There is no way to undo this action, and no way to recover your data.", "Delete", function(result) {
			if (result) {
				app.showProgress( 1.0, "Deleting Account..." );
				app.api.post( 'user_delete', {
					Username: app.username
				}, [self, 'delete_finish'] );
			}
		} );
	},
	
	delete_finish: function(resp, tx) {
		// finished deleting, immediately log user out
		app.doUserLogout();
	},
	
	onDeactivate: function() {
		// called when page is deactivated
		// this.div.html( '' );
		return true;
	}
	
} );

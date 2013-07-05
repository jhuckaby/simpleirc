Class.subclass( AppStr.Page.Base, "AppStr.Page.Login", {	
	
	onInit: function() {
		// called once at page load
		// var html = 'Now is the time (LOGIN)';
		// this.div.html( html );
	},
	
	onActivate: function(args) {
		// page activation
		if (app.user) {
			// user already logged in
			setTimeout( function() { Nav.go(app.navAfterLogin || config.DefaultPage) }, 1 );
			return true;
		}
		
		app.setWindowTitle('Login');
		app.showTabBar(false);
		
		this.div.css({ 'padding-top':'75px', 'padding-bottom':'75px' });
		var html = '';
		
		html += '<div class="dialog_container">';
			html += '<div class="dialog_title shade-light">User Login</div>';
			html += '<div class="dialog_content">';
				html += '<center><table style="margin:0px;">';
					html += '<tr>';
						html += '<td align="right" class="table_label">Username:</td>';
						html += '<td align="left" class="table_value"><div><input type="text" name="username" id="fe_login_username" size="30" spellcheck="false" value="'+(app.cookie.get('username') || '')+'"/></div></td>';
					html += '</tr>';
					html += '<tr><td colspan="2"><div class="table_spacer"></div></td></tr>';
					html += '<tr>';
						html += '<td align="right" class="table_label">Password:</td>';
						html += '<td align="left" class="table_value"><div><input type="password" name="password" id="fe_login_password" size="30" spellcheck="false" value=""/></div></td>';
					html += '</tr>';
					html += '<tr><td colspan="2"><div class="table_spacer"></div></td></tr>';
				html += '</table></center>';
			html += '</div>';
			html += '<div class="dialog_buttons"><center><table><tr>';
				html += '<td><div class="button" style="width:130px; font-weight:normal;" onMouseUp="$P().showPasswordRecoveryDialog()">Forgot Password...</div></td>';
				html += '<td width="50">&nbsp;</td>';
				html += '<td><div class="button" style="width:130px;" onMouseUp="$P().doLogin()">Login</div></td>';
			html += '</tr></table></center></div>';
		html += '</div>';
		
		this.div.html( html );
		
		setTimeout( function() {
			$( app.cookie.get('username') ? '#fe_login_password' : '#fe_login_username' ).focus();
			$('#fe_login_username, #fe_login_password').keypress( function(event) {
				if (event.keyCode == '13') { // enter key
					event.preventDefault();
					$P().doLogin();
				}
			} );
		}, 1 );
		
		return true;
	},
	
	doLogin: function() {
		// attempt to log user in
		var username = $('#fe_login_username').val();
		var password = $('#fe_login_password').val();
		
		if (username && password) {
			app.showProgress(1.0, "Logging in...");
			app.api.post( 'login', {
				Username: username,
				Password: password
			}, 
			function(resp, tx) {
				Debug.trace("User Login: " + username + ": " + resp.SessionID);
				
				app.hideProgress();
				app.doUserLogin( resp );
				
				Nav.go( app.navAfterLogin || config.DefaultPage );
			} );
		}
	},
	
	showPasswordRecoveryDialog: function() {
		// allow user to enter e-mail to recover password
		
		// user must enter username first
		var username = $('#fe_login_username').val();
		if (!username) return app.badField('fe_login_username', "Please enter your username to recover your password.");
		
		var html = '';
		html += '<table>' + get_form_table_row('Email Address:', '<input type="text" id="fe_login_email" size="30" value=""/>') + '</table>';
		html += '<div class="caption">Please enter the e-mail address associated with your account, and we will send you instructions for resetting your password.</div>';
		
		app.confirm( "Forgot Password", html, "Send Email", function(result) {
			if (result) {
				var email = trim($('#fe_login_email').val());
				Dialog.hide();
				if (email.match(/.+\@.+/)) {
					app.showProgress( 1.0, "Sending e-mail..." );
					app.api.post( 'forgot_password', {
						Username: username,
						Email: email
					}, 
					function(resp, tx) {
						app.hideProgress();
						app.showMessage('success', "Password reset instructions sent successfully.");
					} ); // api.post
				} // good address
				else app.doError("The e-mail address you entered does not appear to be correct.");
			} // user clicked send
		} ); // app.confirm
		
		setTimeout( function() { 
			$('#fe_login_email').focus().keypress( function(event) {
				if (event.keyCode == '13') { // enter key
					event.preventDefault();
					app.confirm_click(true);
				}
			} );
		}, 1 );
	},
	
	onDeactivate: function() {
		// called when page is deactivated
		this.div.html( '' );
		return true;
	}
	
} );

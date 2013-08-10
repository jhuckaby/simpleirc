$GR.marginTop = 0;

var app = {
	
	config: null,
	username: '',
	user: null,
	query: parseQueryString( ''+location.search ),
	cookie: new CookieTree({ path: '/' }),
	cacheBust: hires_time_now(),
	proto: location.protocol.match(/^https/i) ? 'https://' : 'http://',
	secure: !!location.protocol.match(/^https/i),
	ie: !!navigator.userAgent.match(/MSIE/),
	retina: (window.devicePixelRatio > 1),
	preload_images: ['loading.gif', 'check_24.png', 'error_24.png', 'aquaprogressbar_bkgnd.gif', 'aquaprogressbar.gif'],
	
	receiveConfig: function(resp) {
		// receive config from server
		this.config = window.config = resp.Config;
		if (resp.Version) this.version = resp.Version;
		
		this.config.Page = [
			{ ID: 'Home' },
			{ ID: 'Login' },
			{ ID: 'Channels' },
			{ ID: 'Users' },
			{ ID: 'Logs' },
			{ ID: 'Settings' },
			{ ID: 'MyAccount' }
		];
		this.config.DefaultPage = 'Home';
	},
	
	init: function() {
		// initialize application
		if (this.abort) return; // fatal error, do not initialize app
		assert( this.config, "window.config is not present in app.js.");
		
		// preload a few essential images
		for (var idx = 0, len = this.preload_images.length; idx < len; idx++) {
			var filename = '' + this.preload_images[idx];
			var img = new Image();
			img.src = '/images/'+filename;
		}
		
		// update page elements from config
		this.updateFromConfig();
		
		// setup page nav system
		this.page_manager = new AppStr.PageManager( always_array(this.config.Page) );
		Nav.init();
	},
	
	updateFromConfig: function() {
		// update page elements based on new configuration
		// set page header title and version
		$('#d_header_title').html( config.ServerDesc );
		$('#d_version').html( this.version.Major + '-' + this.version.Minor + ' (' + this.version.Branch + ')' );
		
		// show/hide tabs depending on enabled features
		if (config.Plugins.NickServ.Enabled) $('#tab_Users').show(); else $('#tab_Users').hide();
		if (config.Plugins.ChanServ.Enabled) $('#tab_Channels').show(); else $('#tab_Channels').hide();
		if (config.Logging.Enabled) $('#tab_Logs').show(); else $('#tab_Logs').hide();
	},
	
	updateHeaderInfo: function() {
		// update top-right display
		var html = '';
		html += '<div>Logged in as <strong>' + app.user.FullName + '</strong></div>';
		html += '<div>' + app.username + ' - ' + app.user.Email + '</div>';
		html += '<div><a href="#" onMouseUp="app.doUserLogout()"><strong>Log out</strong></a></div>';
		$('#d_header_user_bar').html( html );
	},
	
	doUserLogin: function(resp) {
		// user login, called from login page, or session recover
		app.username = resp.Username;
		app.user = resp.User;
		
		app.cookie.set('username', resp.Username);
		app.cookie.set('session_id', resp.SessionID);
		app.cookie.save();
		
		this.updateHeaderInfo();
		
		// update tabs
		if (app.user.Administrator) {
			// Note: although this can be hacked client-side, all API calls are validated on the server,
			// so a non-admin will not see anything except empty tabs and errors if these are forced visible.
			if (config.Plugins.NickServ.Enabled) $('#tab_Users').show(); else $('#tab_Users').hide();
			if (config.Logging.Enabled) $('#tab_Logs').show(); else $('#tab_Logs').hide();
			$('#tab_Settings').show();
		}
		else {
			$('#tab_Users, #tab_Logs, #tab_Settings').hide();
		}
	},
	
	doUserLogout: function(bad_cookie) {
		// log user out and redirect to login screen
		if (!bad_cookie) app.showProgress(1.0, "Logging out...");
		
		app.api.post( 'logout', {
			SessionID: app.cookie.get('session_id')
		}, 
		function(resp, tx) {
			app.hideProgress();
			
			delete app.user;
			delete app.username;
			delete app.user_info;
			
			app.cookie.set('session_id', '');
			app.cookie.save();
			
			// a non-admin may log back in, so we must hide these
			$('#tab_Users, #tab_Logs, #tab_Settings').hide();
			
			Debug.trace("User session cookie was deleted, redirecting to login page");
			Nav.go('Login');
			
			setTimeout( function() {
				if (bad_cookie) app.showMessage('error', "Your session has expired.  Please log in again.");
				else app.showMessage('success', "You were logged out successfully.");
			}, 150 );
		} );
	},
	
	getProgressBar: function(progress, width, height) {
		// return HTML for a nice progress bar using CSS
		var html = '';
		var bradius = Math.min( Math.floor(height / 2), 8 );
		
		html += '<div class="progress_bar_container" style="width:'+width+'px; height:'+height+'px">';
			html += '<div class="progress_bar_bkgnd" style="width:'+width+'px; height:'+Math.floor(height - 1)+'px; border-radius:'+bradius+'px;"></div>';
			html += '<div class="progress_bar_thumb" style="width:'+Math.floor(width * progress)+'px; height:'+Math.floor(height - 1)+'px; border-radius:'+bradius+'px;"></div>';
		html += '</div>';
		
		return html;
	},
	
	handleResize: function() {
		// called when window resizes
		if (this.page_manager && this.page_manager.current_page_id) {
			var id = this.page_manager.current_page_id;
			var page = this.page_manager.find(id);
			if (page && page.onResize) page.onResize();
		}
	},
	
	doError: function(msg, lifetime) {
		this.showMessage( 'error', msg, lifetime );
		
		// remove any progress growls
		$GR.remove_all_by_type('progress');
		
		// remove progress dialog, if present
		if (app.progress) app.hideProgress();
		
		return null;
	},
	
	badField: function(id, msg) {
		// mark field as bad
		$( id.match(/^\w+$/) ? ('#'+id) : id ).addClass('error');
		return this.doError(msg);
	},
	
	clearError: function() {
		// clear last error
		app.hideMessage();
		$('.invalid').removeClass('invalid');
		$('.error').removeClass('error');
	},
	
	showMessage: function(type, msg, lifetime) {
		// show success, warning or error message
		// Dialog.hide();
		// window.scrollTo( 0, 0 );
		Debug.trace(type, msg);
		
		return $GR.growl( type, msg, lifetime );
	},
	
	hideMessage: function() {
		$GR.remove_all();
	},
	
	setWindowTitle: function(name) {
		// set document title
		if (name) document.title = name + ' | ' + config.ServerName;
		else document.title = config.ServerName;
	},
	
	showTabBar: function(visible) {
		// show or hide tab bar
		if (visible) $('.tab_bar').show();
		else $('.tab_bar').hide();
	},
	
	// front-end to ajax.js functions:
	api: {
		mod_cache: {},
		
		post: function(cmd, json, callback, user_data) {
			// send JSON HTTP POST to server using async AJAX control
			var url = '/api/' + cmd + composeQueryString({
				format: 'json',
				pure: 1
			});
			var json_text = JSON.stringify( json );
			Debug.trace( 'api', "Sending HTTP POST to: " + url + ": " + json_text );
			
			if (!user_data) user_data = {};
			user_data._api_callback = callback;
			user_data._api_url = url;

			ajax.send({
				method: 'POST',
				url: url,
				data: json_text,
				headers: { 'Content-Type': 'text/json' }
			}, function(tx) {
				app.api.receive(tx);
			}, user_data);
		},
		
		raw_post: function(cmd, query, args, callback, user_data) {
			// send raw POST to server, where data and headers (content-type) need to be specified
			query.format = 'json';
			query.pure = 1;
			var url = '/api/' + cmd + composeQueryString(query);
			Debug.trace( 'api', "Sending raw HTTP POST to: " + url + " (post data not shown)" );
			
			if (!user_data) user_data = {};
			user_data._api_callback = callback;
			user_data._api_url = url;
			
			args.method = 'POST';
			args.url = url;
			ajax.send(args, function(tx) {
				app.api.receive(tx);
			}, user_data);
		},
		
		get: function(cmd, query, callback, user_data) {
			// send HTTP GET to server using AJAX
			query.format = 'json';
			query.pure = 1;
			
			// possibly add mod date (forced cache miss, date based)
			if (!this.mod_cache[cmd] && app.username) this.mod_cache[cmd] = hires_time_now();
			if (!query.mod && this.mod_cache[cmd]) query.mod = this.mod_cache[cmd];
			
			var url = '/api/' + cmd + composeQueryString(query);
			Debug.trace( 'api', "Sending HTTP GET to: " + url);
			
			if (!user_data) user_data = {};
			user_data._api_callback = callback;
			user_data._api_url = url;
			
			ajax.get( url, function(tx) {
				app.api.receive(tx);
			}, user_data);
		},

		receive: function(tx) {
			// receive AJAX response from server
			Debug.trace( 'api', "Received response from server: " + tx.response.code + ": " + 
				((tx.response.data.length < 8192) ? tx.response.data : '(too long to show here)') );
			
			if (tx.response.code != 200)
				return app.doError( "HTTP "+tx.response.code+": " + tx._api_url + ": " + tx.response.data );
			
			var json = null;
			try { json = JSON.parse( tx.response.data ); }
			catch (e) {
				return app.doError("JSON Parser Error: " + tx._api_url + ": " + e.toString());
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
			
			// call callback
			if (tx._api_callback) {
				if (typeof(tx._api_callback) == 'function') {
					tx._api_callback( tree, tx );
				}
				else if (isa_array(tx._api_callback)) {
					var obj = tx._api_callback[0];
					var func = tx._api_callback[1];
					obj[func](tree, tx);
				}
				else {
					window[tx._api_callback](tree, tx);
				}
			}
		},
		
		mod_touch: function() {
			// touch mod date of one or more 'GET' API calls (controlled cache bust)
			for (var idx = 0, len = arguments.length; idx < len; idx++) {
				this.mod_cache[ arguments[idx] ] = hires_time_now();
			}
		}
	}, // API
	
	hideProgress: function() {
		// hide progress dialog
		Dialog.hide();
		delete app.progress;
	},
	
	showProgress: function(counter, title) {
		// show or update progress bar
		if (!$('#d_progress_bar').length) {
			// no progress dialog is active, so set it up
			if (!counter) counter = 0;
			var cx = Math.floor( counter * 196 );
			
			var html = '';
			html += '<div class="dialog_simple dialog_shadow">';
			html += '<center>';
			// html += '<div class="loading" style="width:32px; height:32px; margin:0 auto 10px auto;"></div>';
			html += '<div id="d_progress_title" class="dialog_subtitle">' + title + '</div>';
			
			var opac_str = '';
			if (counter == 1.0) opac_str = 'opacity:0.5; filter:alpha(opacity=50);';
			
			html += '<div style="position:relative; overflow:hidden; width:196px; height:20px; background-image:url(images/aquaprogressbar_bkgnd.gif);">';
				html += '<div id="d_progress_bar" style="position:absolute; left:0px; top:0px; width:196px; height:20px; clip:rect(0px '+cx+'px 20px 0px);'+opac_str+'">';
					html += '<img src="images/aquaprogressbar.gif" width="196" height="20"/>';
				html += '</div>';
			html += '</div>';
			
			html += '</center>';
			html += '</div>';
			
			app.hideMessage();
			Dialog.show(275, 100, html);
			
			app.progress = {
				start_counter: counter,
				counter: counter,
				counter_max: 1,
				start_time: hires_time_now(),
				last_update: hires_time_now(),
				title: title
			};
		}
		else {
			// dialog is active, so update existing elements
			var now = hires_time_now();
			var cx = Math.floor( counter * 196 );
			var prog_div = document.getElementById('d_progress_bar');
			if (prog_div) {
				prog_div.style.clip = 'rect(0px '+cx+'px 20px 0px)';
				var opacity = (counter == 1.0) ? 0.5 : 1.0;
				if ((opacity > 0) && (opacity < 1.0)) {
					prog_div.style.opacity = opacity;
					if (app.ie) prog_div.style.filter = "alpha(opacity=" + parseInt(opacity * 100) + ")";
				}
				else {
					prog_div.style.opacity = 1.0;
					if (app.ie) prog_div.style.filter = "";
				}
			}

			if (title) app.progress.title = title;
			var title_div = document.getElementById('d_progress_title');
			if (title_div) title_div.innerHTML = app.progress.title;

			app.progress.last_update = now;
			app.progress.counter = counter;
		}
	},
	
	showDialog: function(title, inner_html, buttons_html) {
		// show dialog using our own look & feel
		var html = '';
		html += '<div class="dialog_title shade-light dialog_shadow">' + title + '</div>';
		html += '<div class="dialog_content dialog_shadow">' + inner_html + '</div>';
		html += '<div class="dialog_buttons dialog_shadow">' + buttons_html + '</div>';
		Dialog.showAuto( html );
	},
	
	confirm: function(title, html, ok_btn_label, callback) {
		// show simple OK / Cancel dialog with custom text
		// fires callback with true (OK) or false (Cancel)
		if (!ok_btn_label) ok_btn_label = "OK";
		this.confirm_callback = callback;
		
		var inner_html = "";
		inner_html += '<div style="width:450px; margin-bottom:20px; font-size:13px; color:#444;">'+html+'</div>';
				
		var buttons_html = "";
		buttons_html += '<center><table><tr>';
			buttons_html += '<td><div class="button" style="width:100px; font-weight:normal;" onMouseUp="app.confirm_click(false)">Cancel</div></td>';
			buttons_html += '<td width="40">&nbsp;</td>';
			buttons_html += '<td><div class="button" style="width:100px;" onMouseUp="app.confirm_click(true)">'+ok_btn_label+'</div></td>';
		buttons_html += '</tr></table></center>';
		
		this.showDialog( title, inner_html, buttons_html );
	},
	
	confirm_click: function(result) {
		// user clicked OK or Cancel in confirmation dialog, fire callback
		// caller MUST deal with Dialog.hide() if result is true
		this.confirm_callback(result);
		if (!result) Dialog.hide();
	},
	
	check_privilege: function(path, real) {
		// check if user has privilege
		if (!real && (this.user.Privileges.admin == 1)) return true;
		if (!path.match(/^\//)) path = '/' + path;
		var value = lookup_path(path, this.user.Privileges);
		// may be null, 0, 1 or object
		return ((value == 1) || isa_hash(value));
	},
	
	get_base_url: function() {
		return app.proto + location.hostname + '/';
	}
};

function $P(id) {
	// shortcut for page_manager.find(), also defaults to current page
	if (!id) id = app.page_manager.current_page_id;
	var page = app.page_manager.find(id);
	assert( !!page, "Failed to locate page: " + id );
	return page;
}

function get_form_table_row() {
	var tr_class = '';
	var left = '';
	var right = '';
	if (arguments.length == 3) {
		tr_class = arguments[0]; left = arguments[1]; right = arguments[2];
	}
	else {
		left = arguments[0]; right = arguments[1];
	}
	
	var html = '';
	html += '<tr class="'+tr_class+'">';
		html += '<td align="right" class="table_label">'+left.replace(/\s/g, '&nbsp;').replace(/\:$/, '')+':</td>';
		html += '<td align="left" class="table_value">';
			html += '<div>'+right+'</div>';
		html += '</td>';
	html += '</tr>';
	return html;
};

function get_form_table_caption() {
	var tr_class = '';
	var cap = '';
	if (arguments.length == 2) {
		tr_class = arguments[0]; cap = arguments[1];
	}
	else {
		cap = arguments[0];
	}
	
	var html = '';
	html += '<tr class="'+tr_class+'">';
		html += '<td>&nbsp;</td>';
		html += '<td align="left">';
			html += '<div class="caption">'+cap+'</div>';
		html += '</td>';
	html += '</tr>';
	return html;
};

function get_form_table_spacer() {
	var tr_class = '';
	var extra_classes = '';
	if (arguments.length == 2) {
		tr_class = arguments[0]; extra_classes = arguments[1];
	}
	else {
		extra_classes = arguments[0];
	}
	
	var html = '';
	html += '<tr class="'+tr_class+'"><td colspan="2"><div class="table_spacer '+extra_classes+'"></div></td></tr>';
	return html;
};

function show_hide_password(id) {
	// simple show/hide toggle for password fields using jQuery
	var html = '';
	html += '<span class="link" style="text-decoration:none;" onMouseUp="$(\'#'+id+'\')[0].type=\'text\';$(this).hide().next().show();">&laquo; Show</span>';
	html += '<span class="link" style="text-decoration:none; display:none" onMouseUp="$(\'#'+id+'\')[0].type=\'password\';$(this).hide().prev().show();">&laquo; Hide</span>';
	return html;
};

if (!window.Debug) window.Debug = {
	trace: function(cat, msg) {
		if (cat && !msg) { msg = cat; cat = 'Debug'; }
		if (window.config && config.Logging.Debuglevel >= 5) console.log( cat + ": " + msg );
	}
};

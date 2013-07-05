Class.subclass( AppStr.Page, "AppStr.Page.Base", {	
	
	requireLogin: function(args) {
		// user must be logged into to continue
		if (!app.user) {
			// require login
			app.navAfterLogin = this.ID;
			if (args && num_keys(args)) app.navAfterLogin += composeQueryString(args);
			
			this.div.hide();
			
			var session_id = app.cookie.get('session_id') || '';
			if (session_id) {
				Debug.trace("User has cookie, recovering session: " + session_id);
				// app.showProgress(1.0, "Logging in...");
				app.api.post( 'resume_session', {
					SessionID: session_id
				}, 
				function(resp, tx) {
					if (resp.User) {
						Debug.trace("User Session Resume: " + resp.Username + ": " + resp.SessionID);
						app.hideProgress();
						app.doUserLogin( resp );
						
						// Nav.go( app.navAfterLogin || config.DefaultPage );
						Nav.refresh();
					}
					else {
						Debug.trace("User cookie is invalid, redirecting to login page");
						Nav.go('Login');
					}
				} );
			}
			else {
				Debug.trace("User is not logged in, redirecting to login page (will return to " + this.ID + ")");
				setTimeout( function() { Nav.go('Login'); }, 1 );
			}
			return false;
		}
		return true;
	},
	
	getSidebarTabs: function(current, tabs) {
		// get html for sidebar tabs
		var html = '';
		
		html += '<div style="margin-left:181px; position:relative; min-height:400px;">';
		html += '<div class="side_tab_bar" style="position:absolute; left:-191px;">';
		html += '<div style="height:50px;"></div>';
		
		for (var idx = 0, len = tabs.length; idx < len; idx++) {
			var tab = tabs[idx];
			if (typeof(tab) == 'string') html += tab;
			else {
				var class_name = 'inactive';
				var link = 'Nav.go(\''+this.ID+'?sub='+tab[0]+'\')';
				
				if (tab[0] == current) {
					class_name = 'active';
					link = '';
				}
				html += '<div class="tab side '+class_name+'" onMouseUp="'+link+'"><span class="content">'+tab[1]+'</span></div>';
			}
		}
		
		html += '</div>';
		
		return html;
	},
	
	getPaginatedTable: function(resp, cols, data_type, callback) {
		// get html for paginated table
		var html = '';
		
		// pagination
		html += '<div class="pagination">';
		html += '<table cellspacing="0" cellpadding="0" border="0" width="100%"><tr>';
		
		var results = {
			limit: this.args.limit,
			offset: this.args.offset || 0,
			total: resp.List.length
		};

		var num_pages = Math.floor( results.total / results.limit ) + 1;
		if (results.total % results.limit == 0) num_pages--;
		var current_page = Math.floor( results.offset / results.limit ) + 1;
		
		html += '<td align="left" width="33%">';
		html += results.total + ' ' + pluralize(data_type, results.total) + ' found';
		html += '</td>';
		
		html += '<td align="center" width="34%">';
		if (num_pages > 1) html += 'Page ' + current_page + ' of ' + num_pages;
		else html += '&nbsp;';
		html += '</td>';
		
		html += '<td align="right" width="33%">';
		
		if (num_pages > 1) {
			// html += 'Page: ';
			if (current_page > 1) {
				html += '<a href="#' + this.ID + composeQueryString(merge_objects(this.args, {
					offset: (current_page - 2) * results.limit
				})) + '">&laquo; Prev Page</a>';
			}
			html += '&nbsp;&nbsp;&nbsp;';

			var start_page = current_page - 4;
			var end_page = current_page + 5;

			if (start_page < 1) {
				end_page += (1 - start_page);
				start_page = 1;
			}

			if (end_page > num_pages) {
				start_page -= (end_page - num_pages);
				if (start_page < 1) start_page = 1;
				end_page = num_pages;
			}

			for (var idx = start_page; idx <= end_page; idx++) {
				if (idx == current_page) {
					html += '<b>' + idx + '</b>';
				}
				else {
					html += '<a href="#' + this.ID + composeQueryString(merge_objects(this.args, {
						offset: (idx - 1) * results.limit
					})) + '">'+idx+'</a>';
				}
				html += '&nbsp;';
			}

			html += '&nbsp;&nbsp;';
			if (current_page < num_pages) {
				html += '<a href="#' + this.ID + composeQueryString(merge_objects(this.args, {
					offset: (current_page + 0) * results.limit
				})) + '">Next Page &raquo;</a>';
			}
		} // more than one page
		else {
			html += 'Page 1 of 1';
		}
		html += '</td>';
		html += '</tr></table>';
		html += '</div>';
		
		html += '<div style="margin-top:5px;">';
		html += '<table class="data_table" width="100%">';
		html += '<tr><th>' + cols.join('</th><th>') + '</th></tr>';
		
		for (var idx = 0, len = resp.Rows.Row.length; idx < len; idx++) {
			var row = resp.Rows.Row[idx];
			html += '<tr>';
			html += '<td>' + callback(row, idx).join('</td><td>') + '</td>';
			html += '</tr>';
		} // foreach row
		
		if (!resp.Rows.Row.length) {
			html += '<tr><td colspan="'+cols.length+'" align="center" style="padding-top:10px; padding-bottom:10px; font-weight:bold;">';
			html += 'No '+pluralize(data_type)+' found.';
			html += '</td></tr>';
		}
		
		html += '</table>';
		html += '</div>';
		
		return html;
	}
	
} );

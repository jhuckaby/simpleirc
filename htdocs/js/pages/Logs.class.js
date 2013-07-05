Class.subclass( AppStr.Page.Base, "AppStr.Page.Logs", {	
	
	first: true,
	
	onInit: function() {
		// called once at page load
	},
	
	onActivate: function(args) {
		// page activation
		if (!this.requireLogin(args)) return true;
		
		if (!args) args = {};
		this.args = args;
		
		app.setWindowTitle('Logs');
		app.showTabBar(true);
		
		if (this.first) {
			this.render_log_search_form();
			delete this.first;
		}
		
		return true;
	},
	
	render_log_search_form: function() {
		// show form for searching logs
		var html = '';
		
		html += '<div style="padding:50px 20px 50px 20px">';
		html += '<center>';
		html += '<table style="margin:0; width:700px;">';
		
		// log category
		var cats = [];
		if (config.Logging.ActiveLogs.transcript) cats.push(['transcript', 'Chat Transcript']);
		if (config.Logging.ActiveLogs.debug) cats.push(['debug', 'Debug Log']);
		if (config.Logging.ActiveLogs.error) cats.push(['error', 'Error Log']);
		if (config.Logging.ActiveLogs.maint) cats.push(['maint', 'Maintenance Log']);
		
		html += get_form_table_row( 'Log Category', '<select id="fe_el_cat">' + render_menu_options(cats) + '</select>' );
		html += get_form_table_caption( "Select the log category for your search.  The 'Chat Transcript' contains every command by every user in every channel." );
		html += get_form_table_spacer();
		
		// log date
		html += get_form_table_row( 'Log Date', get_date_selector('fe_el_date', time_now(), -10, 0) );
		html += get_form_table_caption( "Select the date for your log search.  If you select today's date, the current live logs will be used.  Otherwise, logs will be pulled from the compressed archives." );
		html += get_form_table_spacer();
		
		// log hour time range
		var hours = [
			[0, '12:00:00 AM'],
			[3600, '1:00:00 AM'],
			[7200, '2:00:00 AM'],
			[10800, '3:00:00 AM'],
			[14400, '4:00:00 AM'],
			[18000, '5:00:00 AM'],
			[21600, '6:00:00 AM'],
			[25200, '7:00:00 AM'],
			[28800, '8:00:00 AM'],
			[32400, '9:00:00 AM'],
			[36000, '10:00:00 AM'],
			[39600, '11:00:00 AM'],
			[43200, '12:00:00 PM'],
			[46800, '1:00:00 PM'],
			[50400, '2:00:00 PM'],
			[54000, '3:00:00 PM'],
			[57600, '4:00:00 PM'],
			[61200, '5:00:00 PM'],
			[64800, '6:00:00 PM'],
			[68400, '7:00:00 PM'],
			[72000, '8:00:00 PM'],
			[75600, '9:00:00 PM'],
			[79200, '10:00:00 PM'],
			[82800, '11:00:00 PM'],
			[86400, '11:59:59 PM']
		];
		
		html += get_form_table_row( 'Time Range', '<table><tr>' + 
			'<td><select id="fe_el_time_start" onChange="$P().adjust_time()">' + render_menu_options(hours, this_hour() - today_midnight()) + '</td>' + 
			'<td>&nbsp;to&nbsp;</td>' + 
			'<td><select id="fe_el_time_end" onChange="$P().adjust_time()">' + render_menu_options(hours, (this_hour() + 3600) - today_midnight()) + '</td>' + 
		'</tr></table>' );
		html += get_form_table_caption( "Select the time range to narrow your log search (local server time).  By default the current hour is selected." );
		html += get_form_table_spacer();
		
		// search filter
		html += get_form_table_row( 'Search Filter', '<input type="text" id="fe_el_filter" size="30" value=""/>' );
		html += get_form_table_caption( "Enter an optional filter string to narrow the search.  For the transcript log, you can enter a #channel or username here.");
		html += get_form_table_spacer();
		
		// output format
		html += get_form_table_row( 'Output Format', '<select id="fe_el_format">' + render_menu_options([['html','HTML'], ['raw','Raw Text']]) + '</select>' );
		html += get_form_table_caption( "Select the log format you want.  'HTML' is rendered in a table to be easily readible, while 'Raw Text' is the original, bracket-delimited log format as stored on disk." );
		html += get_form_table_spacer();
		
		html += '<tr><td colspan="2" align="center">';
			html += '<div style="height:30px;"></div>';
			
			html += '<table><tr>';
				html += '<td><div class="button" style="width:120px;" onMouseUp="$P().search_logs()">Search Logs</div></td>';
			html += '</tr></table>';
			
		html += '</td></tr>';
		
		html += '</table>';
		html += '</center>';
		html += '</div>'; // table wrapper div
				
		this.div.html( html );
	},
	
	adjust_time: function() {
		// make sure start and end times are legit
		var time_start = parseInt( $('#fe_el_time_start').val(), 10 );
		var time_end = parseInt( $('#fe_el_time_end').val(), 10 );
		
		if (time_start >= 86400) {
			time_start = 82800;
			$('#fe_el_time_start').val( time_start );
		}
		
		if (time_start >= time_end) {
			time_end = time_start + 3600;
			$('#fe_el_time_end').val( time_end );
		}
	},
	
	search_logs: function() {
		var log_query = {
			cat: $('#fe_el_cat').val(),
			date: get_date_menu_value('fe_el_date', '[yyyy]/[mm]/[dd]'),
			time_start: $('#fe_el_time_start').val(),
			time_end: $('#fe_el_time_end').val(),
			filter: $('#fe_el_filter').val(),
			format: $('#fe_el_format').val()
		};
		
		var url = '/api/logs' + composeQueryString(log_query);
		window.open( url );
	},
	
	onDeactivate: function() {
		// called when page is deactivated
		// this.div.html( '' );
		return true;
	}
	
} );

// Joe's Date/Time Tools

window._months = [
	[ 1, 'January' ], [ 2, 'February' ], [ 3, 'March' ], [ 4, 'April' ],
	[ 5, 'May' ], [ 6, 'June' ], [ 7, 'July' ], [ 8, 'August' ],
	[ 9, 'September' ], [ 10, 'October' ], [ 11, 'November' ],
	[ 12, 'December' ]
];
window._days = [
	[1,1], [2,2], [3,3], [4,4], [5,5], [6,6], [7,7], [8,8], [9,9], [10,10],
	[11,11], [12,12], [13,13], [14,14], [15,15], [16,16], [17,17], [18,18], 
	[19,19], [20,20], [21,21], [22,22], [23,23], [24,24], [25,25], [26,26],
	[27,27], [28,28], [29,29], [30,30], [31,31]
];

window._short_month_names = [ 'Jan', 'Feb', 'Mar', 'Apr', 'May', 
	'June', 'July', 'Aug', 'Sept', 'Oct', 'Nov', 'Dec' ];

window._day_names = ['Sunday', 'Monday', 'Tuesday', 'Wednesday', 
	'Thursday', 'Friday', 'Saturday'];

function time_now() {
	// return the Epoch seconds for like right now
	var now = new Date();
	return parseInt( now.getTime() / 1000, 10 );
}

function hires_time_now() {
	// return the Epoch seconds for like right now
	var now = new Date();
	return ( now.getTime() / 1000 );
}

function this_hour() {
	// return epoch seconds for normalized hour
	var now = new Date();
	var then = new Date(
		now.getFullYear(),
		now.getMonth(),
		now.getDate(),
		now.getHours(),
		0, 0, 0 );
	return parseInt( then.getTime() / 1000, 10 );
}

function today_midnight() {
	// return epoch seconds for nearest midnight in past
	var now = new Date();
	var then = new Date(
		now.getFullYear(),
		now.getMonth(),
		now.getDate(),
		0, 0, 0, 0 );
	return parseInt( then.getTime() / 1000, 10 );
}

function yesterday_midnight() {
	// return epoch seconds for yesterday's midnight
	var midnight = today_midnight();
	var yesterday = new Date( (midnight - 1) * 1000 );
	var then = new Date(
		yesterday.getFullYear(),
		yesterday.getMonth(),
		yesterday.getDate(),
		0, 0, 0, 0 );
	return parseInt( then.getTime() / 1000, 10 );
}

function this_month_midnight() {
	// return epoch seconds for midnight on the 1st of this month
	var now = new Date();
	var then = new Date(
		now.getFullYear(),
		now.getMonth(),
		1, 0, 0, 0, 0 );
	return parseInt( then.getTime() / 1000, 10 );
}

function last_month_midnight() {
	// return epoch seconds for midnight on the 1st of last month
	var this_month = this_month_midnight();
	var last_month = new Date( (this_month - 1) * 1000 );
	var then = new Date(
		last_month.getFullYear(),
		last_month.getMonth(),
		1, 0, 0, 0, 0 );
	return parseInt( then.getTime() / 1000, 10 );
}

function get_date_args(epoch) {
	// return hash containing year, mon, mday, hour, min, sec
	// given epoch seconds
	var date = new Date( epoch * 1000 );
	var args = {
		year: date.getFullYear(),
		mon: date.getMonth() + 1,
		mday: date.getDate(),
		hour: date.getHours(),
		min: date.getMinutes(),
		sec: date.getSeconds(),
		msec: date.getMilliseconds()
	};

	args.yyyy = args.year;
	if (args.mon < 10) args.mm = "0" + args.mon; else args.mm = args.mon;
	if (args.mday < 10) args.dd = "0" + args.mday; else args.dd = args.mday;
	if (args.hour < 10) args.hh = "0" + args.hour; else args.hh = args.hour;
	if (args.min < 10) args.mi = "0" + args.min; else args.mi = args.min;
	if (args.sec < 10) args.ss = "0" + args.sec; else args.ss = args.sec;

	if (args.hour >= 12) {
		args.ampm = 'pm';
		args.hour12 = args.hour - 12;
		if (!args.hour12) args.hour12 = 12;
	}
	else {
		args.ampm = 'am';
		args.hour12 = args.hour;
		if (!args.hour12) args.hour12 = 12;
	}
	return args;
}

function get_time_from_args(args) {
	// return epoch given args like those returned from get_date_args()
	var then = new Date(
		args.year,
		args.mon - 1,
		args.mday,
		args.hour,
		args.min,
		args.sec,
		0
	);
	return parseInt( then.getTime() / 1000, 10 );
}

function yyyy(epoch) {
	// return current year (or epoch) in YYYY format
	if (!epoch) epoch = time_now();
	var args = get_date_args(epoch);
	return args.year;
}

function yyyy_mm_dd(epoch) {
	// return current date (or custom epoch) in YYYY/MM/DD format
	if (!epoch) epoch = time_now();
	var args = get_date_args(epoch);
	return args.yyyy + '/' + args.mm + '/' + args.dd;
}

function normalize_time(epoch, zero_args) {
	// quantize time into any given precision
	// example hourly: { min:0, sec:0 }
	// daily: { hour:0, min:0, sec:0 }
	var args = get_date_args(epoch);
	for (key in zero_args) args[key] = zero_args[key];

	// mday is 1-based
	if (!args['mday']) args['mday'] = 1;

	return get_time_from_args(args);
}

function mm_dd_yyyy(epoch, ch) {
	if (!ch) ch = '/';
	var dargs = get_date_args(epoch);
	if (dargs.mon < 10) dargs.mon = '0' + dargs.mon;
	if (dargs.mday < 10) dargs.mday = '0' + dargs.mday;
	return dargs.year + ch + dargs.mon + ch + dargs.mday;
}

function get_nice_date(epoch, abbrev) {
	var dargs = get_date_args(epoch);
	var month = window._months[dargs.mon - 1][1];
	if (abbrev) month = month.substring(0, 3);
	return month + ' ' + dargs.mday + ', ' + dargs.year;
}

function get_nice_time(epoch, secs) {
	// return time in HH12:MM format
	var dargs = get_date_args(epoch);
	if (dargs.min < 10) dargs.min = '0' + dargs.min;
	if (dargs.sec < 10) dargs.sec = '0' + dargs.sec;
	var output = dargs.hour12 + ':' + dargs.min;
	if (secs) output += ':' + dargs.sec;
	output += ' ' + dargs.ampm.toUpperCase();
	return output;
}

function get_nice_date_time(epoch, secs, abbrev_date) {
	return get_nice_date(epoch, abbrev_date) + ' ' + get_nice_time(epoch, secs);
}

function get_short_date_time(epoch) {
	return get_nice_date(epoch, true) + ' ' + get_nice_time(epoch, false);
}

function get_midnight(date) {
	// return epoch of nearest midnight in past (local time)
	var midnight = parseInt( date.getTime() / 1000, 10 );

	midnight -= (date.getHours() * 3600);
	midnight -= (date.getMinutes() * 60);
	midnight -= date.getSeconds();

	return midnight;
}

function get_relative_date(epoch, show_time) {
	// convert epoch to short date string
	var mydate;
	var now = new Date();
	var now_epoch = parseInt( now.getTime() / 1000, 10 );

	if (epoch) {
		mydate = new Date( epoch * 1000 );
		epoch = parseInt( epoch, 10 );
	}
	else {
		mydate = new Date();
		epoch = parseInt( mydate.getTime() / 1000, 10 );
	}

	// relative date display
	var full_date_string = mydate.toLocaleString();
	var html = '<span title="'+full_date_string+'">';

	// get midnight of each
	var mydate_midnight = get_midnight( mydate );
	var now_midnight = get_midnight( now );

	if (mydate_midnight > now_midnight) {
		// date in future
		var mm = mydate.getMonth() + 1; // if (mm < 10) mm = "0" + mm;
		var dd = mydate.getDate(); // if (dd < 10) dd = "0" + dd;
		var yyyy = mydate.getFullYear();

		html += window._short_month_names[ mydate.getMonth() ] + ' ' + dd;
		if (yyyy != now.getFullYear()) html += ', ' + yyyy;
		
		// html += mm + '/' + dd;
		// if (yyyy != now.getFullYear()) html += '/' + yyyy;
		// html += '/' + yyyy;
		// if (show_time) html += ' ' + get_short_time(epoch);
	}
	else if (mydate_midnight == now_midnight) {
		// today
		if (show_time) {
			if (now_epoch - epoch < 1) {
				html += 'Now';
			}
			else if (now_epoch - epoch < 60) {
				// less than 1 minute ago
				/*var sec = (now_epoch - epoch);
				html += sec + ' Second';
				if (sec != 1) html += 's';
				html += ' Ago';*/
				html += 'A Moment Ago';
			}
			else if (now_epoch - epoch < 3600) {
				// less than 1 hour ago
				var min = parseInt( (now_epoch - epoch) / 60, 10 );
				html += min + ' Minute';
				if (min != 1) html += 's';
				html += ' Ago';
			}
			else if (now_epoch - epoch <= 12 * 3600) {
				// 12 hours or less prior
				var hr = parseInt( (now_epoch - epoch) / 3600, 10 );
				html += hr + ' Hour';
				if (hr != 1) html += 's';
				html += ' Ago';
			}
			else {
				// more than 12 hours ago, but still today
				html += 'Earlier Today';
				if (show_time) html += ', ' + get_short_time(epoch);
			}
		}
		else html += 'Today';
	}
	else if (now_midnight - mydate_midnight == 86400) {
		// yesterday
		html += 'Yesterday';
		if (show_time) html += ', ' + get_short_time(epoch);
	}
	else if ((now_midnight - mydate_midnight < 86400 * 7) && (mydate.getDay() < now.getDay())) {
		// this week
		html += window._day_names[ mydate.getDay() ];
		if (show_time) html += ', ' + get_short_time(epoch);
	}
	else if ((mydate.getMonth() == now.getMonth()) && (mydate.getFullYear() == now.getFullYear())) {
		// this month
		var mydate_sunday = mydate_midnight - (mydate.getDay() * 86400);
		var now_sunday = now_midnight - (now.getDay() * 86400);

		if (now_sunday - mydate_sunday == 86400 * 7) {
			// last week
			// html += 'Last Week';
			html += 'Last ' + window._day_names[ mydate.getDay() ];
		}
		else {
			// older
			var mm = mydate.getMonth() + 1; // if (mm < 10) mm = "0" + mm;
			var dd = mydate.getDate(); // if (dd < 10) dd = "0" + dd;
			var yyyy = mydate.getFullYear();

			html += window._short_month_names[ mydate.getMonth() ] + ' ' + dd;
			if (yyyy != now.getFullYear()) html += ', ' + yyyy;
		}
	}
	else {
		// older
		var mm = mydate.getMonth() + 1; // if (mm < 10) mm = "0" + mm;
		var dd = mydate.getDate(); // if (dd < 10) dd = "0" + dd;
		var yyyy = mydate.getFullYear();

		html += window._short_month_names[ mydate.getMonth() ] + ' ' + dd;
		if (yyyy != now.getFullYear()) html += ', ' + yyyy;
		// html += mm + '/' + dd;
		// if (yyyy != now.getFullYear()) html += '/' + yyyy;
		// if (show_time) html += ' ' + get_short_time(epoch);
	}

	html += '</span>';
	return html;
}

function get_short_time(epoch, show_msec) {
	// convert epoch to short time string
	var mydate;
	if (epoch) mydate = new Date( epoch * 1000 );
	else mydate = new Date();
	
	var ampm = 'AM';
	var hh = mydate.getHours();
	if (hh >= 12) { ampm = 'PM'; hh -=12; }
	if (hh == 0) hh = 12;
	
	var mi = mydate.getMinutes(); if (mi < 10) mi = "0" + mi;
	var ss = mydate.getSeconds(); if (ss < 10) ss = "0" + ss;
	var msec = mydate.getMilliseconds();
	if (msec < 10) msec = "00" + msec;
	else if (msec < 100) msec = "0" + msec;
	
	var str = hh+':'+mi;
	if (show_msec) str += ':'+ss+'.'+msec;
	
	str += '&nbsp;'+ampm;
	return str;
}

function get_date_selector(prefix, epoch, start_year, end_year) {
	// return html for mon/mday/year multi-menu selector
	if (!start_year) start_year = 0;
	if (!end_year) end_year = 0;
	var now_year = parseInt( (new Date()).getFullYear(), 10 );
	start_year += now_year;
	end_year += now_year;
	
	var years = [];
	for (var year = start_year; year <= end_year; year++) {
		years.push( [year, ''+year] );
	}
	
	var date = get_date_args(epoch);
	var html = '';
	
	html += render_menu( prefix + '_mon', window._months, date.mon );
	html += render_menu( prefix + '_mday', window._days, date.mday );
	html += render_menu( prefix + '_year', years, date.year );
	
	return html;
}

function set_date_menu_value( prefix, epoch ) {
	// set multi-menu date selector to epoch
	// requires jQuery
	var date = get_date_args(epoch);
	
	$( '#' + prefix + '_mon' ).val( date.mon );
	$( '#' + prefix + '_mday' ).val( date.mday );
	$( '#' + prefix + '_year' ).val( date.year );
}

function get_date_menu_value( prefix, fmt ) {
	// get epoch of multi-menu date selector
	// requires jQuery
	var mon = parseInt( $( '#' + prefix + '_mon' ).val(), 10 );
	var mday = parseInt( $( '#' + prefix + '_mday' ).val(), 10 );
	var year = parseInt( $( '#' + prefix + '_year' ).val(), 10 );
	
	var date = new Date( year, mon - 1, mday, 0, 0, 0, 0 );
	var epoch = parseInt( date.getTime() / 1000 );
	
	if (fmt) {
		var args = get_date_args(epoch);
		return substitute(fmt, args);
	}
	return epoch;
}

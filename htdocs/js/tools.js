// Some tools of Joe

function parseQueryString(queryString) {
	// parse query string into object
	var pair = null;
	var queryObject = new Object();
	queryString = queryString.replace(/^.*\?(.+)$/,'$1');
	
	while ((pair = queryString.match(/(\w+)=([^\&]*)\&?/)) && pair[0].length) {
		queryString = queryString.substring( pair[0].length );
		pair[2] = unescape(pair[2]);
		if (/^\-?\d+$/.test(pair[2])) pair[2] = parseInt(pair[2], 10);
		
		if (typeof(queryObject[pair[1]]) != 'undefined') {
			always_array( queryObject, pair[1] );
			array_push( queryObject[pair[1]], pair[2] );
		}
		else queryObject[pair[1]] = pair[2];
	}
	
	return queryObject;
}

function composeQueryString(queryObj) {
	// compose key/value pairs into query string
	// supports duplicate keys (i.e. arrays)
	var qs = '';
	for (var key in queryObj) {
		var values = always_array(queryObj[key]);
		for (var idx = 0, len = values.length; idx < len; idx++) {
			qs += (qs.length ? '&' : '?') + escape(key) + '=' + escape(values[idx]);
		}
	}
	return qs;
}

function trim(text) {
	// strip whitespace from beginning and end of string
	if (text == null) return '';
	
	if (text && text.replace) {
		text = text.replace(/^\s+/, "");
		text = text.replace(/\s+$/, "");
	}
	
	return text;
}

function ucfirst(text) {
	// capitalize first character only, lower-case rest
	return text.substring(0, 1).toUpperCase() + text.substring(1, text.length).toLowerCase();
}

function encode_entities(text) {
	// Simple entitize function for composing XML
	if (text == null) return '';

	if (text && text.replace) {
		text = text.replace(/\&/g, "&amp;"); // MUST BE FIRST
		text = text.replace(/</g, "&lt;");
		text = text.replace(/>/g, "&gt;");
	}

	return text;
}

function encode_attrib_entities(text) {
	// Simple entitize function for composing XML attributes
	if (text == null) return '';

	if (text && text.replace) {
		text = text.replace(/\&/g, "&amp;"); // MUST BE FIRST
		text = text.replace(/</g, "&lt;");
		text = text.replace(/>/g, "&gt;");
		text = text.replace(/\"/g, "&quot;");
		text = text.replace(/\'/g, "&apos;");
	}

	return text;
}

function decode_entities(text) {
	// Decode XML entities into raw ASCII
	if (text == null) return '';

	if (text && text.replace) {
		text = text.replace(/\&lt\;/g, "<");
		text = text.replace(/\&gt\;/g, ">");
		text = text.replace(/\&quot\;/g, '"');
		text = text.replace(/\&apos\;/g, "'");
		text = text.replace(/\&amp\;/g, "&"); // MUST BE LAST
	}

	return text;
}

function find_object(obj, criteria) {
	// walk array looking for nested object matching criteria object
	
	var criteria_length = 0;
	for (var a in criteria) criteria_length++;
	obj = always_array(obj);
	
	for (var a = 0; a < obj.length; a++) {
		var matches = 0;
		
		for (var b in criteria) {
			if (obj[a][b] && (obj[a][b] == criteria[b])) matches++;
			else if (obj[a]["_Attribs"] && obj[a]["_Attribs"][b] && (obj[a]["_Attribs"][b] == criteria[b])) matches++;
		}
		if (matches >= criteria_length) return obj[a];
	}
	return null;
}

function find_objects(obj, criteria) {
	// walk array gathering all nested objects that match criteria object
	var objs = new Array();
	var criteria_length = 0;
	for (var a in criteria) criteria_length++;
	obj = always_array(obj);
	
	for (var a = 0; a < obj.length; a++) {
		var matches = 0;
		for (var b in criteria) {
			if (obj[a][b] && obj[a][b] == criteria[b]) matches++;
			else if (obj[a]["_Attribs"] && obj[a]["_Attribs"][b] && (obj[a]["_Attribs"][b] == criteria[b])) matches++;
		}
		if (matches >= criteria_length) array_push( objs, obj[a] );
	}
	
	return objs;
}

function find_object_idx(obj, criteria) {
	// walk array looking for nested object matching criteria object
	// return index in outer array, not object itself
	
	var criteria_length = 0;
	for (var a in criteria) criteria_length++;
	obj = always_array(obj);
	
	for (var idx = 0; idx < obj.length; idx++) {
		var matches = 0;
		
		for (var b in criteria) {
			if (obj[idx][b] && (obj[idx][b] == criteria[b])) matches++;
			else if (obj[idx]["_Attribs"] && obj[idx]["_Attribs"][b] && (obj[idx]["_Attribs"][b] == criteria[b])) matches++;
		}
		if (matches >= criteria_length) return idx;
	}
	return -1;
}

function delete_object(obj, criteria) {
	// walk array looking for nested object matching criteria object
	// delete first object found
	var idx = find_object_idx(obj, criteria);

	if (idx > -1) {
		// array_splice( obj, idx, 1 );
		obj.splice( idx, 1 );
		return true;
	}
	return false;
}

function delete_objects(obj, criteria) {
	// delete all objects in obj array matching criteria
	while (delete_object(obj, criteria)) ;
}

function insert_object_before(obj, criteria, insert) {
	// insert object in array before element found via criteria
	var idx = find_object_idx(obj, criteria);

	if (idx > -1) {
		// array_splice( obj, idx, 0, insert );
		obj.splice( idx, 0, insert );
		return true;
	}
	return false;
}

function always_array(obj, key) {
	// if object is not array, return array containing object
	// if key is passed, work like XMLalwaysarray() instead
	// apparently MSIE has weird issues with obj = always_array(obj);
	
	if (key) {
		if ((typeof(obj[key]) != 'object') || (typeof(obj[key].length) == 'undefined')) {
			var temp = obj[key];
			delete obj[key];
			obj[key] = new Array();
			obj[key][0] = temp;
		}
		return null;
	}
	else {
		if ((typeof(obj) != 'object') || (typeof(obj.length) == 'undefined')) { return [ obj ]; }
		else return obj;
	}
}

function hash_keys_to_array(hash) {
	// convert hash keys to array (discard values)
	var array = [];
	for (var key in hash) array.push(key);
	return array;
}

function isa_hash(arg) {
	// determine if arg is a hash
	return( !!arg && (typeof(arg) == 'object') && (typeof(arg.length) == 'undefined') );
}

function isa_array(arg) {
	// determine if arg is an array or is array-like
	if (typeof(arg) == 'array') return true;
	return( !!arg && (typeof(arg) == 'object') && (typeof(arg.length) != 'undefined') );
}

function lookup_path(path, obj) {
	// walk through object tree, psuedo-XPath-style
	// supports arrays as well as objects
	// return final object or value
	// always start query with a slash, i.e. /something/or/other
	path = path.replace(/\/$/, ""); // strip trailing slash
	
	while (/\/[^\/]+/.test(path) && (typeof(obj) == 'object')) {
		// find first slash and strip everything up to and including it
		var slash = path.indexOf('/');
		path = path.substring( slash + 1 );
		
		// find next slash (or end of string) and get branch name
		slash = path.indexOf('/');
		if (slash == -1) slash = path.length;
		var name = path.substring(0, slash);

		// advance obj using branch
		if (typeof(obj.length) == 'undefined') {
			// obj is hash
			if (typeof(obj[name]) != 'undefined') obj = obj[name];
			else return null;
		}
		else {
			// obj is array
			var idx = parseInt(name, 10);
			if (isNaN(idx)) return null;
			if (typeof(obj[idx]) != 'undefined') obj = obj[idx];
			else return null;
		}

	} // while path contains branch

	return obj;
}

function copy_object(obj) {
	// return copy of object (NOT DEEP)
	var new_obj = {};

	for (var key in obj) new_obj[key] = obj[key];

	return new_obj;
}

function merge_objects(a, b) {
	// merge keys from a and b into c and return c
	// b has precedence over a
	if (!a) a = {};
	if (!b) b = {};
	var c = {};

	// also handle serialized objects for a and b
	if (typeof(a) != 'object') eval( "a = " + a );
	if (typeof(b) != 'object') eval( "b = " + b );

	for (var key in a) c[key] = a[key];
	for (var key in b) c[key] = b[key];

	return c;
}

function render_menu_options(items, sel_value, auto_add) {
	// return HTML for menu options
	var html = '';
	var found = false;
	
	for (var idx = 0, len = items.length; idx < len; idx++) {
		var item = items[idx];
		var item_name = '';
		var item_value = '';
		if (isa_hash(item)) {
			item_name = item.label;
			item_value = item.data;
		}
		else if (isa_array(item)) {
			item_value = item[0];
			item_name = item[1];
		}
		else {
			item_name = item_value = item;
		}
		html += '<option value="'+item_value+'" '+((item_value == sel_value) ? 'selected="selected"' : '')+'>'+item_name+'</option>';
		if (item_value == sel_value) found = true;
	}
	
	if (!found && (str_value(sel_value) != '') && auto_add) {
		html += '<option value="'+sel_value+'" selected="selected">'+sel_value+'</option>';
	}
	
	return html;
}

function render_menu( id, items, value ) {
	// render simple menu given id, array of items, and value
	if (typeof(value) == 'undefined') value = null;
	var html = '<select name="'+id+'" id="'+id+'">';
	html += render_menu_options(items, value);
	html += '</select>';
	return html;
}

function populate_menu(id, items, sel_value) {
	// If using jquery, pass in real selector, not id
	var menu = $(id)[0];
	if (!menu) return false;
	menu.options.length = 0;
	
	for (var idx = 0, len = items.length; idx < len; idx++) {
		var item = items[idx];
		var item_name = isa_array(item) ? item[0] : item;
		var item_value = isa_array(item) ? item[1] : item;
		menu.options[ menu.options.length ] = new Option( item_name, item_value );
		if (item_value == sel_value) menu.selectedIndex = idx;
	} // foreach item
}

function get_text_from_bytes(bytes) {
	// convert raw bytes to english-readable format
	if (bytes >= 1024) {
		bytes = parseInt( (bytes / 1024) * 10, 10 ) / 10;
		if (bytes >= 1024) {
			bytes = parseInt( (bytes / 1024) * 10, 10 ) / 10;
			if (bytes >= 1024) {
				bytes = parseInt( (bytes / 1024) * 10, 10 ) / 10;
				if (bytes >= 1024) {
					bytes = parseInt( (bytes / 1024) * 10, 10 ) / 10;
					return bytes + ' TB';
				} 
				else return bytes + ' GB';
			} 
			else return bytes + ' MB';
		}
		else return parseInt(bytes, 10) + ' K';
	}
	else return bytes + ' bytes';
}

function get_bytes_from_text(text) {
	// parse text into raw bytes, e.g. "1 K" --> 1024
	if (text.toString().match(/^\d+$/)) return text; // already in bytes
	var multipliers = {
		b: 1,
		k: 1024,
		m: 1024 * 1024,
		g: 1024 * 1024 * 1024,
		t: 1024 * 1024 * 1024 * 1024
	};
	var bytes = 0;
	text = text.replace(/([\d\.]+)\s*(\w)\w*\s*/g, function(m_all, m_g1, m_g2) {
		var mult = multipliers[ m_g2.toLowerCase() ] || 0;
		bytes += (parseFloat(m_g1) * mult); 
		return '';
	} );
	return Math.floor(bytes);
}

function commify(number) {
	// add commas to integer, like 1,234,567
	// from: http://javascript.internet.com/messages/add-commas.html
	if (!number) number = 0;

	number = '' + number;
	if (number.length > 3) {
		var mod = number.length % 3;
		var output = (mod > 0 ? (number.substring(0,mod)) : '');
		for (i=0 ; i < Math.floor(number.length / 3); i++) {
			if ((mod == 0) && (i == 0))
				output += number.substring(mod+ 3 * i, mod + 3 * i + 3);
			else
				output+= ',' + number.substring(mod + 3 * i, mod + 3 * i + 3);
		}
		return (output);
	}
	else return number;
}

function short_float(value) {
	// Shorten floating-point decimal to 2 places, unless they are zeros.
	if (!value) value = 0;
	return value.toString().replace(/^(\-?\d+\.[0]*\d{2}).*$/, '$1');
}

function pct(count, max) {
	// Return percentage given a number along a sliding scale from 0 to 'max'
	var pct = (count * 100) / (max || 1);
	if (!pct.toString().match(/^\d+(\.\d+)?$/)) { pct = 0; }
	return '' + short_float( pct ) + '%';
}

function get_text_from_seconds(sec, abbrev, no_secondary) {
	// convert raw seconds to human-readable relative time
	var neg = '';
	sec = parseInt(sec, 10);
	if (sec<0) { sec =- sec; neg = '-'; }
	
	var p_text = abbrev ? "sec" : "second";
	var p_amt = sec;
	var s_text = "";
	var s_amt = 0;
	
	if (sec > 59) {
		var min = parseInt(sec / 60, 10);
		sec = sec % 60; 
		s_text = abbrev ? "sec" : "second"; 
		s_amt = sec; 
		p_text = abbrev ? "min" : "minute"; 
		p_amt = min;
		
		if (min > 59) {
			var hour = parseInt(min / 60, 10);
			min = min % 60; 
			s_text = abbrev ? "min" : "minute"; 
			s_amt = min; 
			p_text = abbrev ? "hr" : "hour"; 
			p_amt = hour;
			
			if (hour > 23) {
				var day = parseInt(hour / 24, 10);
				hour = hour % 24; 
				s_text = abbrev ? "hr" : "hour"; 
				s_amt = hour; 
				p_text = "day"; 
				p_amt = day;
				
				if (day > 29) {
					var month = parseInt(day / 30, 10);
					day = day % 30; 
					s_text = "day"; 
					s_amt = day; 
					p_text = abbrev ? "mon" : "month"; 
					p_amt = month;
				} // day>29
			} // hour>23
		} // min>59
	} // sec>59
	
	var text = p_amt + "&nbsp;" + p_text;
	if ((p_amt != 1) && !abbrev) text += "s";
	if (s_amt && !no_secondary) {
		text += ", " + s_amt + "&nbsp;" + s_text;
		if ((s_amt != 1) && !abbrev) text += "s";
	}
	
	return(neg + text);
}

function get_nice_remaining_time(epoch_start, epoch_now, counter, counter_max, abbrev) {
	// estimate remaining time given starting epoch, a counter and the 
	// counter maximum (i.e. percent and 100 would work)
	// return in english-readable format
	
	if (counter == counter_max) return 'Complete';
	if (counter == 0) return 'n/a';
	
	var sec_remain = parseInt(((counter_max - counter) * (epoch_now - epoch_start)) / counter, 10);
	
	return get_text_from_seconds( sec_remain, abbrev );
}

function rand_array(arr) {
	// return random element from array
	return arr[ parseInt(Math.random() * arr.length, 10) ];
}

function getInnerWindowSize(dom) {
	// get size of inner window
	// From: http://www.howtocreate.co.uk/tutorials/javascript/browserwindow
	if (!dom) dom = window;
	var myWidth = 0, myHeight = 0;
	
	if( typeof( dom.innerWidth ) == 'number' ) {
		// Non-IE
		myWidth = dom.innerWidth;
		myHeight = dom.innerHeight;
	}
	else if( dom.document.documentElement && ( dom.document.documentElement.clientWidth || dom.document.documentElement.clientHeight ) ) {
		// IE 6+ in 'standards compliant mode'
		myWidth = dom.document.documentElement.clientWidth;
		myHeight = dom.document.documentElement.clientHeight;
	}
	else if( dom.document.body && ( dom.document.body.clientWidth || dom.document.body.clientHeight ) ) {
		// IE 4 compatible
		myWidth = dom.document.body.clientWidth;
		myHeight = dom.document.body.clientHeight;
	}
	return { width: myWidth, height: myHeight };
}

function getScrollXY(dom) {
	// get page scroll X, Y
	if (!dom) dom = window;
  var scrOfX = 0, scrOfY = 0;
  if( typeof( dom.pageYOffset ) == 'number' ) {
    //Netscape compliant
    scrOfY = dom.pageYOffset;
    scrOfX = dom.pageXOffset;
  } else if( dom.document.body && ( dom.document.body.scrollLeft || dom.document.body.scrollTop ) ) {
    //DOM compliant
    scrOfY = dom.document.body.scrollTop;
    scrOfX = dom.document.body.scrollLeft;
  } else if( dom.document.documentElement && ( dom.document.documentElement.scrollLeft || dom.document.documentElement.scrollTop ) ) {
    //IE6 standards compliant mode
    scrOfY = dom.document.documentElement.scrollTop;
    scrOfX = dom.document.documentElement.scrollLeft;
  }
  return { x: scrOfX, y: scrOfY };
}

function getScrollMax(dom) {
	// get maximum scroll width/height
	if (!dom) dom = window;
	var myWidth = 0, myHeight = 0;
	if (dom.document.body.scrollHeight) {
		myWidth = dom.document.body.scrollWidth;
		myHeight = dom.document.body.scrollHeight;
	}
	else if (dom.document.documentElement.scrollHeight) {
		myWidth = dom.document.documentElement.scrollWidth;
		myHeight = dom.document.documentElement.scrollHeight;
	}
	return { width: myWidth, height: myHeight };
}

function dirname(path) {
	// return path excluding file at end (same as POSIX function of same name)
	return path.toString().replace(/\\/g, "/").replace(/\/$/, "").replace(/\/[^\/]+$/, "");
}

function basename(path) {
	// return filename, strip path (same as POSIX function of same name)
	return path.toString().replace(/\\/g, "/").replace(/\/$/, "").replace(/^(.*)\/([^\/]+)$/, "$2");
}

function load_script(url) {
	var scr = document.createElement('SCRIPT');
	scr.type = 'text/javascript';
	scr.src = url;
	document.getElementsByTagName('HEAD')[0].appendChild(scr);
}

function hideDelete(elem, duration) {
	// use jquery to animate-hide element, then delete it
	$(elem).hide( duration, function() {
		$(this).remove();
	} );
}

function collapseAttribs(obj) {
	// recursively walk object and collapse XML _Attribs keys into parents
	// Note: This is destructive to the original tree.
	if (isa_hash(obj)) {
		if (obj._Attribs && isa_hash(obj._Attribs)) {
			for (var key in obj._Attribs) obj[key] = obj._Attribs[key];
			delete obj._Attribs;
		}
		for (var key in obj) {
			if (isa_hash(obj[key]) || isa_array(obj[key])) collapseAttribs( obj[key] );
		}
	}
	else if (isa_array(obj)) {
		for (var idx = 0, len = obj.length; idx < len; idx++) {
			if (isa_hash(obj[idx]) || isa_array(obj[idx])) collapseAttribs( obj[idx] );
		}
	}
	
	return obj;
}

function serialize(thingy) {
	return JSON.stringify( thingy );
}

function num_keys(hash) {
	// count the number of keys in a hash
	var count = 0;
	for (var a in hash) count++;
	return count;
}

function first_key(hash) {
	// return first key from hash (unordered)
	for (var key in hash) return key;
	return null; // no keys in hash
}

function popup_window(url, name) {
	// popup URL in new window, and make sure it worked
	if (!url) url = '';
	if (!name) name = '';
	var win = window.open(url, name);
	if (!win) return alert('Failed to open popup window.  If you have a popup blocker, please disable it for this website and try again.');
	if (!win.opener) win.opener = window;
	return win;
}

function str_value(str) {
	if (typeof(str) == 'undefined') str = '';
	else if (str === null) str = '';
	return '' + str;
}

function pluralize(word, num) {
	if (num != 1) {
		return word.replace(/y$/, 'ie') + 's';
	}
	else return word;
}

function escape_text_field_value(text) {
	// escape text field value, with stupid IE support
	text = encode_attrib_entities( str_value(text) );
	if (navigator.userAgent.match(/MSIE/) && text.replace) text = text.replace(/\&apos\;/g, "'");
	return text;
}

function escape_textarea_field_value(text) {
	// escape textarea field value, with stupid IE support
	text = encode_entities( str_value(text) );
	if (navigator.userAgent.match(/MSIE/) && text.replace) text = text.replace(/\&apos\;/g, "'");
	return text;
}

function format_price(value, cur_code, raw) {
	// format number to USD or CAD price: 0 == "$0.00 USD", 1.5 = "$1.50 CAD"
	var output = '';
	if (cur_code) cur_code = ' ' + cur_code;
	var matches = value.toString().match(/^(\d+)\.(\d+)$/);
	if (matches) {
		if (matches[2].length < 2) matches[2] = '0' + matches[2];
		else if (matches[2].length > 2) matches[2] = matches[2].substring(0, 2);
		output = '$' + commify(matches[1]) + '.' + matches[2] + (cur_code ? cur_code : '');
	}
	else output = '$' + commify(value) + '.00' + (cur_code ? cur_code : '');
	return raw ? output.replace(/[\$\,]/g, '') : output;
}

function stop_event(e) {
	// prevent default behavior for event
	if (e.preventDefault) {
		e.preventDefault();
		e.stopPropagation();
	}
	else {
		e.returnValue = false;
		e.cancelBubble = true;
	}
	return false;
}

function get_unique_id() {
	// get unique id using hires time and random number
	if (this.__unique_id_counter) this.__unique_id_counter = 0;
	this.__unique_id_counter++;
	return hex_md5( '' + hires_time_now() + Math.random() + this.__unique_id_counter );
}

function parse_useragent(useragent) {
	// parse useragent into OS and browser
	// if (!useragent) useragent = navigator.userAgent;
	useragent = '' + useragent;
	var os = 'Unknown';
	var browser = 'Unknown';
	
	// remove squid
	useragent = useragent.replace(/\;\s+[\d\.]+\s+cache[\.\w]+(\:\d+)?\s+\(squid[^\)]+\)/, '');
	
	if (useragent.match(/SunOS/)) { os = 'SunOS'; }
	else if (useragent.match(/IRIX/)) { os = 'IRIX'; }
	else if (useragent.match(/Android\D+(\d+\.\d)/)) { os = 'Android ' + RegExp.$1; }
	else if (useragent.match(/Linux/)) { os = 'Linux'; }
	else if (useragent.match(/iPhone/)) { os = 'iPhone'; }
	else if (useragent.match(/Mac\s+OS\s+X\s+([\d\_]+)/)) { os = 'Mac OS X ' + RegExp.$1.replace(/_/g, '.'); }
	else if (useragent.match(/(Mac\s+OS\s+X|Mac_PowerPC)/)) { os = 'Mac OS X'; }
	else if (useragent.match(/Mac/)) { os = 'Mac OS'; }
	else if (useragent.match(/Windows\s+CE/)) { os = 'Windows CE'; }
	else if (useragent.match(/(Windows\s+ME|Win\s9x)/)) { os = 'Windows Me'; }
	else if (useragent.match(/Win(95|98|NT)/)) { os = "Windows " + RegExp.$1; }
	else if (useragent.match(/Win\D+([\d\.]+)/)) {
		var ver = RegExp.$1;
		if (ver.match(/95/)) { os = 'Windows 95'; }
		else if (ver.match(/98/)) { os = 'Windows 98'; }
		else if (ver.match(/4\.0/)) { os = 'Windows NT'; }
		else if (ver.match(/5\.0/)) { os = 'Windows 2000'; }
		else if (ver.match(/5\.[12]/)) {
			os = 'Windows XP';
			// if (useragent.match(/(SV1|MSIE\D+7)/)) { os += ' SP2'; }
		}
		else if (ver.match(/6.0/)) { os = 'Windows Vista'; }
		else if (ver.match(/6.1/)) { os = 'Windows 7'; }
		else if (ver.match(/6.2/)) { os = 'Windows 8'; }
		else if (useragent.match(/Windows\sNT/)) { os = 'Windows NT'; }
	}
	else if (useragent.match(/Windows\sNT/)) { os = 'Windows NT'; }
	else if (useragent.match(/PSP/)) { os = 'Sony PSP'; }
	else if (useragent.match(/WebTV/)) { os = 'Web TV'; }
	else if (useragent.match(/Palm/)) { os = 'Palm OS'; }
	else if (useragent.match(/Wii/)) { os = 'Nintendo Wii'; }
	else if (useragent.match(/Symbian/)) { os = 'Symbian OS'; }
		
	if (useragent.match(/Chrome\D+(\d+)/)) {
		browser = "Chrome " + RegExp.$1;
	}
	else if (useragent.match(/Android/) && useragent.match(/WebKit/) && useragent.match(/Version\D(\d+\.\d)/)) {
		browser = 'WebKit ' + RegExp.$1;
	}
	else if (useragent.match(/Safari\/((\d+)[\d\.]+)/)) {
		if (useragent.match(/Version\D+([\d\.]+)/)) {
			// Safari 3+ has version embedded in useragent (FINALLY)
			browser = "Safari " + RegExp.$1;
		}
		else {
			browser = 'Safari 2';
		}
	}
	else if (useragent.match(/iCab/)) { browser = 'iCab'; }
	else if (useragent.match(/OmniWeb/)) { browser = 'OmniWeb'; }
	else if (useragent.match(/Opera\D*(\d+)/)) { browser = "Opera " + RegExp.$1; }
	else if (useragent.match(/(Camino|Chimera)/)) { browser = 'Camino'; }
	else if (useragent.match(/Firefox\D*(\d+\.\d+)/)) { browser = "Firefox " + RegExp.$1; }
	else if (useragent.match(/Netscape\D*(\d+(\.\d+)?)/)) { browser = "Netscape " + RegExp.$1; }
	else if (useragent.match(/Minefield\D+(\d+\.\d)/)) { browser = 'Firefox ' + RegExp.$1 + ' Nightly Build'; }
	else if (useragent.match(/Gecko/)) { browser = 'Mozilla'; }
	else if (useragent.match(/America\s+Online\s+Browser\D+(\d+(\.\d+)?)/)) { browser = "AOL Explorer " + RegExp.$1; }
	else if (useragent.match(/PSP\D+(\d+(\.\d+)?)/)) { browser = "PSP " + RegExp.$1; }
	else if (useragent.match(/Lynx\D+(\d+(\.\d+)?)/)) { browser = "Lynx " + RegExp.$1; }
	else if (useragent.match(/Konqueror\D+(\d+(\.\d+)?)/)) { browser = "Konqueror " + RegExp.$1; }
	else if (useragent.match(/Blazer\D+(\d+(\.\d+)?)/)) { browser = "Blazer " + RegExp.$1; }
	else if (useragent.match(/MSIE\D+(\d+)/)) { browser = "Internet Explorer " + RegExp.$1; }
	else if (useragent.match(/Mozilla\/(4\.\d)/)) {
		var ver = RegExp.$1;
		if (ver != '4.0') { browser = "Netscape " + ver; }
		else { browser = "Mozilla"; }
	}
	else if (useragent.match(/Mozilla/)) { browser = "Mozilla"; }
	
	if ((os == 'Unknown') && (browser == 'Unknown') && useragent.match(/Flash\s+Player\s+([\d\.\,]+)/)) {
		os = 'Adobe';
		browser = 'Flash Player ' + RegExp.$1;
	}
	
	return { os: os, browser: browser };
}

function get_nice_useragent(useragent) {
	// get short useragent for display
	var info = parse_useragent(useragent);
	var str = trim( info.os + ' ' + info.browser );
	return '<span title="'+useragent.replace(/[\n\"]/g, '')+'">' + str + '</span>';
}

function expando_text(text, max, link) {
	// if text is longer than max chars, chop with ellipsis and include link to show all
	// requires jQuery
	if (!link) link = 'More';
	text = str_value(text);
	if (text.length <= max) return text;
	
	var before = text.substring(0, max);
	var after = text.substring(max);
	
	return before + 
		'<span>... <a href="javascript:void(0)" onMouseUp="$(this).parent().hide().next().show()">'+link+'</a></span>' + 
		'<span style="display:none">' + after + '</span>';
}

function nch(chan) {
	// normalize irc channel name
	if (!chan.match(/^\#/)) chan = '#' + chan;
	return chan;
}
function sch(chan) {
	return chan.replace(/^\#/, '');
}

function substitute(text, args) {
	// perform simple [placeholder] substitution using supplied
	// args object (or eval) and return transformed text
	if (typeof(text) == 'undefined') text = '';
	text = '' + text;
	if (!args) args = {};

	while (text.indexOf('[') > -1) {
		var open_bracket = text.indexOf('[');
		var close_bracket = text.indexOf(']');

		var before = text.substring(0, open_bracket);
		var after = text.substring(close_bracket + 1, text.length);

		var name = text.substring( open_bracket + 1, close_bracket );
		var value = '';
		if (name.indexOf('/') == 0) value = lookup_path(name, args);
		else if (typeof(args[name]) != 'undefined') value = args[name];
		else if (!/^\w+$/.test(name)) value = eval(name);
		else value = '[' + name + ']';

		text = before + value + after;
	} // while text contains [

	return text;
}

//
// Easing functions
//

var EaseAlgos = {
	Linear: function(amount) { return amount; },
	Quadratic: function(amount) { return Math.pow(amount, 2); },
	Cubic: function(amount) { return Math.pow(amount, 3); },
	Quartetic: function(amount) { return Math.pow(amount, 4); },
	Quintic: function(amount) { return Math.pow(amount, 5); },
	Sine: function(amount) { return 1 - Math.sin((1 - amount) * Math.PI / 2); },
	Circular: function(amount) { return 1 - Math.sin(Math.acos(amount)); }
};
var EaseModes = {
	EaseIn: function(amount, algo) { return EaseAlgos[algo](amount); },
	EaseOut: function(amount, algo) { return 1 - EaseAlgos[algo](1 - amount); },
	EaseInOut: function(amount, algo) {
		return (amount <= 0.5) ? EaseAlgos[algo](2 * amount) / 2 : (2 - EaseAlgos[algo](2 * (1 - amount))) / 2;
	}
};
function ease(amount, mode, algo) {
	return EaseModes[mode]( amount, algo );
}
function tweenFrame(start, end, amount, mode, algo) {
	return start + (ease(amount, mode, algo) * (end - start));
}

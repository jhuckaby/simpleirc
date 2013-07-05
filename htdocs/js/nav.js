/**
 * AppStr 1.0 Navigation System
 * Author: Joseph Huckaby
 * Copyright (c) 2007 - 2008 Joseph Huckaby
 **/

var Nav = {
	
	loc: '',
	old_loc: '',
	inited: false,
	nodes: [],
	
	init: function() {
		// initialize nav system
		if (!this.inited) {
			this.inited = true;
			this.loc = 'init';
			this.monitor();
		}
	},

	monitor: function() {
		// monitor browser location and activate handlers as needed
		var parts = window.location.href.split(/\#/);
		var anchor = parts[1];
		if (!anchor) anchor = config.DefaultPage;
		
		var full_anchor = '' + anchor;
		var sub_anchor = '';
		
		anchor = anchor.replace(/\%7C/, '|');
		if (anchor.match(/\|(\w+)$/)) {
			// inline section anchor after article name, pipe delimited
			sub_anchor = RegExp.$1.toLowerCase();
			anchor = anchor.replace(/\|(\w+)$/, '');
		}
		
		if ((anchor != this.loc) && !anchor.match(/^_/)) { // ignore doxter anchors
			Debug.trace('nav', "Caught navigation anchor: " + full_anchor);
			
			var page_name = '';
			var page_args = null;
			if (full_anchor.match(/^\w+\?.+/)) {
				parts = full_anchor.split(/\?/);
				page_name = parts[0];
				page_args = parseQueryString( parts[1] );
			}
			else if (full_anchor.match(/^(\w+)\/(.*)$/)) {
				page_name = RegExp.$1;
				page_args = RegExp.$2;
			}
			else {
				parts = full_anchor.split(/\//);
				page_name = parts[0];
				page_args = parts.slice(1);
			}
			
			Debug.trace('nav', "Calling page: " + page_name + ": " + serialize(page_args));
			Dialog.hide();
			app.hideMessage();
			var result = app.page_manager.click( page_name, page_args );
			if (result) {
				this.old_loc = this.loc;
				if (this.old_loc == 'init') this.old_loc = config.DefaultPage;
				this.loc = anchor;
			}
			else {
				// current page aborted navigation -- recover current page without refresh
				this.go( this.loc );
			}
		}
		else if (sub_anchor != this.sub_anchor) {
			Debug.trace('nav', "Caught sub-anchor: " + sub_anchor);
			$P().gosub( sub_anchor );
		} // sub-anchor changed
		
		this.sub_anchor = sub_anchor;
	
		setTimeout( 'Nav.monitor()', 100 );
	},

	go: function(anchor, force) {
		// navigate to page
		anchor = anchor.replace(/^\#/, '');
		if (force) this.loc = 'init';
		window.location.href = '#' + anchor;
	},

	prev: function() {
		// return to previous page
		this.go( this.old_loc || config.DefaultPage );
	},

	refresh: function() {
		// re-nav to current page
		this.loc = 'refresh';
	},
	
	currentAnchor: function() {
		// return current page anchor
		var parts = window.location.href.split(/\#/);
		var anchor = parts[1] || '';
		var sub_anchor = '';
		
		anchor = anchor.replace(/\%7C/, '|');
		if (anchor.match(/\|(\w+)$/)) {
			// inline section anchor after article name, pipe delimited
			sub_anchor = RegExp.$1.toLowerCase();
			anchor = anchor.replace(/\|(\w+)$/, '');
		}
		
		return anchor;
	}

};

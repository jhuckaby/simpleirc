/**
 * AppStr 1.0 Page Class
 * Author: Joseph Huckaby
 * Copyright (c) 2007 - 2008 Joseph Huckaby
 **/

Class.create( 'AppStr.Page', {
	// 'AppStr.Page' class is the abstract base class for all pages
	// Each web component calls this class daddy
	
	// member variables
	ID: '', // ID of DIV for component
	data: null,   // holds all data for freezing
	active: false, // whether page is active or not
	sidebar: true, // whether to show sidebar or not
	
	// methods
	__construct: function(config, div) {
		if (!config) return;
		
		// class constructor, import config into self
		this.data = {};
		if (!config) config = {};
		for (var key in config) this[key] = config[key];
		
		this.div = div || $('#page_' + this.ID);
		assert(this.div, "Cannot find page div: page_" + this.ID);
	},
	
	onInit: function() {
		// called with the page is initialized
	},
	
	onActivate: function() {
		// called when page is activated
		return true;
	},
	
	onDeactivate: function() {
		// called when page is deactivated
		return true;
	},
	
	show: function() {
		// show page
		this.div.show();
	},
	
	hide: function() {
		this.div.hide();
	},
	
	gosub: function(anchor) {
		// go to sub-anchor (article section link)
	}
	
} ); // class Page

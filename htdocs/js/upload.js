// HTML5 Drag n' Drop File Uploader
// Works in Safari, Chrome, Firefox
// Clipboard paste support supported in Chrome only
// Author: Joseph Huckaby
// Copyright (c) 2011 Joseph Huckaby
// License: MIT

// Requires: jQuery
// Requires: blank.html to be in current server directory (safari hack)

var Uploader = {
	
	url: '', // set this to your server API endpoint
	maxFiles: 0, // max files to allow at once, 0 = infinite
	acceptTypes: '', // file mime types to accept
	inited: false, // set to true when init() is called
	
	onStart: null, // argument: array of files
	onProgress: null, // argument: float between 0.0 and 1.0
	onComplete: null, // argument: object with: code (http), data (text)
	onError: null, // argument: error message string
	
	onPasteHTML: null, // if set, will receive rich HTML when pasted (chrome only)
	onPasteText: null, // if set, will receive plain text when pasted (chrome only)
	
	setURL: function(url) { this.url = url; },
	
	setMaxFiles: function(maxFiles) {
		this.maxFiles = maxFiles;
		if (this.fileElem) {
			if (this.maxFiles != 1) this.fileElem.attr('multiple', 'multiple');
			else this.fileElem.removeAttr('multiple');
		}
	},
	
	setTypes: function(types) {
		this.acceptTypes = types;
		if (this.fileElem) {
			if (this.acceptTypes) this.fileElem.attr('accept', this.acceptTypes);
			else this.fileElem.removeAttr('accept');
		}
	},
	
	init: function(maxFiles) {
		// initialize library
		if (this.inited) return;
		this.inited = true;
		
		if (maxFiles) this.maxFiles = maxFiles;
		if (!window.jQuery) return this.fireCallback('onError', "jQuery is not loaded.", null);
		
		// setup clipboard paste support (chrome only)
		this.setupClipboard();
		
		// create file element for clicks
		this.setupFileElem();
	},
	
	setupFileElem: function() {
		// create file system for clicks
		if (this.fileElem) {
			this.fileElem.remove();
		}
		this.fileElem = $(
			'<input type="file" ' + 
			((this.maxFiles != 1) ? 'multiple="multiple"' : '') + 
			(this.acceptTypes ? ('accept="'+this.acceptTypes+'"') : '') +
			' style="display:none"/>'
		)
		.appendTo('body')
		.bind('change', function() {
			if (this.files && this.files.length) {
				Uploader.upload(this.files, Uploader.clickUrlParams, Uploader.clickUserData);
			}
		});
	},
	
	addDropTarget: function(target, urlParams, userData) {
		// public method
		// hook drag n' drop events on target dom object (defaults to document)
		// pass in anything that jQuery accepts (selector)
		if (!target) target = document;
		if (!urlParams) urlParams = null;
		if (!userData) userData = null;
		
		$(target).unbind('dragenter').bind('dragenter', function(e) {
			$(this).addClass('dragover');
			e.preventDefault();
			e.stopPropagation();
			return false;
		})
		.unbind('dragover').bind('dragover', function(e) {
			$(this).addClass('dragover');
			e.preventDefault();
			e.stopPropagation();
			return false;
		})
		.unbind('dragleave').bind('dragleave', function(e) {
			$(this).removeClass('dragover');
			e.preventDefault();
			e.stopPropagation();
			return false;
		})
		.unbind('drop').bind('drop', function(e) {
			$(this).removeClass('dragover');
			if (e.originalEvent.dataTransfer.files.length) {
				e.preventDefault();
				e.stopPropagation();
				Uploader.upload(e.originalEvent.dataTransfer.files, urlParams, userData);
				return false;
			}
		});
	},
	
	removeDropTarget: function(target) {
		// public method
		// remove all hooks on target element
		$(target).unbind('dragenter').unbind('dragover').unbind('dragleave').unbind('drop');
	},
	
	chooseFiles: function(urlParams, userData) {
		// public method
		// prompt user for files to upload
		if (!urlParams) urlParams = null;
		if (!userData) userData = null;
		
		this.clickUrlParams = urlParams;
		this.clickUserData = userData;
		
		this.fileElem[0].click();
	},
	
	upload: function(files, urlParams, userData) {
		// upload one or more files
		if (this.inProgress) return;
		if (!this.url) return;
		if (!window.FormData) return this.fireCallback('onError', "Your browser does not support drag and drop file upload.", userData);
		
		// clamp to maxFiles
		var numFiles = files.length;
		if (this.maxFiles && (files.length > this.maxFiles)) {
			numFiles = this.maxFiles;
		}
		
		// validate file types
		if (this.acceptTypes) {
			var regex = new RegExp( '^(' + this.acceptTypes.replace(/\*/g, '.+').replace(/\//g, "\\/").split(/\,\s*/).join('|') + ')$' );
			for (var idx = 0; idx < numFiles; idx++) {
				if (!files[idx].type.match(regex)) {
					return this.fireCallback('onError', "File type not accepted: " + files[idx].name + " (" + files[idx].type + ")");
				}
			}
		}
		
		this.inProgress = true;
		
		if (navigator.userAgent.match(/Safari/) && !navigator.userAgent.match(/Chrome/)) {
			// safari hack to prevent random hang
			// see: http://www.smilingsouls.net/Blog/20110413023355.html
			$.get('blank.html');
		}
		
		var http = new XMLHttpRequest();
		
		// add listener for progress (if supported)
		if (http.upload && http.upload.addEventListener) {
			http.upload.addEventListener( 'progress', function(e) {
				if (e.lengthComputable) {
					var progress = e.loaded / e.total;
					Uploader.fireCallback('onProgress', progress, e, userData);
				}
			}, false );
		} // supports progress events
		
		// construct form data object
		var form = new FormData();
		// form.append('path', '/');
		for (var idx = 0; idx < numFiles; idx++) {
			form.append('file' + Math.floor(idx + 1), files[idx]);
		}
		
		// listen for completion
		http.onreadystatechange = function() {
			if (http.readyState == 4) {
				var response = {
					code: http.status,
					data: http.responseText,
					statusLine: http.statusText
				};
				Uploader.inProgress = false;
				if ((response.code >= 200) && (response.code < 400)) {
					// http codes 200 thru 399 are generally considered "successful"
					Uploader.fireCallback('onComplete', response, userData);
				}
				else {
					// http codes out of the 200 - 399 range are generally considered errors
					Uploader.fireCallback('onError', "Error uploading files: HTTP " + response.code + " " + response.statusLine, userData);
				}
			}
		};
		
		this.fireCallback('onStart', files, userData);
		
		// construct url
		var url = '' + this.url;
		if (urlParams) {
			if (typeof(urlParams) == 'string') {
				// string, replace entire url
				url = urlParams;
			}
			else if (typeof(urlParams) == 'object') {
				// object, add key/value pairs to query string on url
				for (var key in urlParams) {
					url += (url.match(/\?/) ? '&' : '?') + key + '=' + encodeURIComponent(urlParams[key]);
				}
			}
		}
		
		// begin upload
		try {
			http.open('POST', url, true);
			http.send(form);
		}
		catch (e) {
			this.inProgress = false;
			this.fireCallback('onError', "Error uploading files: " + e.toString(), userData);
		}
		
		// recreate file element for clicks
		this.setupFileElem();
	},
	
	fireCallback: function(name) {
		// fire callback, which can be a function name, ref, or special object ref
		// inline arguments are passed verbatim to callback function
		var args = [];
		for (var idx = 1; idx < arguments.length; idx++) args.push( arguments[idx] );
		
		var callback = this[name];
		if (!callback) return;
		
		if (typeof(callback) == 'function') {
			return callback.apply(null, args);
		}
		else if (callback[0] && callback[1]) {
			var obj = callback[0];
			var func = callback[1];
			return obj[func].apply(obj, args);
		}
		else {
			return window[callback].apply(null, args);
		}
	},
	
	setupClipboard: function() {
		// initialize clipboard support (chrome only)
		$(document).bind('paste', function(event) {
			Uploader.handlePaste(event);
		} );
		
		// hidden rich textarea for capturing pasted HTML
		this.richCatch = $('<div></div>').css({
			position: 'absolute',
			left: '-9999px',
			top: '0px',
			width: '1px',
			height: '1px'
		}).attr({
			designMode: 'true',
			contentEditable: 'true'
		}).appendTo('body');
		
		// hidden plain textarea for capturing pasted text
		this.textCatch = $('<textarea></textarea>').css({
			position: 'absolute',
			left: '-9999px',
			top: '1px',
			width: '1px',
			height: '1px'
		}).appendTo('body');
	},
	
	handlePaste: function(event) {
		// handle paste operation
		event = event.originalEvent;
		
		if (event.clipboardData && event.clipboardData.items) {
			var items = event.clipboardData.items;
			var files = [];
			
			for (var idx = 0, len = items.length; idx < len; idx++) {
				var item = items[idx];
				var file = item.getAsFile();
				if (file) {
					files.push(file);
				} // got file
			} // foreach item
			
			if (files.length) {
				// upload files to server
				this.upload(files);
				event.preventDefault();
			}
			else  {
				// no files found, but maybe look for text / html
				if (this.onPasteHTML) {
					for (var idx = 0, len = items.length; idx < len; idx++) {
						var item = items[idx];
						if (item.type == 'text/html') {
							// okay, item has html, focus our hidden rich text field to catch it
							this.richCatch.focus();
							setTimeout( function() {
								var html = Uploader.richCatch.html();
								Uploader.fireCallback('onPasteHTML', html);
								Uploader.richCatch.empty().blur();
							}, 100 );
							idx = len;
						} // type is html
					} // foreach item
				} // onPasteHTML
				else if (this.onPasteText) {
					for (var idx = 0, len = items.length; idx < len; idx++) {
						var item = items[idx];
						if (item.type == 'text/plain') {
							// okay, item has text, focus our hidden textarea to catch it
							this.textCatch.focus();
							setTimeout( function() {
								var text = Uploader.textCatch.val();
								Uploader.fireCallback('onPasteText', text);
								Uploader.textCatch.val('').blur();
							}, 100 );
							idx = len;
						} // type is html
					} // foreach item
				} // onPasteText
			} // no files found
		} // event.clipboardData.items
	}
	
};

Class.create( 'GrowlManager', {
	
	lifetime: 10,
	marginRight: 0,
	marginTop: 40,
	nextId: 1,
	
	__construct: function() {
		this.growls = [];
	},
	
	growl: function(type, msg, lifetime) {
		// prevent duplicate messages
		var self = this;
		if (find_object(this.growls, { type: type, msg: msg })) return;
		
		var div = $('<div></div>')
			.addClass( 'growl_message ' + type )
			.css( 'opacity', 0.0 )
			.html( '<div class="growl_message_inner">'+msg+'</div>' );
				
		$('#d_growl_wrapper').prepend( div );
				
		var growl = {
			id: this.nextId++, 
			type: type, 
			msg: msg, 
			opacity: 0.0, 
			start: hires_time_now(), 
			div: div,
			inner_div: div.find('div.growl_message_inner'),
			lifetime: lifetime || this.lifetime,
			
			remove: function() {
				if (!this.deleted) {
					delete_object(self.growls, { id: this.id });
					this.div.remove();
					this.deleted = true;
				}
			}
		};
		
		this.growls.push(growl);
		this.handle_resize();
		
		this.animate(growl);
		
		div.click( function() {
			if (type == 'progress') return;
			delete_object(self.growls, { id: growl.id });
			div.hide( 250, function() { div.remove(); } );
			growl.deleted = true;
		} );
		
		return growl;
	},
	
	animate: function(growl) {
		// fade opacity in, out
		if (growl.deleted) return;
		
		var now = hires_time_now();
		var div = growl.div;
		
		if (now - growl.start <= 0.5) {
			// fade in
			div.css( 'opacity', tweenFrame(0.0, 1.0, (now - growl.start) * 2, 'EaseOut', 'Quadratic') );
		}
		else if (now - growl.start <= growl.lifetime) {
			// sit around looking pretty
			if (!growl._fully_opaque) {
				div.css( 'opacity', 1.0 );
				growl._fully_opaque = true;
			}
		}
		else if (now - growl.start <= growl.lifetime + 1.0) {
			// fade out
			div.css( 'opacity', tweenFrame(1.0, 0.0, (now - growl.start) - growl.lifetime, 'EaseOut', 'Quadratic') );
		}
		else {
			// die
			delete_object(this.growls, { id: growl.id });
			div.remove();
			growl.deleted = true;
			return; // stop animation timer
		}
		
		var self = this;
		setTimeout( function() { self.animate(growl); }, 33 );
	},
	
	handle_resize: function() {
		// reposition growl wrapper
		var div = $('#d_growl_wrapper');
		
		if (this.growls.length) {
			var size = getInnerWindowSize();
			div.css({
				top: '' + (10 + this.marginTop) + 'px',
				left: '' + Math.floor((size.width - 300) - this.marginRight) + 'px'
			});
		}
		else {
			div.css( 'left', '-2000px' );
		}
	},
	
	remove_all_by_type: function(type) {
		// remove all growls by type
		for (var idx = this.growls.length - 1; idx >= 0; idx--) {
			var growl = this.growls[idx];
			if ((growl.type == type) && !growl.deleted) {
				delete_object(this.growls, { id: growl.id });
				growl.div.remove();
				growl.deleted = true;
			} // yes delete
		} // foreach growl
	},
	
	remove_all: function() {
		// remove all growls
		for (var idx = this.growls.length - 1; idx >= 0; idx--) {
			var growl = this.growls[idx];
			if (!growl.deleted) {
				delete_object(this.growls, { id: growl.id });
				growl.div.remove();
				growl.deleted = true;
			} // yes delete
		} // foreach growl
	}
	
} );

window.$GR = new GrowlManager();

if (window.addEventListener) {
	window.addEventListener( "resize", function() {
		$GR.handle_resize();
	}, false );
}

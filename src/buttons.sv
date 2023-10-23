`default_nettype none

`include "defs.svh"

module ButtonFilter (
	input logic clk,
	input logic reset_n,

	// Raw button inputs from the I/O pins
	input buttons_t raw_buttons,

	// Which button should be handled next.
	// Only one (or none) of the buttons will be asserted at a time.
	output buttons_t pressed,

	input logic poll_inputs
);

	buttons_t prev_raw_buttons;
	always_ff @(posedge clk) prev_raw_buttons <= raw_buttons;

	// Buttons that were newly pressed on this clock cycle
	buttons_t new_buttons;
	assign new_buttons = raw_buttons & ~prev_raw_buttons;

	// Buttons that were pressed at some point before we last polled the input
	buttons_t buffered_buttons, next_buffered_buttons;

	always_comb begin
		pressed = 'b0;
		if (buffered_buttons.left)
			pressed.left = 1'b1;
		else if (buffered_buttons.right)
			pressed.right = 1'b1;
		else if (buffered_buttons.down)
			pressed.down = 1'b1;
		else if (buffered_buttons.cw)
			pressed.cw = 1'b1;
		else if (buffered_buttons.ccw)
			pressed.ccw = 1'b1;
		
		next_buffered_buttons = buffered_buttons;
		if (poll_inputs)
			next_buffered_buttons &= ~pressed;
		next_buffered_buttons |= new_buttons;
	end

	always_ff @(posedge clk)
		if (~reset_n)
			buffered_buttons <= 'b0;
		else
			buffered_buttons <= next_buffered_buttons;


endmodule : ButtonFilter
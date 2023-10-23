`default_nettype none

`ifndef TETRIS_DEFS_SVH
`define TETRIS_DEFS_SVH

// This chip uses VESA 800x600 @ 72 Hz VGA timings.
// http://tinyvga.com/vga-timing/800x600@72Hz.
//
// However, it only uses a 25MHz clock, so each clock cycle is 2 pixels.
localparam LINE_WIDTH = 10'd520; // 1040 / 2
localparam FRAME_HEIGHT = 10'd666;

//localparam FALL_TIME = 7'd72;
localparam FALL_TIME = 7'd36;
//localparam FALL_TIME = 7'd0;


typedef struct packed {
	logic bank;
	logic [4:0] row; 
} address_t;


typedef struct packed {
	logic left;
	logic right;
	logic down;

	logic cw;
	logic ccw;
} buttons_t;


typedef enum logic [2:0] {
	TILE_EMPTY  = 3'b000,
	TILE_BLUE   = 3'b001,
	TILE_GREEN	= 3'b010,
	TILE_CYAN   = 3'b011,
	TILE_RED	= 3'b100,
	TILE_PURPLE = 3'b101,
	TILE_YELLOW = 3'b110,
	TILE_WHITE  = 3'b111
} tile_t;

`endif
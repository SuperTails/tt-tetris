`default_nettype none

`include "defs.svh"

module CollisionChecker (
	input logic clk,
	input logic reset_n,

	input tile_t matrix_tile,
	input logic matrix_tile_valid,

	input logic falling_tile,

	output logic collision_occurred,

	input logic reset_collisions
);

	logic collision_now;
	assign collision_now = (matrix_tile_valid && matrix_tile != TILE_EMPTY && falling_tile);

	always_ff @(posedge clk)
		if (~reset_n || reset_collisions)
			collision_occurred <= 1'b0;
		else
			collision_occurred <= collision_occurred | collision_now;

endmodule : CollisionChecker


module FullRowChecker (
	input logic clk,
	input logic reset_n,

	input tile_t matrix_tile,
	input logic matrix_tile_valid,

	input logic [5:0] vert_tile,

	output logic row_is_full,
	output logic matrix_has_full_row,
	output logic [5:0] full_row_index,

	input logic next_row,
	input logic accumulate_row,
	input logic reset_matrix_full_check
);
	always_ff @(posedge clk)
		if (~reset_n || next_row)
			row_is_full <= 1'b1;
		else if (matrix_tile_valid)
			row_is_full <= row_is_full & (matrix_tile != TILE_EMPTY);
		
	always_ff @(posedge clk)
		if (~reset_n || reset_matrix_full_check)
			matrix_has_full_row <= 1'b0;
		else if (next_row && accumulate_row) begin
			matrix_has_full_row <= matrix_has_full_row | row_is_full;
			if (row_is_full)
				full_row_index <= vert_tile;
		end

endmodule : FullRowChecker
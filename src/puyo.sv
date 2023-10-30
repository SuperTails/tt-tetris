`default_nettype none

`include "defs.svh"

/*
typedef enum logic [3:0] {
	BEAN_EMPTY   = 3'b000,
	BEAN_WALL    = 3'b011,
	BEAN_BLOCKER = 3'b010,

	BEAN_RED    = 3'b100,
	BEAN_GREEN  = 3'b101,
	BEAN_BLUE   = 3'b110,
	BEAN_YELLOW = 3'b111,

} bean_t;
*/

module Lfsr(
	input logic clk,
	input logic reset_n,

	input logic enable,

	output logic [7:0] state
);
	logic [7:0] next_state;

	assign next_state = { state[6:0], (state[3] ^ state[4] ^ state[5] ^ state[7]) };

	always_ff @(posedge clk)
		if (~reset_n)
			state <= 8'd1;
		else if (enable)
			state <= next_state;

endmodule : Lfsr

parameter WIDTH = 10;

typedef enum logic [1:0] {
	SPIN_NONE = 2'b00,
	SPIN_CW   = 2'b01,
	SPIN_CCW  = 2'b10
} spin_t;

module TetrominoTable (
	input tile_t tile,

	output logic [15:0] data
);

	always_comb begin
		data = 16'b0;

		case (tile)
			TILE_EMPTY: data = 16'b0;
			// J
			TILE_BLUE: data = {
				{ 1'b0, 1'b0, 1'b0, 1'b0 },
				{ 1'b1, 1'b0, 1'b0, 1'b0 },
				{ 1'b1, 1'b1, 1'b1, 1'b0 },
				{ 1'b0, 1'b0, 1'b0, 1'b0 }
			};
			// S
			TILE_GREEN: data = {
				{ 1'b0, 1'b0, 1'b0, 1'b0 },
				{ 1'b0, 1'b1, 1'b1, 1'b0 },
				{ 1'b1, 1'b1, 1'b0, 1'b0 },
				{ 1'b0, 1'b0, 1'b0, 1'b0 }
			};
			// I
			TILE_CYAN: data = {
				{ 1'b0, 1'b0, 1'b0, 1'b0 },
				{ 1'b0, 1'b0, 1'b0, 1'b0 },
				{ 1'b1, 1'b1, 1'b1, 1'b1 },
				{ 1'b0, 1'b0, 1'b0, 1'b0 }
			};
			// Z
			TILE_RED: data = {
				{ 1'b0, 1'b0, 1'b0, 1'b0 },
				{ 1'b1, 1'b1, 1'b0, 1'b0 },
				{ 1'b0, 1'b1, 1'b1, 1'b0 },
				{ 1'b0, 1'b0, 1'b0, 1'b0 }
			};
			// T
			TILE_PURPLE: data = {
				{ 1'b0, 1'b0, 1'b0, 1'b0 },
				{ 1'b0, 1'b1, 1'b0, 1'b0 },
				{ 1'b1, 1'b1, 1'b1, 1'b0 },
				{ 1'b0, 1'b0, 1'b0, 1'b0 }
			};
			// O
			TILE_YELLOW: data = {
				{ 1'b0, 1'b0, 1'b0, 1'b0 },
				{ 1'b0, 1'b1, 1'b1, 1'b0 },
				{ 1'b0, 1'b1, 1'b1, 1'b0 },
				{ 1'b0, 1'b0, 1'b0, 1'b0 }
			};
			// L
			TILE_WHITE: data = {
				{ 1'b0, 1'b0, 1'b0, 1'b0 },
				{ 1'b0, 1'b0, 1'b1, 1'b0 },
				{ 1'b1, 1'b1, 1'b1, 1'b0 },
				{ 1'b0, 1'b0, 1'b0, 1'b0 }
			};
		endcase
	end

endmodule : TetrominoTable

module MovementBuffer (
	input logic clk,
	input logic reset_n,

	input buttons_t pressed_buttons,

	input logic frame_parity,

	input logic collision_occurred,

	// Should be asserted for 1 clock cycle per frame.
	// Will cause button inputs to be handled or collisions to be resolved.
	input logic ready_to_move,

	// When ready_to_move is high and clear is asserted, moves the piece back to the origin.
	input logic clear,

	output logic [4:0] falling_row,
	output logic [3:0] falling_col,

	output logic needs_to_lock,
	output logic game_should_end,

	output logic spin
);

	logic [6:0] fall_timer, next_fall_timer;

	logic [6:0] total_fall_time;

	logic [4:0] next_falling_row;
	logic [3:0] next_falling_col;

	// Which button was handled on the previous frame.
	// Only updated on movement frames.
	// Collision frames may "undo" this button.
	buttons_t shift, next_shift;

	logic [1:0] spin_counter, next_spin_counter;

	assign spin = (spin_counter != 2'd0);

	logic [11:0] accelerate_counter;
	logic do_accelerate;

	always_comb begin
		game_should_end = 1'b0;
		next_falling_row = falling_row;
		next_falling_col = falling_col;
		next_fall_timer = fall_timer;
		next_shift = 5'b0;
		needs_to_lock = 1'b0;

		if (spin_counter == 2'd0)
			next_spin_counter = 2'd0;
		else
			next_spin_counter = spin_counter - 2'd1;

		if (ready_to_move) begin
			if (frame_parity == 1'b0) begin
				// Movement is processed on even frames

				next_fall_timer = fall_timer - 7'b1;

				next_shift = 5'b0;
				if (fall_timer == 7'd0 || pressed_buttons.down) begin
					next_fall_timer = total_fall_time;
					next_shift.down = 1'b1;
					next_falling_row = falling_row + 5'd1;
				end else if (pressed_buttons.left) begin
					next_shift.left = 1'b1;
					next_falling_col = falling_col - 4'd1;
				end else if (pressed_buttons.right) begin
					next_shift.right = 1'b1;
					next_falling_col = falling_col + 4'd1;
				end else if (pressed_buttons.cw) begin
					next_shift.cw = 1'b1;
					next_spin_counter = 2'd1;
					// TODO: Actually spin the piece
				end else if (pressed_buttons.ccw) begin
					next_shift.ccw = 1'b1;
					next_spin_counter = 2'd3;
					// TODO: Actually spin the piece
				end
			end else begin
				// Collisions are processed on odd frames

				if (collision_occurred) begin
					if (shift.left == 1'b1) begin
						next_falling_col = falling_col + 1'd1;
					end else if (shift.right == 1'b1) begin
						next_falling_col = falling_col - 1'd1;
					end else if (shift.down == 1'b1) begin
						next_falling_row = falling_row - 1'd1;
						needs_to_lock = 1'b1;
					end else if (shift.cw == 1'b1) begin
						next_spin_counter = 2'd3;
					end else if (shift.ccw == 1'b1) begin
						next_spin_counter = 2'd1;
					end else begin
						game_should_end = 1'b1;
					end
				end
			end
		end
	end


	always_ff @(posedge clk)
		if (~reset_n || clear) begin
			falling_row <= 5'd0;
			falling_col <= 4'd4;
		end else if (ready_to_move) begin
			falling_row <= next_falling_row;
			falling_col <= next_falling_col;
			shift <= next_shift;
		end

	always_ff @(posedge clk)
		if (~reset_n)
			accelerate_counter <= 12'd0;
		else if (ready_to_move)
			accelerate_counter <= accelerate_counter + 12'd1;
	
	logic [12:0] temp;
	assign temp = accelerate_counter + 13'd1;

	assign do_accelerate = temp[12];
	always_ff @(posedge clk)
		if (~reset_n || game_should_end)
			total_fall_time <= FALL_TIME;
		else if (ready_to_move && do_accelerate && total_fall_time > 7'd6)
			total_fall_time <= total_fall_time - 7'd3; 

	always_ff @(posedge clk)
		if (~reset_n) begin
			fall_timer <= FALL_TIME;
		end else begin
			fall_timer <= next_fall_timer;
		end
		
	always_ff @(posedge clk)
		if (~reset_n)
			spin_counter <= 2'd0;
		else
			spin_counter <= next_spin_counter;
	
endmodule : MovementBuffer

module FallingBuffer (
	input logic clk,

	input tile_t new_tile,
	input logic load_new,

	input logic spin,

	// indexed by [row][column]
	output logic [15:0] data,

	output tile_t color
);

	tile_t current_tile;

	logic [15:0] next_load_data;
	TetrominoTable tetr_table(.tile(new_tile), .data(next_load_data));

	logic [15:0] next_spin_data;
	
	logic is_3x3 = (color != TILE_CYAN && color != TILE_YELLOW);

	always_comb begin
		next_spin_data = data;
		if (spin) begin
			if (is_3x3) begin
				next_spin_data[ 9] = data[ 1];
				next_spin_data[10] = data[ 5];
				next_spin_data[11] = data[ 9];

				next_spin_data[ 5] = data[ 2];
				next_spin_data[ 6] = data[ 6];
				next_spin_data[ 7] = data[10];

				next_spin_data[ 1] = data[ 3];
				next_spin_data[ 2] = data[ 7];
				next_spin_data[ 3] = data[11];
			end else begin
				next_spin_data[ 4] = data[14];
				next_spin_data[ 5] = data[10];
				next_spin_data[ 6] = data[ 6];
				next_spin_data[ 7] = data[ 2];

				next_spin_data[14] = data[ 4];
				next_spin_data[10] = data[ 5];
				next_spin_data[ 6] = data[ 6];
				next_spin_data[ 2] = data[ 7];
			end
		end
	end

	always_ff @(posedge clk) begin
		if (load_new) begin
			color <= new_tile;
			data <= next_load_data;
		end else begin
			data <= next_spin_data;
		end
	end

endmodule : FallingBuffer

module RowBuffer (
	input logic clk,

	input tile_t new_tile,
	input logic read_new,

	input logic shift_enable,

	output tile_t matrix_tile
);

	tile_t buffer [WIDTH-1:0];

	assign matrix_tile = buffer[0];

	always_ff @(posedge clk) begin
		for (int i = 0; i < WIDTH - 1; i += 1) begin
			if (shift_enable) begin
				buffer[i] <= buffer[i + 1];
			end
		end
		if (shift_enable) begin
			if (read_new)
				buffer[WIDTH-1] <= new_tile;
			else
				buffer[WIDTH-1] <= buffer[0];
		end
	end

endmodule : RowBuffer

typedef struct packed {
	logic [6:0] tile;
	logic subtile;
} horiz_pos_t;

typedef struct packed {
	logic [5:0] tile;
	logic [3:0] subtile;
} vert_pos_t;

module TileSelector (
	input logic [15:0] data,

	input logic [4:0] falling_row,
	input logic [3:0] falling_col,

	input logic [6:0] horiz_tile,
	input logic [5:0] vert_tile,

	// Asserted if the tile is at the current position, for either normal or writeback.
	output logic falling_tile_present
);

	logic [1:0] falling_row_index;
	logic [1:0] falling_col_index;
	logic falling_row_data_valid;
	logic falling_col_data_valid;
	logic falling_tile_valid;

	/* verilator lint_off WIDTH */
	assign falling_row_index = (vert_tile - falling_row + 5'd1);
	assign falling_row_data_valid = (falling_row <= vert_tile + 5'd1) && (vert_tile < falling_row + 5'd3);

	assign falling_col_index = (horiz_tile - falling_col + 4'd1);
	assign falling_col_data_valid = (falling_col <= horiz_tile + 7'd1) && (horiz_tile < falling_col + 7'd3);
	/* verilator lint_on WIDTH */

	logic tile;

	logic [3:0] row_data;
	always_comb begin
		row_data = 4'b0000;
		case (falling_row_index)
			2'b11: row_data = data[ 3: 0];
			2'b10: row_data = data[ 7: 4];
			2'b01: row_data = data[11: 8];
			2'b00: row_data = data[15:12];
		endcase

		tile = 1'b0;
		case (falling_col_index)
			2'b11: tile = row_data[0];
			2'b10: tile = row_data[1];
			2'b01: tile = row_data[2];
			2'b00: tile = row_data[3];
		endcase
	end

	assign falling_tile_present = falling_row_data_valid && falling_col_data_valid && tile;

endmodule : TileSelector

typedef enum logic [2:0] {
	FALLING,    // The player has control of the falling piece
	LOCKING,    // The falling piece hit the bottom and is being written to the matrix
	COLLAPSING, // Complete rows are being deleted
	GAME_OVER,
	RESETTING
} game_state_t;

module GameState (
	input logic clk,
	input logic reset_n,

	// Indicates the end of a frame's processing.
	// State transitions only occur once every other assertion of enable.
	input logic enable, 

	input logic needs_to_lock,  // When asserted, the falling piece has hit the bottom
	input logic game_should_end,
	input logic matrix_has_full_row, // When asserted, there was a row in the matrix that was full
	input logic any_button_pressed,

	output game_state_t state,
	output logic frame_parity
);

	game_state_t next_state;

	always_comb begin
		next_state = state;
		unique case (state)
			FALLING:    if (needs_to_lock) next_state = LOCKING; else next_state = FALLING;
			LOCKING:    next_state = COLLAPSING;
			COLLAPSING: if (matrix_has_full_row) next_state = COLLAPSING; else next_state = FALLING;
			GAME_OVER:  if (any_button_pressed) next_state = RESETTING; else next_state = GAME_OVER;
			RESETTING:  next_state = COLLAPSING;
		endcase

		if (game_should_end) begin
			next_state = GAME_OVER;
		end
	end

	always_ff @(posedge clk)
		if (~reset_n)
			frame_parity <= 1'b0;
		else if (enable)
			frame_parity <= ~frame_parity;

	always_ff @(posedge clk)
		if (~reset_n)
			state <= GAME_OVER;
		else if (enable && frame_parity)
			state <= next_state;

endmodule : GameState

module Game (
	input logic clk,
	input logic reset_n,

	input logic [ 7:0] pixel,
	input logic [ 9:0] scanline,

	output logic r, g, b,

	input  logic [2:0] mem_data_in,
	output logic [2:0] mem_data_out,
	output logic mem_start,
	output logic mem_write_enable,
	output logic mem_cont,
	output address_t mem_addr,

	input buttons_t pressed_buttons,
	input logic raw_buttons_changed,
	output logic poll_inputs
);

	horiz_pos_t horiz;
	assign horiz = pixel;

	vert_pos_t vert;
	assign vert = scanline;

	logic frame_end;
	assign frame_end = (pixel == 8'd129 && scanline == 10'd665);

	logic enable_state_transition;
	logic needs_to_lock, game_should_end;

	game_state_t state;
	logic frame_parity;

	assign enable_state_transition = (pixel == 8'd0 && scanline == 10'd665); // TODO: ??

	GameState game_state(
		.clk, .reset_n,
		.enable(enable_state_transition), .needs_to_lock, .game_should_end, .matrix_has_full_row,
		.any_button_pressed(| pressed_buttons),
		.state, .frame_parity
	);

	logic [7:0] lfsr_state;

	logic [3:0] pauser;
	always_ff @(posedge clk)
		if (raw_buttons_changed)
			pauser <= pixel[3:0];
		else if (pauser != 4'b0000)
			pauser <= pauser - 4'd1;
	Lfsr lfsr(.clk, .reset_n, .enable(pauser != 4'd0), .state(lfsr_state));

	logic primary_buffer;
	assign primary_buffer = frame_parity;

	tile_t new_falling_tile_kind;
	logic load_new_falling_tile;
	logic spin;

	logic [2:0] raw_new_falling_tile_kind;
	always_comb begin
		if (lfsr_state[2:0] != 3'd0)
			raw_new_falling_tile_kind = lfsr_state[2:0];
		else if (lfsr_state[5:3] != 3'd0)
			raw_new_falling_tile_kind = lfsr_state[5:3];
		else
			raw_new_falling_tile_kind = 3'd1;
	end

	`ifdef __ICARUS__
	assign new_falling_tile_kind = tile_t'(raw_new_falling_tile_kind);
	`elsif verilator
	assign new_falling_tile_kind = tile_t'(raw_new_falling_tile_kind);
	`else
	assign new_falling_tile_kind = (raw_new_falling_tile_kind);
	`endif

	tile_t next_new_falling_tile;

	always_ff @(posedge clk)
		if (~reset_n)
			next_new_falling_tile <= TILE_PURPLE;
		else if (state == COLLAPSING && !matrix_has_full_row && update_step && frame_parity == 1'b1)
			next_new_falling_tile <= new_falling_tile_kind;

	assign load_new_falling_tile = (state == COLLAPSING) && !matrix_has_full_row && update_step && frame_parity == 1'b1;

	logic [15:0] falling_data;
	tile_t falling_color;

	FallingBuffer falling_buffer(
		.clk, .new_tile(next_new_falling_tile), .load_new(load_new_falling_tile), .spin,
		.data(falling_data), .color(falling_color)
	);

	logic raw_falling_tile_present;
	logic falling_tile_present;

	assign falling_tile_present = raw_falling_tile_present && (state != GAME_OVER && state != RESETTING);

	logic [3:0] falling_col;
	logic [4:0] falling_row;

	logic collision_occurred, ready_to_move, movement_clear;

	assign movement_clear = (state == COLLAPSING);

	MovementBuffer movement_buffer(
		.clk, .reset_n,

		.pressed_buttons, .frame_parity(primary_buffer), .collision_occurred,

		.ready_to_move, .needs_to_lock, .game_should_end, .clear(movement_clear),

		.falling_row, .falling_col,

		.spin
	);

	// Figure out which tile on the falling block
	// corresponds to the current position.

	TileSelector tile_sel(
		.data(falling_data),
		.falling_row, .falling_col,
		.horiz_tile(horiz.tile), .vert_tile(vert.tile),
		.falling_tile_present(raw_falling_tile_present)
	);

	// check for full row:

	logic matrix_tile_valid;
	assign matrix_tile_valid = (7'd1 <= horiz.tile && horiz.tile < 7'd11);

	logic row_shift_coarse_enable;
	assign row_shift_coarse_enable = (
		vert.tile < 6'd21 && (matrix_tile_valid || (7'd17 <= horiz.tile && horiz.tile < 7'd27))
	);

	logic row_shift_enable;
	assign row_shift_enable = (horiz.subtile == 1'h1 && row_shift_coarse_enable);

	tile_t matrix_tile;

	/* Check for intersection between the falling block and the matrix */

	// collision_occurred will be ready at vert.tile == 6'd22

	logic update_step;
	assign update_step = enable_state_transition;

	// TODO:
	assign ready_to_move = update_step && (state == FALLING);
	assign poll_inputs = (update_step && ~frame_parity);

	logic reset_all_collision_checks;
	assign reset_all_collision_checks = update_step;

	logic on_matrix_boundary;
	assign on_matrix_boundary = (horiz.tile == 7'd0 || horiz.tile == 7'd11 || vert.tile == 6'd21);

	CollisionChecker collision_checker(
		.clk, .reset_n,
		.matrix_tile, .matrix_tile_valid(matrix_tile_valid | on_matrix_boundary),
		.falling_tile(falling_tile_present),
		.collision_occurred,
		.reset_collisions(reset_all_collision_checks)
	);

	tile_t written_tile;

	always_comb begin
		written_tile = matrix_tile;
		if (state == LOCKING && falling_tile_present)
			written_tile = falling_color;
	end

	logic row_is_full, matrix_has_full_row;
	logic [5:0] full_row_index;

	FullRowChecker full_row_checker(
		.clk, .reset_n,
		.matrix_tile, .matrix_tile_valid,
		.row_is_full, .matrix_has_full_row, .full_row_index,
		.vert_tile(vert.tile),
		.next_row(pixel == 8'd129),
		.accumulate_row((vert.tile < 6'd21) && frame_parity == 1'b0),
		.reset_matrix_full_check(reset_all_collision_checks && frame_parity == 1'b1)
	);

	// If asserted, rows will be written shifted downwards by 1 tile.
	logic write_downwards;
	logic write_disable;

	always_comb begin
		write_downwards = 1'b0;
		write_disable = 1'b0;

		if (state == COLLAPSING && frame_parity == 1'b1 && matrix_has_full_row && vert.tile < full_row_index) begin
			write_downwards = 1'b1;
		end

		if (state == COLLAPSING && frame_parity == 1'b1 && matrix_has_full_row && vert.tile == full_row_index) begin
			write_disable = 1'b1;
		end
	end

	/* verilator lint_off WIDTH */
	assign mem_addr.bank = primary_buffer ^ mem_write_enable;
	assign mem_addr.row = vert.tile - (mem_write_enable & ~write_downwards);
	/* verilator lint_on WIDTH */

	assign mem_write_enable = ~pixel[5];
	// 0 <= pixel < 130
	// pixel[4:0] == 5'b0 implies pixel % 32 == 0
	// pixel[6] != 1'b1   implies pixel < 64 (or pixel is really big?)
	assign mem_start = (pixel[4:1] == 4'b0 && pixel[7:6] == 2'b00);
	assign mem_cont = row_shift_coarse_enable && ~(mem_write_enable & write_disable);

	assign mem_data_out = (state == RESETTING) ? 3'b0 : written_tile;
	//assign mem_data_out = { 1'b0, written_tile };
	//assign mem_data_out = { 1'b0, scanline[6] ? TILE_RED : TILE_BLUE };

	tile_t new_tile;
	//assign new_tile = (pixel[5:3] + tile_row[2:0]);
	`ifdef __ICARUS__
	assign new_tile = tile_t'(mem_data_in[2:0]);
	`elsif verilator
	assign new_tile = tile_t'(mem_data_in[2:0]);
	`else
	assign new_tile = (mem_data_in[2:0]);
	`endif

	logic read_new;
	assign read_new = (vert.subtile == 4'b1111) && pixel[5];

	tile_t raw_matrix_tile;

	RowBuffer row_buffer(.clk, .new_tile, .read_new, .shift_enable(row_shift_enable), .matrix_tile(raw_matrix_tile));

	`ifdef __ICARUS__
	assign matrix_tile = tile_t'(on_matrix_boundary ? TILE_WHITE : raw_matrix_tile);
	`else
	assign matrix_tile = (on_matrix_boundary ? TILE_WHITE : raw_matrix_tile);
	`endif

	/* Output matrix and falling colors */

	logic [15:0] next_piece_data;
	TetrominoTable next_tetr_table(.tile(next_new_falling_tile), .data(next_piece_data));

	logic [2:0] displayed_tile;
	always_comb
		if (horiz.tile < 7'd12 && vert.tile < 6'd22)
			displayed_tile = (falling_tile_present ? falling_color : matrix_tile);
		else if ((state != GAME_OVER) && 7'd14 <= horiz.tile && horiz.tile < 7'd18 && 6'd4 <= vert.tile && vert.tile < 6'd8) begin
			displayed_tile = next_piece_data[(((vert.tile - 6'd4) << 2) | (horiz.tile - 7'd14)) & 4'hF] ? next_new_falling_tile : 3'b000;
		end else begin
			displayed_tile = 3'b000;
		end

	logic text_filled;
	GameOverText game_over_text(.clk, .filled(text_filled), .horiz, .vert);

	always_comb begin
		r = displayed_tile[2];
		g = displayed_tile[1];
		b = displayed_tile[0];

		if (state == GAME_OVER && text_filled) begin
			r = 1'b1;
			g = 1'b0;
			b = 1'b0;
		end


		/*r = mem_data_in[2];
		g = mem_data_in[1];
		b = mem_data_in[0];*/

		/*if (pixel == 8'd2 || pixel == 8'd22) begin
			r = 1'b1;
		end*/

		/*if (pixel <= 8'd1) begin
			r = state[0];
			g = state[1];
			b = 1'b0;
		end*/

		/*if (pixel > 10'd96) begin
			r = 1'b0;
			g = matrix_has_full_row && (frame_parity == 1'b0);
			b = matrix_has_full_row && (frame_parity == 1'b1);
		end*/
	end

	/*assign r = (pixel == 10'd8 || pixel == 10'd88) ? 1'b1 : (displayed_tile[2]);
	assign g = displayed_tile[1];
	assign b = displayed_tile[0];*/

endmodule : Game

module GameOverText(
	input logic clk,

	output logic filled,

	input horiz_pos_t horiz,
	input vert_pos_t vert);

	logic [351:0] data = {
		32'b111110011111001000100111110,
		32'b100000010001001101100100000,
		32'b101110011111001010100111000,
		32'b100010010001001000100100000,
		32'b111110010001001000100111110,
		32'b000000000000000000000000000,
		32'b111110010001001111100111110,
		32'b100010010001001000000100010,
		32'b100010001010001110000111110,
		32'b100010001010001000000100100,
		32'b111110000100001111100100010
	};

	always_comb begin
		if (6'd3 <= vert.tile && vert.tile < 6'd14 && 7'd1 <= horiz.tile && horiz.tile < 7'd28) begin
			filled = data[((9'd13 - vert.tile) << 5) | (7'd27 - horiz.tile)];
		end else begin
			filled = 1'b0;
		end
	end


endmodule : GameOverText
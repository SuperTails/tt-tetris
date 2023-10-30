`default_nettype none

`include "defs.svh"

module Memory (
	input logic sck,

	input logic start,
	input logic write_enable,
	input logic cont,
	input address_t addr,

	input  logic [2:0] data_in,
	output logic [2:0] data_out
);

	logic [2:0] data[64][10];

	logic writing;
	logic [5:0] addr_hi;
	logic [3:0] addr_lo;

	/*logic addr_hi_valid;
	assign addr_hi_valid = !((6'd20 <= addr_hi && addr_hi < 6'd32) || (6'd52 <= addr_hi));*/

	always_ff @(posedge sck) begin
		if (start) begin
			addr_hi <= addr;
			addr_lo <= 4'b0;
			writing <= write_enable;
		end else if (cont) begin
			if (writing /*&& addr_hi_valid*/)
				data[addr_hi][addr_lo] <= data_in;
			addr_lo <= addr_lo + 4'b1;
		end
	end

	assign data_out = data[addr_hi][addr_lo];
	//assign data_out = (addr_hi == 6'd19) ? 3'b101 : data[addr_hi][addr_lo];
	/*always_comb
		if (!addr_hi_valid)
			data_out = 3'b0;
		else
			data_out = data[addr_hi][addr_lo];*/

endmodule : Memory

// led[0] -> G14 -> IOR_141 -> B21
// led[1] -> F14 -> IOR_140 -> B20

module ClockDivider(
	input logic clk100,
	output logic clk6_25,
);

	logic clk50;
	always_ff @(posedge clk100)
		clk50 <= ~clk50;
	
	logic clk25;
	always_ff @(posedge clk50)
		clk25 <= ~clk25;
	
	logic clk12_5;
	always_ff @(posedge clk25)
		clk12_5 <= ~clk12_5;

	always_ff @(posedge clk12_5)
		clk6_25 <= ~clk6_25;


endmodule : ClockDivider

module FpgaInterface
	(
		input logic clk100,
		input logic reset_n,

		output logic [7:0] base_led,

		output logic [9:0] led,

		inout logic [5:0] mem_addr_data,

		output logic mem_clk,

		input logic [23:0] sw,

		input logic [4:0] btn,

		output logic [3:0] display_sel,
		output logic [7:0] display
	);

	logic clk6_25;
	ClockDivider clock_divider(.clk100, .clk6_25);
	
	logic r_signal, g_signal, b_signal;
	logic hsync, vsync;

	logic [2:0] mem_data_in;
	logic [2:0] mem_data_out;
	logic mem_start;
	logic mem_write_enable;
	logic mem_cont;
	address_t mem_addr;

	logic [7:0] uio_in;
	logic [7:0] uio_out;
	logic [7:0] uio_oe;

	tt_um_supertails_tetris tetris(
		.ui_in({ 3'b000, sw[4:0] }),
		.uo_out({
			mem_cont, mem_write_enable, mem_start,
			b_signal, g_signal, r_signal,
			vsync, hsync }),
		.uio_in,	// World -> Tetris
		.uio_out,	// Tetris -> World
		.uio_oe,
		.ena(1'b1),
		.clk(clk6_25),
		.rst_n(reset_n),
	);

	assign led[9] = mem_start; // C9 -> IOT_190 -> B8
	assign led[8] = mem_cont; // C10 -> IOT_186 -> B9
	assign led[7] = mem_write_enable; // A12 -> IOT_170 -> B11

	genvar i;
	for (i = 0; i < 6; i += 1) begin
		SB_IO #(
			.PIN_TYPE(6'b1010_01)	// PIN_OUTPUT_TRISTATE, PIN_INPUT
		) io_pin (
			.PACKAGE_PIN(mem_addr_data[i]),
			.INPUT_CLK(clk6_25),
			.OUTPUT_CLK(clk6_25),
			.OUTPUT_ENABLE(uio_oe[i]),
			.D_OUT_0(uio_out[i]),
			.D_IN_0(uio_in[i])
		);
	end

	// mem_addr_data:
	// 0: A11 -> IOT_179 -> B6
	// 1: A10 -> IOT_181 -> B5
	// 2: A7  -> IOT_197 -> B3
	// 3: A6  -> IOT_198 -> B2
	// 4: A4  -> IOT_219 -> A24
	// 5: A3  -> IOT_222 -> A23

	// (unused)
	// 6: A2  -> IOT_223 -> A21

	assign mem_clk = uio_out[7] & uio_oe[7];

	assign led[0] = hsync; // B21
	assign led[1] = vsync; // B20

	assign led[2] = r_signal; // B18
	assign led[3] = g_signal; // B17
	assign led[5] = b_signal; // B14

	assign led[6] = clk6_25; // B12

	// Button mappings:
	// sw[0] -> G12 -> IOR_129 -> B30
	// sw[1] -> F12 -> IOR_137 -> B31
	// sw[2] -> F11 -> IOR_144 -> B33
	// sw[3] -> E11 -> IOR_146 -> B34
	// sw[4] -> D12 -> IOR_160 -> B36

endmodule : FpgaInterface

module Debouncer #(BITS=13) (
	input logic clk,

	input logic signal,

	output logic debounced
);

	logic [BITS-1:0] ctr, next_ctr;

	assign debounced = (ctr == { BITS { 1'b1 }});

	always_comb begin
		next_ctr = 'b0;
		if (signal)
			if (ctr == { BITS { 1'b1 } })
				next_ctr = ctr;
			else
				next_ctr = ctr + 'b1;
	end

	always_ff @(posedge clk)
		ctr <= next_ctr;

endmodule : Debouncer

module tt_um_supertails_tetris
	(
		input  wire [7:0] ui_in,    // Dedicated inputs - connected to the input switches
		output wire [7:0] uo_out,   // Dedicated outputs - connected to the 7 segment display
		input  wire [7:0] uio_in,   // IOs: Bidirectional Input path
		output wire [7:0] uio_out,  // IOs: Bidirectional Output path
		output wire [7:0] uio_oe,   // IOs: Bidirectional Enable path (active high: 0=input, 1=output)
		input  wire       ena,      // will go high when the design is enabled
		input  wire       clk,      // clock
		input  wire       rst_n     // reset_n - low to reset
	);

	logic r_signal, g_signal, b_signal;
	logic hsync, vsync;
	buttons_t buttons, buttons_q0, buttons_q1;

	buttons_t buttons_db;

	Debouncer dl(.clk(clk), .signal(buttons_q1.left ), .debounced(buttons_db.left ));
	Debouncer dr(.clk(clk), .signal(buttons_q1.right), .debounced(buttons_db.right));
	Debouncer dd(.clk(clk), .signal(buttons_q1.down ), .debounced(buttons_db.down ));
	Debouncer dw(.clk(clk), .signal(buttons_q1.cw   ), .debounced(buttons_db.cw   ));
	Debouncer dc(.clk(clk), .signal(buttons_q1.ccw  ), .debounced(buttons_db.ccw  ));

	logic [2:0] mem_data_in;
	logic [2:0] mem_data_out;
	logic mem_start;
	logic mem_write_enable;
	logic mem_cont;
	address_t mem_addr;

	logic pixel_0;
	logic mem_clk;

	assign mem_clk = ~pixel_0;

	Tetris tetris(
		.clk6_25(clk), .reset_n(rst_n),

		.r_signal, .g_signal, .b_signal, .hsync, .vsync, .pixel_0,

		.buttons(buttons_db),

		.mem_data_in, .mem_data_out, .mem_start, .mem_write_enable, .mem_cont, .mem_addr
	);

	assign uo_out[0] = hsync;
	assign uo_out[1] = vsync;

	assign uo_out[2] = r_signal;
	assign uo_out[3] = g_signal;
	assign uo_out[4] = b_signal;

	assign uo_out[5] = mem_start;
	assign uo_out[6] = mem_write_enable;
	assign uo_out[7] = mem_cont;

	logic writing;
	always_ff @(posedge clk)
		if (mem_start)
			writing <= mem_write_enable;
		
	assign mem_data_in = uio_in[2:0];
	assign uio_out[7] = mem_clk;
	assign uio_out[6] = 1'b0;
	assign uio_out[5:0] = mem_start ? mem_addr : { 2'b0, mem_data_out };

	assign uio_oe = { 2'b10, (writing || mem_start) ? 6'b111111 : 6'b000000 };

	always_comb begin
		buttons.left  = ui_in[0];
		buttons.right = ui_in[1];
		buttons.down  = ui_in[2];
		buttons.cw    = ui_in[3];
		buttons.ccw   = ui_in[4];
	end

	always_ff @(posedge clk) begin
		buttons_q0 <= buttons;
		buttons_q1 <= buttons_q0;
	end

endmodule : tt_um_supertails_tetris

module Tetris 
	(
		input logic clk6_25,
		input logic reset_n,

		output logic r_signal,
		output logic g_signal,
		output logic b_signal,
		output logic hsync,
		output logic vsync,

		input buttons_t buttons,

		input  logic [2:0] mem_data_in,
		output logic [2:0] mem_data_out,
		output logic mem_start,
		output logic mem_write_enable,
		output logic mem_cont,
		output address_t mem_addr,

		output logic pixel_0
	);


	logic [9:0] scanline;
	//logic [10:0] pixel;
	logic [7:0] pixel;

	assign pixel_0 = pixel[0];

	logic porch;

	logic r, g, b;

	VgaGenerator vga_generator(
		.clk(clk6_25), .reset_n, .scanline, .pixel,
		.r, .g, .b,
		.hsync, .vsync, .r_signal, .g_signal, .b_signal);
	
	/*logic [2:0] mem_data_in;
	logic [2:0] mem_data_out;
	logic mem_start;
	logic mem_write_enable;
	logic mem_cont;
	address_t mem_addr;*/

	buttons_t pressed_buttons;
	logic poll_inputs;

	ButtonFilter button_filter(
		.clk(clk6_25), .reset_n,
		.raw_buttons(buttons),
		.pressed(pressed_buttons),
		.poll_inputs
	);

	buttons_t prev_buttons;
	always_ff @(posedge clk6_25)
		prev_buttons <= buttons;
	logic raw_buttons_changed = (buttons != prev_buttons);

	Game game(
		.clk(clk6_25), .reset_n,
		.pixel, .scanline, .r, .g, .b,
		.mem_data_in, .mem_data_out, .mem_start, .mem_write_enable, .mem_cont, .mem_addr,
		
		.pressed_buttons, .raw_buttons_changed, .poll_inputs);
	
	/*Memory memory(
		.sck(clk6_25),
		.start(mem_start),
		.write_enable(mem_write_enable),
		.cont(mem_cont),
		.addr(mem_addr),
		.data_in(mem_data_out),
		.data_out(mem_data_in)
	);*/

	//assign r = (scanline[1:0] == 2'b00);
	//assign g = (scanline[1:0] == 2'b01);
	//assign b = (scanline[1:0] == 2'b10);

	`ifndef SYNTHESIS
		initial begin
			$dumpfile("_mm_out.vcd");
			$dumpvars;
		end
	`endif


endmodule : Tetris

module VgaGenerator
	(
		input logic clk, reset_n,

		output logic [ 9:0] scanline,
		//output logic [10:0] pixel,
		output logic [ 7:0] pixel,

		output logic hsync,
		output logic vsync,

		input logic r,
		input logic g,
		input logic b,

		output logic r_signal,
		output logic g_signal,
		output logic b_signal
	);

	//logic [10:0] pixel;

	assign r_signal = r & ~porch;
	assign g_signal = g & ~porch;
	assign b_signal = b & ~porch;

	logic porch;

	always_ff @(posedge clk)
		if (~reset_n) begin
			scanline <= '0;
			pixel <= '0;
		end else begin
			//if (pixel == 11'd1039) begin
			if (pixel == 8'd129) begin
				pixel <= '0;
				if (scanline == 10'd665) begin
					scanline <= '0;
				end else begin
					scanline <= scanline + 10'd1;
				end
			end else begin
				//pixel <= pixel + 11'd1;
				pixel <= pixel + 8'd1;
			end
		end
	
	assign vsync = (scanline < 10'd637 || 10'd643 <= scanline);
	//assign hsync = (pixel < 11'd856 || 11'd976 <= pixel);
	assign hsync = (pixel < 8'd107 || 8'd122 <= pixel);

	logic hporch, vporch;

	assign vporch = (10'd600 <= scanline);
	//assign hporch = (11'd800 <= pixel);
	assign hporch = (8'd100 <= pixel);

	assign porch = hporch | vporch;

endmodule : VgaGenerator
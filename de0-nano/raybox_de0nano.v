`default_nettype none
`timescale 1ns / 1ps

// Wrapper for raybox module, targeting DE0-Nano board:
module raybox_de0nano(
	input 					CLOCK_50,	// Onboard 50MHz clock
	output	[7:0]		LED,			// 8 onboard LEDs
	input		[1:0]		KEY,			// 2 onboard pushbuttons
	input		[3:0]		SW,				// 4 onboard DIP switches
	inout		[33:0]	gpio1,		// GPIO1
	input		[1:0]		gpio1_IN	// GPIO1 input-only pins
);

//=======================================================
//  PARAMETER declarations
//=======================================================


//=======================================================
//  REG/WIRE declarations
//=======================================================

	// K4..K1 external buttons.
	wire [4:1] K = {gpio1[23], gpio1[21], gpio1[19], gpio1[17]};
	//assign K = 4'bZ; // Hi-Z because they're inputs.
	wire reset = !KEY[0]; // This button is normally pulled high, but our design needs an active-high reset.
    wire [1:0] r;
    wire [1:0] g;
    wire [1:0] b;
    wire hsync;
    wire vsync;
	wire speaker;

//=======================================================
//  Structural coding
//=======================================================
    assign gpio1[0] = r[1]; // Actual hardware is only using MSB of each colour channel.
    assign gpio1[1] = g[1];
    assign gpio1[3] = b[1];
    assign gpio1[5] = hsync;
    assign gpio1[7] = vsync;
	assign LED[7] = speaker;		// Visualise speaker on LED7.
	assign gpio1[9] = speaker;	// Also sound the speaker on GPIO_19.

	//SMELL: This is a bad way to do clock dividing.
	// ...i.e. if we can't make it a global clock, then instead use it as a clock enable.
    // Otherwise, can we use the built-in FPGA clock divider?
	reg clock_25;
	always @(posedge CLOCK_50) clock_25 <= ~clock_25;
	
	raybox raybox(
		.clk(clock_25),
		.reset(reset),
		.hsync(hsync),
		.vsync(vsync),
		.red(r),
		.green(g),
		.blue(b),
		.speaker(speaker)
	);

endmodule
`default_nettype none
`timescale 1ns / 1ps

`include "raybox_target_defs.v"


// Wrapper for raybox module, targeting DE0-Nano board:
module raybox_de0nano(
  input           CLOCK_50, // Onboard 50MHz clock
  output  [7:0]   LED,      // 8 onboard LEDs
  input   [1:0]   KEY,      // 2 onboard pushbuttons
  input   [3:0]   SW,       // 4 onboard DIP switches
  inout   [33:0]  gpio1,    // GPIO1
  input   [1:0]   gpio1_IN  // GPIO1 input-only pins
);

//=======================================================
//  PARAMETER declarations
//=======================================================


//=======================================================
//  REG/WIRE declarations
//=======================================================

  // K4..K1 external buttons (K4 is top, K1 is bottom):
  wire [4:1] K = {gpio1[23], gpio1[21], gpio1[19], gpio1[17]};
  //assign K = 4'bZ; // Hi-Z because they're inputs.
  // These buttons are normally pulled high, but our design needs active-high:
  wire reset    = !KEY[0];
  wire show_map = !KEY[1];
  wire [1:0] r;
  wire [1:0] g;
  wire [1:0] b;
  wire hsync;
  wire vsync;
  wire speaker;

  // The following 3 are used on my FPGA hardware implementation to implement simple
  // temporal dithering, i.e. use a 2x2 ordered dither to get 4 tone levels out of each R,G,B channel,
  // but mirror that ordered dither on alternate frames to effectively fake extra tonal resolution.
  // This is only necessary because I haven't implemented a proper DAC yet.
  wire px0; // Bit 0 of VGA pixel X position.
  wire py0; // Bit 0 of VGA pixel Y position.
  wire fr0; // Bit 0 of VGA frame number.

//=======================================================
//  Structural coding
//=======================================================

  // Because actual hardware is only using MSB of each colour channel, attenuate that output
  // (i.e. mask it out for some pixels) to create a pattern dither:
  wire alt = fr0;
  wire dither_hi = (px0^py0)^alt;
  wire dither_lo = (px0^alt)&(py0^alt);
  assign gpio1[0] = (r==2'b11) ? 1'b1 : (r==2'b10) ? dither_hi : (r==2'b01) ? dither_lo : 1'b0;
  assign gpio1[1] = (g==2'b11) ? 1'b1 : (g==2'b10) ? dither_hi : (g==2'b01) ? dither_lo : 1'b0;
  assign gpio1[3] = (b==2'b11) ? 1'b1 : (b==2'b10) ? dither_hi : (b==2'b01) ? dither_lo : 1'b0;
    
  assign gpio1[5] = hsync;
  assign gpio1[7] = vsync;
  assign gpio1[9] = speaker;    // Also sound the speaker on GPIO_19.
  assign LED[7] = speaker;      // Visualise speaker on LED7.
  assign LED[6:0] = {7{1'bz}};  // Leave these open (Hi-Z).
  
  // Check for debug buttons: Because we have limited input buttons wired up,
  // holding down a pair of opposing directional buttons will instead treat either
  // of the remaining buttons as a "debug" input:
  wire debug1 = !K[2] && !K[3]; // Two middle buttons are held, so we're in debugA/B mode.
  wire debug2 = !K[1] && !K[4]; // Two outer buttons are held, so we're in debugC/D mode.
//  wire debugA = debug1 && !K[4];
//  wire debugB = debug1 && !K[1];
//  wire debugC = debug2 && !K[2];
//  wire debugD = debug2 && !K[3];

  wire moveL = !debug1 && !debug2 && !K[3];
  wire moveR = !debug1 && !debug2 && !K[2];
  wire moveF = !debug1 && !debug2 && !K[4];
  wire moveB = !debug1 && !debug2 && !K[1];
  
  //SMELL: This is a bad way to do clock dividing.
  // ...i.e. if we can't make it a global clock, then instead use it as a clock enable.
  // Otherwise, can we use the built-in FPGA clock divider?
  reg clock_25;
  always @(posedge CLOCK_50) clock_25 <= ~clock_25;
  
  raybox raybox(
    .clk      (clock_25),
    .reset    (reset),
    .show_map (show_map),
    
    .moveL    (moveL),
    .moveR    (moveR),
    .moveF    (moveF),
    .moveB    (moveB),
    
//    .debugA   (debugA),
//    .debugB   (debugB),
//    .debugC   (debugC),
//    .debugD   (debugD),
    
    .write_new_position(0),
//    .new_playerX(0),
//    .new_playerY(0),
//    .new_facingX(0),
//    .new_facingY(0),
//    .new_vplaneX(0),
//    .new_vplaneY(0),
    
    .hsync    (hsync),
    .vsync    (vsync),
    .red      (r),
    .green    (g),
    .blue     (b),
    .px0      (px0),
    .py0      (py0),
    .fr0      (fr0),
//    .speaker  (speaker),

    .show_debug(1)
  );
  
  assign speaker = 1'bz;

endmodule
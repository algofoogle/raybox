// SPDX-FileCopyrightText: 2023 Anton Maurovic <anton@maurovic.com>
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//      http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
// SPDX-License-Identifier: Apache-2.0


`default_nettype none
`timescale 1ns / 1ps

`define DUMMY_MAP       // If defined, map is made by combo logic instead of ROM.
`define ENABLE_DEBUG    // If defined, extra logic exists that reacts to the `show_debug` signal.

`include "fixed_point_params.v"

module raybox(
    input           clk,
    input           reset,
    input           show_map,           // Button to control whether we show the map overlay.
    input           show_debug,
    
    input           moveL,
    input           moveR,
    input           moveF,
    input           moveB,

    input           write_new_position, // If true, use the `new_*` values to overwrite the design's registers.
    input   `F      new_playerX,
    input   `F      new_playerY,
    input   `F      new_facingX,
    input   `F      new_facingY,
    input   `F      new_vplaneX,
    input   `F      new_vplaneY,
    
    output  [1:0]   red,   // Each of R, G, and B are 2bpp, for a total of 64 possible colours.
    output  [1:0]   green,
    output  [1:0]   blue,
    output          hsync,
    output          vsync,
    output  [9:0]   px,   // Current pixel x.
    output  [9:0]   py,   // Current pixel y.
    output  [10:0]  frame_num,
    output          speaker
);

    //localparam DEBUG_X          = 300;  // Column to highlight.
    localparam DEBUG_SCALE          = 3;                        // Power of 2 scaling for debug overlay.

    localparam SCREEN_HEIGHT        = 480;
    localparam HALF_HEIGHT          = SCREEN_HEIGHT>>1;
    localparam MAP_SCALE            = 4;                        // Power of 2 scaling for map overlay size.
    localparam MAP_OVERLAY_SIZE     = (1<<(MAP_SCALE))*16+1;    // Total size of map overlay. //NOTE: *16 is map width/height in cells.

/* verilator lint_off REALCVT */
    localparam `F facingXstart      = `realF( 0.0); // ...
    localparam `F facingYstart      = `realF(-1.0); // ...Player is facing (0,-1); upwards on map.
    localparam `F vplaneXstart      = `realF( 0.5); // Viewplane dir is (0.5,0); right...
    localparam `F vplaneYstart      = `realF( 0.0); // ...makes FOV 45deg. Too small, but makes maths easy for now.

`ifdef DUMMY_MAP
    localparam `I playerXstartcell  = 1;
    localparam `I playerYstartcell  = 13;
`else
    localparam `I playerXstartcell  = 8;
    localparam `I playerYstartcell  = 14;
`endif
    // Player's full start position is in the middle of a cell:
    localparam playerXstartoffset   = 0.50;    // Should normally be 0.5, but for debugging might need to be other values.
    localparam playerYstartoffset   = 0.50;
    localparam `F playerXstart      = `realF(playerXstartcell+playerXstartoffset);
    localparam `F playerYstart      = `realF(playerYstartcell+playerYstartoffset);

    localparam `F moveQuantum       = `realF(0.001953125);                      //0b0.0000_0000_1000 or    8 or  0.4cm => ~0.23m/s =>  0.8km/hr
    localparam `F playerCrawl       =  4*moveQuantum;   //`realF(0.007812500);  //0b0.0000_0010_0000 or  4*8 or ~1.5cm => ~0.94m/s =>  3.3km/hr
    localparam `F playerWalk        = 10*moveQuantum;   //`realF(0.019531250);  //0b0.0000_0101_0000 or 10*8 or ~4cm   => ~2.34m/s =>  8.4km/hr
    localparam `F playerRun         = 18*moveQuantum;   //`realF(0.035156250);  //0b0.0000_1001_0000 or 18*8 or ~7cm   => ~4.22m/s => 15.2km/hr

    localparam `F playerMove        = playerWalk;
    // Note that for Q12.12, it seems playerMove needs to be a multiple of 8 (i.e. 'b0.000000001000)
    // in order to be reliable (although this goes out the window when fine-grained rotations are involved).
    // This should be OK: It's a very small movement, equivalent to maybe 5mm in the real world?
    // My preference for player speeds per frame at 60fps:
    // -  32  (4*8) for slow walking speed
    // -  80 (10*8) regular walking speed
    // - 144 (18*8) for running.

    initial begin
        $display("Raybox params: Fixed-point precision is Q%0d.%0d (%0d-bit)", `Qm, `Qn, `Qmn);
        $display("Raybox params: player(X,Y)start=%X,%X", playerXstart, playerYstart);
        $display("Raybox params: facing(X,Y)start=%X,%X", facingXstart, facingYstart);
        $display("Raybox params: vplane(X,Y)start=%X,%X", vplaneXstart, vplaneYstart);
        $display("Raybox params: playerMove=%X", playerMove);
    end

/* verilator lint_on REALCVT */

    reg `F playerX /* verilator public */;
    reg `F playerY /* verilator public */;
    reg `F facingX /* verilator public */;     // Heading is the vector of the direction the player is facing.
    reg `F facingY /* verilator public */;
    reg `F vplaneX /* verilator public */;     // Viewplane vector (typically 'facing' rotated clockwise by 90deg and then scaled).
    reg `F vplaneY /* verilator public */;     // (which could also be expressed as vx=-fy, vy=fx, then scaled).


    assign speaker = 0; // Speaker is unused for now.

    // Outputs from vga_sync:
    wire [9:0]  h;          // Horizontal scan position (i.e. X pixel).
    wire [9:0]  v;          // Vertical scan position (Y).
    wire        visible;    // Are we in the visible region of the screen?
    wire [10:0] frame;      // Frame counter (0..2047); mostly unused.
    // `tick` pulses once, with the clock, at the start of a frame, to signal that animation can happen:
    
    wire        tick = h==0 && v==0;
    //SMELL: Should `tick` come from vga_sync?
    // Should it be an output signal (e.g. for IRQ and diagnostics)?
    // Should one be generated at the start of VBLANK too?

    assign px = h;
    assign py = v;
    assign frame_num = frame;   //SMELL: Work on getting rid of the need for this.

    // General reset and game state animation (namely, motion):
    always @(posedge clk) begin
        if (reset) begin
            // Set player's starting position and direction:
            playerX <= playerXstart;
            playerY <= playerYstart;

            facingX <= facingXstart;
            facingY <= facingYstart;

            vplaneX <= vplaneXstart;
            vplaneY <= vplaneYstart;
        end else if (tick) begin
            // Animation can happen here.
            if (write_new_position) begin
                // Host wants to directly set new vectors:
                //SMELL: This should be handled properly with a synchronised loading method,
                // and consideration for crossing clock domains.
                playerX <= new_playerX;
                playerY <= new_playerY;
                facingX <= new_facingX;
                facingY <= new_facingY;
                vplaneX <= new_vplaneX;
                vplaneY <= new_vplaneY;
            end else begin
                // Handle player motion:
                //SMELL: This isn't properly implemented:
                // - L/R should use vplane vector (which isn't a unit)
                // - F/B should use facing vector.
                // If we were to use a multiplier, we'd do something like this:
                //      if (moveL) begin
                //          playerX <= playerX - `FF(playerMove*vplaneX);
                //          playerY <= playerY - `FF(playerMove*vplaneY);
                //      end else ...
                // We don't HAVE to use a multiplier, though, if we know things about the scale
                // of playerMove.
                if (moveL)
                    playerX <= playerX - playerMove;
                else if (moveR)
                    playerX <= playerX + playerMove;

                if (moveF)
                    playerY <= playerY - playerMove;
                else if (moveB)
                    playerY <= playerY + playerMove;

                //SMELL: Ideally *diagonal* motion should be a vector equal to playerMove,
                // i.e. move by 1/sqrt(2) on both X and Y.
            end
        end
    end
    always @(negedge reset) begin
        $display("playerX=%f, playerY=%f", `Freal(playerX), `Freal(playerY));
        $display("facingX=%f, facingY=%f", `Freal(facingX), `Freal(facingY));
        $display("vplaneX=%f, vplaneY=%f", `Freal(vplaneX), `Freal(vplaneY));
    end

    // RGB output gating:
    wire [1:0]  r, g, b; // Raw R, G, B values to be gated by 'visible'.
    assign red  = visible ? r : 2'b00;
    assign green= visible ? g : 2'b00;
    assign blue = visible ? b : 2'b00;

    // This generates base VGA timing:
    vga_sync sync(
        .clk    (clk),
        .reset  (reset),
        .hsync  (hsync),
        .vsync  (vsync),
        .visible(visible),
        .h      (h),
        .v      (v),
        .frame  (frame)
    );


    wire        vblank = v>=SCREEN_HEIGHT;  // VBLANK: Not rendering, so no screen data reads needed.
    wire        ceiling = v<HALF_HEIGHT;    // Are we in the ceiling or floor part of the frame?
    wire [1:0]  background = ceiling ? 2'b01 : 2'b10;    // Ceiling is dark grey, floor is light grey.
    wire        trace_we; // trace_buffer Write Enable; tracer-driven. When off, trace_buffer stays in read mode.

    // During VBLANK, tracer writes to memory.
    // During visible, memory reads get wall column heights/sides to render.
    //SMELL: I might replace this with a huge shift register ring so that
    // we can do away with bi-dir (inout) ports, and simplify it in general.
    trace_buffer traces(
        .clk    (clk),
        .column (buffer_column),
        .side   (wall_side),
        .height (wall_height[7:0]),
        .cs     (1),    //SMELL: Redundant?
        .we     (trace_we),
        .oe     (!trace_we)
    );

    // Trace column is selected either by screen render read loop, or by tracer state machine:
    wire [9:0]  buffer_column = visible ? h : tracer_addr;
    wire [9:0]  tracer_addr;    // Driven by tracer directly...
    wire        tracer_side;    // ...
    wire [7:0]  tracer_height;  // .

    // During trace_buffer write, we drive wall_height directly.
    // Otherwise, set it to Z because trace_buffer drives it:
    wire        wall_side    = trace_we ? tracer_side            :  1'bz;
    wire [9:0]  wall_height  = trace_we ? {2'b00,tracer_height}  : 10'bz; //SMELL: [9:0], only to avoid in_wall logic warnings.

    wire [3:0] map_row, map_col;
    wire [1:0] map_val;
    tracer tracer(
        // Inputs to tracer:
        .clk    (clk),
        .reset  (reset),
        .enable (vblank),
        .map_val(map_val),
        .playerX(playerX),
        .playerY(playerY),
        .facingX(facingX),
        .facingY(facingY),
        .vplaneX(vplaneX),
        .vplaneY(vplaneY),
        .debug_frame(frame),
        // Outputs from tracer:
        .map_col(map_col),
        .map_row(map_row),
        .store  (trace_we),
        .column (tracer_addr),
        .side   (tracer_side),
        .height (tracer_height)
    );

    // Map ROM, both for tracing, and for optional show_map overlay:
    map_rom map(
        .col    (visible ? h[MAP_SCALE+3:MAP_SCALE] : map_col),
        .row    (visible ? v[MAP_SCALE+3:MAP_SCALE] : map_row),
        .val    (map_val)
    );

    // Considering vertical position: Are we rendering wall or background in this pixel?
    wire        in_wall = (HALF_HEIGHT-wall_height) <= v && v <= (HALF_HEIGHT+wall_height);

    // Are we in the border area?
    //SMELL: This conceals some slight rendering glitches that we really should fix.
    wire        in_border = h<66 || h>=574;

    // Is this a dead column, i.e. height is 0? This shouldn't happen normally,
    // but if it does (either due to a glitch or debug purpose) then it should render
    // this pixel as magenta:
    wire        dead_column = wall_height==0;// || h==DEBUG_X;

    // Are we in the region of the screen where the map overlay must currently render?
    //SMELL: Should this be a separate module, too, for clarity?
    wire        in_map_overlay  = show_map && h < MAP_OVERLAY_SIZE && v < MAP_OVERLAY_SIZE;
    wire        in_map_gridline = in_map_overlay && (h[MAP_SCALE-1:0]==0||v[MAP_SCALE-1:0]==0);
    wire        in_player_cell  = in_map_overlay && (playerX[3:0]==h[MAP_SCALE+3:MAP_SCALE] && playerY[3:0]==v[MAP_SCALE+3:MAP_SCALE]);
    wire        in_player_pixel = in_player_cell
                                    && (playerX[-1:-MAP_SCALE]==h[MAP_SCALE-1:0])
                                    && (playerY[-1:-MAP_SCALE]==v[MAP_SCALE-1:0]);

`ifdef ENABLE_DEBUG
    wire signed [10:0]  debug_offset  = {1'b0,h} - (640 - (1<<DEBUG_SCALE)*(`Qm+`Qn) - 1);
    wire                in_debug_info = debug_offset>=0 && v<8*(1<<DEBUG_SCALE)+1;
    wire                in_debug_grid = in_debug_info && debug_offset[DEBUG_SCALE-1:0]==0||v[DEBUG_SCALE-1:0]==0;
    wire `F             debug_bit_mask = 1 << (`Qmn-debug_offset[10:DEBUG_SCALE]-1);
    wire [1:0]          debug_level =
                            in_debug_grid                   ? ( debug_offset==(`Qm<<DEBUG_SCALE) ? 2'b10 : 2'b00 ):
                            v[DEBUG_SCALE+2:DEBUG_SCALE]==0 ? ( (playerX&debug_bit_mask)!=0 ? 2'b11 : 2'b01) :
                            v[DEBUG_SCALE+2:DEBUG_SCALE]==1 ? ( (playerY&debug_bit_mask)!=0 ? 2'b11 : 2'b01) :
                            v[DEBUG_SCALE+2:DEBUG_SCALE]==3 ? ( (facingX&debug_bit_mask)!=0 ? 2'b11 : 2'b01) :
                            v[DEBUG_SCALE+2:DEBUG_SCALE]==4 ? ( (facingY&debug_bit_mask)!=0 ? 2'b11 : 2'b01) :
                            v[DEBUG_SCALE+2:DEBUG_SCALE]==6 ? ( (vplaneX&debug_bit_mask)!=0 ? 2'b11 : 2'b01) :
                            v[DEBUG_SCALE+2:DEBUG_SCALE]==7 ? ( (vplaneY&debug_bit_mask)!=0 ? 2'b11 : 2'b01) :
                                                              2'b00;
`else
    wire                in_debug_info = 0;
    wire [1:0]          debug_level = 0;
`endif

    assign r =
        in_debug_info   ?   debug_level :
        in_player_pixel ?   2'b11 :             // Player pixel in map is yellow.
        in_player_cell  ?   0 :
        in_map_gridline ?   0 :
        in_map_overlay  ?   0 :
        in_border       ?   2'b01 :             // Border is dark purple.
        dead_column     ?   2'b11 :             // 0-height columns are filled with magenta.
        in_wall         ?   0 :
                            background;
    
    assign g =
        in_debug_info   ?   debug_level :
        in_player_pixel ?   2'b11 :             // Player pixel in map is yellow.
        in_player_cell  ?   2'b01 :             // Player cell in map is dark green.
        in_map_gridline ?   0 :
        in_map_overlay  ?   0 :
        in_border       ?   0 :
        dead_column     ?   0 :
        in_wall         ?   0 :
                            background;
    
    assign b =
        in_debug_info   ?   debug_level :
        in_player_pixel ?   0 :
        in_player_cell  ?   0 :
        in_map_gridline ?   2'b01 :             // Map gridlines are dark blue.
        in_map_overlay  ?   map_val :           // Map cell (colour).
        in_border       ?   2'b01 :             // Border is dark purple.
        dead_column     ?   2'b11 :             // 0-height columns are filled with magenta.
        in_wall         ?
                            wall_side ?
                                2'b11 :         // Bright wall side.
                                2'b10 :         // Dark wall side.
                            background;         // Ceiling/floor background.

endmodule

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
// `define DEBUG_X 320

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
    
    output  reg [1:0]   red,   // Each of R, G, and B are 2bpp, for a total of 64 possible colours.
    output  reg [1:0]   green,
    output  reg [1:0]   blue,
    output          hsync,
    output          vsync,
    output  [9:0]   px,   // Current pixel x.
    output  [9:0]   py,   // Current pixel y.
    output  [10:0]  frame_num,
    output          speaker
);

    localparam SPRITE_TRANSPARENT_COLOR = 6'b110011;

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
    //SMELL: defines instead of params, to work around Quartus bug: https://community.intel.com/t5/Intel-Quartus-Prime-Software/BUG/td-p/1483047
    `define       playerXstartcell    1
    `define       playerYstartcell    13
`else
    `define       playerXstartcell    8
    `define       playerYstartcell    14
`endif
    // Player's full start position is in the middle of a cell:
    //SMELL: defines instead of params, to work around Quartus bug: https://community.intel.com/t5/Intel-Quartus-Prime-Software/BUG/td-p/1483047
    `define       playerXstartoffset  0.5       // Should normally be 0.5, but for debugging might need to be other values.
    `define       playerYstartoffset  0.5
    localparam `F playerXstart      = `realF(`playerXstartcell+`playerXstartoffset);
    localparam `F playerYstart      = `realF(`playerYstartcell+`playerYstartoffset);

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

    reg `F      playerX /* verilator public */;
    reg `F      playerY /* verilator public */;
    reg `F      facingX /* verilator public */;     // Heading is the vector of the direction the player is facing.
    reg `F      facingY /* verilator public */;
    reg `F      vplaneX /* verilator public */;     // Viewplane vector (typically 'facing' rotated clockwise by 90deg and then scaled).
    reg `F      vplaneY /* verilator public */;     // (which could also be expressed as vx=-fy, vy=fx, then scaled).

    reg [9:0]   spriteX /* verilator public */;     // Centre point of sprite in screen coordinates.
    reg `F      spriteD /* verilator public */;     // Sprite distance (using same units as walls). Affects visibility and scaling.


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
    integer debug_frame_count = 0;
    always @(posedge clk) begin
        if (tick) begin
            debug_frame_count = debug_frame_count + 1;
        end
    end


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

            spriteX <= 320;
            spriteD <= `intF(3);

            debug_frame_count = 0;

        end else if (v < SCREEN_HEIGHT && write_new_position) begin
            // Host wants to directly set new vectors:
            //SMELL: This should be handled properly with a synchronised loading method,
            // and consideration for crossing clock domains.
            // In particular, do we just need to buffer write_new_position?
            playerX <= new_playerX;
            playerY <= new_playerY;
            facingX <= new_facingX;
            facingY <= new_facingY;
            vplaneX <= new_vplaneX;
            vplaneY <= new_vplaneY;
        end else if (tick && !write_new_position) begin
            // Animation can happen here.
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
        end
    end
    always @(negedge reset) begin
        $display("playerX=%f, playerY=%f", `Freal(playerX), `Freal(playerY));
        $display("facingX=%f, facingY=%f", `Freal(facingX), `Freal(facingY));
        $display("vplaneX=%f, vplaneY=%f", `Freal(vplaneX), `Freal(vplaneY));
    end

    // RGB output gating:
    wire [1:0]  r, g, b; // Raw R, G, B values to be gated by 'visible'.
		
		always @(posedge clk) begin
				red   <= visible ? r : 2'b00;
				green <= visible ? g : 2'b00;
				blue  <= visible ? b : 2'b00;
		end

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

    wire                vblank      = v>=SCREEN_HEIGHT;         // VBLANK: Not rendering, so no screen data reads needed.
    wire                ceiling     = v<HALF_HEIGHT;            // Are we in the ceiling or floor part of the frame?
    wire [1:0]          background  = ceiling ? 2'b01 : 2'b10;  // Ceiling is dark grey, floor is light grey.
    wire                trace_we;                               // trace_buffer Write Enable; tracer-driven. When off, trace_buffer stays in read mode.

    // During VBLANK, tracer writes to memory.
    // During visible, memory reads get wall column heights/sides to render.
    //SMELL: I might replace this with a huge shift register ring so that
    // we can do away with bi-dir (inout) ports, and simplify it in general.
    trace_buffer traces(
        .clk    (clk),
        .column (buffer_column),
        .side   (wall_side),
        .vdist  (wall_dist),
        .tex    (wall_texX),
        .cs     (1),    //SMELL: Redundant?
        .we     (trace_we),
        .oe     (!trace_we)
    );

    // Trace column is selected either by screen render read loop, or by tracer state machine:
    wire [9:0]          buffer_column = visible ? h : tracer_addr;
    wire [9:0]          tracer_addr;    // Driven by tracer directly...
    wire                tracer_side;    // ...
    wire [`DII:`DFI]    tracer_dist;    // ...(using fewer bits, to reduce memory size)...
    wire [5:0]          tracer_texX;    // .

    // During trace_buffer write, we drive wall_height directly.
    // Otherwise, set it to Z because trace_buffer drives it:
    wire                wall_side   = trace_we ? tracer_side : 1'bz;
    wire [`DII:`DFI]    wall_dist   = trace_we ? tracer_dist : { `Dbits{1'bz} };
    wire [5:0]          wall_texX   = trace_we ? tracer_texX : 6'bz;

    wire `F             heightScale;    // Comes from reciprocal of wall_dist.
    wire                satHeight;      //SMELL: Unused.
    //SMELL: Can this reciprocal use `DI and `DF or something similar instead, so we don't need to pad it out to a full Q12.12?
    reciprocal #(.M(`Qm),.N(`Qn)) height_scaler (
        .i_data ( { {(`Qm-`DI){1'b0}}, wall_dist, {(`Qn-`DF){1'b0}} } ), // Pad wall_dist to full `F range.
        .i_abs  (1),
        .o_data (heightScale),
        .o_sat  (satHeight)
    );

/* verilator lint_off WIDTH */
    //SMELL: We could pack yscale into a smaller number of bits. Basically we could just use wall_dist directly...?
    wire `F             yscale      = wall_dist;// >> 3;    // NOTE: This scales the TEXTURE coordinate look-up... not the height of the wall.
    wire [9:0]          wall_height = heightScale[1:-8];    // Equiv. to: fixed-point heightScale value, *256, floored. Note that this can go up to 511.

    // Work out the texture Y offset (in range 0..63) by using how far v is through wall_height:
    // wire `F     yscale = `intF(64) / (wall_height<<1);
    //NOTE: for yscale, imagine it is now 0..511, and we already know its reciprocal (distance?) via the tracer.
    // Could we then just store the distance value in the trace buffer, reciprocate in THIS module to get the wall_height,
    // and shift it by 6 or 7 bits?
    // Think of it this way, based on what we have right now:
    //      heightScale = 1 / visualWallDist
    //      wall_height = heightScale * 256     (or <<8)
    //      yscale = 64 / wall_height*2         (or <<1)
    // Conversely:
    //      yscale = 64 / (heightScale*256)
    // =>   yscale = 64 / ((heightScale*256)*2)
    // =>   yscale = 64 / (((1/visualWallDist)*256)*2)
    // =>   yscale = 64 / (512/visualWallDist)
    // =>   yscale = visualWallDist / (512/64)
    // =>   yscale = visualWallDist / 8
    // =>   yscale = visualWallDist >> 3
    //NOW: Is there ANOTHER to think of this that simplifies wall_base*yscale?
    // For instance:
    //      wtyf = (v-240+wall_height) * (64/wall_height*2)
    // =>   wtyf = ...

    wire [9:0]  midline_offset = v-HALF_HEIGHT; // For textures.
    wire [9:0]  wall_basis = midline_offset+wall_height;
    wire `F2    wtyf = `IF(wall_basis) * yscale; //SMELL: We could fix this up to just use the necessary number of its bits (i.e. 10+16)
    wire [5:0]  wall_texY = wtyf[5:0];
/* verilator lint_on WIDTH */

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
        .vdist  (tracer_dist),
        .tex    (tracer_texX)
    );

    // Map ROM, both for tracing, and for optional show_map overlay:
    map_rom map(
        .col    (visible ? h[MAP_SCALE+3:MAP_SCALE] : map_col),
        .row    (visible ? v[MAP_SCALE+3:MAP_SCALE] : map_row),
        .val    (map_val)
    );

    // Considering vertical position: Are we rendering wall or background in this pixel?
    wire        in_wall_comb = (wall_height > HALF_HEIGHT) || ((HALF_HEIGHT-wall_height) <= v && v <= (HALF_HEIGHT+wall_height));
		
		reg					in_wall;
		
		always @(posedge clk) begin
			in_wall <= in_wall_comb;
		end
		



    wire signed [9:0]  hso = h - spriteX; // h, offset by sprite centre (i.e. spriteX).

    wire `F     spriteHeightScale;    // Comes from reciprocal of spriteD.
    wire        spriteSatHeight;      //SMELL: Unused.
    //SMELL: Can this reciprocal use `DI and `DF or something similar instead, so we don't need to pad it out to a full Q12.12?
    reciprocal #(.M(`Qm),.N(`Qn)) sprite_scaler (
        .i_data (spriteD),
        .i_abs  (1),
        .o_data (spriteHeightScale),
        .o_sat  (spriteSatHeight)
    );
    wire [9:0]  sprite_height = spriteHeightScale[1:-8];    // Equiv. to: fixed-point heightScale value, *256, floored. Note that this can go up to 511.
    wire `F     spriteTextureScale = spriteD>>3; // >>3: Texture range is 0..63 (<<6), divided by height range 0..511 (>>9).
    wire `F2    stxf = `IF(hso) * spriteTextureScale;
    wire [5:0]  sprite_texX = stxf[5:0]+32;

    wire signed [9:0] shs = sprite_height;  // sprite_height signed (for visibility comparisons).

    wire [9:0]  sprite_basis = midline_offset+sprite_height;
    wire `F2    styf = `IF(sprite_basis) * spriteTextureScale;
    wire [5:0]  sprite_texY = styf[5:0];
    
    wire        transparent_pixel = {sprite_r,sprite_g,sprite_b}==SPRITE_TRANSPARENT_COLOR;
    wire        sprite_behind_wall = spriteTextureScale > yscale;

    wire        in_sprite = 
        // Not a transparent pixel:
        !transparent_pixel &&
        // Vertical axis is in range:
        ((sprite_height > HALF_HEIGHT) || ((HALF_HEIGHT-sprite_height) <= v && v <= (HALF_HEIGHT+sprite_height))) &&
        // Horizontal axis is in range:
        hso >= (-shs) && hso < (shs) &&
        // Sprite is in front of nearest wall:
        !sprite_behind_wall;


    // always @(posedge clk) begin
    //     if (debug_frame_count == 10 && h==160 && (v==0||v==480)) begin
    //         $display("================================================================");
    //     end
    //     if (debug_frame_count == 10 && h==160 && v<480) begin
    //         $display("v=%d hso=%d sprite_texX=%d sprite_texY=%d color=%b in_sprite=%b", v, hso, sprite_texX, sprite_texY, {sprite_r,sprite_g,sprite_b}, in_sprite);
    //     end
    // end

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
`ifdef DEBUG_X
    always @(posedge clk) begin
        if (h == `DEBUG_X && v==0) begin
            $display("\t\t\t\t\t\t\t\t\t\tWALL HEIGHT: %d  YSCALE: %b %f", wall_height, yscale, `Freal(yscale));
        end
    end
`endif

    wire [1:0]  wall_r,     wall_g,     wall_b;
    wire [1:0]  sprite_r,   sprite_g,   sprite_b;



    texture_rom wall_textures(
        .side(wall_side),
        .col(wall_texX),
        .row(wall_texY),
        .val( {wall_r, wall_g, wall_b} )
    );

    sprite_rom sprites(
        .col(sprite_texX),
        .row(sprite_texY),
        .val( {sprite_r, sprite_g, sprite_b} )
    );
    
    // wire [1:0]  wall_r = 0;
    // wire [1:0]  wall_g =
    //     wall_side ? {~wall_texX[2]^wall_texY[2], 1'b1} :  // Bright.
    //                 {~wall_texX[2]^wall_texY[2], 1'b0};   // Dark.

    // wire [1:0]  wall_b =
    //     wall_side ? {wall_texX[2]^wall_texY[2], 1'b1} :  // Bright wall side.
    //                 {wall_texX[2]^wall_texY[2], 1'b0};   // Dark wall side.


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
        in_sprite       ?   sprite_r :
        in_border       ?   2'b01 :             // Border is dark purple.
        dead_column     ?   2'b11 :             // 0-height columns are filled with magenta.
        in_wall         ?   wall_r :
                            background;
    
    assign g =
        in_debug_info   ?   debug_level :
        in_player_pixel ?   2'b11 :             // Player pixel in map is yellow.
        in_player_cell  ?   2'b01 :             // Player cell in map is dark green.
        in_map_gridline ?   0 :
        in_map_overlay  ?   0 :
        in_sprite       ?   sprite_g :
        in_border       ?   0 :
        dead_column     ?   0 :
        in_wall         ?   wall_g :
                            background;
    
    assign b =
        in_debug_info   ?   debug_level :
        in_player_pixel ?   0 :
        in_player_cell  ?   0 :
        in_map_gridline ?   2'b01 :             // Map gridlines are dark blue.
        in_map_overlay  ?   map_val :           // Map cell (colour).
        in_sprite       ?   sprite_b :
        in_border       ?   2'b01 :             // Border is dark purple.
        dead_column     ?   2'b11 :             // 0-height columns are filled with magenta.
        in_wall         ?   wall_b :
                            background;         // Ceiling/floor background.

endmodule

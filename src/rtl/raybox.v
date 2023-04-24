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

// `define SIM_H_HELPER

`include "fixed_point_params.v"

module raybox(
    input           clk,
    input           reset,
    input           show_map,           // Button to control whether we show the map overlay.
    input   [7:0]   debug_set_height,   // If NZ, write this height to the trace buffer, but only during VBLANK.
    output  [1:0]   red,   // Each of R, G, and B are 2bpp, for a total of 64 possible colours.
    output  [1:0]   green,
    output  [1:0]   blue,
    output          hsync,
    output          vsync,
    output          speaker
);

    localparam SCREEN_HEIGHT    = 480;
    localparam HALF_HEIGHT      = SCREEN_HEIGHT>>1;
    localparam MAP_SCALE        = 3;                        // Power of 2 scaling for map overlay size.
    localparam MAP_OVERLAY_SIZE = (1<<(MAP_SCALE))*16+1;    // Total size of map overlay.

    localparam facingXstart =  0 << `Qn;
    localparam facingYstart = -1 << `Qn;
    localparam vplaneXstart = 16'b0_00000_1000000000;
    localparam vplaneYstart =  0 << `Qn;
    // localparam playerXstartcell = 12;
    // localparam playerYstartcell = 14;
    localparam playerXstartcell = 8;
    localparam playerYstartcell = 14;
    // localparam playerXstartcell = 3;
    // localparam playerYstartcell = 11;
    localparam playerXstartpos  = (playerXstartcell << `Qn) + 16'b1000000000;
    localparam playerYstartpos  = (playerYstartcell << `Qn) + 16'b1000000000;

    // Outputs from vga_sync:
    wire [9:0]  h;
    wire [9:0]  v;
    wire        visible;
    wire [7:0]  frame;

    reg `Fixed playerX;
    reg `Fixed playerY;
    reg `Fixed facingX;     // Heading is the vector of the direction the player is facing.
    reg `Fixed facingY;
    reg `Fixed vplaneX;     // Viewplane vector (typically 'facing' rotated clockwise by 90deg and then scaled).
    reg `Fixed vplaneY;     // (which could also be expressed as vx=-fy, vy=fx, then scaled).
    //NOTE: raybox-app original FOV is 70deg, which coincidentally works out to be almost exactly
    // a 0.7 scaling factor: tan(70/2) = 0.7002...
    // No scaling factor (i.e. 1.0) would be easiest/simplest, and that means an
    // FOV of 90deg, but maybe that's too much?
    // If we use a 0.75 scaling factor, maybe this means simpler multiply logic?
    // atan(0.75) ~= 36.87deg, so an FOV of ~73.74deg

    initial begin
        $dumpfile ("raybox.vcd");
        $dumpvars (0, tracer);
    end

    always @(posedge clk) begin
        if (reset) begin
            // Set starting position of the player to (8.5,14.5) using fixed-point:
            playerX <=  playerXstartpos; // 8.5
            playerY <=  playerYstartpos; // 14.5

            facingX <=  facingXstart;
            facingY <=  facingYstart; //-1 << `Qn; // 16'b1_11111_0000000000

            // vplaneX <= 16'b0_00000_1000000000;   // 0.5 in Q6.10; means an FOV of about 53deg
            // vplaneX <= 16'b0_00000_1100000000;   // 0.75 in Q6.10; means an FOV of about 74deg
            // vplaneX <=  1 << `Qn; // 16'b0_00001_0000000000    //NOTE: For now, this means an FOV of 90deg.
            // vplaneY <=  0 << `Qn;
            vplaneX <= vplaneXstart;
            vplaneY <= vplaneYstart;
        end else begin
            playerX <= playerXstartpos - {3'b0,frame,5'b0};
        end
    end
    always @(negedge reset) begin
        $display("playerX=%f, playerY=%f", playerX*`SF, playerY*`SF);
        $display("facingX=%f, facingY=%f", facingX*`SF, facingY*`SF);
        $display("vplaneX=%f, vplaneY=%f", vplaneX*`SF, vplaneY*`SF);
    end

    // RGB output gating:
    wire [1:0]  r, g, b; // Raw R, G, B values to be gated by 'visible'.
`ifdef SIM_H_HELPER
    //SMELL: This is a kludge to help the simulator get its horizontal alignment right:
    wire [1:0]  p00 = (h==0&&v==0 ? 2'b11 : 0);
    assign red  = visible ? r|p00 : 0;
`else
    assign red  = visible ? r : 0;
`endif
    assign green= visible ? g : 0;
    assign blue = visible ? b : 0;

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

    // Are we in VBLANK, i.e. no screen data reads needed, no visible rendering taking place?
    wire        vblank = v>=SCREEN_HEIGHT;

    // Are we in the ceiling or floor part of the frame?
    wire        ceiling = v<HALF_HEIGHT;

    // Determine background colour:
    wire [1:0]  background = ceiling ? 2'b01 : 2'b10;    // Ceiling is dark grey, floor is light grey.

    // Write to trace_buffer only if we're in VBLANK and we have an input height to write:
    wire        trace_we; // Driven by tracer. When NOT active, the trace_buffer remains in read mode.

    // Trace column is selected either by render read loop, or
    // by tracer state machine:
    wire        tracer_side;
    wire [7:0]  tracer_height;
    wire [9:0]  tracer_addr;    // Driven by tracer directly.
    wire [9:0]  trace_column = visible ? h : tracer_addr; //SMELL: Should we rename trace_column to buffer_column? Less confusing.

    // During trace_buffer write, we drive wall_height directly.
    // Otherwise, set it to Z because trace_buffer drives it:
    wire        wall_side    = trace_we ? tracer_side            :  1'bz;
    wire [9:0]  wall_height  = trace_we ? {2'b00,tracer_height}  : 10'bz; //SMELL: This is only [9:0] to avoid in_wall logic warnings.

    // During VBLANK, tracer writes to memory.
    // During visible, memory reads get wall column heights/sides to render.
    //SMELL: I might replace this with a huge shift register ring so that
    // we can do away with bi-dir (inout) ports, and simplify it in general.
    trace_buffer traces(
        .clk    (clk),
        .column (trace_column),
        .side   (wall_side),
        .height (wall_height[7:0]),
        .cs     (1),    // Redundant?
        .we     (trace_we),
        .oe     (!trace_we)
    );

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
        .debug_set_height(debug_set_height),
        .debug_frame(frame),
        // Outputs from tracer:
        .map_col(map_col),
        .map_row(map_row),
        .store  (trace_we),
        .column (tracer_addr),
        .side   (tracer_side),
        .height (tracer_height)
    );

    // Map ROM, both for tracing, and for optional overlay:
    map_rom map(
        .col    (visible ? h[MAP_SCALE+3:MAP_SCALE] : map_col),
        .row    (visible ? v[MAP_SCALE+3:MAP_SCALE] : map_row),
        .val    (map_val)
    );

    // Are we rendering wall or background in this pixel?
    wire        in_wall = (HALF_HEIGHT-wall_height) <= v && v <= (HALF_HEIGHT+wall_height);

    // Are we in the region of the screen where the map overlay must currently render?

    wire        in_map_overlay = show_map && h < MAP_OVERLAY_SIZE && v < MAP_OVERLAY_SIZE;

    assign r = (in_wall || in_map_overlay) ? 0 : background;
    assign g = (in_wall || in_map_overlay) ? 0 : background;
    assign b =
        in_map_overlay ?
            h[MAP_SCALE-1:0]==0||v[MAP_SCALE-1:0]==0 ?
                2'b01 :         // Map gridline.
                map_val :       // Map cell (colour).
        in_wall ?
            wall_side ?
                2'b11 :         // Bright wall side.
                2'b10 :         // Dark wall side.
            background;         // Ceiling/floor background.

endmodule

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

    localparam SCREEN_HEIGHT = 480;
    localparam HALF_HEIGHT = SCREEN_HEIGHT>>1;

    // Outputs from vga_sync:
    wire [9:0]  h;
    wire [9:0]  v;
    wire        visible;
    wire [7:0]  frame;

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

    tracer tracer(
        // Inputs to tracer:
        .clk    (clk),
        .reset  (reset),
        .enable (vblank),
        .debug_set_height(debug_set_height),
        // Outputs from tracer:
        .store  (trace_we),
        .column (tracer_addr),
        .side   (tracer_side),
        .height (tracer_height)
    );

    wire [1:0] map_color;
    // Map ROM, both for tracing, and for optional overlay:
    map_rom map(
        .col    (h[7:4]),
        .row    (v[7:4]),
        .val    (map_color)
    );

    // Are we rendering wall or background in this pixel?
    wire        in_wall = (HALF_HEIGHT-wall_height) <= v && v <= (HALF_HEIGHT+wall_height);

    // Are we in the region of the screen where the map overlay must currently render?
    wire        in_map_overlay = show_map && h < 16*16+1 && v < 16*16+1;

    // always_comb begin
    //     if (in_map_overlay) begin
    //         r = 0;
    //         g = 0;
    //         b = map_color;
    //     end else if (in_wall) begin
    //         r = 0;
    //         g = 0;
    //         b = wall_side ? 2'b11 : 2'b10;
    //     end else begin
    //         r = background;
    //         g = background;
    //         b = background;
    //     end
    // end

    assign r = (in_wall || in_map_overlay) ? 0 : background;
    assign g = (in_wall || in_map_overlay) ? 0 : background;
    assign b =
        in_map_overlay ?
            h[3:0]==0||v[3:0]==0 ?
                2'b01 :         // Map gridline.
                map_color :     // Map cell.
        in_wall ?
            wall_side ?
                2'b11 :         // Bright wall side.
                2'b10 :         // Dark wall side.
            background;         // Ceiling/floor background.

endmodule

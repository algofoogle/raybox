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

module raybox(
    input clk,
    input reset,
    output [1:0] red,   // Each of R, G, and B are 2bpp, for a total of 64 possible colours.
    output [1:0] green,
    output [1:0] blue,
    output hsync,
    output vsync,
    output speaker
);

    localparam SCREEN_HEIGHT = 480;
    localparam HALF_HEIGHT = SCREEN_HEIGHT>>1;

    // Outputs from vga_sync:
    wire [9:0] h;
    wire [9:0] v;
    wire visible;
    wire [7:0] frame;

    //SMELL: This is a kludge to help the simulator get its horizontal alignment right:
    wire [1:0] p00 = (h==0&&v==0 ? 2'b11 : 0);

    // RGB output gating:
    wire [1:0] r, g, b; // Raw R, G, B values to be gated by 'visible'.
    assign red  = visible ? r|p00 : 0;
    assign green= visible ? g     : 0;
    assign blue = visible ? b     : 0;

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

    // Are we in the ceiling or floor part of the frame?
    wire ceiling = (v<240);

    // Determine background colour:
    wire [1:0] background = ceiling ? 2'b01 : 2'b10;    // Ceiling is dark grey, floor is light grey.

    // Read memory to get wall column heights/sides to render:
    trace_buffer traces(
        .clk    (clk),
        .column (h),
        .height (wall_height[7:0]),
        .side   (wall_side),
        .cs     (1),
        .we     (0),
        .oe     (1)
    );

    wire [9:0] wall_height;
    wire wall_side;

    // Are we rendering wall or background in this pixel?
    wire in_wall = (HALF_HEIGHT-wall_height) <= v && v <= (HALF_HEIGHT+wall_height);

    assign r = !in_wall ? background : 2'b00;
    assign g = !in_wall ? background : 2'b00;
    assign b = !in_wall ? background : wall_side ? 2'b11 : 2'b10;

endmodule

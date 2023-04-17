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

/* verilator lint_off UNOPT */
module raybox(
    input clk,
    input reset,
    output [1:0] red,
    output [1:0] green,
    output [1:0] blue,
    output hsync,
    output vsync,
    output speaker
);
    wire [9:0] h;
    wire [9:0] v;
    wire visible;
    wire [7:0] frame;

    // RGB output gating:
    wire [1:0] r, g, b; // Raw R, G, B values to be gated by 'visible'.
    wire [1:0] p00 = (h==0&&v==0 ? 2'b11 : 0); //SMELL: Simulator might not get HSYNC right without this.
    assign red  = visible ? r|p00 : 0;
    assign green= visible ? g     : 0;
    assign blue = visible ? b     : 0;

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

    // Simple colour range test:
    // assign r = h[3:2];
    // assign g = h[5:4];
    // assign b = h[7:6];

    wire vblank = v>=480;
    wire [9:0] trace_addr;
    wire [7:0] trace_val;

    // This is constantly outputting a height value to be written to a column address:
    tracer tracer(
        .clk(clk),
        .active(vblank),
        .col(trace_addr),
        .height(trace_val)
    );

    wire [9:0] trace_buffer_addr = vblank ? trace_addr : h;

    trace_buffer trace_buffer(
        .clk(clk),
        .active(vblank),
        .trace_addr(trace_buffer_addr),
        .trace_val_in(trace_val),
        .trace_val_out(height_temp)
    );

    wire [7:0] height_temp;
    wire [9:0] height = {2'b00,height_temp};

    wire ceiling = (v<240);
    wire [1:0] background = ceiling ? 2'b01 : 2'b10;

    // Render column heights (in blue only):
    wire wall = ceiling ? v > 240-height : v-240 < height;
    assign r = wall ? 2'b00 : background;
    assign g = wall ? 2'b00 : background;
    assign b = wall ? 2'b11 : background;

endmodule
/* verilator lint_on UNOPT */



module tracer(
    input clk,
    input active,
    output [9:0] col,
    output [7:0] height
);
    reg [14:0] col_counter;

    assign col = col_counter[14:5]; // This is a dummy delay which shows we can take at least 32 clocks to trace each ray.
    assign height = col > 240 ? 240 : col[7:0];

    always @(posedge clk) begin
        if (!active) begin
            col_counter <= 0;
        end else begin
            col_counter <= col_counter+1;
        end
    end

endmodule


// This is a memory that stores the results of each trace loop,
// and allows the renderer to read it while in the visible region of the screen:
module trace_buffer(
    input clk,
    input active,
    input [9:0] trace_addr,
    input [7:0] trace_val_in,
    output [7:0] trace_val_out
);

    reg [7:0] traces [639:0];

    assign trace_val_out = traces[trace_addr];

    always @(posedge clk) begin
        if (active) begin
            traces[trace_addr] <= trace_val_in;
        end
    end

endmodule

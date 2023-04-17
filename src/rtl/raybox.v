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

    assign red  [1] =  visible & (h[4]^v[4]);
    assign green[1] =  visible & (h[5]^v[5]);
    assign blue [1] =  visible & (h[6]^v[6]);

    wire [9:0] h2 = h+{6'b0,frame[4:1]};
    wire [9:0] v2 = v+{6'b0,frame[5:2]};
    wire boost = (h2[3]^v2[3]);
    assign red  [0] = red  [1] & boost;
    assign green[0] = green[1] & boost;
    assign blue [0] = blue [1] & boost;

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

endmodule
/* verilator lint_on UNOPT */

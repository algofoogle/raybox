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

    assign red     = visible ? {2{h[4]^v[4]}} : 2'b0;
    assign green   = visible ? {2{h[5]^v[5]}} : 2'b0;
    assign blue    = visible ? {2{h[6]^v[6]}} : 2'b0;

    vga_sync sync(
        .clk    (clk),
        .reset  (reset),
        .hsync  (hsync),
        .vsync  (vsync),
        .visible(visible),
        .h      (h),
        .v      (v)
    );

endmodule

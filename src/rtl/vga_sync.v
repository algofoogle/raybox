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

module vga_sync #(
  parameter HRES        = 640,
  parameter HF          = 16,
  parameter HS          = 96,
  parameter HB          = 48,
  parameter VRES        = 480,
  parameter VF          = 10,
  parameter VS          = 2,
  parameter VB          = 33
)(
  input clk,          // 25MHz clock.
  input reset,        // Reset: active HIGH.
  output hsync,
  output vsync,
  output visible,
  output reg [9:0] h, // 0..799
  output reg [9:0] v, // 0..524
  output reg [10:0] frame // frame counter, for now limited to 0..2047
);
  localparam HFULL = HRES+HF+HS+HB;
  localparam VFULL = VRES+VF+VS+VB;

  wire hmax = h == (HFULL-1); //NOTE: Because we don't care about values ABOVE hmax, we can also look for &{h[9:8], h[5:0]} i.e. 10'b11xx111111 (and in fact, can we compare exactly with this?)
  wire vmax = v == (VFULL-1); //NOTE: Because we don't care about values ABOVE vmax, we can also look for &{v[9],   v[3:2]} i.e. 10'b1xxxxx11xx (and in fact, can we compare exactly with this?)

  //SMELL: Would it be better to use equality and set a reg to detect when we enter/leave visible regions, instead of using full comparators?
  assign visible = h < HRES && v < VRES;
  assign hsync = ~((HRES+HF) <= h && h < (HRES+HF+HS));
  assign vsync = ~((VRES+VF) <= v && v < (VRES+VF+VS));

  always @(posedge clk) begin

    if (reset) begin
      //NOTE: We might not need to care too much about doing this reset if we want to be really
      // compact, because ANY state will eventually come good within 1 or 2 frames.
      h <= 0;
      v <= 0;
      frame <= 0;
    end else begin
      // Increment pixel counter:
      h <= hmax ? 10'b0 : h+1'b1; // Roll over horizontal scan when we've hit hmax.

      if (hmax) begin
        // Increment line counter:
        v <= vmax ? 10'b0 : v+1'b1;

        if (vmax) begin
          // End of frame; animation can happen here...
          frame <= frame + 1'b1;
        end // if (vmax)
      end //if (hmax)
    end // else (i.e. not in reset)
  end

endmodule

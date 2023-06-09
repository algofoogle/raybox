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


// This is influenced by:
// https://www.asic-world.com/examples/verilog/ram_sp_sr_sw.html


`default_nettype none
`timescale 1ns / 1ps

//NOTE: This would probably work better as a huge shift register: We know that
// at the end of the frame, we will generate exactly 640 traces, and then
// we'll be reading back those same 640 traces repeatedly for each line.
module trace_buffer(
    // Input ports:
    input           clk,
    input           cs,
    input           we,
    input           oe,
    input [9:0]     column,

    // InOut ports (i.e. bi-dir):
    //SMELL: Should we have separate read/write ports for simplicity?
    inout [15:0]    vdist,  // View (trace) distance, as Q7.9.
    inout [1:0]     wtid,   // Wall Type ID.
    inout           side,
    inout [5:0]     tex
);

    reg [15:0]      vdist_out;
    reg [1:0]       wtid_out;   // Wall Type ID.
    reg             side_out;
    reg [5:0]       tex_out;

    reg [15:0]      dummy_vdist_memory  [0:640-1];  // 10240 bits.
    reg [1:0]       dummy_wtid_memory   [0:640-1];  // 1280 bits.
    reg             dummy_side_memory   [0:640-1];  // 640 bits.
    reg [5:0]       dummy_tex_memory    [0:640-1];  // 3840 bits.

    // Tri-state buffer control for output mode:
    wire read_mode  = (cs && oe && !we);
    assign vdist    = read_mode ? vdist_out : 16'bz;
    assign wtid     = read_mode ? wtid_out  : 2'bz;
    assign side     = read_mode ? side_out  : 1'bz;
    assign tex      = read_mode ? tex_out   : 6'bz;

    // Memory write block:
    always @(posedge clk) begin : MEM_WRITE
        if (cs && we) begin
            dummy_vdist_memory  [column]    = vdist;
            dummy_wtid_memory   [column]    = wtid;
            dummy_side_memory   [column]    = side;
            dummy_tex_memory    [column]    = tex;
        end
    end

    // Memory read block:
    always @(posedge clk) begin : MEM_READ
        if (read_mode) begin
            vdist_out   = dummy_vdist_memory[column];
            wtid_out    = dummy_wtid_memory [column];
            side_out    = dummy_side_memory [column];
            tex_out     = dummy_tex_memory  [column];
        end
    end

endmodule

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
    input       clk,
    input       cs,
    input       we,
    input       oe,
    input [9:0] column,

    // InOut ports (i.e. bi-dir):
    inout [7:0] height, //SMELL: Should we have separate read/write ports for simplicity?
    inout       side
);

    reg [7:0]   height_out;
    reg         side_out;

    //NOTE: dummy_memory arrangement is a pair of bytes for each
    // traced screen column.
    // - First byte is wall height (8 bits, but should only typically be 1..240).
    // - Second byte, only LSB is used for wall facing: EW (0) or NS (1) facing.
    reg [7:0]   dummy_memory [0:640*2-1];
    initial $readmemh("assets/traces_capture_0001.hex", dummy_memory);

    // Tri-state buffer control for output mode:
    wire read_mode = (cs && oe && !we);
    assign height   = read_mode ? height_out    : 8'bz;
    assign side     = read_mode ? side_out      : 1'bz;

    // Memory write block:
    always @(posedge clk) begin : MEM_WRITE
        if (cs && we) begin
            dummy_memory[ {column,1'b0} ][7:0] = height;
            dummy_memory[ {column,1'b1} ][0:0] = side;
        end
    end

    // Memory read block:
    always @(posedge clk) begin : MEM_READ
        if (read_mode) begin
            height_out  = dummy_memory[ {column,1'b0} ][7:0];
            side_out    = dummy_memory[ {column,1'b1} ][0:0];
        end
    end

endmodule
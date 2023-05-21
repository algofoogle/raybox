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

`include "fixed_point_params.v"


module sprite_buffer(
    // Input ports:
    input           clk,
    input           we,
    input           oe,
    input [2:0]     index,         

    // InOut ports (i.e. bi-dir):
    //SMELL: Should we have separate read/write ports for simplicity?
    inout `F        sdist,   // Sprite's distance. //SMELL: Only need about 16 bits for this.
    inout [10:0]    scol     // Screen column sprite's centred on.
    //NOTE: Sprite centre needs to range from probably (0-256)..(640+256) = -256..896.
    //SMELL: Instead it should probably be based on actual screen centre (which is what the tracer
    // gives us anyway), which means it can be (-320-256)..(320+256) = -576..576 or possibly fit in -512..511
);

    reg `F          sdist_out;
    reg [10:0]      scol_out;

    reg `F          sdist_memory [0:7];
    reg [10:0]      scol_memory  [0:7];

    // Tri-state buffer control for output mode:
    wire read_mode  = (oe && !we);
    assign sdist    = read_mode ? sdist_out  : {`Qmn{1'bz}};
    assign scol     = read_mode ? scol_out   : 11'bz;

    // Memory write block:
    always @(posedge clk) begin : MEM_WRITE
        if (we) begin
            sdist_memory [index] = sdist;
            scol_memory  [index] = scol;
        end
    end

    // Memory read block:
    always @(posedge clk) begin : MEM_READ
        if (read_mode) begin
            sdist_out    = sdist_memory [index];
            scol_out     = scol_memory  [index];
        end
    end

endmodule

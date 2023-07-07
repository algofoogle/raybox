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

// This module implements a dummy memory for holding wall texture data.
//SMELL: Currently this ROM gets populated directly from the sim, which means
// it is NOT going to work the same way when synthesised for an FPGA or ASIC!

`default_nettype none
`timescale 1ns / 1ps

`include "raybox_target_defs.v"

//`define DUMMY_TEXTURE

module texture_rom #(
    parameter CHANNEL_BITS=2
)(
    input               side,
    input   [1:0]       wtid,
    input   [5:0]       col,
    input   [5:0]       row,
    output  [CHANNEL_BITS*3-1:0]  val
);

`ifdef DUMMY_TEXTURE
    assign val = {
        1'b1,side,
        1'b0,1'b0,
        1'b0,1'b0
    };
`else

    `ifdef QUARTUS
        reg [7:0] data [0:3*8192-1]; // 3 textures in total. Textures are 64x64, and there are 2 "sides" to each.

        initial begin
            //NOTE: This file scans on Y axis first, then X.
            $readmemh(`TEXTURE1_FILE, data,     0,   8191);
            $readmemh(`TEXTURE2_FILE, data,  8192,  16383);
            $readmemh(`TEXTURE3_FILE, data, 16384,  24575);
        end

        wire [1:0] wtid_1 = wtid-1'b1;
        //SMELL: Because there are only 3 textures, we initialise only 3*8kB memory,
        // but imply (via wtid_1 as upper 2 bits) that our memory should be up to 32kB.
        // Hence, we get a Quartus warning about some uninitialised/undriven memory.
        // In this case, Quartus pads the rest of the memory space with 0.
        assign val[CHANNEL_BITS*3-1:0] = data[{wtid_1,~side,col,row}][CHANNEL_BITS*3-1:0];
    `else // not QUARTUS
        //SMELL: This reg should be however many bits our output val is.
        // I've just made it 8-bit for now to match my data file.
        reg [7:0] data [0:2][0:8191] /* verilator public */;

        initial begin
            //NOTE: This file scans on Y axis first, then X.
            $readmemh(`TEXTURE1_FILE, data,     0,   8191);
            $readmemh(`TEXTURE2_FILE, data,  8192,  16383);
            $readmemh(`TEXTURE3_FILE, data, 16384,  24575);
        end

        wire [1:0] wtid_1 = wtid-1;
        assign val[CHANNEL_BITS*3-1:0] = data[wtid_1][{~side,col,row}][CHANNEL_BITS*3-1:0];
        // assign val[CHANNEL_BITS*3-1:0] = data[{~side,col,row}][CHANNEL_BITS*3-1:0];
        // assign val[1:0] = data[{~side,col,row}][1:0];
        // assign val[3:2] = data[{~side,col,row}][3:2];
        // assign val[5:4] = wtid;
    `endif
    
`endif

endmodule

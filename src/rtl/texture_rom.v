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

//`define DUMMY_TEXTURE
`ifdef NOT_QUARTUS
    `define TEXTURE_FILE "assets/texture-xrgb-2222.hex"
`else
    // Quartus needs a different relative path to find this file.
    `define TEXTURE_FILE "../assets/texture-xrgb-2222.hex"
`endif

module texture_rom #(
    parameter CHANNEL_BITS=2
)(
    input               side,
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
    //SMELL: This reg should be however many bits our output val is.
    // I've just made it 8-bit for now to match my data file.
//    reg [7:0] data [0:127][0:63] /* verilator public */;
    reg [7:0] data [0:8191] /* verilator public */;

    initial begin
        //NOTE: This file scans on Y axis first, then X.
        $readmemh(`TEXTURE_FILE, data);
    end

    assign val[CHANNEL_BITS*3-1:0] = data[{~side,col,row}][CHANNEL_BITS*3-1:0];
`endif

endmodule

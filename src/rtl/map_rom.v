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

//NOTE: If we actually wanted to store the game map statically in ROM (or RAM)
// then we could get away with 14x14 if we assume the outer edge is always solid wall.
// That means 60 fewer cells, but also means we'd have to hard-code the outer wall type.
//NOTE: Is it more efficient to store each cell as 1 array element,
// or each *row* as one array element (i.e. packed bits)?
module map_rom #(
    parameter COLS=16,
    parameter ROWS=16,
    parameter BITS=2    // Bits needed to store 1 map cell.
)(
    input   [3:0]       row, //SMELL: Row and col bit width are hardcoded here.
    input   [3:0]       col,
    output  [BITS-1:0]  val
);

`ifdef DUMMY_MAP
    assign val = 
        (
            ((row==0 || row==15 || col==0 || col==15) ||
            ((~row[2:0]==col[2:0]) & ~row[3] & ~col[3]) ||
            (((
                (row[1] ^ col[2]) ^ (row[0] & col[1])
            ) & row[2] & col[1]) | (~row[0]&~col[0]))
            & (row[2]^~col[2]))
        ) ? 2'b11 : 0;
`else
    reg [7:0]   dummy_memory [0:ROWS-1][0:COLS-1];
    initial $readmemh("assets/map_16x16.hex", dummy_memory);

    assign val = dummy_memory[row][col][BITS-1:0];
`endif

endmodule

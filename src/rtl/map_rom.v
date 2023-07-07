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

`include "raybox_target_defs.v"


// `define DUMMY_MAP
// `define EMPTY_MAP   // Outer walls only.
// `define INF_MAP     // Map with a hole in it, allowing tracer to overflow.

//NOTE: If we actually wanted to store the game map statically in ROM (or RAM)
// then we could get away with 14x14 if we assume the outer edge is always solid wall.
// That means 60 fewer cells, but also means we'd have to hard-code the outer wall type.
//NOTE: Is it more efficient to store each cell as 1 array element,
// or each *row* as one array element (i.e. packed bits)?
module map_rom #(
    parameter COLBITS=4,
    parameter ROWBITS=4,
    parameter BITS=2    // Bits needed to store 1 map cell.
)(
    input   [COLBITS-1:0]   row,
    input   [ROWBITS-1:0]   col,
    output  [BITS-1:0]      val
);
    localparam COLCOUNT = (1<<COLBITS);
    localparam ROWCOUNT = (1<<ROWBITS);
    localparam MAXCOL = COLCOUNT-1;
    localparam MAXROW = ROWCOUNT-1;
    localparam MIDCOL1 = (1<<(COLBITS-1))-1;
    localparam MIDCOL2 = MIDCOL1+1;

`ifdef DUMMY_MAP
    assign val = 
        (
            ((row==0 || row==MAXROW || col==0 || col==MAXCOL) ||    // Outer box.
    `ifdef EMPTY_MAP
            0)
        `ifdef INF_MAP
            && (col!=MIDCOL1) && (col!=MIDCOL2)
        `endif
    `else
            ((~row[2:0]==col[2:0]) & ~row[3] & ~col[3]) ||
            (((
                (row[1] ^ col[2]) ^ (row[0] & col[1])
            ) & row[2] & col[1]) | (~row[0]&~col[0]))
            & (row[2]^~col[2]))
    `endif
        ) ? 2'b11 : 2'b00;
`else


    `ifdef QUARTUS
        // $readmemh needs 1D array in Quartus:
        reg [7:0]   dummy_memory [0:COLCOUNT*ROWCOUNT-1];
        initial $readmemh(`MAP_FILE, dummy_memory);
        assign val = dummy_memory[{col,row}][BITS-1:0];
    `else // not QUARTUS
        // $readmemh works OK with 2D array in everything else:
        reg [7:0]   dummy_memory [0:MAXCOL][0:MAXROW];
        initial $error("NEED TO CHANGE REFERENCE BELOW TO USE MAP_FILE");
        initial $readmemh("assets/map_64x64.hex", dummy_memory);
        assign val = dummy_memory[col][row][BITS-1:0];
    `endif // QUARTUS
    
`endif

endmodule

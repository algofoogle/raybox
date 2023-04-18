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

// For now this is just a dummy implementation that outputs traces for
// *some* columns, only when debug_set_height is non-zero:
module tracer(
    input           clk,
    input           reset,
    input           enable,             // High when we want the tracer to operate.
    input   [7:0]   debug_set_height,   //SMELL: This will be removed later, when the tracer is more-developed.

    output          store,              // Driven high when we've got a result to store.
    output  [9:0]   column,
    output          side,
    output  [7:0]   height              //NOTE: Make sure we only output 1..240
);
    
    // For now, we fake "work" by using a larger col_counter to slow down how often
    // we output the (fake) trace result for each column...
    reg [14:0] col_counter;

    always @(posedge clk) begin
        if (reset || !enable) begin
            col_counter <= 0;
        end else if (enable) begin
            // While enabled, we're a free-running state machine...
            col_counter <= col_counter + 1;
        end
    end

    assign store    = enable && debug_set_height!=0 && col_counter[14:5]<640;
    assign column   = col_counter[14:5];    // This updates a column every 32 clocks, to fake a workload.
    assign height   = debug_set_height;
    assign side     = debug_set_height[0];

endmodule

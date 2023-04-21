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
    input               clk,
    input               reset,
    input               enable,             // High when we want the tracer to operate.
    input       [7:0]   debug_set_height,   //SMELL: This will be removed later, when the tracer is more-developed.
    input       [7:0]   debug_frame,

    output reg          store,              // Driven high when we've got a result to store.
    output      [9:0]   column,
    output              side,
    output      [7:0]   height,             //NOTE: Make sure we only output 1..240

    // Map ROM access:
    output      [3:0]   map_col,
    output      [3:0]   map_row,
    input       [1:0]   map_val
);
    // How much time do we have?
    // VBLANK is for v in [480,524], which is 45 lines in total.
    // Each line is 800 clocks: 36,000 clocks in total.
    // Now let's assume we actually need 2 clocks per operation: 18,000 op cycles.
    // We have 640 columns to trace, so a budget of about 28 ops per ray if we want to do full horizontal resolution.
    // If our external clock was doubled (50MHz instead of 25) then we could get 56 ops.
    // If we used the internal DLL to get a 100MHz internal clock, we could get 112 ops.
    // SKY130 can supposedly go faster than that internally (maybe 200MHz, even)?

    // For now, I'm just doing a simple example where, for the first 240 columns,
    // we divide 240 by the column number (+1 to avoid div-0), and the result becomes
    // the height that we output. Remainder==0 drives 'side'.
    // This is a naive divider FSM, which just subtracts the divisor from the dividend
    // until it reaches a result.
    // Using that approach, it should take about 1363 cycles to do all 240 columns.
    // It could take less depending on how many cycles go just on managing the FSM
    // and "writing" the output.

    reg [1:0] state;
    localparam TRACE    = 0;    // Trace the curretn column.
    localparam STEP     = 1;    // Step to the next column.
    localparam DONE     = 3;    // Stop tracing (halt).

    reg [7:0] n;    // Dividend (numerator)
    reg [7:0] d;    // Divisor (denominator)
    reg [7:0] q;    // Quotient.

    reg [9:0] col_counter;
    reg [15:0] cycles;

    assign column   = col_counter; // Arbitrary, for our test.
    assign height   = q;
    assign side     = (n==0); // Remainder is 0?
    
    always @(posedge clk) begin
        if (reset || !enable) begin
            // Prep for when we're ready to start tracing a new frame,
            // starting with column 0:
            state <= TRACE;
            n <= 240;
            d <= 1;
            q <= 0;
            store <= 0;
            col_counter <= 0;
            cycles <= 0;
        end else begin
            // We must be enabled (and not in reset):
            cycles <= cycles + 1;
            case (state)
                TRACE: begin
                    // We're tracing this column...
                    if (d <= n) begin
                        // Dividing...
                        n <= n - d;
                        q <= q + 1;
                    end else begin
                        // Result reached; store it.
                        //NOTE: 'height' and 'side' are already asserted thru comb. logic.
                        store <= 1;
                        state <= STEP;
                    end
                end
                STEP: begin
                    store <= 0;
                    if (col_counter < 240) begin
                        // Advance to the next column to trace.
                        n <= 240;
                        d <= col_counter[7:0] + 1;
                        q <= 0;
                        col_counter <= col_counter + 1;
                        state <= TRACE;
                    end else begin
                        // $display("Frame tracing done after cycles:", cycles);
                        state <= DONE;
                    end
                end
            endcase
        end
    end

endmodule

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

// This module does basic ray-casting through a map to calculate distances
// to wall hits (and ultimately column heights) of each vertical column of
// the screen.
//
// It more-or-less implements this in Verilog:
// https://github.com/algofoogle/raybox-app/blob/22195e6b0482bc0c244ebb3a2c79cb7015d1c713/src/raybox.cpp#L340
//
// To keep this simple for now, I'm going for a screen width of 512,
// because it makes fixed-point division so much easier.
//
// Note that this is a state machine, and runs only while we're in VBLANK,
// i.e. when we're beyond the normal 480 VGA lines.
// How much time do we have?
// VBLANK is for v in [480,524], which is 45 lines in total.
// Each line is 800 clocks: 36,000 clocks in total.
// In a simple 16x16 map, I've observed that 512 columns can use up to 10,000 cycles.
// If we need more clocks, we can either:
//  1.  Optimise the FSM (though this won't give us much more).
//  2.  Do more checks in parallel (complex, but doable, if there is enough chip space and STA is OK).
//  3.  Give up more lines for more tracing time, e.g. 470 VGA lines for the main view area
//      would still look fine, but gives us 10 extra lines, so 8,000 extra cycles (44,000 total).
//  4.  Implement a faster internal clock. We know 50MHz should be fine, but with sky130
//      we could get to 100MHz without too much trouble, or even 200MHz?


`default_nettype none
`timescale 1ns / 1ps

`include "fixed_point_params.v"

module tracer(
    input               clk,
    input               reset,
    input               enable,             // High when we want the tracer to operate.
    input       `F      playerX,            // Position of the player.
    input       `F      playerY,            //SMELL: Player position must be positive, in fact [0,15]
    input       `F      facingX,            // Vector direction the player is facing.
    input       `F      facingY,            //
    input       `F      vplaneX,            // Viewplane vector.
    input       `F      vplaneY,
    input       [10:0]  debug_frame,

    output reg          store,              // Driven high when we've got a result to store.
    output      [9:0]   column,             // The column we'll write to in the trace_buffer.
    output reg          side,               // The side data we'll write for the respective column.
    output      [15:0]  vdist,
    // output      [7:0]   height,             // The height data we'll write for the column. NOTE: Make sure we only output 1..240
    output      [5:0]   tex,                // X coordinate (column) of wall's texture where the hit occurred.

    // Map ROM access:
    output      [3:0]   map_col,
    output      [3:0]   map_row,
    input       [1:0]   map_val
);

    localparam INIT     = 0;
    localparam STEP     = 1;
    localparam CHECK    = 2;
    localparam HIT1     = 3;  // For now, this has a 1 suffix because there are other repeats of this...
    localparam HIT2     = 10;
    localparam HIT3     = 11;
    localparam STORE1   = 4;  
    localparam STORE2   = 12;
    localparam STORE3   = 13; // ...to try working around FPGA timing issues.
    localparam DONE     = 5;
    localparam STOP     = 6;
    localparam LCLEAR   = 7;
    localparam RCLEAR   = 8;
    localparam DEBUG    = 9;

    reg [3:0] state;
    reg hit;
    reg [9:0] col_counter;

    reg `I      mapX, mapY;             // Map cell we're testing.

    reg `F      rayAddX, rayAddY;       // Ray direction offset (full precision; before scaling).
    // `rayAdd` will start off being -vplane*(columns/2) and will gradually accumulate another
    // +vplane per column until it reaches +vplane*(columns/2). It gets scaled back to a normal
    // fractional value with >>>8 when it gets added to `facing` in order to yield `rayDir`.

    // Ray direction vector:
    wire `F     rayDirX = facingX + (rayAddX>>>8);  //NOTE: >>>8 is based on 256 columns EITHER SIDE of screen centre.
    wire `F     rayDirY = facingY + (rayAddY>>>8);

    // Ray dir incrementing/decrementing flags per X and Y:
    wire        rxi =  rayDirX > 0;    // Is ray X direction positive?
    wire        ryi =  rayDirY > 0;    // Is ray Y direction positive?

    // trackXdist and trackYdist are not a vector; they're separate trackers
    // for distance travelled along X and Y gridlines:
    //NOTE: These are defined as UNSIGNED because in some cases they may get such a big
    // number added to them that they wrap around and appear negative, and this would
    // otherwise break comparisons. I expect this to be OK because such a huge addend
    // cannot exceed its normal positive range anyway, AND would only get added once
    // to an existing non-negative number, which would cause it to stop accumulating
    // without further wrapping beyond its possible unsigned range.
    reg `UF      trackXdist;
    reg `UF      trackYdist;

    // Get fractional part [0,1) of where the ray hits the wall:
    //SMELL: Surely there's a way to optimise this:
    wire `F2 rayFullHitX = visualWallDist*rayDirX;
    wire `F2 rayFullHitY = visualWallDist*rayDirY;
    wire `F wallX = side
        ? playerX + `FF(rayFullHitX)
        : playerY + `FF(rayFullHitY);
    assign tex = wallX[-1:-6];

    //SMELL: Do these need to be signed? They should only ever be positive, anyway.
    // Get integer player position:
    wire `I     playerXint  = `FI(playerX);
    wire `I     playerYint  = `FI(playerY);
    // Get fractional player position:
    wire `f     playerXfrac = `Ff(playerX);
    wire `f     playerYfrac = `Ff(playerY);

    // Work out size of the initial partial ray step, and whether it's towards a lower or higher cell:
    //NOTE: a playerfrac could be 0, in which case the partial must be 1.0 if the rayDir is increasing,
    // or 0 otherwise. playerfrac cannot be 1.0, however, since by definition it is the fractional part
    // of the player position.
    wire `F     partialX = rxi ? `intF(1)-`fF(playerXfrac) : `fF(playerXfrac); //SMELL: Why does Quartus think these are 32 bits being assigned?
    wire `F     partialY = ryi ? `intF(1)-`fF(playerYfrac) : `fF(playerYfrac);
    //NOTE: We're using full `F fixed-point numbers here so we can include the possibility of an integer
    // part because of the 1.0 case, mentioned above. However, we really only need 1 extra bit to support
    // this, if that makes any difference.
    
    // What distance (i.e. what extension of our ray's vector) do we go when travelling by 1 cell in the...
    wire `F     stepXdist;  // ...map X direction...
    wire `F     stepYdist;  // ...may Y direction...
    // ...which are values generated combinationally by the `reciprocal` instances below.
    //NOTE: If we needed to save space, we could have just one reciprocal,
    // and use different states to share it... which would probably work OK since we don't need to CONSTANTLY
    // be getting the reciprocals; just once at ray start, and once at ray end?
    reciprocal #(.M(`Qm),.N(`Qn)) flipX         (.i_data(rayDirX),          .i_abs(1), .o_data(stepXdist),  .o_sat(satX));
    reciprocal #(.M(`Qm),.N(`Qn)) flipY         (.i_data(rayDirY),          .i_abs(1), .o_data(stepYdist),  .o_sat(satY));
    // reciprocal #(.M(`Qm),.N(`Qn)) height_scaler (.i_data(visualWallDist),   .i_abs(1), .o_data(heightScale),.o_sat(satHeight));
    // These capture the "saturation" (i.e. overflow) state of our reciprocal calculators:
    wire satX;
    wire satY;
    // wire satHeight;
    // We might need these as we improve the design, in order to stop tracing on a given axis.

    // Generate the initial tracking distances, as a portion of the full
    // step distances, relative to where our player is (fractionally) in the map cell:
    //SMELL: These only needs to capture the middle half of the result,
    // i.e. if we're using Q16.16, our result should still be the [15:-16] bits
    // extracted from the product:
    wire `F2    trackXinit = stepXdist * partialX;
    wire `F2    trackYinit = stepYdist * partialY;

    // Send the current tested map cell to the map ROM:
    assign map_col = mapX[3:0];
    assign map_row = mapY[3:0];

    wire `F     visualWallDist = side ? trackYdist-stepYdist : trackXdist-stepXdist;
    assign vdist = visualWallDist[6:-9]; //HACK:
    //HACK: Range [6:-9] are enough bits to get the precision and limits we want for distance,
    // i.e. UQ7.9 allows distance to have 1/512 precision and range of [0,127).

    // wire `F     heightScale;

    // // Use a wall reference height of 256, which makes the maths simpler
    // // (i.e. simple bit extraction instead of a multiplier), and happens to
    // // also make the aspect ratio closer to square for each map cell:
    // wire [7:0] wallHeight =
    //     (heightScale >= `intF(1)) ? 8'd255 : // Cap height at 255 if heightScale >= 1.0
    //     heightScale[-1:-8];  // Else we just need the upper 8 bits of the fractional part.
    // //SMELL: Yes, this is hard-coded, but it works given we are assuming a max height of 255
    // // (so, a full 8-bit range), and hence the upper 8 bits of precision would effectively
    // // be multiplied by 256 anyway. Example:
    // // - If heightScale is 1.0 or 1.5, then the first condition catches it and clamps it to 255.
    // // - If heightScale is 0.75, then the second condition should yield 256*0.75=192.
    // //   It accomplishes this by just grabbing the upper 8 fractional bits: b.1100'0000
    // //   which is 192.
    // //NOTE: First (cap) condition could probably just be: |`FI(heightScale).

    // // Determine the final height value we'll write:
    // assign height =
    //     // Write 0 if we're in the "dead" region. //SMELL: We don't want this in future.
    //     (state == LCLEAR || state == RCLEAR) ? 8'd0 :
    //     // Values above 240 are CURRENTLY too high, so clamp:
    //     (wallHeight > 8'd240) ? 8'd240 :
    //     wallHeight;
    // Output current column counter value:
    assign column = col_counter;

    wire needStepX = trackXdist < trackYdist; //NOTE: UNSIGNED comparison per def'n of trackX/Ydist.

    //DEBUG: Used to count actual clock cycles it takes to trace a frame:
    integer trace_cycle_count;

    always @(posedge clk) begin
        if (reset || !enable) begin
            // if (trace_cycle_count > 0)
            //     $display("Total frame VBLANK cycles: %d", trace_cycle_count);
            trace_cycle_count = 0; //DEBUG
            // Prime the system...
            store <= 0;
            // The values below are starting conditions which are then
            // modified through each iteration, as opposed to values that
            // are recalculated through each iteration.

            col_counter <= 0;
            // col_counter <= (640-512)/2; // For 512w, will range from 64..575

            // Get the initial ray direction (column at screen LHS):
            rayAddX <= -vplaneX<<<8;    //NOTE: <<<8 because it starts 256 columns to the left of centre.
            rayAddY <= -vplaneY<<<8;

            side <= 0;
            state <= LCLEAR;
        end else begin
            trace_cycle_count = trace_cycle_count + 1; //DEBUG
            // We must be enabled (and not in reset) so we're a free-running system now...
            case (state)
                LCLEAR: begin
                    store <= 1;
                    col_counter <= col_counter + 1'b1;
                    if (col_counter == 63) begin
                        state <= INIT;
                    end
                end
                INIT: begin
                    // if (col_counter == 64) begin
                    //     $display("Start trace at player X,Y:%f,%f", playerX*`SF, playerY*`SF);
                    // end
                    store <= 0;
                    // Get the cell the player's currently in:
                    mapX <= playerXint;
                    mapY <= playerYint;
                    //SMELL: Could we get better precision with these trackers, by scaling?
                    trackXdist <= `FF(trackXinit);
                    trackYdist <= `FF(trackYinit);
                    state <= DEBUG;
                    // state <= STEP;
                end
                DEBUG: begin
                        // $display(
                        //     "Start: Frame:%d col:%d X:%d Y:%d trackXdist:%b trackYdist:%b -- rxi:%b ryi:%b rDX:%b rDY:%b",
                        //     debug_frame, col_counter, mapX, mapY, trackXdist, trackYdist, rxi, ryi, rayDirX, rayDirY
                        // );
                    state <= STEP;
                end
                STEP: begin
                    //SMELL: Can we explicitly set different states to match which trace/step we're doing?
                    // Might be easier to read than this muck.
                    // if (satY || trackXdist < trackYdist) begin
                    if (needStepX) begin
                        mapX <= rxi ? mapX+1'b1 : mapX-1'b1;
                        trackXdist <= trackXdist + stepXdist;
                        side <= 0;
                    end else begin
                        mapY <= ryi ? mapY+1'b1 : mapY-1'b1;
                        trackYdist <= trackYdist + stepYdist;
                        side <= 1;
                    end
                    // if (stopY || (!stopX && trackXdist < trackYdist)) begin
                    //     mapX <= rxi ? mapX+1 : mapX-1;
                    //     trackXdist <= trackXdist + stepXdist;
                    //     side <= 0;
                    // end else begin
                    //     mapY <= ryi ? mapY+1 : mapY-1;
                    //     trackYdist <= trackYdist + stepYdist;
                    //     side <= 1;
                    // end
                    state <= CHECK;
                end
                CHECK: begin
                    // Check if we've hit a wall yet.
                    if (map_val!=0) begin
                        // Hit a wall.
                        // if (col_counter >= 295 && col_counter <= 305) begin
                        //     $display(
                        //         "HIT:   Frame:%d col:%d X:%d Y:%d trackXdist:%b trackYdist:%b side:%b visualWallDist:%f heightScale:%f height:%d",
                        //         debug_frame, col_counter, mapX, mapY, trackXdist, trackYdist, side, `Freal(visualWallDist), `Freal(heightScale), height
                        //     );
                        // end
                        //SMELL: This extra step is in here to help with timing, i.e. setup violations.
                        state <= HIT1;
                    end else begin
                        // No hit yet; keep going.
                        state <= STEP;
                    end
                end
                HIT1: begin
                    // Hit a wall.
                    //store <= 1;
                    //SMELL: Dummy cycle to complete the write before we update for next ray.
                    state <= HIT2;
                end
                HIT2: begin
                    //SMELL: Dummy cycle to complete the write before we update for next ray.
                    state <= HIT3;
                end
                HIT3: begin
                    //SMELL: Dummy cycle to complete the write before we update for next ray.
                    state <= STORE1;
                end
                STORE1: begin
                    store <= 1;
                    state <= STORE2;
                end
                STORE2: begin
                    //SMELL: Dummy cycle to complete the write before we update for next ray.
                    state <= STORE3;
                end
                STORE3: begin
                    // Store is finished.
                    store <= 0;
                    if (col_counter == 575) begin
                        // No more columns to trace.
                        state <= DONE;
                    end else begin
                        // Start the next column.
                        col_counter <= col_counter + 1'b1;
                        // Advance the ray dir offset (rayAdd) by 1 whole vplane vector value:
                        rayAddX <= rayAddX + vplaneX;
                        rayAddY <= rayAddY + vplaneY;
                        state <= INIT;
                    end
                end
                DONE: begin
                    $display("Frame %d, finished tracing after %d clock cycles", debug_frame, trace_cycle_count);
                    state <= RCLEAR;
                    store <= 0;
                end
                RCLEAR: begin
                    store <= 1;
                    col_counter <= col_counter + 1'b1;
                    if (col_counter == 639) begin
                        state <= STOP;
                        store <= 0;
                    end
                end
            endcase
        end
    end

endmodule

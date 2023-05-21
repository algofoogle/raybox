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

    // Map ROM read access:
    output      [3:0]   map_col,
    output      [3:0]   map_row,
    input       [1:0]   map_val,

    // Trace buffer write access:
    output reg          store,              // Driven high when we've got a result to store.
    output      [9:0]   column,             // The column we'll write to in the trace_buffer.
    output reg          side,               // The side data we'll write for the respective column.
    output      [15:0]  vdist,              // Distance this column is from the viewer.
    output      [5:0]   tex,                // X coordinate (column) of wall's texture where the hit occurred.

    // Sprite buffer write access:
    output reg          spriteStore,
    output reg  [2:0]   spriteIndex,        //SMELL: Currently not supported.
    output      `F      spriteDist,
    output      [10:0]  spriteCol
);

    localparam SPRITE   = 0;
    localparam PREP     = 1;
    localparam STEP     = 2;
    localparam TEST     = 3;
    localparam DONE     = 4;  // For now, this has a 1 suffix because there are other repeats of this...
    
    reg [2:0] state;
    reg hit;
    reg [9:0] col_counter;

/* verilator lint_off REALCVT */
    localparam `F spriteX = `realF(1.5);
    localparam `F spriteY = `realF(9.5);
/* verilator lint_on REALCVT */

    // Calculate vector from player to sprite.
    wire `F     Dx = spriteX - playerX;
    wire `F     Dy = spriteY - playerY;

    // Calculate determinant of matrix |vplaneX vplaneY, facingX facingY|
    // and get its reciprocal, so we can effectively use it as a numerator:
    wire `F2    det = vplaneX*facingY - vplaneY*facingX;
    wire `F     invDet;
    wire        invDetSat;
    reciprocal #(.M(`Qm),.N(`Qn)) flipDet (.i_data(`FF(det)), .i_abs(0), .o_data(invDet), .o_sat(invDetSat));

    // I guess here we're calculating the determinant of matrix |vplaneX vplaneY, Dx Dy|
    //NOTE: The following is a of a very similar structure to that above; we could logic-share this to save on area.
    wire `F2    a = vplaneX*Dy - vplaneY*Dx;
    wire `F     Fa = `FF(a);
    wire `F     invFa;
    wire        invFaSat;
    reciprocal #(.M(`Qm),.N(`Qn)) flipA (.i_data(Fa), .i_abs(0), .o_data(invFa), .o_sat(invFaSat));

    // t1 is on-screen distance from the player to the sprite:
    wire `F2    t1 = Fa * invDet;

    // If sprite screen position would overshoot, kill it by setting distance to 0:
    wire `F     t2f = `FF(t2);
    assign spriteDist = (t2f<`intF(4) && t2f>`intF(-4)) ? `FF(t1) : 0;

    // t2 is horizontal sprite position, displaced from screen centre, in game units (i.e. relative to vplane vector??).
    // Could also be defined as:
    // ((Dx*facingY-Dy*facingX)*invDet)/t1, i.e.
    // (Dx*facingY-Dy*facingX) / (Fa)
    wire `F2    b = Dx*facingY - Dy*facingX;
    wire `F     Fb = `FF(b);
    wire `F2    t2 = Fb * invFa;

    // Sprite column (screen X) position should now be:
    // 320 + w*t2 (where 'w' is screen width as represented by left and right vplane extensions).
    // Assuming 512w, get spriteCol as relative to the facing direction (ie. screen centre),
    // which is multiplied by 256 (half 512w) by virtue of right-shifted indices:
    assign spriteCol = t2f[2:-8]; // 11 bits, per spriteCol def'n.
    //NOTE: Above, we're only allowing the range of this to be based on -4 < t2 < 4,
    // so a possible screen range of -1023 to +1023 (11 bits).
    //NOTE: Even though abs(t2) > 1 means the sprite CENTRE is off the screen, the scaled
    // width of the sprite might still be partially visible, hence the -4..4 range.
    

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
            spriteStore <= 0;
            spriteIndex <= 0;
            // The values below are starting conditions which are then
            // modified through each iteration, as opposed to values that
            // are recalculated through each iteration.

            col_counter <= 64; // // col_counter <= (640-512)/2; for now we skip the first 64 columns to keep things simpler.
            // Thus, we have a 512w range from 64..575.

            // Get the initial ray direction (column at screen LHS):
            rayAddX <= -vplaneX<<<8;    //NOTE: <<<8 because it starts 256 columns to the left of centre when we are working with 512w.
            rayAddY <= -vplaneY<<<8;

            side <= 0;
            state <= SPRITE;
        end else begin
            trace_cycle_count = trace_cycle_count + 1; //DEBUG
            // We must be enabled (and not in reset) so we're a free-running system now...
            case (state)
                SPRITE: begin
                    spriteStore <= 1;
                    //NOTE: spriteDist and spriteCol are worked out as combo logic above.
                    state <= PREP;
                end
                PREP: begin
                    spriteStore <= 0;
                    // Get the cell the player's currently in:
                    mapX <= playerXint;
                    mapY <= playerYint;
                    //SMELL: Could we get better precision with these trackers, by scaling?
                    trackXdist <= `FF(trackXinit);
                    trackYdist <= `FF(trackYinit);
                    state <= STEP;
                end
                STEP: begin
                    //SMELL: Can we explicitly set different states to match which trace/step we're doing?
                    if (needStepX) begin
                        mapX <= rxi ? mapX+1'b1 : mapX-1'b1;
                        trackXdist <= trackXdist + stepXdist;
                        side <= 0;
                    end else begin
                        mapY <= ryi ? mapY+1'b1 : mapY-1'b1;
                        trackYdist <= trackYdist + stepYdist;
                        side <= 1;
                    end
                    state <= TEST;
                end
                TEST: begin
                    // Check if we've hit a wall yet.
                    if (map_val!=0) begin
                        // Hit a wall.
                        if (col_counter == 575) begin
                            //NOTE: trace_cycle_count+2 to ensure DONE state will be covered:
                            $display("Frame %d finished tracing after %d clocks", debug_frame, trace_cycle_count+2);
                            $display("\t\t\t\t\t\t\t\t  spriteDist=%f t2=%f spriteCol=%d", `FrealS(spriteDist), `FrealS(t2), spriteCol);
                        end
                        state <= DONE; // Finish the column; advance to next or stop.
                        store <= 1;
                    end else begin
                        // No hit yet; keep going.
                        state <= STEP;
                    end
                end
                DONE: begin
                    // Store is finished.
                    store <= 0;
                    if (col_counter == 575) begin
                        // No more columns to trace; hang here.
                        state <= DONE;
                    end else begin
                        // Start the next column.
                        col_counter <= col_counter + 1'b1;
                        // Advance the ray dir offset (rayAdd) by 1 whole vplane vector value:
                        rayAddX <= rayAddX + vplaneX;
                        rayAddY <= rayAddY + vplaneY;
                        state <= PREP;
                    end
                end
            endcase
        end
    end

endmodule

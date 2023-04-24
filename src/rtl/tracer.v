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

module tracer(
    input               clk,
    input               reset,
    input               enable,             // High when we want the tracer to operate.
    input       `Fixed  playerX,            // Position of the player.
    input       `Fixed  playerY,            //SMELL: Player position must be positive, in fact [0,15]
    input       `Fixed  facingX,            // Vector direction the player is facing.
    input       `Fixed  facingY,            //
    input       `Fixed  vplaneX,            // Viewplane vector.
    input       `Fixed  vplaneY,
    input       [10:0]  debug_frame,

    output reg          store,              // Driven high when we've got a result to store.
    output      [9:0]   column,             // The column we'll write to in the trace_buffer.
    output reg          side,               // The side data we'll write for the respective column.
    output      [7:0]   height,             // The height data we'll write for the column. NOTE: Make sure we only output 1..240

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

    // Implement this in Verilog:
    // https://github.com/algofoogle/raybox-app/blob/22195e6b0482bc0c244ebb3a2c79cb7015d1c713/src/raybox.cpp#L340

    reg [9:0] col_counter;

    //SMELL: Roll these X,Y pairs up into 1 line per vector:
    reg `Int    mapX;           // Map cell we're testing.
    reg `Int    mapY;           //
    reg `Fixed  rayDirX;        // Ray direction vector.
    reg `Fixed  rayDirY;        //
    wire rxi =  (rayDirX>0);    // Is ray X direction positive?
    wire ryi =  (rayDirY>0);    // Is ray Y direction positive?
    reg `Fixed  rayIncX;        // What increment should we add to the ray direction per screen column?
    reg `Fixed  rayIncY;        //
    // trackXdist and trackYdist are not a vector; they're separate trackers
    // for distance travelled along X and Y gridlines:
    reg `Fixed  trackXdist;
    reg `Fixed  trackYdist;

    reg [2:0] state;

    reg hit;

    localparam INIT = 0;
    localparam STEP = 1;
    localparam CHECK = 2;
    localparam DONE = 3;
    localparam STOP = 4;
    localparam DEBUG = 5;
    localparam LCLEAR = 6;
    localparam RCLEAR = 7;

    //SMELL: Should any of these be signed? They should only ever be positive, anyway.
    wire signed [5:0]  playerXint  = playerX[15:`Qn];
    wire signed [5:0]  playerYint  = playerY[15:`Qn];
    wire [15:0] playerXfrac = playerX & 16'b0_00000_1111111111;
    wire [15:0] playerYfrac = playerY & 16'b0_00000_1111111111;
    wire [15:0] partialX    = rxi ? (1<<`Qn)-playerXfrac : playerXfrac;
    wire [15:0] partialY    = ryi ? (1<<`Qn)-playerYfrac : playerYfrac;
    wire [31:0] trackXinit  = {16'b0,stepXdist} * {16'b0,partialX};
    wire [31:0] trackYinit  = {16'b0,stepYdist} * {16'b0,partialY};

    wire `Fixed stepXdist;
    wire `Fixed stepYdist;
    wire satX;
    wire satY;
    wire satHeight;
    //SMELL: To save space, we could have just one reciprocal, and use different
    // states to share it:
    reciprocal flipX        (.i_data(rayDirX),          .i_abs(1), .o_data(stepXdist),  .o_sat(satX));
    reciprocal flipY        (.i_data(rayDirY),          .i_abs(1), .o_data(stepYdist),  .o_sat(satY));
    reciprocal height_scaler(.i_data(visualWallDist),   .i_abs(1), .o_data(heightScale),.o_sat(satHeight));


    assign map_col = mapX[3:0];
    assign map_row = mapY[3:0];

    wire [15:0] visualWallDist = side ? trackYdist-stepYdist : trackXdist-stepXdist;
    wire [15:0] heightScale;
    wire [31:0] wallHeight32 = (heightScale > (1<<`Qn)) ? (240<<`Qn) : 240 * {16'b0,heightScale};
    wire [15:0] wallHeight16 = wallHeight32[25:10];

    assign height = (state == LCLEAR || state == RCLEAR) ? 0 : wallHeight16[7:0];
    assign column = col_counter;

    //SMELL: Stop when map coordinates would wrap.
    wire stopX = satX || stepXdist[14];//stepXdist>(12<<`Qn);//[14];
    wire stopY = satY || stepYdist[14];//stepYdist>(12<<`Qn);//[14];

    //NOTE: To keep this simple for now, I'm going for a screen width of 512,
    // because it makes fixed-point division so much easier.

    always @(posedge clk) begin
        if (reset || !enable) begin
            // Prime the system...
            store <= 0;
            // The values below are starting conditions which are then
            // modified through each iteration, as opposed to values that
            // are recalculated through each iteration.

            col_counter <= 0;
            // col_counter <= (640-512)/2; // For 512w, will range from 64..575

            // Get the initial ray direction (column at screen LHS):
            rayDirX <= facingX - vplaneX;
            rayDirY <= facingY - vplaneY;
            // Divide vplane vector by 256 to get the ray increment per each sreen column
            // when using a 512w render area:
            //SMELL: Do we *need* to register these, or can they just be a wire?
            rayIncX <= vplaneX >> 8;    //NOTE: Verify sign extension happens here.
            rayIncY <= vplaneY >> 8;    //NOTE: Verify sign extension happens here.
            //SMELL: Q6.10 might not have enough precision to do the resolution we want
            // for our rotations, so either we need more precision, or bresenham/DDA approach,
            // or some other way to calculate the ray.
            side <= 0;
            state <= LCLEAR;
        end else begin
            // Oh, we must be enabled (and not in reset) so we're a free-running system now...
            case (state)
                LCLEAR: begin
                    store <= 1;
                    col_counter <= col_counter+1;
                    if (col_counter == 63) begin
                        state <= INIT;
                    end
                end
                INIT: begin
                    if (col_counter == 64) begin
                        $display("Start trace at player X,Y:%f,%f", playerX*`SF, playerY*`SF);
                    end
                    store <= 0;
                    // Get the cell the player's currently in:
                    mapX <= playerXint; //>> `Qn; //fixed2int(playerX);
                    mapY <= playerYint; //>> `Qn; //fixed2int(playerY);
                    //SMELL: Could we get better precision with these trackers, by scaling?
                    //SMELL: Fixed multiplication needs wider registers and truncation to middle bits:
                    trackXdist <= trackXinit[25:10];
                    trackYdist <= trackYinit[25:10];
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
                    if (stopY || (!stopX && trackXdist < trackYdist)) begin
                        mapX <= rxi ? mapX+1 : mapX-1;
                        trackXdist <= trackXdist + stepXdist;
                        side <= 0;
                    end else begin
                        mapY <= ryi ? mapY+1 : mapY-1;
                        trackYdist <= trackYdist + stepYdist;
                        side <= 1;
                    end
                    state <= CHECK;
                end
                CHECK: begin
                    if (map_val!=0) begin
                        // Hit a wall.
                        // $display(
                        //     "HIT:   Frame:%d col:%d X:%d Y:%d trackXdist:%b trackYdist:%b side:%b visualWallDist:%f heightScale:%f wallHeight16:%d",
                        //     debug_frame, col_counter, mapX, mapY, trackXdist, trackYdist, side, visualWallDist*`SF, heightScale*`SF, wallHeight16
                        // );
                        store <= 1;
                        if (col_counter == 575) begin
                            // No more columns to trace.
                            state <= DONE;
                        end else begin
                            // Start the next column.
                            col_counter <= col_counter + 1;
                            rayDirX <= rayDirX + rayIncX;
                            rayDirY <= rayDirY + rayIncY;
                            state <= INIT;
                        end
                    end else begin
                        // No hit yet.
                        state <= STEP;
                    end
                end
                DONE: begin
                    $display("Frame %d, finished tracing at col_counter=%d", debug_frame, col_counter);
                    state <= RCLEAR;
                    store <= 0;
                end
                RCLEAR: begin
                    store <= 1;
                    col_counter <= col_counter+1;
                    if (col_counter == 639) begin
                        state <= STOP;
                        store <= 0;
                    end
                end
            endcase
        end
    end

endmodule

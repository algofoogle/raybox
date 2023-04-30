// Fixed-point reciprocal for Q16.16, adapted from:
// https://github.com/ameetgohil/reciprocal-sv/blob/master/rtl/reciprocal.sv
// See also: https://observablehq.com/@drom/reciprocal-approximation

`default_nettype none
`timescale 1ns / 1ps

//SMELL: If possible, make this work using parameters in fixed_point_params.v:
// `include "fixed_point_params.v"


module reciprocal(
    input   wire [15:-16]   i_data,
    input   wire            i_abs,  // 1=we want the absolute value only.
    output  wire [15:-16]   o_data,
    output  wire            o_sat   // 1=saturated
);

    localparam [5:0] M = 16;

    /*
    Reciprocal Algorithm for numbers in the range [0.5,1)
    a = input
    b = 1.466 - a
    c = a * b;
    d = 1.0012 - c
    e = d * b;
    output = e * 4;
    */

    wire [5:0]      lzc_cnt, rescale_lzc;
    wire [15:-16]   a, b, d, f, reci, sat_data, scale_data;
    wire [31:-32]   rescale_data;
    wire            sign;
    wire [15:-16]   unsigned_data;

    /* verilator lint_off UNUSED */
    wire [31:-32]   c, e;
    /* verilator lint_on UNUSED */

    assign sign = i_data[15];

    assign unsigned_data = sign ? (~i_data + 1'b1) : i_data;

    lzc#(.WIDTH(32)) lzc_inst(.i_data(unsigned_data), .lzc_cnt(lzc_cnt));

    assign rescale_lzc = $signed(M) - $signed(lzc_cnt);

    //scale input data to be b/w .5 and 1 for accurate reciprocal result
    assign scale_data = M >= lzc_cnt ? unsigned_data >>> (M-lzc_cnt): unsigned_data <<< (lzc_cnt - M);

    assign a = scale_data;

    // Find raw fixed-point value representing 1.466:
    // In  Q6.10: 1.466*1024  =  1501(.184) = 0x005DD.
    // In Q16.16: 1.466*65536 = 96075(.776) = 0x1774B (or 0x1774C if rounded UP).
    assign b = 32'h1774B - a;

    assign c = $signed(a) * $signed(b);

    // Find raw fixed-point value representing 1.0012:
    // In  Q6.10: 1.0012*1024  =  1025(.2288) = 0x00401.
    // In Q16.16: 1.0012*65536 = 65614(.6432) = 0x1004E (or 0x1004F if rounded UP).
    assign d = 32'h1004E - $signed(c[15:-16]);

    assign e = $signed(d) * $signed(b);

    assign f = e[15:-16];

    //SMELL: Double-check this f[15:14]. I think it makes sense,
    // because these are the bits that would overflow if multiplied by 4 (i.e. SHL-2):
    assign reci = |f[15:14] ? 32'h7FFF_FFFF : f << 2; //saturation detection and (e*4)

    //rescale reci by the lzc factor
    //SMELL: Double-check this [5]; it was [4] for Q6.10, so I'm not sure how it works.
    // I think it's testing whether our rescale factor is NEGATIVE, so this would be correct as the sign bit...?
    assign rescale_data =
        rescale_lzc[5] ?    {32'b0,reci} << (~rescale_lzc + 1'b1) :
                            {32'b0,reci} >> rescale_lzc;

    //Saturation logic
    //SMELL: Double-check our bit range here. In the original, the check was against [31:15], which is 17 bits,
    // but I feel like it was meant to be 16 bits (i.e. [31:16]).
    assign o_sat = |rescale_data[31:0]; // If any upper bits are used, we've overflowed, so saturate.
    assign sat_data = o_sat ? 32'h7FFF_FFFF : rescale_data[-1:-32];

    assign o_data = (sign && !i_abs) ? (~sat_data + 1'b1) : sat_data;

endmodule

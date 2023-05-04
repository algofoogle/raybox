// Fixed-point reciprocal for Q16.16, adapted from:
// https://github.com/ameetgohil/reciprocal-sv/blob/master/rtl/reciprocal.sv
// See also: https://observablehq.com/@drom/reciprocal-approximation

`default_nettype none
`timescale 1ns / 1ps

//SMELL: If possible, make this work using parameters in fixed_point_params.v:
// `include "fixed_point_params.v"

//`define LZC_TYPE_A  //SMELL: lzc_a is currently hardcoded to 32-bit.
`define LZC_TYPE_B
//`define LZC_TYPE_C
//`define LZC_TYPE_D

module reciprocal #(
    parameter [6:0] M = 16,         // Integer bits, inc. sign.
    parameter       N = 16          // Fractional bits.
)(
    input   wire [M-1:-N]   i_data,
    input   wire            i_abs,  // 1=we want the absolute value only.
    output  wire [M-1:-N]   o_data,
    output  wire            o_sat   // 1=saturated
);
/* verilator lint_off REALCVT */
    `define ROUNDING_FIX -0.5
    // Find raw fixed-point value representing 1.466:
    // In  Q6.10: 1.466*1024  =  1501(.184) = 0x005DD.
    // In Q16.16: 1.466*65536 = 96075(.776) = 0x1774B (or 0x1774C if rounded UP).
    // localparam integer nb = 1.466*(2.0**N);
    
    //SMELL: Wackiness to work around Quartus bug: https://community.intel.com/t5/Intel-Quartus-Prime-Software/BUG/td-p/1483047
    localparam SCALER = 1<<N;
    localparam real FSCALER = SCALER;
    
    localparam [M-1:-N] n1466 = 1.466*FSCALER+`ROUNDING_FIX; //'h1774B;      // 1.466 in QM.N

    // Find raw fixed-point value representing 1.0012:
    // In  Q6.10: 1.0012*1024  =  1025(.2288) = 0x00401.
    // In Q16.16: 1.0012*65536 = 65614(.6432) = 0x1004E (or 0x1004F if rounded UP).
    // localparam integer nd = 1.0012*(2.0**N);
    localparam [M-1:-N] n10012 = 1.0012*FSCALER+`ROUNDING_FIX; //'h1004E;      // 1.0012 in QM.N
/* verilator lint_on REALCVT */

    localparam [M-1:-N] nSat = ~(1<<(M+N-1)); //'h7FFF_FFFF, if Q16.16;  // Max positive integer (i.e. saturation).

    localparam S = M-1; // Sign bit (top-most bit index too).
    // localparam [5:0] M = 16;

    initial begin
        //NOTE: In Quartus, at compile-time, this should hopefully spit out the params from above
        // in the compilation log:
        $display("reciprocal params for Q%0d.%0d:  n1466=%X, n10012=%X, nSat=%X", M, N, n1466, n10012, nSat);
    end


    /*
    Reciprocal Algorithm for numbers in the range [0.5,1)
    a = input
    b = 1.466 - a
    c = a * b;
    d = 1.0012 - c
    e = d * b;
    output = e * 4;
    */

    wire [6:0]          lzc_cnt, rescale_lzc; //SMELL: These should be sized per M+N; extra bit is for sign?? Is that necessary? See `rescale_data`.
    wire [S:-N]         a, b, d, f, reci, sat_data, scale_data;
    wire [M*2-1:-N*2]   rescale_data; // Double the size of [S:-N], i.e. size of 2 full fixed-point numbers, i.e. their product. //SMELL: FIXME: Should be [M*2-1:-N*2]? For 10.16 => 19:-32
    wire                sign;
    wire [S:-N]         unsigned_data;

    /* verilator lint_off UNUSED */
    wire [M*2-1:-N*2]   c, e;
    /* verilator lint_on UNUSED */

    assign sign = i_data[S];

    assign unsigned_data = sign ? (~i_data + 1'b1) : i_data;

`ifdef LZC_TYPE_A
    lzc_a #(.WIDTH(M+N)) lzc_inst(.i_data(unsigned_data), .lzc_cnt(lzc_cnt)); // TEST TYPE A

`elsif LZC_TYPE_B
    lzc_b #(.WIDTH(M+N)) lzc_inst(.i_data(unsigned_data), .lzc_cnt(lzc_cnt)); // TEST TYPE B

`elsif LZC_TYPE_C
    lzc_c #(.WIDTH(M+N)) lzc_inst(.i_data(unsigned_data), .lzc_cnt(lzc_cnt)); // TEST TYPE C

`elsif LZC_TYPE_D
    lzc_d #(.WIDTH(32)) lzc_inst(.i_data({unsigned_data, {(32-`Qm-`Qn){1'b1}} }), .lzc_cnt(lzc_cnt)); // TEST TYPE D
    //NOTE: Type D needs WIDTH to be a power of 2; if we use fewer `F bits, then LSBs are padded with 1. This keeps the range normal, in 0..(`Qm+`Qn).
`endif

    assign rescale_lzc = $signed(M) - $signed(lzc_cnt); //SMELL: rescale_lzc and lzc_cnt are both 7 bits; could there be a sign problem??

    // Scale input data to be between .5 and 1 for accurate reciprocal result
    assign scale_data =
        M >= lzc_cnt ?  // Is our leading digit within the integer part?
                        unsigned_data >>> (M-lzc_cnt) : // Yes: Scale magnitude down to [0.5,1) range.
                        unsigned_data <<< (lzc_cnt-M);  // No: Scale magnitude up to [0.5,1) range.

    assign a = scale_data;

    assign b = n1466 - a;

    assign c = $signed(a) * $signed(b);

    assign d = n10012 - $signed(c[S:-N]);

    assign e = $signed(d) * $signed(b);

    assign f = e[S:-N];

    // [M-1:M-2] are the bits that would overflow if multiplied by 4 (i.e. SHL-2):
    assign reci = |f[M-1:M-2] ? nSat : f << 2; //saturation detection and (e*4)
    //SMELL: I think we could keep 2 extra bits of precision if we didn't simply do f<<2,
    // but rather extracted a shifted bit range from `e`.

    // Rescale reciprocal by the lzc factor
    //SMELL: Double-check this [6]; it was [4] for Q6.10, so I'm not sure how it works.
    // I think it's testing whether our rescale factor is NEGATIVE, so this would be correct as the sign bit...?
    assign rescale_data =
        rescale_lzc[6] ? { {(M+N){1'b0}}, reci} << (~rescale_lzc + 1'b1) :
                         { {(M+N){1'b0}}, reci} >> rescale_lzc;

    //Saturation logic
    //SMELL: Double-check our bit range here. In the original, the check was against [31:15], which is 17 bits,
    // but I feel like it was meant to be 16 bits (i.e. [31:16]).
    assign o_sat = |rescale_data[M*2-1:M-N]; // If any upper bits are used, we've overflowed, so saturate. //SMELL: FIXME: For 10.16, should be 26 bits [19:-6]??
    assign sat_data = o_sat ? nSat : rescale_data[M-N-1:-N*2];  //SMELL: FIXME: For 10.16, should be 26 bits [-7:-32]??

    assign o_data = (sign && !i_abs) ? (~sat_data + 1'b1) : sat_data;

endmodule

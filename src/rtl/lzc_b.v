/*** lzc_b: Leading Zeroes Counter, type B

This is a dumb LZC that uses a giant casez statement to count leading zeroes,
and is basically the same as type A but reshuffled/extended slightly.

Read the notes for lzc_a for more info.

See also: lzc_c and _d.

***/

`undef SZ
`define SZ  24  //SMELL: This should match WIDTH, i.e. `Qm+`Qn

module lzc_b #(
/* verilator lint_off WIDTH */
    parameter [6:0] WIDTH=`SZ
/* verilator lint_on WIDTH */
)(
    input   [WIDTH-1:0] i_data,
    output  [6:0]       lzc_cnt  // 0..64
);

    function [6:0] f_lzc(input [WIDTH-1:0] data);
        if (WIDTH>64 || WIDTH<1) begin
            $error("lzc_b module only designed to support 1..64 inputs but you want: %1d", WIDTH);
        end
        if (WIDTH!=`SZ) begin
            $error("lzc_b module is currently hardcoded to expect a WIDTH of %1d, but you want: %1d", `SZ, WIDTH);
        end

        //HINT!!!
        //HINT: After matching SZ to your desired WIDTH, comment out the higher-up lines you don't need:
        //HINT!!!

        casez(data)
            // `SZ'b1???????????????????????????????????????????????????????????????:  f_lzc = WIDTH - 64;
            // `SZ'b01??????????????????????????????????????????????????????????????:  f_lzc = WIDTH - 63;
            // `SZ'b001?????????????????????????????????????????????????????????????:  f_lzc = WIDTH - 62;
            // `SZ'b0001????????????????????????????????????????????????????????????:  f_lzc = WIDTH - 61;
            // `SZ'b00001???????????????????????????????????????????????????????????:  f_lzc = WIDTH - 60;
            // `SZ'b000001??????????????????????????????????????????????????????????:  f_lzc = WIDTH - 59;
            // `SZ'b0000001?????????????????????????????????????????????????????????:  f_lzc = WIDTH - 58;
            // `SZ'b00000001????????????????????????????????????????????????????????:  f_lzc = WIDTH - 57;
            // `SZ'b000000001???????????????????????????????????????????????????????:  f_lzc = WIDTH - 56;
            // `SZ'b0000000001??????????????????????????????????????????????????????:  f_lzc = WIDTH - 55;
            // `SZ'b00000000001?????????????????????????????????????????????????????:  f_lzc = WIDTH - 54;
            // `SZ'b000000000001????????????????????????????????????????????????????:  f_lzc = WIDTH - 53;
            // `SZ'b0000000000001???????????????????????????????????????????????????:  f_lzc = WIDTH - 52;
            // `SZ'b00000000000001??????????????????????????????????????????????????:  f_lzc = WIDTH - 51;
            // `SZ'b000000000000001?????????????????????????????????????????????????:  f_lzc = WIDTH - 50;
            // `SZ'b0000000000000001????????????????????????????????????????????????:  f_lzc = WIDTH - 49;
            // `SZ'b00000000000000001???????????????????????????????????????????????:  f_lzc = WIDTH - 48;
            // `SZ'b000000000000000001??????????????????????????????????????????????:  f_lzc = WIDTH - 47;
            // `SZ'b0000000000000000001?????????????????????????????????????????????:  f_lzc = WIDTH - 46;
            // `SZ'b00000000000000000001????????????????????????????????????????????:  f_lzc = WIDTH - 45;
            // `SZ'b000000000000000000001???????????????????????????????????????????:  f_lzc = WIDTH - 44;
            // `SZ'b0000000000000000000001??????????????????????????????????????????:  f_lzc = WIDTH - 43;
            // `SZ'b00000000000000000000001?????????????????????????????????????????:  f_lzc = WIDTH - 42;
            // `SZ'b000000000000000000000001????????????????????????????????????????:  f_lzc = WIDTH - 41;
            // `SZ'b0000000000000000000000001???????????????????????????????????????:  f_lzc = WIDTH - 40;
            // `SZ'b00000000000000000000000001??????????????????????????????????????:  f_lzc = WIDTH - 39;
            // `SZ'b000000000000000000000000001?????????????????????????????????????:  f_lzc = WIDTH - 38;
            // `SZ'b0000000000000000000000000001????????????????????????????????????:  f_lzc = WIDTH - 37;
            // `SZ'b00000000000000000000000000001???????????????????????????????????:  f_lzc = WIDTH - 36;
            // `SZ'b000000000000000000000000000001??????????????????????????????????:  f_lzc = WIDTH - 35;
            // `SZ'b0000000000000000000000000000001?????????????????????????????????:  f_lzc = WIDTH - 34;
            // `SZ'b00000000000000000000000000000001????????????????????????????????:  f_lzc = WIDTH - 33;
            // `SZ'b000000000000000000000000000000001???????????????????????????????:  f_lzc = WIDTH - 32; // Comment lines ABOVE here if your WIDTH is 32 (Q16.16)
            // `SZ'b0000000000000000000000000000000001??????????????????????????????:  f_lzc = WIDTH - 31;
            // `SZ'b00000000000000000000000000000000001?????????????????????????????:  f_lzc = WIDTH - 30;
            // `SZ'b000000000000000000000000000000000001????????????????????????????:  f_lzc = WIDTH - 29;
            // `SZ'b0000000000000000000000000000000000001???????????????????????????:  f_lzc = WIDTH - 28;
            // `SZ'b00000000000000000000000000000000000001??????????????????????????:  f_lzc = WIDTH - 27;
            // `SZ'b000000000000000000000000000000000000001?????????????????????????:  f_lzc = WIDTH - 26;
            // `SZ'b0000000000000000000000000000000000000001????????????????????????:  f_lzc = WIDTH - 25;
            `SZ'b00000000000000000000000000000000000000001???????????????????????:  f_lzc = WIDTH - 24; // Comment lines ABOVE here if your WIDTH is 24 (Q12.12)
            `SZ'b000000000000000000000000000000000000000001??????????????????????:  f_lzc = WIDTH - 23;
            `SZ'b0000000000000000000000000000000000000000001?????????????????????:  f_lzc = WIDTH - 22;
            `SZ'b00000000000000000000000000000000000000000001????????????????????:  f_lzc = WIDTH - 21;
            `SZ'b000000000000000000000000000000000000000000001???????????????????:  f_lzc = WIDTH - 20; // Comment lines ABOVE here if your WIDTH is 20 (Q11.9)
            `SZ'b0000000000000000000000000000000000000000000001??????????????????:  f_lzc = WIDTH - 19;
            `SZ'b00000000000000000000000000000000000000000000001?????????????????:  f_lzc = WIDTH - 18;
            `SZ'b000000000000000000000000000000000000000000000001????????????????:  f_lzc = WIDTH - 17;
            `SZ'b0000000000000000000000000000000000000000000000001???????????????:  f_lzc = WIDTH - 16;
            `SZ'b00000000000000000000000000000000000000000000000001??????????????:  f_lzc = WIDTH - 15;
            `SZ'b000000000000000000000000000000000000000000000000001?????????????:  f_lzc = WIDTH - 14;
            `SZ'b0000000000000000000000000000000000000000000000000001????????????:  f_lzc = WIDTH - 13;
            `SZ'b00000000000000000000000000000000000000000000000000001???????????:  f_lzc = WIDTH - 12;
            `SZ'b000000000000000000000000000000000000000000000000000001??????????:  f_lzc = WIDTH - 11;
            `SZ'b0000000000000000000000000000000000000000000000000000001?????????:  f_lzc = WIDTH - 10;
            `SZ'b00000000000000000000000000000000000000000000000000000001????????:  f_lzc = WIDTH -  9;
            `SZ'b000000000000000000000000000000000000000000000000000000001???????:  f_lzc = WIDTH -  8;
            `SZ'b0000000000000000000000000000000000000000000000000000000001??????:  f_lzc = WIDTH -  7;
            `SZ'b00000000000000000000000000000000000000000000000000000000001?????:  f_lzc = WIDTH -  6;
            `SZ'b000000000000000000000000000000000000000000000000000000000001????:  f_lzc = WIDTH -  5;
            `SZ'b0000000000000000000000000000000000000000000000000000000000001???:  f_lzc = WIDTH -  4;
            `SZ'b00000000000000000000000000000000000000000000000000000000000001??:  f_lzc = WIDTH -  3;
            `SZ'b000000000000000000000000000000000000000000000000000000000000001?:  f_lzc = WIDTH -  2;
            `SZ'b0000000000000000000000000000000000000000000000000000000000000001:  f_lzc = WIDTH -  1;
            `SZ'b0000000000000000000000000000000000000000000000000000000000000000:  f_lzc = WIDTH -  0;
        endcase

    endfunction

    assign lzc_cnt = f_lzc(i_data);

endmodule

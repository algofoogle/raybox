// Leading Zeroes Counter logic, borrowed from:
// https://github.com/ameetgohil/leading-zeroes-counter/blob/master/rtl/lzc.sv
// ...then fudged to just be Verilog (instead of SystemVerilog) and work with 32-bit input only.


module lzc #(
    parameter WIDTH=32
)(
    input   [WIDTH-1:0] i_data,
    output  [6:0]       lzc_cnt
);

    function [6:0] f_lzc(input [WIDTH-1:0] data);
        if (WIDTH>32 || WIDTH<1) begin
            $error("lzc module only designed to support inputs up to 32 bits, but you want: ", WIDTH);
        end
        //SMELL: YUCK! What a horrible way to do this.
        // If possible, try to use a generator or something instead,
        // and consider treating this like a tree so it doesn't become
        // just one huge logic chain:
        // https://electronics.stackexchange.com/questions/196914/verilog-synthesize-high-speed-leading-zero-count
                if (            data[WIDTH- 1]) f_lzc =  0; // No zeroes.
        else    if (WIDTH>1  && data[WIDTH- 2]) f_lzc =  1;
        else    if (WIDTH>2  && data[WIDTH- 3]) f_lzc =  2;
        else    if (WIDTH>3  && data[WIDTH- 4]) f_lzc =  3;
        else    if (WIDTH>4  && data[WIDTH- 5]) f_lzc =  4;
        else    if (WIDTH>5  && data[WIDTH- 6]) f_lzc =  5;
        else    if (WIDTH>6  && data[WIDTH- 7]) f_lzc =  6;
        else    if (WIDTH>7  && data[WIDTH- 8]) f_lzc =  7;
        else    if (WIDTH>8  && data[WIDTH- 9]) f_lzc =  8;
        else    if (WIDTH>9  && data[WIDTH-10]) f_lzc =  9;
        else    if (WIDTH>10 && data[WIDTH-11]) f_lzc = 10;
        else    if (WIDTH>11 && data[WIDTH-12]) f_lzc = 11;
        else    if (WIDTH>12 && data[WIDTH-13]) f_lzc = 12;
        else    if (WIDTH>13 && data[WIDTH-14]) f_lzc = 13;
        else    if (WIDTH>14 && data[WIDTH-15]) f_lzc = 14;
        else    if (WIDTH>15 && data[WIDTH-16]) f_lzc = 15;
        else    if (WIDTH>16 && data[WIDTH-17]) f_lzc = 16;
        else    if (WIDTH>17 && data[WIDTH-18]) f_lzc = 17;
        else    if (WIDTH>18 && data[WIDTH-19]) f_lzc = 18;
        else    if (WIDTH>19 && data[WIDTH-20]) f_lzc = 19;
        else    if (WIDTH>20 && data[WIDTH-21]) f_lzc = 20;
        else    if (WIDTH>21 && data[WIDTH-22]) f_lzc = 21;
        else    if (WIDTH>22 && data[WIDTH-23]) f_lzc = 22;
        else    if (WIDTH>23 && data[WIDTH-24]) f_lzc = 23;
        else    if (WIDTH>24 && data[WIDTH-25]) f_lzc = 24;
        else    if (WIDTH>25 && data[WIDTH-26]) f_lzc = 25;
        else    if (WIDTH>26 && data[WIDTH-27]) f_lzc = 26;
        else    if (WIDTH>27 && data[WIDTH-28]) f_lzc = 27;
        else    if (WIDTH>28 && data[WIDTH-29]) f_lzc = 28;
        else    if (WIDTH>29 && data[WIDTH-30]) f_lzc = 29;
        else    if (WIDTH>30 && data[WIDTH-31]) f_lzc = 30;
        else    if (WIDTH>31 && data[WIDTH-32]) f_lzc = 31;
/* verilator lint_off WIDTH */
        else                                    f_lzc = WIDTH;
/* verilator lint_on WIDTH */

        // casez(data)
        //     32'b0:                                  f_lzc = 32;
        //     32'b1:                                  f_lzc = 31;
        //     32'b1?:                                 f_lzc = 30;
        //     32'b1??:                                f_lzc = 29;
        //     32'b1???:                               f_lzc = 28;
        //     32'b1????:                              f_lzc = 27;
        //     32'b1?????:                             f_lzc = 26;
        //     32'b1??????:                            f_lzc = 25;
        //     32'b1???????:                           f_lzc = 24;
        //     32'b1????????:                          f_lzc = 23;
        //     32'b1?????????:                         f_lzc = 22;
        //     32'b1??????????:                        f_lzc = 21;
        //     32'b1???????????:                       f_lzc = 20;
        //     32'b1????????????:                      f_lzc = 19;
        //     32'b1?????????????:                     f_lzc = 18;
        //     32'b1??????????????:                    f_lzc = 17;
        //     32'b1???????????????:                   f_lzc = 16;
        //     32'b1????????????????:                  f_lzc = 15;
        //     32'b1?????????????????:                 f_lzc = 14;
        //     32'b1??????????????????:                f_lzc = 13;
        //     32'b1???????????????????:               f_lzc = 12;
        //     32'b1????????????????????:              f_lzc = 11;
        //     32'b1?????????????????????:             f_lzc = 10;
        //     32'b1??????????????????????:            f_lzc = 9;
        //     32'b1???????????????????????:           f_lzc = 8;
        //     32'b1????????????????????????:          f_lzc = 7;
        //     32'b1?????????????????????????:         f_lzc = 6;
        //     32'b1??????????????????????????:        f_lzc = 5;
        //     32'b1???????????????????????????:       f_lzc = 4;
        //     32'b1????????????????????????????:      f_lzc = 3;
        //     32'b1?????????????????????????????:     f_lzc = 2;
        //     32'b1??????????????????????????????:    f_lzc = 1;
        //     default:                                f_lzc = 0;
        // endcase
    endfunction

    assign lzc_cnt = f_lzc(i_data);

endmodule




//module lzc#(int WIDTH=8)
//  (input wire[WIDTH-1:0] i_data,
//   output wire [$clog2(WIDTH):0] lzc_cnt
//   );
//
//   wire       allzeroes;
//
//   function bit f(bit[WIDTH-1:0] x, int size);
//      bit                        jval = 0;
//      bit                        ival = 0;
//
//      for(int i = 1; i < size; i+=2) begin
//         jval = 1;
//         for(int j = i+1; j < size; j+=2) begin
//            jval &= ~x[j];
//         end
//         ival |= jval & x[i];
//      end
//
//      return ival;
//
//   endfunction // f
//
//   function bit[WIDTH-1:0] f_input(bit[WIDTH-1:0] x, int stage );
//      bit[WIDTH-1:0] dout = 0;
//      int            stagePow2 = 2**stage;
//      int            j=0;
//      for(int i=0; i<WIDTH; i++) begin
//         dout[j] |= x[i];
//         if(i % stagePow2 == stagePow2 - 1)
//           j++;
//      end
//      return dout;
//   endfunction
//
//   genvar i;
//
//   assign allzeroes = ~(|i_data);
//
//   assign lzc_cnt[$clog2(WIDTH)] = allzeroes;
//
//   generate
//      for(i=0; i < $clog2(WIDTH); i++) begin
//         assign lzc_cnt[i] = ~allzeroes & ~f(f_input(i_data, i),WIDTH);
//      end
//   endgenerate
//
//endmodule

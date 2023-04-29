// Leading Zeroes Counter logic, borrowed from:
// https://github.com/ameetgohil/leading-zeroes-counter/blob/master/rtl/lzc.sv
// ...then fudged to just be Verilog (instead of SystemVerilog) and work with 16-bit input only.


module lzc #(
    parameter WIDTH=16 //SMELL: Not used.
)(
    input   [15:0]  i_data,
    output   [4:0]  lzc_cnt
);

    function [4:0] f_lzc(input [15:0] data);
        casez(data)
            16'b0000000000000000:   f_lzc = 16;
            16'b0000000000000001:   f_lzc = 15;
            16'b000000000000001?:   f_lzc = 14;
            16'b00000000000001??:   f_lzc = 13;
            16'b0000000000001???:   f_lzc = 12;
            16'b000000000001????:   f_lzc = 11;
            16'b00000000001?????:   f_lzc = 10;
            16'b0000000001??????:   f_lzc = 9;
            16'b000000001???????:   f_lzc = 8;
            16'b00000001????????:   f_lzc = 7;
            16'b0000001?????????:   f_lzc = 6;
            16'b000001??????????:   f_lzc = 5;
            16'b00001???????????:   f_lzc = 4;
            16'b0001????????????:   f_lzc = 3;
            16'b001?????????????:   f_lzc = 2;
            16'b01??????????????:   f_lzc = 1;
            default:                f_lzc = 0;
        endcase
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

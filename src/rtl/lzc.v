// Leading Zeroes Counter logic, borrowed from:
// https://github.com/ameetgohil/leading-zeroes-counter/blob/master/rtl/lzc.sv

module lzc#(int WIDTH=8)
  (input wire[WIDTH-1:0] i_data,
   output wire [$clog2(WIDTH):0] lzc_cnt
   );

   wire       allzeroes;

   function bit f(bit[WIDTH-1:0] x, int size);
      bit                        jval = 0;
      bit                        ival = 0;

      for(int i = 1; i < size; i+=2) begin
         jval = 1;
         for(int j = i+1; j < size; j+=2) begin
            jval &= ~x[j];
         end
         ival |= jval & x[i];
      end

      return ival;

   endfunction // f

   function bit[WIDTH-1:0] f_input(bit[WIDTH-1:0] x, int stage );
      bit[WIDTH-1:0] dout = 0;
      int            stagePow2 = 2**stage;
      int            j=0;
      for(int i=0; i<WIDTH; i++) begin
         dout[j] |= x[i];
         if(i % stagePow2 == stagePow2 - 1)
           j++;
      end
      return dout;
   endfunction

   genvar i;

   assign allzeroes = ~(|i_data);

   assign lzc_cnt[$clog2(WIDTH)] = allzeroes;

   generate
      for(i=0; i < $clog2(WIDTH); i++) begin
         assign lzc_cnt[i] = ~allzeroes & ~f(f_input(i_data, i),WIDTH);
      end
   endgenerate

endmodule

/*** lzc_d: Leading Zeroes Counter, type D

This is a smart LZC that uses SystemVerilog features, and I think uses a balanced tree
approach for better timing.

See also: lzc_a, _b, and _c.

This is a hacked version of what I found here:
https://github.com/ameetgohil/leading-zeroes-counter/blob/master/rtl/lzc.sv

It's VERY slow in Verilator, and I haven't been able to get it to work on my FPGA yet.

There are possibly a couple of problems to resolve for FPGA targets:
-   Are the input/output sizes sensible, and implemented properly?
-   Per instructions on the original:
    https://github.com/ameetgohil/leading-zeroes-counter/tree/master
    ...this only works as-is for a WIDTH that is a power of 2, unless you
    use the padding method provided (which I haven't tried yet).

NOTE: This might use a segmented method similar to what's described here:
https://electronics.stackexchange.com/questions/196914/verilog-synthesize-high-speed-leading-zero-count

NOTE: output (lzc_cnt) is 7 bits wide, because I'm working on the assumption that supporting up to
64-bit inputs might be required, and hence the count output needs to range from 0..64, which requires
7 bits.

***/

`define SMART_LZC_COUNT_WIDTH  7
// If defined, SMART_LZC_COUNT_WIDTH explicitly sets the smart LZC count output width to this number of bits.
// If not defined, the code chooses itself based on WIDTH.

module lzc_d #(int WIDTH=8)
  (input wire[WIDTH-1:0] i_data,
`ifdef SMART_LZC_COUNT_WIDTH
    output wire [`SMART_LZC_COUNT_WIDTH-1:0] lzc_cnt
`else
    output wire [$clog2(WIDTH):0] lzc_cnt
`endif
    );

    wire       allzeroes;

    // f()
    function bit f(bit[WIDTH-1:0] x, int size);
        bit jval = 0;
        bit ival = 0;

        for(int i = 1; i < size; i+=2) begin
            jval = 1;
            for(int j = i+1; j < size; j+=2) begin
                jval &= ~x[j];
            end
            ival |= jval & x[i];
        end

        return ival;

    endfunction // f()

    // f_input()
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
    endfunction // f_input()

    genvar i;

    assign allzeroes = ~(|i_data);

`ifdef SMART_LZC_COUNT_WIDTH
    generate
        for(i=0; i < `SMART_LZC_COUNT_WIDTH; i++) begin : ASSIGN_COUNT_BITS
                if (i < $clog2(WIDTH))
                    assign lzc_cnt[i] = ~allzeroes & ~f(f_input(i_data, i),WIDTH);
                else if (i == $clog2(WIDTH))
                    assign lzc_cnt[$clog2(WIDTH)] = allzeroes;
                else
                    assign lzc_cnt[i] = 0;
        end
    endgenerate
`else
    assign lzc_cnt[$clog2(WIDTH)] = allzeroes;

    generate
        for(i=0; i < $clog2(WIDTH); i++) begin : ASSIGN_COUNT_BITS
            assign lzc_cnt[i] = ~allzeroes & ~f(f_input(i_data, i),WIDTH);
        end
    endgenerate
`endif

endmodule

`default_nettype none
`timescale 1ns / 1ps

module map_rom_tb;
    reg  [3:0] row;
    reg  [3:0] col;
    wire [1:0] val;

    initial begin
        #1 col=13; row=13; #1 $display("Map cell at (%d,%d)=%d", col, row, val);
        #1 col=14; row=13; #1 $display("Map cell at (%d,%d)=%d", col, row, val);
        #1 col=15; row=13; #1 $display("Map cell at (%d,%d)=%d", col, row, val);
        #1 col=13; row=14; #1 $display("Map cell at (%d,%d)=%d", col, row, val);
        #1 col=14; row=14; #1 $display("Map cell at (%d,%d)=%d", col, row, val);
        #1 col=15; row=14; #1 $display("Map cell at (%d,%d)=%d", col, row, val);
        #1 col=13; row=15; #1 $display("Map cell at (%d,%d)=%d", col, row, val);
        #1 col=14; row=15; #1 $display("Map cell at (%d,%d)=%d", col, row, val);
        #1 col=15; row=15; #1 $display("Map cell at (%d,%d)=%d", col, row, val);
        $display("Done");
        $finish;
    end

    map_rom uut(.row(row), .col(col), .val(val));
endmodule

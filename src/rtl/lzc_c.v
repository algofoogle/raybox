/*** lzc_c: Leading Zeroes Counter, type C

This is a dumb LZC that uses a giant if-else-if chain to count leading zeroes.

See also: lzc_a, _b, and _d.

This type was found to run fast in Verilator, and it synthesises in Quartus, but I haven't
yet been able to verify if it works on my DE0-Nano (Cyclone IV) FPGA board.

This is probably the worst one I've come up with so far, but so long as you comment out
the cases that are beyond your needs (and bit depth) it will at least be supported by
pretty much anything. The problem remains: It works in Verilator, but not on my FPGA.
That could be a timing issue; not sure yet.

***/

`undef SZ
`define SZ  24  //SMELL: This should match WIDTH.

module lzc_c #(
    parameter WIDTH=`SZ
)(
    input   [WIDTH-1:0] i_data,
    output  [6:0]       lzc_cnt
);

    function [6:0] f_lzc(input [WIDTH-1:0] data);
        if (WIDTH>64 || WIDTH<1) begin
            $error("lzc module only designed to support 1..64 inputs but you want: %1d", WIDTH);
        end
        if (WIDTH!=`SZ) begin
            $error("lzc_b module is currently hardcoded to expect a WIDTH of %1d, but you want: %1d", `SZ, WIDTH);
        end

        //SMELL: YUCK! What a horrible way to do this.

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
        else    if (WIDTH>23 && data[WIDTH-24]) f_lzc = 23; //NOTE: Final case (24) is in the bottom `else`.
//        else    if (WIDTH>24 && data[WIDTH-25]) f_lzc = 24;
//        else    if (WIDTH>25 && data[WIDTH-26]) f_lzc = 25;
//        else    if (WIDTH>26 && data[WIDTH-27]) f_lzc = 26;
//        else    if (WIDTH>27 && data[WIDTH-28]) f_lzc = 27;
//        else    if (WIDTH>28 && data[WIDTH-29]) f_lzc = 28;
//        else    if (WIDTH>29 && data[WIDTH-30]) f_lzc = 29;
//        else    if (WIDTH>30 && data[WIDTH-31]) f_lzc = 30;
//        else    if (WIDTH>31 && data[WIDTH-32]) f_lzc = 31;
//        else    if (WIDTH>32 && data[WIDTH-33]) f_lzc = 32;
//        else    if (WIDTH>33 && data[WIDTH-34]) f_lzc = 33;
//        else    if (WIDTH>34 && data[WIDTH-35]) f_lzc = 34;
//        else    if (WIDTH>35 && data[WIDTH-36]) f_lzc = 35;
//        else    if (WIDTH>36 && data[WIDTH-37]) f_lzc = 36;
//        else    if (WIDTH>37 && data[WIDTH-38]) f_lzc = 37;
//        else    if (WIDTH>38 && data[WIDTH-39]) f_lzc = 38;
//        else    if (WIDTH>39 && data[WIDTH-40]) f_lzc = 39;
//        else    if (WIDTH>40 && data[WIDTH-41]) f_lzc = 40;
//        else    if (WIDTH>41 && data[WIDTH-42]) f_lzc = 41;
//        else    if (WIDTH>42 && data[WIDTH-43]) f_lzc = 42;
//        else    if (WIDTH>43 && data[WIDTH-44]) f_lzc = 43;
//        else    if (WIDTH>44 && data[WIDTH-45]) f_lzc = 44;
//        else    if (WIDTH>45 && data[WIDTH-46]) f_lzc = 45;
//        else    if (WIDTH>46 && data[WIDTH-47]) f_lzc = 46;
//        else    if (WIDTH>47 && data[WIDTH-48]) f_lzc = 47;
//        else    if (WIDTH>48 && data[WIDTH-49]) f_lzc = 48;
//        else    if (WIDTH>49 && data[WIDTH-50]) f_lzc = 49;
//        else    if (WIDTH>50 && data[WIDTH-51]) f_lzc = 50;
//        else    if (WIDTH>51 && data[WIDTH-52]) f_lzc = 51;
//        else    if (WIDTH>52 && data[WIDTH-53]) f_lzc = 52;
//        else    if (WIDTH>53 && data[WIDTH-54]) f_lzc = 53;
//        else    if (WIDTH>54 && data[WIDTH-55]) f_lzc = 54;
//        else    if (WIDTH>55 && data[WIDTH-56]) f_lzc = 55;
//        else    if (WIDTH>56 && data[WIDTH-57]) f_lzc = 56;
//        else    if (WIDTH>57 && data[WIDTH-58]) f_lzc = 57;
//        else    if (WIDTH>58 && data[WIDTH-59]) f_lzc = 58;
//        else    if (WIDTH>59 && data[WIDTH-60]) f_lzc = 59;
//        else    if (WIDTH>60 && data[WIDTH-61]) f_lzc = 60;
//        else    if (WIDTH>61 && data[WIDTH-62]) f_lzc = 61;
//        else    if (WIDTH>62 && data[WIDTH-63]) f_lzc = 62;
//        else    if (WIDTH>63 && data[WIDTH-64]) f_lzc = 63;
/* verilator lint_off WIDTH */
        else                                    f_lzc = WIDTH;
/* verilator lint_on WIDTH */

    endfunction

    assign lzc_cnt = f_lzc(i_data);

endmodule


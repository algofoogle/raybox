`ifndef _FIXED_POINT_PARAMS__H_
`define _FIXED_POINT_PARAMS__H_
`define Qm      6                   // Number of fixed point integer bits (per Qm.n)
`define Qn      10                  // Number of fixed point fraction bits
`define Qmn     (`Qm+`Qn)           // Total bits in our fixed point format
`define Fixed   signed [`Qmn-1:0]   // I'll try signed Q6.10 for my fixed-point numbers, for now.
`define Int     signed [`Qm-1:0]    // Can hold a truncated (floored) integer value from one of our fixed point values.
// `define fixedFloor(f) f[`Qmn-1:`Qn] // Extracts the integer part from a Fixed value.
// `define fixedFrac(f) {f[`Qmn-1],f[`Qn-1:0]}
// `define fixed2int(n)   
`define SF      (2.0**-`Qn)         // Q6.10 scaling factor is 2^-10. Used for test prints as real numbers.
//NOTE: Range of Q6.10 is -32.0 to 31.999023438, with a precision of 1/1024 (or 0.000976562).
`endif //_FIXED_POINT_PARAMS__H_

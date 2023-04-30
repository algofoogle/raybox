`ifndef _FIXED_POINT_PARAMS__H_
`define _FIXED_POINT_PARAMS__H_

//SMELL: Base all of these hardcoded numbers on Qm and Qn values:
`define F           signed [15:-16] // 15:0 is M (int), -1:-16 is N (frac).
`define I           signed [15:0]
`define f           [-1:-16]        //SMELL: Not signed.
`define F2          signed [31:-32] // Double-sized F (e.g. result of multiplication).

`define intF(i)     ((i)<<<16)      // Convert const int to F.
`define Fint(f)     ((f)>>>16)      // Convert F to int.

`define realF(r)    (((r)*(2.0**16)))
`define Freal(f)    ((f)*(2.0**-16))

`define FF(f)       f[15:-16]       // Get full F out of something bigger (e.g. F2).
`define FI(f)       f[15:0]         // Extract I part from an F.
`define IF(i)       {i,16'b0}       // Expand I part to a full F.

`define Ff(f)       f[-1:-16]       // Extract fractional part from an F. //SMELL: Discards sign!
`define fF(f)       {16'b0,f}       // Build a full F from just a fractional part.

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

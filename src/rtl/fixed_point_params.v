`ifndef _FIXED_POINT_PARAMS__H_
`define _FIXED_POINT_PARAMS__H_

`define Qm          16
`define Qn          16
`define QMI         (`Qm-1)         // Just for convenience; M-1.

//SMELL: Base all of these hardcoded numbers on Qm and Qn values:
`define F           signed [`QMI:-`Qn] // 15:0 is M (int), -1:-16 is N (frac).
`define I           signed [`QMI:0]
`define f           [-1:-`Qn]        //SMELL: Not signed.
// `define F2          signed [`Qm+`Qn-1:-`Qm-`Qn] // Double-sized F (e.g. result of multiplication).  //SMELL: Should this be [`Qm*2-1:-`Qn*2] ?
`define F2          signed [`Qm*2-1:-`Qn*2] // Double-sized F (e.g. result of multiplication).  //SMELL: Should this be [`Qm*2-1:-`Qn*2] ?

`define intF(i)     ((i)<<<`Qn)      // Convert const int to F.
`define Fint(f)     ((f)>>>`Qn)      // Convert F to int.

`define realF(r)    (((r)*(2.0**`Qn)))
`define Freal(f)    ((f)*(2.0**-`Qn))

`define FF(f)       f[`QMI:-`Qn]    // Get full F out of something bigger (e.g. F2).
`define FI(f)       f[`QMI:0]       // Extract I part from an F.
`define IF(i)       {i,`Qn'b0}      // Expand I part to a full F.

`define Ff(f)       f[-1:-`Qn]       // Extract fractional part from an F. //SMELL: Discards sign!
`define fF(f)       {`Qm'b0,f}       // Build a full F from just a fractional part.


// `define Qm      6                   // Number of fixed point integer bits (per Qm.n)
// `define Qn      10                  // Number of fixed point fraction bits
// `define Qmn     (`Qm+`Qn)           // Total bits in our fixed point format
// `define Fixed   signed [`Qmn-1:0]   // I'll try signed Q6.10 for my fixed-point numbers, for now.
// `define Int     signed [`Qm-1:0]    // Can hold a truncated (floored) integer value from one of our fixed point values.
// // `define fixedFloor(f) f[`Qmn-1:`Qn] // Extracts the integer part from a Fixed value.
// // `define fixedFrac(f) {f[`Qmn-1],f[`Qn-1:0]}
// // `define fixed2int(n)   
// `define SF      (2.0**-`Qn)         // Q6.10 scaling factor is 2^-10. Used for test prints as real numbers.
// //NOTE: Range of Q6.10 is -32.0 to 31.999023438, with a precision of 1/1024 (or 0.000976562).
`endif //_FIXED_POINT_PARAMS__H_

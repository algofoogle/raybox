`ifndef _FIXED_POINT_PARAMS__H_
`define _FIXED_POINT_PARAMS__H_

`define Qm          12                  // Signed.
`define Qn          12                  // I don't think I can go lower than 10; things get glitchy otherwise.
`define QMI         (`Qm-1)             // Just for convenience; M-1.

//SMELL: Base all of these hardcoded numbers on Qm and Qn values:
`define F           signed [`QMI:-`Qn]  // `Qm-1:0 is M (int), -1:-`Qn is N (frac).
`define I           signed [`QMI:0]
`define f           [-1:-`Qn]           //SMELL: Not signed.
`define F2          signed [`Qm*2-1:-`Qn*2] // Double-sized F (e.g. result of multiplication).

`define intF(i)     ((i)<<<`Qn)         // Convert const int to F.
`define Fint(f)     ((f)>>>`Qn)         // Convert F to int.

`define realF(r)    (((r)*(2.0**`Qn)))
`define Freal(f)    ((f)*(2.0**-`Qn))

`define FF(f)       f[`QMI:-`Qn]        // Get full F out of something bigger (e.g. F2).
`define FI(f)       f[`QMI:0]           // Extract I part from an F.
`define IF(i)       {i,`Qn'b0}          // Expand I part to a full F.

`define Ff(f)       f[-1:-`Qn]          // Extract fractional part from an F. //SMELL: Discards sign!
`define fF(f)       {`Qm'b0,f}          // Build a full F from just a fractional part.

`endif //_FIXED_POINT_PARAMS__H_

// QUARTUS (de0-nano) raybox_target_defs.v

// This file contains definitions necessary to change the synthesis
// to work with Quartus Prime Lite 22.1 and to a lesser extent for targeting
// the DE0-Nano board (featuring Altera Cyclone IV FPGA).

//NOTE: This file has the same name as another used by other targets, to hopefully
// allow for generic `include statements that will end up picking the correct file
// by virtue of the compiler used.

`default_nettype none
`timescale 1ns / 1ps

`define QUARTUS

// It seems Quartus treats $readmemh paths as relative to its project directory.
`define SPRITE_FILE     "../assets/sprite-xrgb-2222.hex"
`define TEXTURE_FILE    "../assets/texture-xrgb-2222.hex"
`define MAP_FILE        "../assets/map_16x16.hex"

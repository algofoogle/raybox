// OPENLANE (openlane) raybox_target_defs.v

// This file is included by some of the main RTL files, and some targets require
// this for global definitions (e.g. Quartus).

// This instance of the file suits the needs of how OpenLane works.

//NOTE: This file has the same name as another used by other targets, to hopefully
// allow for generic `include statements that will end up picking the correct file
// by virtue of the compiler used.

`default_nettype none
`timescale 1ns / 1ps

`define OPENLANE

// It seems OpenLane treats $readmemh paths as relative to the file that references them
// (i.e. relative to src/rtl/).
`define SPRITE_FILE     "../../assets/sprite-xrgb-2222.hex"
`define TEXTURE1_FILE   "../../assets/blue-wall-xrgb2222.hex"
`define TEXTURE2_FILE   "../../assets/red-wall-xrgb2222.hex"
`define TEXTURE3_FILE   "../../assets/grey-wall-xrgb2222.hex"
`define MAP_FILE        "../../assets/map_16x16.hex"

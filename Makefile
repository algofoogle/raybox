# SPDX-FileCopyrightText: 2023 Anton Maurovic <anton@maurovic.com>
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#
# SPDX-License-Identifier: Apache-2.0


# This is inspired by: https://github.com/mattvenn/rgb_mixer/blob/main/Makefile

# Main Verilog sources for our design:
MAIN_VSOURCES = \
	src/rtl/raybox.v \
	src/rtl/vga_sync.v \
	src/rtl/trace_buffer.v \
	src/rtl/map_rom.v \
	src/rtl/tracer.v \
	src/rtl/lzc_a.v \
	src/rtl/lzc_b.v \
	src/rtl/lzc_c.v \
	src/rtl/lzc_d.sv \
	src/rtl/reciprocal.v \
	src/rtl/texture_rom.v

# Top Verilog module representing our design:
TOP = raybox


# Stuff for simulation:
#CFLAGS = -CFLAGS -municode
#CFLAGS := -CFLAGS -DINSPECT_INTERNAL
SIM_LDFLAGS = -lSDL2 -lSDL2_ttf -lSDL2_image
ifeq ($(OS),Windows_NT)
	SIM_EXE = sim/obj_dir/V$(TOP).exe
else
	SIM_EXE = sim/obj_dir/V$(TOP)
endif
XDEFINES := $(DEF:%=+define+%)
# A fixed seed value for sim_seed:
SEED ?= 22860
ifeq ($(OS),Windows_NT)
	CFLAGS := -CFLAGS -DWINDOWS
	RSEED := $(shell ./winrand.bat)
else
	RSEED := $(shell bash -c 'echo $$RANDOM')
endif
#NOTE: RSEED is a random seed value for sim_random.

# COCOTB variables:
export COCOTB_REDUCED_LOG_FMT=1
export PYTHONPATH := test:$(PYTHONPATH)
export LIBPYTHON_LOC=$(shell cocotb-config --libpython)


# Simulate our design visually using Verilator, outputting to an SDL2 window.
#NOTE: All unassigned bits are set to 0:
sim: $(SIM_EXE)
	@$(SIM_EXE)

# Simulate with all unassigned bits set to 1:
sim_ones: $(SIM_EXE)
	@$(SIM_EXE) +verilator+rand+reset+1

# Simulate with unassigned bits fully randomised each time:
sim_random: $(SIM_EXE)
	echo "Random seed: " $(RSEED)
	@$(SIM_EXE) +verilator+rand+reset+2 +verilator+seed+$(RSEED)

# Simulate with unassigned bits randomised based on a known seed each time:
sim_seed: $(SIM_EXE)
	echo "Random seed: " $(SEED)
	@$(SIM_EXE) +verilator+rand+reset+2 +verilator+seed+$(SEED)

# Build main simulation exe:
$(SIM_EXE): $(MAIN_VSOURCES) sim/sim_main.cpp sim/main_tb.h sim/testbench.h
	echo $(RSEED)
	verilator \
		--Mdir sim/obj_dir \
		-Isrc/rtl \
		--cc $(MAIN_VSOURCES) \
		--top-module $(TOP) \
		--exe --build ../sim/sim_main.cpp \
		$(CFLAGS) \
		-LDFLAGS "$(SIM_LDFLAGS)" \
		+define+RESET_AL \
		$(XDEFINES)

clean:
	rm -rf sim_build
	rm -rf results
	rm -rf sim/obj_dir
	rm -rf test/__pycache__

clean_build: clean $(SIM_EXE)

# For Linux:
raybox_sim_debug_target: clean_build $(SIM_EXE)
	cp $(SIM_EXE) $@

# For Windows:
raybox_sim_debug_target.exe: clean_build $(SIM_EXE)
	cp $(SIM_EXE) $@

clean_sim: clean sim

clean_sim_random: clean sim_random

# This tells make that 'test' and 'clean' are themselves not artefacts to make,
# but rather tasks to always run:
.PHONY: test clean sim sim_ones sim_random sim_seed show_results clean_sim clean_sim_random clean_build


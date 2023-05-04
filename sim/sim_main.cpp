/*
 * SPDX-FileCopyrightText: 2023 Anton Maurovic <anton@maurovic.com>
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *      http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * SPDX-License-Identifier: Apache-2.0
 */

#include <stdio.h>
#include <err.h>
#include <iostream>
#include <string>
#include <filesystem> // For std::filesystem::absolute() (which is only used if we have C++17)
#include "testbench.h"
using namespace std;

#include "Vraybox.h"

#define DESIGN      raybox
#define VDESIGN     Vraybox
#define MAIN_TB     Vraybox_TB
#define BASE_TB     TESTBENCH<VDESIGN>

#define HILITE      0b0001'1111

#define NEW_GAME_SIGNAL
#define PAUSE_SIGNAL

//SMELL: These must be set to the same numbers in fixed_point_params.v:
#define Qm  12
#define Qn  12


// #define USE_POWER_PINS //NOTE: This is automatically set in the Makefile, now.
#define INSPECT_INTERNAL //NOTE: This is automatically set in the Makefile, now.
#ifdef INSPECT_INTERNAL
  #include "Vraybox_raybox.h" // Needed for accessing "verilator public" stuff.
#endif

#define FONT_FILE "sim/font-cousine/Cousine-Regular.ttf"

// #define DOUBLE_CLOCK
#ifdef DOUBLE_CLOCK
  #define CLOCK_HZ    50'000'000
#else
  #define CLOCK_HZ    25'000'000
#endif

#define S1(s1) #s1
#define S2(s2) S1(s2)

#include <SDL2/SDL.h>
#include <SDL2/SDL_ttf.h>

// It would be nice if these could be retrieved directly from the Verilog.
// I think there's a way to do it with a "DPI" or some other Verilator method.
#define HDA 640    // Horizontal display area.
#define HFP 16     // Front porch (defined in this case to mean "coming after HDA, and before HSP").
#define HSP 96     // HSYNC pulse.
#define HBP 48     // Back porch (defined in this case to mean "coming after HSP").
#define VDA 480    // Vertical display area.
#define VFP 11     // Front porch.
#define VSP 2      // VSYNC pulse.
#define VBP 32     // Back porch.

#define HFULL (HDA+HFP+HSP+HBP)
#define VFULL (VDA+VFP+VSP+VBP)

// Extra space to show on the right and bottom of the virtual VGA screen,
// used for identifying extreme limits of things (and possible overflow):
#define EXTRA_RHS         50
#define EXTRA_BOT         50
#define H_OFFSET          HSP+HBP   // Left-hand margin during HSYNC pulse and HBP that comes before HDA.
#define V_OFFSET          VSP+VBP

#define REFRESH_PIXEL     1
#define REFRESH_SLOW      8
#define REFRESH_FASTPIXEL 100
#define REFRESH_LINE      HFULL
#define REFRESH_10LINES   HFULL*10
#define REFRESH_80LINES   HFULL*80
#define REFRESH_FRAME     HFULL*VFULL

// SDL window size in pixels. This is what our design's timing should drive in VGA:
#define WINDOW_WIDTH  (HFULL+EXTRA_RHS)
#define WINDOW_HEIGHT (VFULL+EXTRA_BOT)
#define FRAMEBUFFER_SIZE WINDOW_WIDTH*WINDOW_HEIGHT*4

// The MAIN_TB class that includes specifics about running our design in simulation:
#include "main_tb.h"


// Testbench for main design:
MAIN_TB       *TB;
bool          gQuit = false;
int           gRefreshLimit = REFRESH_FRAME;
int           gOriginalTime;
int           gPrevTime;
int           gPrevFrames;
unsigned long gPrevTickCount;
bool          gSyncLine = false;
bool          gSyncFrame = false;
bool          gHighlight = true;
bool          gGuides = false;
bool          gOverrideVectors = false;

typedef struct {
  uint32_t px, py, fx, fy, vx, vy;
} fixed_vectors_t;

typedef struct {
  double px, py, fx, fy, vx, vy;
} float_vectors_t;

float_vectors_t gOvers; // Floating point overrides.


enum {
  LOCK_F = 0,
  LOCK_B,
  LOCK_L,
  LOCK_R,
  LOCK_MAP,
  LOCK__MAX
};

bool gLockInputs[LOCK__MAX] = {0};


// From: https://stackoverflow.com/a/38169008
// - x, y: upper left corner.
// - texture, rect: outputs.
void get_text_and_rect(
  SDL_Renderer *renderer,
  int x,
  int y,
  const char *text,
  TTF_Font *font,
  SDL_Texture **texture,
  SDL_Rect *rect
) {
  int text_width;
  int text_height;
  SDL_Surface *surface;
  SDL_Color textColor = {255, 255, 255, 0};

  surface = TTF_RenderText_Solid(font, text, textColor);
  *texture = SDL_CreateTextureFromSurface(renderer, surface);
  text_width = surface->w;
  text_height = surface->h;
  SDL_FreeSurface(surface);
  rect->x = x;
  rect->y = y;
  rect->w = text_width;
  rect->h = text_height;
}

// If part is 0, calculate from both the integer and fractional parts.
// If <0, calculate from fractional part only.
// If >0, calculate from integer part only.
double fixed2double(uint32_t fixed, int part = 0) {
  int32_t t = fixed;
  if (part<0) {
    // Kill integer part:
    t &= (1<<Qn)-1;
  }
  else if (part>0) {
    // Kill fractional part:
    t &= ((1<<Qm)-1)<<Qn;
  }
  // Sign extension:
  bool sign = t & (1<<((Qm+Qn)-1));
  if (sign) t |= ((1<<(32-(Qm+Qn)))-1)<<(Qm+Qn);
  return double(t) / pow(2.0, Qn);
}

uint32_t double2fixed(double d) {
  int32_t t = d * pow(2.0, Qn);
  return t & ((1<<(Qm+Qn))-1);
}

// Get current internal vectors from the design, so we can take them over
// without disrupting the current view:
void get_override_vectors() {
  // #error "load_override_vectors() is not implemented!"
  fixed_vectors_t get;
  get.px = TB->m_core->DESIGN->playerX;
  get.py = TB->m_core->DESIGN->playerY;
  get.fx = TB->m_core->DESIGN->facingX;
  get.fy = TB->m_core->DESIGN->facingY;
  get.vx = TB->m_core->DESIGN->vplaneX;
  get.vy = TB->m_core->DESIGN->vplaneY;
  gOvers.px = fixed2double(get.px);
  gOvers.py = fixed2double(get.py);
  gOvers.fx = fixed2double(get.fx);
  gOvers.fy = fixed2double(get.fy);
  gOvers.vx = fixed2double(get.vx);
  gOvers.vy = fixed2double(get.vy);
  printf(
    "Loaded vectors:\n"
    "  px=%16.10lf\n"
    "  py=%16.10lf\n"
    "  fx=%16.10lf\n"
    "  fy=%16.10lf\n"
    "  vx=%16.10lf\n"
    "  vy=%16.10lf\n"
    ,
    gOvers.px,
    gOvers.py,
    gOvers.fx,
    gOvers.fy,
    gOvers.vx,
    gOvers.vy
  );
}



void rotate_override_vectors(double a) {
  double nx, ny;
  double ca = cos(a);
  double sa = sin(a);
  // Rotate direction vector:
  nx =  gOvers.fx*ca + gOvers.fy*sa;
  ny = -gOvers.fx*sa + gOvers.fy*ca;
  gOvers.fx = nx;
  gOvers.fy = ny;
  // // Generate viewplane vector:
  // viewX = -headingY * viewMag;
  // viewY =  headingX * viewMag;
  // Rotate viewplane vector:
  nx =  gOvers.vx*ca + gOvers.vy*sa;
  ny = -gOvers.vx*sa + gOvers.vy*ca;
  gOvers.vx = nx;
  gOvers.vy = ny;
}


void recalc_override_vectors(const Uint8* k) {
  const double move_quantum = pow(2.0, -9.0); // This borrows from `playerMove` in the design, and in Q12.12 it is the raw value: 8
  const double playerCrawl  = move_quantum *  4.0;
  const double playerWalk   = move_quantum * 10.0; // Should be 0.01953125
  const double playerRun    = move_quantum * 18.0;
  const double playerMove   = playerWalk;
  double m = playerMove;
  if (k[SDL_SCANCODE_LSHIFT]) m = playerRun;
  if (k[SDL_SCANCODE_LEFT])   rotate_override_vectors( 0.01);
  if (k[SDL_SCANCODE_RIGHT])  rotate_override_vectors(-0.01);
  if (k[SDL_SCANCODE_W]) { gOvers.px += m * gOvers.fx;   gOvers.py += m * gOvers.fy; }
  if (k[SDL_SCANCODE_S]) { gOvers.px -= m * gOvers.fx;   gOvers.py -= m * gOvers.fy; }
  if (k[SDL_SCANCODE_A]) { gOvers.px -= m * gOvers.vx;   gOvers.py -= m * gOvers.vy; }
  if (k[SDL_SCANCODE_D]) { gOvers.px += m * gOvers.vx;   gOvers.py += m * gOvers.vy; }
}




void set_override_vectors() {
  // Convert gOvers to fixed-point values we can write back into the design:
  TB->m_core->new_playerX = double2fixed(gOvers.px);
  TB->m_core->new_playerY = double2fixed(gOvers.py);
  TB->m_core->new_facingX = double2fixed(gOvers.fx);
  TB->m_core->new_facingY = double2fixed(gOvers.fy);
  TB->m_core->new_vplaneX = double2fixed(gOvers.vx);
  TB->m_core->new_vplaneY = double2fixed(gOvers.vy);
}


void process_sdl_events() {
  // Event used to receive window close, keyboard actions, etc:
  SDL_Event e;
  // Consume SDL events, if any, until the event queue is empty:
  while (SDL_PollEvent(&e) == 1) {
    if (SDL_QUIT == e.type) {
      // SDL quit event (e.g. close window)?
      gQuit = true;
    } else if (SDL_KEYDOWN == e.type) {
      switch (e.key.keysym.sym) {
        case SDLK_q:
        case SDLK_ESCAPE:
          // ESC or Q key pressed, for Quit
          gQuit = true;
          break;
        case SDLK_SPACE:
          TB->pause(!TB->paused);
          break;
        case SDLK_g:
          gGuides = !gGuides;
          printf("Guides turned %s\n", gGuides ? "ON" : "off");
          break;
        case SDLK_h:
          gHighlight = !gHighlight;
          printf("Highlighting turned %s\n", gHighlight ? "ON" : "off");
          break;
        case SDLK_1:
          gRefreshLimit = REFRESH_PIXEL;
          gSyncLine = false;
          gSyncFrame = false;
          printf("Refreshing every pixel\n");
          break;
        case SDLK_8:
          gRefreshLimit = REFRESH_SLOW;
          gSyncLine = false;
          gSyncFrame = false;
          printf("Refreshing every 8 pixels\n");
          break;
        case SDLK_9:
          gRefreshLimit = REFRESH_FASTPIXEL;
          gSyncLine = false;
          gSyncFrame = false;
          printf("Refreshing every 100 pixels\n");
          break;
        case SDLK_2:
          gRefreshLimit = REFRESH_LINE;
          gSyncLine = true;
          gSyncFrame = false;
          printf("Refreshing every line\n");
          break;
        case SDLK_3:
          gRefreshLimit = REFRESH_10LINES;
          gSyncLine = true;
          gSyncFrame = false;
          printf("Refreshing every 10 lines\n");
          break;
        case SDLK_4:
          gRefreshLimit = REFRESH_80LINES;
          gSyncLine = true;
          gSyncFrame = false;
          printf("Refreshing every 80 lines\n");
          break;
        case SDLK_5:
          gRefreshLimit = REFRESH_FRAME;
          gSyncLine = true;
          gSyncFrame = true;
          printf("Refreshing every frame\n");
          break;
        case SDLK_6:
          gRefreshLimit = REFRESH_FRAME*3;
          gSyncLine = true;
          gSyncFrame = true;
          printf("Refreshing every 3 frames\n");
          break;
        case SDLK_v:
          TB->log_vsync = !TB->log_vsync;
          printf("Logging VSYNC %s\n", TB->log_vsync ? "enabled" : "disabled");
          break;
        case SDLK_KP_PLUS:
          printf("gRefreshLimit increased to %d\n", gRefreshLimit+=1000);
          break;
        case SDLK_KP_MINUS:
          printf("gRefreshLimit decreated to %d\n", gRefreshLimit-=1000);
          break;
        case SDLK_x: // eXamine: Pause as soon as a frame is detected with any tone generation.
          TB->examine_mode = !TB->examine_mode;
          if (TB->examine_mode) {
            printf("Examine mode ON\n");
            TB->examine_condition_met = false;
          }
          else {
            printf("Examine mode off\n");
          }
          break;
        case SDLK_s: // Step-examine, basically the same as hitting X then P while already paused.
          TB->examine_mode = true;
          TB->examine_condition_met = false;
          TB->pause(false); // Unpause.
          break;
        case SDLK_f:
          printf("Stepping by 1 frame is not yet implemented!\n");
          break;
        case SDLK_o:
          gOverrideVectors = !gOverrideVectors;
          if (!gOverrideVectors) {
            printf("Vectors override turned off\n");
          }
          else {
            printf("Vectors override turned ON\n");
            get_override_vectors();
            // Turn off all input locks EXCEPT map:
            gLockInputs[LOCK_F] = gLockInputs[LOCK_B] = gLockInputs[LOCK_L] = gLockInputs[LOCK_R] = 0;
          }
          break;
        // Turn off all input locks:
        case SDLK_END:    memset(&gLockInputs, 0, sizeof(gLockInputs)); break;

        default:
          // The following keys are treated differently depending on whether we're in gOverrideVectors mode or not:
          if (gOverrideVectors) {
            // Override Vectors mode: Let the sim directly set our player position and viewpoint.
            //NOTE: Nothing to do here: handle_control_inputs will take care of it.
          }
          else {
            // Not in Override Vectors mode; let the design handle motion.
            switch (e.key.keysym.sym) {
              // Toggle map input:
              case SDLK_INSERT: gLockInputs[LOCK_MAP] ^= 1; break;
              // Toggle direction inputs (and turn off any that are opposing):
              case SDLK_UP:     if (KMOD_SHIFT & e.key.keysym.mod) TB->m_core->moveF=1; else if( (gLockInputs[LOCK_F] ^= 1) ) gLockInputs[LOCK_B] = false; break;
              case SDLK_DOWN:   if (KMOD_SHIFT & e.key.keysym.mod) TB->m_core->moveB=1; else if( (gLockInputs[LOCK_B] ^= 1) ) gLockInputs[LOCK_F] = false; break;
              case SDLK_LEFT:   if (KMOD_SHIFT & e.key.keysym.mod) TB->m_core->moveL=1; else if( (gLockInputs[LOCK_L] ^= 1) ) gLockInputs[LOCK_R] = false; break;
              case SDLK_RIGHT:  if (KMOD_SHIFT & e.key.keysym.mod) TB->m_core->moveR=1; else if( (gLockInputs[LOCK_R] ^= 1) ) gLockInputs[LOCK_L] = false; break;
              // NOTE: If SHIFT is held, send momentary (1-frame) signal inputs instead of locks.
              //SMELL: This won't work if we're calling handle_control_inputs more often than once per frame...?
            }
          }
          break;
      }
    }
  }
}


//NOTE: handle_control_inputs is called twice; once with `true` before process_sdl_events, then once after with `false`.
void handle_control_inputs(bool prepare) {
  if (prepare) {
    // PREPARE mode: Clear all inputs, so process_sdl_events has a chance to preset MOMENTARY inputs:
    TB->m_core->reset     = 0;
    TB->m_core->show_map  = 0;
    TB->m_core->moveF     = 0;
    TB->m_core->moveL     = 0;
    TB->m_core->moveB     = 0;
    TB->m_core->moveR     = 0;
  }
  else {
    // ACTIVE mode: Read the momentary state of all keyboard keys, and add them via `|=` to whatever is already asserted:
    auto keystate = SDL_GetKeyboardState(NULL);

    if (gOverrideVectors) {
      recalc_override_vectors(keystate);
      set_override_vectors();
      TB->m_core->write_new_position = 1;
    } else {
      TB->m_core->write_new_position = 0;
    }

    TB->m_core->reset     |= keystate[SDL_SCANCODE_R];
    TB->m_core->show_map  |= keystate[SDL_SCANCODE_TAB ] | gLockInputs[LOCK_MAP];
    TB->m_core->moveF     |= keystate[SDL_SCANCODE_W   ] | gLockInputs[LOCK_F];
    TB->m_core->moveL     |= keystate[SDL_SCANCODE_A   ] | gLockInputs[LOCK_L];
    TB->m_core->moveB     |= keystate[SDL_SCANCODE_S   ] | gLockInputs[LOCK_B];
    TB->m_core->moveR     |= keystate[SDL_SCANCODE_D   ] | gLockInputs[LOCK_R];
  }
}



void check_performance() {
  auto time_now = SDL_GetTicks();
  int time_delta = time_now-gPrevTime;

  if (time_delta >= 1000) {
    // 1S+ has elapsed, so print FPS:
    printf("Current FPS: %5.2f", float(TB->frame_counter-gPrevFrames)/float(time_delta)*1000.0f);
    // Estimate clock speed based on delta of m_tickcount:
    long hz = (TB->m_tickcount-gPrevTickCount)*1000L / time_delta;
    // Now print long-term average:
    printf(" - Total average FPS: %5.2f", float(TB->frame_counter)/float(time_now-gOriginalTime)*1000.0f);
    printf(" - m_tickcount=");
    TB->print_big_num(TB->m_tickcount);
    printf(" (");
    TB->print_big_num(hz);
    printf(" Hz; %3ld%% of target)\n", (hz*100)/CLOCK_HZ);
    gPrevTime = SDL_GetTicks();
    gPrevFrames = TB->frame_counter;
    gPrevTickCount = TB->m_tickcount;
  }
}



void clear_freshness(uint8_t *fb) {
  // If we're not refreshing at least one full frame at a time,
  // then clear the "freshness" of pixels that haven't been updated.
  // We make this conditional in the hopes of getting extra speed
  // for higher refresh rates.
  // if (gRefreshLimit < REFRESH_FRAME) {
    // In this simulation, the 6 lower bits of each colour channel
    // are not driven by the design, and so we instead use them to
    // help visualise what region of the framebuffer has been updated
    // between SDL window refreshes (by the rendering loop forcing them on,
    // which appears as a slight brightening).
    // THIS loop clears all that between refreshes:
    for (int x = 0; x < HFULL; ++x) {
      for (int y = 0; y < VFULL; ++y) {
        fb[(x+y*WINDOW_WIDTH)*4 + 0] &= ~HILITE;
        fb[(x+y*WINDOW_WIDTH)*4 + 1] &= ~HILITE;
        fb[(x+y*WINDOW_WIDTH)*4 + 2] &= ~HILITE;
      }
    }
  // }
}

void overlay_display_area_frame(uint8_t *fb, int h_shift = 0, int v_shift = 0) {
  // if (!gGuides) return;
  // Vertical range: Horizontal lines (top and bottom):
  if (v_shift > 0) {
    for (int x = 0; x < WINDOW_WIDTH; ++x) {
      fb[(x+(v_shift-1)*WINDOW_WIDTH)*4 + 0] |= 0b0100'0000;
      fb[(x+(v_shift-1)*WINDOW_WIDTH)*4 + 1] |= 0b0100'0000;
      fb[(x+(v_shift-1)*WINDOW_WIDTH)*4 + 2] |= 0b0100'0000;
    }
  }
  if (v_shift+VDA < WINDOW_HEIGHT) {
    for (int x = 0; x < WINDOW_WIDTH; ++x) {
      fb[(x+(VDA+v_shift)*WINDOW_WIDTH)*4 + 0] |= 0b0100'0000;
      fb[(x+(VDA+v_shift)*WINDOW_WIDTH)*4 + 1] |= 0b0100'0000;
      fb[(x+(VDA+v_shift)*WINDOW_WIDTH)*4 + 2] |= 0b0100'0000;
    }
  }
  // Horizontal range: Vertical lines (left and right sides):
  if (h_shift > 0) {
    for (int y = 0; y < WINDOW_HEIGHT; ++y) {
      fb[(h_shift-1+y*WINDOW_WIDTH)*4 + 0] |= 0b0100'0000;
      fb[(h_shift-1+y*WINDOW_WIDTH)*4 + 1] |= 0b0100'0000;
      fb[(h_shift-1+y*WINDOW_WIDTH)*4 + 2] |= 0b0100'0000;
    }
  }
  if (h_shift+HDA < WINDOW_WIDTH) {
    for (int y = 0; y < WINDOW_HEIGHT; ++y) {
      fb[(HDA+h_shift+y*WINDOW_WIDTH)*4 + 0] |= 0b0100'0000;
      fb[(HDA+h_shift+y*WINDOW_WIDTH)*4 + 1] |= 0b0100'0000;
      fb[(HDA+h_shift+y*WINDOW_WIDTH)*4 + 2] |= 0b0100'0000;
    }
  }
  // Guides:
  if (gGuides) {
    // Mid-screen vertical line:
    for (int y = 0; y < WINDOW_HEIGHT; ++y) {
        fb[(HDA/2+h_shift+y*WINDOW_WIDTH)*4 + 0] |= 0b0110'0000;
        fb[(HDA/2+h_shift+y*WINDOW_WIDTH)*4 + 1] |= 0b0110'0000;
        fb[(HDA/2+h_shift+y*WINDOW_WIDTH)*4 + 2] |= 0b0110'0000;
    }
    // Overlay camera orientation:

  }
}


void fade_overflow_region(uint8_t *fb) {
  for (int x = HFULL; x < WINDOW_WIDTH; ++x) {
    for (int y = 0 ; y < VFULL; ++y) {
      fb[(x+y*WINDOW_WIDTH)*4 + 0] *= 0.95;
      fb[(x+y*WINDOW_WIDTH)*4 + 1] *= 0.95;
      fb[(x+y*WINDOW_WIDTH)*4 + 2] *= 0.95;
    }
  }
  for (int x = 0; x < WINDOW_WIDTH; ++x) {
    for (int y = VFULL; y < WINDOW_HEIGHT; ++y) {
      fb[(x+y*WINDOW_WIDTH)*4 + 0] *= 0.95;
      fb[(x+y*WINDOW_WIDTH)*4 + 1] *= 0.95;
      fb[(x+y*WINDOW_WIDTH)*4 + 2] *= 0.95;
    }
  }
}


void overflow_test(uint8_t *fb) {
  for (int x = HFULL; x < WINDOW_WIDTH; ++x) {
    for (int y = 0 ; y < VFULL; ++y) {
      fb[(x+y*WINDOW_WIDTH)*4 + 0] = 50;
      fb[(x+y*WINDOW_WIDTH)*4 + 1] = 150;
      fb[(x+y*WINDOW_WIDTH)*4 + 2] = 255;
    }
  }
  for (int x = 0; x < WINDOW_WIDTH; ++x) {
    for (int y = VFULL; y < WINDOW_HEIGHT; ++y) {
      fb[(x+y*WINDOW_WIDTH)*4 + 0] = 50;
      fb[(x+y*WINDOW_WIDTH)*4 + 1] = 150;
      fb[(x+y*WINDOW_WIDTH)*4 + 2] = 255;
    }
  }
}



void render_text(SDL_Renderer* renderer, TTF_Font* font, int x, int y, string s) {
  SDL_Rect r;
  SDL_Texture* tex;
  get_text_and_rect(renderer, x, y, s.c_str(), font, &tex, &r);
  if (tex) {
    SDL_RenderCopy(renderer, tex, NULL, &r);
    SDL_DestroyTexture(tex);
  }
}



int main(int argc, char **argv) {

  Verilated::commandArgs(argc, argv);
  // Verilated::traceEverOn(true);
  
  TB = new MAIN_TB();
#ifdef USE_POWER_PINS
  #pragma message "Howdy! This simulation build has USE_POWER_PINS in effect"
  TB->m_core->VGND = 0;
  TB->m_core->VPWR = 1;
#else
  #pragma message "Oh hi! USE_POWER_PINS is not in effect for this simulation build"
#endif
  uint8_t *framebuffer = new uint8_t[FRAMEBUFFER_SIZE];

  //SMELL: This needs proper error handling!
  printf("SDL_InitSubSystem(SDL_INIT_VIDEO): %d\n", SDL_InitSubSystem(SDL_INIT_VIDEO));

  SDL_Window* window =
      SDL_CreateWindow(
          " Verilator VGA simulation: " S2(VDESIGN),
          SDL_WINDOWPOS_UNDEFINED, SDL_WINDOWPOS_UNDEFINED,
          WINDOW_WIDTH, WINDOW_HEIGHT,
          0
      );
  SDL_Renderer* renderer =
      SDL_CreateRenderer(
          window,
          -1,
          SDL_RENDERER_ACCELERATED
      );

  TTF_Init();
  TTF_Font *font = TTF_OpenFont(FONT_FILE, 12);
  if (!font) {
#if __cplusplus == 201703L
    std::filesystem::path font_path = std::filesystem::absolute(FONT_FILE);
#else
    string font_path = FONT_FILE;
#endif
    printf(
      "WARNING: Cannot load default font. Text rendering will be disabled.\n"
      "-- Looking for: %s\n",
      font_path.c_str()
    );
  }
  else {
    printf("Font loaded.\n");
  }
  
  SDL_SetRenderDrawColor(renderer, 0, 0, 0, SDL_ALPHA_OPAQUE);
  SDL_RenderClear(renderer);
  SDL_Texture* texture =
      SDL_CreateTexture(
          renderer,
          SDL_PIXELFORMAT_ARGB8888,
          SDL_TEXTUREACCESS_STREAMING,
          WINDOW_WIDTH, WINDOW_HEIGHT
      );

  printf(
    "\n"
    "Target clock speed: "
  );
  TB->print_big_num(CLOCK_HZ);
  printf(" Hz\n");

// #ifdef INSPECT_INTERNAL
//   printf(
//     "\n"
//     "Initial state of design:\n"
//     "  h        : %d\n"
//     "  v        : %d\n"
//     "\n",
//     TB->m_core->DESIGN->h,
//     TB->m_core->DESIGN->v,
//   );
// #endif


  // printf("Starting simulation in ");
  // for (int c=3; c>0; --c) {
  //   printf("%i... ", c);
  //   fflush(stdout);
  //   sleep(1);
  // }
  printf("Cold start...\n");

  int h = 0;
  int v = 0;

  printf("Main loop...\n");

  gOriginalTime = gPrevTime = SDL_GetTicks();
  gPrevTickCount = TB->m_tickcount; // Used for measuring simulated clock speed.
  gPrevFrames = 0;

  bool count_hbp = false;
  int hbp_counter = 0; // Counter for timing the HBP (i.e. time after HSP, but before HDA).
  int h_adjust = HBP*2; // Amount to count in hbp_counter. Start at a high value and then sync back down.
  int h_adjust_countdown = REFRESH_FRAME*2;
  int v_shift = VBP*2; // This will try to find the vertical start of the image.

  while (!gQuit) {
    if (TB->done()) gQuit = true;
    if (TB->paused) SDL_WaitEvent(NULL); // If we're paused, an event is needed before we could resume.

    handle_control_inputs(true); // true = PREPARE mode; set default signal inputs, so process_sdl_events can OPTIONALLY override.
    //SMELL: Should we do handle_control_inputs(true) only when we detect the start of a new frame,
    // so as to preserve/capture any keys that were pressed across *partial* refreshes?
    process_sdl_events();
    if (gQuit) break;
    if (TB->paused) continue;

    int old_reset = TB->m_core->reset;
    handle_control_inputs(false); // false = ACTIVE mode; add in actual HID=>signal input changes.
    if (old_reset != TB->m_core->reset) {
      // Reset state changed, so we probably need to resync:
      h_adjust = HBP*2;
      count_hbp = false;
      hbp_counter = 0; // Counter for timing the HBP (i.e. time after HSP, but before HDA).
      h_adjust = HBP*2; // Amount to count in hbp_counter. Start at a high value and then sync back down.
      h_adjust_countdown = REFRESH_FRAME*2;
      v_shift = VBP*2; // This will try to find the vertical start of the image.
    }

    check_performance();

    clear_freshness(framebuffer);

    //SMELL: In my RTL, I call the time that comes before the horizontal display area the BACK porch,
    // even though arguably it comes first (so surely should be the FRONT), but this swapped naming
    // comes from other charts and diagrams I was reading online at the time.

    for (int i = 0; i < gRefreshLimit; ++i) {

      if (h_adjust_countdown > 0) --h_adjust_countdown;

      bool hsync_stopped = false;
      bool vsync_stopped = false;
      TB->tick();      hsync_stopped |= TB->hsync_stopped();      vsync_stopped |= TB->vsync_stopped();      TB->examine_condition_met |= TB->m_core->speaker;
#ifdef DOUBLE_CLOCK
      TB->tick();      hsync_stopped |= TB->hsync_stopped();      vsync_stopped |= TB->vsync_stopped();      TB->examine_condition_met |= TB->m_core->speaker;
      // ^ We tick twice if the design halves the clock to produce the pixel clock.
#endif

      if (hsync_stopped) {
        count_hbp = true;
        hbp_counter = 0;
      }

      int pixel_lit = TB->m_core->red | TB->m_core->green | TB->m_core->blue;

      if (count_hbp) {
        // We are counting the HBP before we start the next line.
        if (hbp_counter >= h_adjust) {
          // OK, counter ran out, so let's start our next line.
          count_hbp = false;
          hbp_counter = 0;
          h = 0;
          v++;
        }
        else if (pixel_lit) {
          // If we got here, we got a display signal earlier than the current
          // horizontal adjustment expects, so we need to adjust HBP to match
          // HDA video signal, but only after the first full frame:
          if (h_adjust_countdown <= 0) {
            h_adjust = hbp_counter;
            printf(
              "[H,V,F=%4d,%4d,%2d] "
              "Horizontal auto-adjust to %d after HSYNC\n",
              h, v, TB->frame_counter,
              h_adjust
            );
          }
        }
        else {
          h++;
          hbp_counter++;
        }
      }
      else {
        h++;
      }

      if (vsync_stopped) {
        // Start a new frame.
        v = 0;
        // if (TB->frame_counter%60 == 0) overflow_test(framebuffer);
        fade_overflow_region(framebuffer);
      }

      if (pixel_lit && h_adjust_countdown <= 0 && v < v_shift) {
        v_shift = v;
        printf(
          "[H,V,F=%4d,%4d,%2d] "
          "Vertical frame auto-shift to %d after VSYNC\n",
          h, v, TB->frame_counter,
          v_shift
        );
        gSyncLine = true;
        gSyncFrame = true;
      }

      int x = h;
      int y = v;

      int speaker = (TB->m_core->speaker<<6);
      int hilite = gHighlight ? HILITE : 0; // hilite turns on lower 5 bits to show which pixel(s) have been updated.

      if (x >= 0 && x < WINDOW_WIDTH && y >= 0 && y < WINDOW_HEIGHT) {

        int red  = (TB->m_core->red   << 6) | hilite; // Design drives upper 2 bits of each colour channel.
        int green= (TB->m_core->green << 6) | hilite; 
        int blue = (TB->m_core->blue  << 6) | hilite; 
        framebuffer[(y*WINDOW_WIDTH + x)*4 + 2] = red   | (TB->m_core->hsync ? 0 : 0b1000'0000) | speaker;  // R
        framebuffer[(y*WINDOW_WIDTH + x)*4 + 1] = green;                                                    // G
        framebuffer[(y*WINDOW_WIDTH + x)*4 + 0] = blue  | (TB->m_core->vsync ? 0 : 0b1000'0000) | speaker;  // B.
      }

      if (gSyncLine && h==0) {
        gSyncLine = false;
        break;
      }

      if (gSyncFrame && v==0) {
        gSyncFrame = false;
        break;
      }

    }

    overlay_display_area_frame(framebuffer, 0, v_shift);

    SDL_UpdateTexture( texture, NULL, framebuffer, WINDOW_WIDTH * 4 );
    SDL_RenderCopy( renderer, texture, NULL, NULL );
    if (font) {
      SDL_Rect rect;
      SDL_Texture *text_texture = NULL;
      string s = "[";
      s += TB->paused           ? "P" : ".";
      s += gGuides              ? "G" : ".";
      s += gHighlight           ? "H" : ".";
      s += TB->log_vsync        ? "V" : ".";
      s += gOverrideVectors     ? "O" : ".";
      s += TB->examine_mode     ? "X" : ".";
      s += gLockInputs[LOCK_MAP]? "m" : ".";
      s += gLockInputs[LOCK_L]  ? "<" : ".";
      s += gLockInputs[LOCK_F]  ? "^" : ".";
      s += gLockInputs[LOCK_B]  ? "v" : ".";
      s += gLockInputs[LOCK_R]  ? ">" : ".";
#ifdef INSPECT_INTERNAL
      s += "] ";
      // s += " h="         + to_string(TB->m_core->DESIGN->h);
      // s += " v="         + to_string(TB->m_core->DESIGN->v);
      // s += " v_shift="   + to_string(v_shift);
      // s += " h_adjust="  + to_string(h_adjust);
      // Player position:
      s += " pX=" + to_string(fixed2double(TB->m_core->DESIGN->playerX));
      s += " pY=" + to_string(fixed2double(TB->m_core->DESIGN->playerY));
#endif
      get_text_and_rect(renderer, 10, VFULL+10, s.c_str(), font, &text_texture, &rect);
      if (text_texture) {
        SDL_RenderCopy(renderer, text_texture, NULL, &rect);
        SDL_DestroyTexture(text_texture);
      }
      else {
        printf("Cannot create text_texture\n");
      }
    }
    if (gGuides) {
      int ox = HDA/2;
      int oy = VDA/2;
      double s = VDA/4;
      //SMELL: Add in grid-cell alignment too.
      // Draw the design's current vectors in green:
      SDL_SetRenderDrawColor(renderer, 0,255,0,255);
      double fx = fixed2double(TB->m_core->DESIGN->facingX);
      double fy = fixed2double(TB->m_core->DESIGN->facingY);
      double vx = fixed2double(TB->m_core->DESIGN->vplaneX);
      double vy = fixed2double(TB->m_core->DESIGN->vplaneY);
      int lx = ox+(fx-vx)*s;
      int ly = oy+(fy-vy)*s;
      int rx = ox+(fx+vx)*s;
      int ry = oy+(fy+vy)*s;
      // Draw center directional line:
      SDL_RenderDrawLine(renderer, ox, oy, ox+fx*s, oy+fy*s);
      // Draw left camera vector:
      SDL_RenderDrawLine(renderer, ox, oy, lx, ly);
      // Draw right camera vector:
      SDL_RenderDrawLine(renderer, ox, oy, rx, ry);
      // Draw viewplane:
      SDL_RenderDrawLine(renderer, lx, ly, rx, ry);
      // Draw the box representing the position of the player in the current cell,
      // i.e. just draw a unit square offset by the fractional part of the player position:
      double px  = fixed2double(TB->m_core->DESIGN->playerX,  1); // Integer part.
      double py  = fixed2double(TB->m_core->DESIGN->playerY,  1); // Integer part.
      double pxf = fixed2double(TB->m_core->DESIGN->playerX, -1); // Fractional part.
      double pyf = fixed2double(TB->m_core->DESIGN->playerY, -1); // Fractional part.
      SDL_Rect r;
      r.x = ox-pxf*s;
      r.y = oy-pyf*s;
      r.w = r.h = s;
      SDL_RenderDrawRect(renderer, &r);
      render_text(renderer, font, r.x+3, r.y+s-14, to_string(int(px)) + ", " + to_string(int(py)));
      if (gOverrideVectors) {
        // Now draw sim's overriding vectors over them, in white:
        SDL_SetRenderDrawColor(renderer, 255,255,255,255);
        lx = ox+(gOvers.fx-gOvers.vx)*s;
        ly = oy+(gOvers.fy-gOvers.vy)*s;
        rx = ox+(gOvers.fx+gOvers.vx)*s;
        ry = oy+(gOvers.fy+gOvers.vy)*s;
        // Draw center directional line:
        SDL_RenderDrawLine(renderer, ox, oy, ox+gOvers.fx*VDA/4, oy+gOvers.fy*VDA/4);
        // Draw left camera vector:
        SDL_RenderDrawLine(renderer, ox, oy, lx, ly);
        // Draw right camera vector:
        SDL_RenderDrawLine(renderer, ox, oy, rx, ry);
        // Draw viewplane:
        SDL_RenderDrawLine(renderer, lx, ly, rx, ry);
        // Draw box:
        px = gOvers.px;
        py = gOvers.py;
        double dummy;
        pxf = modf(px, &dummy);
        pyf = modf(py, &dummy);
        // Fix negative partials: //SMELL: Why is this necessary?
        if (pxf < 0) pxf = pxf+1;
        if (pyf < 0) pyf = pyf+1;
        r.x = ox-pxf*s;
        r.y = oy-pyf*s;
        r.w = r.h = s;
        SDL_RenderDrawRect(renderer, &r);
      }
    }
    SDL_RenderPresent(renderer);
  }

  SDL_DestroyRenderer(renderer);
  SDL_DestroyWindow(window);
  SDL_Quit(); //SMELL: Should use SDL_QuitSubSystem instead? https://wiki.libsdl.org/SDL2/SDL_QuitSubSystem
  if (font) TTF_CloseFont(font);
  TTF_Quit();

  delete framebuffer;

  printf("Done at %lu ticks.\n", TB->m_tickcount);
  return EXIT_SUCCESS;
}

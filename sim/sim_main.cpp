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
// #include <err.h>
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

//#define DESIGN_DIRECT_VECTOR_ACCESS   // Defined=new_playerX etc are exposed; else=SPI only.
//#define DEBUG_BUTTON_INPUTS
//#define USE_SPEAKER

//SMELL: These must be set to the same numbers in fixed_point_params.v:
#define Qm  12
#define Qn  12

// #define USE_POWER_PINS //NOTE: This is automatically set in the Makefile, now.
#define INSPECT_INTERNAL //NOTE: This is automatically set in the Makefile, now.
#ifdef INSPECT_INTERNAL
  #include "Vraybox_raybox.h"       // Needed for accessing "verilator public" stuff in `raybox`
  #include "Vraybox_texture_rom.h"  // Needed for accessing "verilator public" stuff in `raybox.wall_textures`
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
#include <SDL2/SDL_image.h> // This will be used for loading "ROMs" that interface with the design: Map & Texture data.
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


//SMELL: This doesn't do anything besides keeping certain linkers happy.
// See: https://veripool.org/guide/latest/faq.html#why-do-i-get-undefined-reference-to-sc-time-stamp
double sc_time_stamp() { return 0; }

#ifdef WINDOWS
//SMELL: For some reason, when building this under Windows, it stops building as a console command
// and instead builds as a Windows app requiring WinMain. Possibly something to do with Verilator
// or SDL2 under windows. I'm not sure yet. Anyway, this is a temporary workaround. The Makefile
// will include `-CFLAGS -DWINDOWS`, when required, in order to activate this code:
#include <windows.h>
int WINAPI WinMain(HINSTANCE hInstance, HINSTANCE hPrevInstance, LPSTR lpCmdLine, int nCmdShow)
{
  // char* nothing = "nothing";
  // return main(1, &nothing);
  printf("DEBUG: WinMain command-line: '%s'\n", lpCmdLine);
  return main(__argc, __argv); // See: https://stackoverflow.com/a/40107581
  return 0;
}
#endif // WINDOWS


uint32_t gTestVectors[10][6] {
  //NOTE: These are based on Q12.12...
  { // F1: Shows 0 line on X:
    0x00001800, // 1.500000
    0x0000D800, // 13.500000
    0x0000011E, // 0.069824
    0x00FFF00B, // -0.997314
    0x000007FA, // 0.498535
    0x0000008F, // 0.034912
  },
  { // F2: Shows oversized column:
    0x00001800, // 1.500000
    0x0000D800, // 13.500000
    0x00000198, // 0.099609
    0x00FFF015, // -0.994873
    0x000007F5, // 0.497314
    0x000000CC, // 0.049805
  },
  { // F3: Shows undersized column:
    0x00002172, // 2.090332
    0x0000D681, // 13.406494
    0x0000052F, // 0.323975
    0x00FFF0DE, // -0.945801
    0x00000791, // 0.472900
    0x00000297, // 0.161865
  },
  { // F4: Another undersized column:
    0x0000249A, // 2.287598
    0x0000C860, // 12.523438
    0x00000E9A, // 0.912598
    0x00FFF977, // -0.408447
    0x00000344, // 0.204102
    0x0000074D, // 0.456299
  },
  { // F5: 0 line on Y:
    0x0000250D, // 2.315674
    0x0000BB16, // 11.692871
    0x00000FF5, // 0.997314
    0x00FFFEDF, // -0.070557
    0x00000090, // 0.035156
    0x000007FA, // 0.498535
  },
  { // F6: Testing a little "jitter" on a wall block edge:
    0x000044C4, // 4.297852
    0x0000BC33, // 11.762451
    0x00000F7F, // 0.968506
    0x00FFFC09, // -0.247803
    0x000001FB, // 0.123779
    0x000007BF, // 0.484131
  },
  { // F7: HACK: 0.53125 vplane:
    0x00001800, // 1.500000
    0x0000D800, // 13.500000
    0x00000000, // 0.000000
    0x00FFF000, // -1.000000
    0x00000880, // 0.531250
    0x00000000, // 0.000000
  },
  { // F8: HACK: 0.5625 vplane:
    0x00001800, // 1.500000
    0x0000D800, // 13.500000
    0x00000000, // 0.000000
    0x00FFF000, // -1.000000
    0x00000900, // 0.562500
    0x00000000, // 0.000000
  },
  { // F9: HACK: 0.625 vplane:
    0x00001800, // 1.500000
    0x0000D800, // 13.500000
    0x00000000, // 0.000000
    0x00FFF000, // -1.000000
    0x00000A00, // 0.625000
    0x00000000, // 0.000000
  },
  { // F10: HACK: 0.75 vplane:
    0x00001800, // 1.500000
    0x0000D800, // 13.500000
    0x00000000, // 0.000000
    0x00FFF000, // -1.000000
    0x00000C00, // 0.750000
    0x00000000, // 0.000000
  },
};


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
int           gMouseX, gMouseY;
double        gMotionMultiplier = 1.0;
#ifdef WINDOWS
bool          gMouseCapture = true;
#else
bool          gMouseCapture = false; // Not on by default in Linux, because of possible mouse relative motion weirdness.
#endif

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


void recalc_override_vectors(const Uint8* k, int mouseX, int mouseY) {
  const double key_rotate_speed   = 0.01;
  const double mouse_rotate_speed = 0.001;
  const double move_quantum       = pow(2.0, -9.0); // This borrows from `playerMove` in the design, and in Q12.12 it is the raw value: 8
  const double playerCrawl        = move_quantum *  4.0;
  const double playerWalk         = move_quantum * 10.0; // Should be 0.01953125
  const double playerRun          = move_quantum * 18.0;
  const double playerMove         = playerWalk;
  bool fast = k[SDL_SCANCODE_LSHIFT];
  double m = fast ? playerRun : playerMove;
  m *= gMotionMultiplier;
  double r = key_rotate_speed;
  r *= gMotionMultiplier;
  if (fast) r *= 1.8;
  if (k[SDL_SCANCODE_LEFT])   rotate_override_vectors( r);
  if (k[SDL_SCANCODE_RIGHT])  rotate_override_vectors(-r);
  if (mouseX != 0)            rotate_override_vectors(-mouse_rotate_speed * double(mouseX));
  if (k[SDL_SCANCODE_W]) { gOvers.px += m * gOvers.fx;   gOvers.py += m * gOvers.fy; }
  if (k[SDL_SCANCODE_S]) { gOvers.px -= m * gOvers.fx;   gOvers.py -= m * gOvers.fy; }
  if (k[SDL_SCANCODE_A]) { gOvers.px -= m * gOvers.vx;   gOvers.py -= m * gOvers.vy; }
  if (k[SDL_SCANCODE_D]) { gOvers.px += m * gOvers.vx;   gOvers.py += m * gOvers.vy; }
}




void set_override_vectors() {
  // Convert gOvers to fixed-point values we can write back into the design:
#ifdef DESIGN_DIRECT_VECTOR_ACCESS
  TB->m_core->new_playerX = double2fixed(gOvers.px);
  TB->m_core->new_playerY = double2fixed(gOvers.py);
  TB->m_core->new_facingX = double2fixed(gOvers.fx);
  TB->m_core->new_facingY = double2fixed(gOvers.fy);
  TB->m_core->new_vplaneX = double2fixed(gOvers.vx);
  TB->m_core->new_vplaneY = double2fixed(gOvers.vy);
#else//!DESIGN_DIRECT_VECTOR_ACCESS
  #warning SPI vector access not yet implemented
#endif//DESIGN_DIRECT_VECTOR_ACCESS
}


void activate_vectors_override() {
  gOverrideVectors = 1;
  printf("Vectors override turned ON\n");
  get_override_vectors();
  // Turn off all input locks EXCEPT map:
  gLockInputs[LOCK_F] = gLockInputs[LOCK_B] = gLockInputs[LOCK_L] = gLockInputs[LOCK_R] = 0;
}


void toggle_mouse_capture(bool force = false, bool force_to = false) {
  if (!force) {
    gMouseCapture = !gMouseCapture;
  } else {
    gMouseCapture = force_to;
  }
  if (gMouseCapture) {
    int r = SDL_SetRelativeMouseMode(SDL_TRUE);
    if (r) {
      printf("SDL_SetRelativeMouseMode(SDL_TRUE) failed (%d): %s\n", r, SDL_GetError());
    } else {
      printf("Mouse captured.\n");
      gMouseX = 0;
      gMouseY = 0;
    }
  } else {
    int r = SDL_SetRelativeMouseMode(SDL_FALSE);
    if (r) {
      printf("SDL_SetRelativeMouseMode(SDL_FALSE) failed (%d): %s\n", r, SDL_GetError());
    } else {
      printf("Mouse released.\n");
    }
  }
}


void scale_motion_multiplier(double s) {
  gMotionMultiplier *= s;
  printf("Motion multiplier is now: %lf\n", gMotionMultiplier);
}


class RawImage {
public:
  uint8_t* m_raw;
  int width;
  int height;
  bool valid;
  RawImage() {
    width = 0;
    height = 0;
    m_raw = NULL;
    valid = false;
  }
  RawImage(const char* texture_file, int expect_width=0, int expect_height=0) : RawImage() {
    load_image(texture_file);
  }
  ~RawImage() {
    if (m_raw) delete m_raw;
  }
  void load_image(const char* f, int xw=0, int xh=0) {
    SDL_Surface* s = IMG_Load(f);
    if (!s) {
      printf("ERROR: Failed to load texture image file '%s' due to error '%s'\n", f, SDL_GetError());
      return;
    }
    width = s->w;
    height = s->h;
    if ( (xw && xw != width) || (xh && xh != height) ) {
      printf("ERROR: Image '%s' should be %dx%d pixels, but is: %dx%d\n", f, xw, xh, width, height);
      SDL_FreeSurface(s);
      return;
    }
    Uint32 fmt = s->format->format;
    if (fmt != SDL_PIXELFORMAT_RGB24) {
      printf("ERROR: Image '%s' is wrong pixel format. Was expecting %x but got %x\n", f, SDL_PIXELFORMAT_RGB24, fmt);
      SDL_FreeSurface(s);
      return;
    }
    // Load raw image data...
    SDL_LockSurface(s);
    m_raw = new uint8_t[width*height*3];
    for (int y = 0; y < height; ++y) {
      // Copy line by line, because of s->pitch.
      memcpy(m_raw + y*width*3, ((uint8_t*)(s->pixels)) + y*s->pitch, width*3 );
    }
    SDL_UnlockSurface(s);
    // Done:
    SDL_FreeSurface(s);
    valid = true;
  }
  uint8_t* rgba(int x, int y) {
    return m_raw+((y*width)+x)*3;
  }
  uint8_t r(int x, int y) { return rgba(x,y)[0]; }
  uint8_t g(int x, int y) { return rgba(x,y)[1]; }
  uint8_t b(int x, int y) { return rgba(x,y)[2]; }
  // uint8_t a(int x, int y) { return rgba(x,y)[3]; }
};


// Texture file is expected to be a 24-bit PNG that is 128x64px, with the left
// half of it being "bright" wall, and right half "dark" wall.
// Only the upper 2 bits should be used in each of the R,G,B channels, to be
// compatible with how Raybox currently works. The code just picks off the
// upper 2 bits of each channel anyway.
void load_texture_rom(const char *texture_file) {
  RawImage tex(texture_file, 128, 64);
  if (!tex.valid) {
    printf("ERROR: Texture ROM image %s is invalid\n", texture_file);
    return;
  } else {
    printf("DEBUG: Loaded texture ROM image %s\n", texture_file);
  }
  // Transfer texture image data into the design's wall_textures ROM,
  // while also writing out to assets/texture-xrgb-2222.hex:
  const char* tex_dump = "assets/texture-xrgb-2222.hex";
  printf("Dumping texture data to %s\n", tex_dump);
  FILE *f = fopen(tex_dump, "w");
  fprintf(f, "@00000000\n");
  int counter = 0;
  for (int x=0; x<tex.width; ++x) {
    for (int y=0; y<tex.height; ++y) {
      uint8_t r = (tex.r(x, y) & 0xC0) >> 6; // Upper 2 bits only.
      uint8_t g = (tex.g(x, y) & 0xC0) >> 6; // Upper 2 bits only.
      uint8_t b = (tex.b(x, y) & 0xC0) >> 6; // Upper 2 bits only.
      uint8_t v = (r<<4) | (g<<2) | (b);
      // TB->m_core->DESIGN->wall_textures->data[x][y] = v;
      fprintf(f, "%02X%c", v, counter%16==15 ? '\n' : ' ');
      ++counter;
    }
  }
  printf("DEBUG: Transferred texture ROM into raybox.wall_textures\n");
  fclose(f);
}



void convert_image_rom_png_to_hex(const char *infile, const char *outfile, int width, int height) {
  RawImage image(infile, width, height);
  if (!image.valid) {
    printf("ERROR: Image ROM file %s is invalid\n", infile);
    return;
  } else {
    printf("DEBUG: Loaded Image ROM %s\n", infile);
  }
  printf("Dumping Image ROM data to %s\n", outfile);
  FILE *f = fopen(outfile, "w");
  fprintf(f, "@00000000\n");
  int counter = 0;
  for (int x=0; x<image.width; ++x) {
    for (int y=0; y<image.height; ++y) {
      uint8_t r = (image.r(x, y) & 0xC0) >> 6; // Upper 2 bits only.
      uint8_t g = (image.g(x, y) & 0xC0) >> 6; // Upper 2 bits only.
      uint8_t b = (image.b(x, y) & 0xC0) >> 6; // Upper 2 bits only.
      uint8_t v = (r<<4) | (g<<2) | (b);
      fprintf(f, "%02X%c", v, counter%16==15 ? '\n' : ' ');
      ++counter;
    }
  }
  fclose(f);
}



void process_sdl_events() {
  // Event used to receive window close, keyboard actions, etc:
  SDL_Event e;
  // Consume SDL events, if any, until the event queue is empty:
  while (SDL_PollEvent(&e) == 1) {
    if (SDL_QUIT == e.type) {
      // SDL quit event (e.g. close window)?
      gQuit = true;
    // } else if (SDL_MOUSEMOTION == e.type) {
    //   int x = e.motion.xrel;
    //   int y = e.motion.yrel;
    //   printf("\t\t\t\t\t\t\t\t\t\t\t\t\tMouse motion: %d, %d\n", x, y);
    } else if (SDL_KEYDOWN == e.type) {
      int fn_key = 0;
      switch (e.key.keysym.sym) {
        case SDLK_F12:
          // Toggle mouse capture.
          toggle_mouse_capture();
          break;
        case SDLK_F10:++fn_key;
        case SDLK_F9: ++fn_key;
        case SDLK_F8: ++fn_key;
        case SDLK_F7: ++fn_key;
        case SDLK_F6: ++fn_key;
        case SDLK_F5: ++fn_key;
        case SDLK_F4: ++fn_key;
        case SDLK_F3: ++fn_key;
        case SDLK_F2: ++fn_key;
        case SDLK_F1: ++fn_key;
          {
            // Directly set override vectors...
            printf("Loading state #%d\n", fn_key);
            uint32_t* v = gTestVectors[fn_key-1];
            TB->m_core->DESIGN->playerX = *(v++);
            TB->m_core->DESIGN->playerY = *(v++);
            TB->m_core->DESIGN->facingX = *(v++);
            TB->m_core->DESIGN->facingY = *(v++);
            TB->m_core->DESIGN->vplaneX = *(v++);
            TB->m_core->DESIGN->vplaneY = *(v++);
            // ...then activate vectors override (which will reload gOvers from what we just set above):
            activate_vectors_override();
            break;
          }
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
        case SDLK_PAGEDOWN:
          scale_motion_multiplier(0.909091); // Deduct 10%
          break;
        case SDLK_PAGEUP:
          scale_motion_multiplier(1.1); // Add 10%
          break;
        case SDLK_i:
          // Inspect: Print out current vector data as C++ code:
          printf("\n// Vectors inspection data:\n");
          uint32_t v;
          v=TB->m_core->DESIGN->playerX; printf("TB->m_core->DESIGN->playerX = 0x%08X; // %lf\n", v, fixed2double(v));
          v=TB->m_core->DESIGN->playerY; printf("TB->m_core->DESIGN->playerY = 0x%08X; // %lf\n", v, fixed2double(v));
          v=TB->m_core->DESIGN->facingX; printf("TB->m_core->DESIGN->facingX = 0x%08X; // %lf\n", v, fixed2double(v));
          v=TB->m_core->DESIGN->facingY; printf("TB->m_core->DESIGN->facingY = 0x%08X; // %lf\n", v, fixed2double(v));
          v=TB->m_core->DESIGN->vplaneX; printf("TB->m_core->DESIGN->vplaneX = 0x%08X; // %lf\n", v, fixed2double(v));
          v=TB->m_core->DESIGN->vplaneY; printf("TB->m_core->DESIGN->vplaneY = 0x%08X; // %lf\n", v, fixed2double(v));
          printf("\n");
          if (KMOD_SHIFT & e.key.keysym.mod) {
            // Shift key held, so pause too.
            TB->pause(true);
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
            activate_vectors_override();
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
#ifdef DESIGN_DIRECT_VECTOR_ACCESS
              // Toggle direction inputs (and turn off any that are opposing):
              case SDLK_UP:     if (KMOD_SHIFT & e.key.keysym.mod) TB->m_core->moveF=1; else if( (gLockInputs[LOCK_F] ^= 1) ) gLockInputs[LOCK_B] = false; break;
              case SDLK_DOWN:   if (KMOD_SHIFT & e.key.keysym.mod) TB->m_core->moveB=1; else if( (gLockInputs[LOCK_B] ^= 1) ) gLockInputs[LOCK_F] = false; break;
              case SDLK_LEFT:   if (KMOD_SHIFT & e.key.keysym.mod) TB->m_core->moveL=1; else if( (gLockInputs[LOCK_L] ^= 1) ) gLockInputs[LOCK_R] = false; break;
              case SDLK_RIGHT:  if (KMOD_SHIFT & e.key.keysym.mod) TB->m_core->moveR=1; else if( (gLockInputs[LOCK_R] ^= 1) ) gLockInputs[LOCK_L] = false; break;
              // NOTE: If SHIFT is held, send momentary (1-frame) signal inputs instead of locks.
              //SMELL: This won't work if we're calling handle_control_inputs more often than once per frame...?
#else//!DESIGN_DIRECT_VECTOR_ACCESS
              #warning SPI vector access not yet implemented
#endif//DESIGN_DIRECT_VECTOR_ACCESS
            }
          }
          break;
      }
    }
  }
}


void set_write_new_position(int assert) {
#ifdef DESIGN_DIRECT_VECTOR_ACCESS
  TB->m_core->write_new_position = assert;
#else//!DESIGN_DIRECT_VECTOR_ACCESS
  #warning SPI vector access not yet implemented
#endif//DESIGN_DIRECT_VECTOR_ACCESS
}



//NOTE: handle_control_inputs is called twice; once with `true` before process_sdl_events, then once after with `false`.
void handle_control_inputs(bool prepare) {
  if (prepare) {
    // PREPARE mode: Clear all inputs, so process_sdl_events has a chance to preset MOMENTARY inputs:
    TB->m_core->reset     = 0;
    TB->m_core->show_map  = 0;
  #ifdef DESIGN_DIRECT_VECTOR_ACCESS
      TB->m_core->moveF     = 0;
      TB->m_core->moveL     = 0;
      TB->m_core->moveB     = 0;
      TB->m_core->moveR     = 0;
  #else//!DESIGN_DIRECT_VECTOR_ACCESS
      #warning SPI vector access not yet implemented
  #endif//DESIGN_DIRECT_VECTOR_ACCESS

#ifdef DEBUG_BUTTON_INPUTS
    TB->m_core->debugA    = 0;
    TB->m_core->debugB    = 0;
    TB->m_core->debugC    = 0;
    TB->m_core->debugD    = 0;
#endif // DEBUG_BUTTON_INPUTS
  }
  else {

    int mouseX, mouseY;
    if (gMouseCapture) {
      uint32_t buttons = SDL_GetRelativeMouseState(&mouseX, &mouseY);
      gMouseX += mouseX;
      gMouseY += mouseY;
      // printf("\t\t\t\t\t\t\t\t\t\tMouse motion: %6d, %6d\tGlobal pos: %7d, %7d\n", mouseX, mouseY, gMouseX, gMouseY);
    } else {
      mouseX = 0;
      mouseY = 0;
    }

    // ACTIVE mode: Read the momentary state of all keyboard keys, and add them via `|=` to whatever is already asserted:
    auto keystate = SDL_GetKeyboardState(NULL);

    if (gOverrideVectors) {
      recalc_override_vectors(keystate, mouseX, mouseY);
      set_override_vectors();
      set_write_new_position(1);
    } else {
      set_write_new_position(0);
    }

    TB->m_core->show_debug = 1;
    TB->m_core->reset     |= keystate[SDL_SCANCODE_R];
    TB->m_core->show_map  |= keystate[SDL_SCANCODE_TAB ] | gLockInputs[LOCK_MAP];

    #ifdef DESIGN_DIRECT_VECTOR_ACCESS
      TB->m_core->moveF     |= keystate[SDL_SCANCODE_W   ] | gLockInputs[LOCK_F];
      TB->m_core->moveL     |= keystate[SDL_SCANCODE_A   ] | gLockInputs[LOCK_L];
      TB->m_core->moveB     |= keystate[SDL_SCANCODE_S   ] | gLockInputs[LOCK_B];
      TB->m_core->moveR     |= keystate[SDL_SCANCODE_D   ] | gLockInputs[LOCK_R];
    #else//!DESIGN_DIRECT_VECTOR_ACCESS
      #warning SPI vector access not yet implemented
    #endif//DESIGN_DIRECT_VECTOR_ACCESS

#ifdef DEBUG_BUTTON_INPUTS
    TB->m_core->debugA    |= keystate[SDL_SCANCODE_KP_4];
    TB->m_core->debugB    |= keystate[SDL_SCANCODE_KP_6];
    TB->m_core->debugC    |= keystate[SDL_SCANCODE_KP_2];
    TB->m_core->debugD    |= keystate[SDL_SCANCODE_KP_8];
#endif // DEBUG_BUTTON_INPUTS
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
    // Mouse crosshairs:
    // X axis, vertical line:
    int mx = gMouseX + HDA/2;
    int my = gMouseY + VDA/2;
    if (mx >= 0 && mx < HDA) {
      for (int y = 0; y < WINDOW_HEIGHT; ++y) {
          fb[(mx+h_shift+y*WINDOW_WIDTH)*4 + 0] |= 0b0110'0000;
          fb[(mx+h_shift+y*WINDOW_WIDTH)*4 + 1] |= 0b0110'0000;
          fb[(mx+h_shift+y*WINDOW_WIDTH)*4 + 2] |= 0b0110'0000;
      }
    }
    if (my >= 0 && my < VDA) {
      for (int x = 0; x < WINDOW_WIDTH; ++x) {
          fb[(x+(my+v_shift)*WINDOW_WIDTH)*4 + 0] |= 0b0110'0000;
          fb[(x+(my+v_shift)*WINDOW_WIDTH)*4 + 1] |= 0b0110'0000;
          fb[(x+(my+v_shift)*WINDOW_WIDTH)*4 + 2] |= 0b0110'0000;
      }
    }
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

  printf("DEBUG: main() command-line arguments:\n");
  for (int i = 0; i < argc; ++i) {
    printf("%d: [%s]\n", i, argv[i]);
  }

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

  toggle_mouse_capture(true, gMouseCapture); // Dummy "toggle" to just set current mode, in order to print it.

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

  //SMELL: This isn't actually used anymore because now the ROM data is embedded in the Verilog:
  // load_texture_rom("assets/blue-wall-222.png");
  //SMELL: Image conversion should now be done when needed with utils/asset_tool:
  // convert_image_rom_png_to_hex("assets/Wolf3D-guard-sprite-RGB222.png", "assets/sprite-xrgb-2222.hex", 64, 64);
  
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
      TB->tick();      hsync_stopped |= TB->hsync_stopped();      vsync_stopped |= TB->vsync_stopped();
#ifdef USE_SPEAKER
      TB->examine_condition_met |= TB->m_core->speaker;
#endif // USE_SPEAKER

#ifdef DOUBLE_CLOCK
      TB->tick();      hsync_stopped |= TB->hsync_stopped();      vsync_stopped |= TB->vsync_stopped();
#ifdef USE_SPEAKER
      TB->examine_condition_met |= TB->m_core->speaker;
#endif // USE_SPEAKER
      // ^ We tick twice if the design halves the clock to produce the pixel clock.
#endif // DOUBLE_CLOCK

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

#ifdef USE_SPEAKER
      int speaker = (TB->m_core->speaker<<6);
#else
      int speaker = 0;
#endif // USE_SPEAKER
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
      // Show the state of controls that can be toggled:
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
      s += gMouseCapture        ? "*" : ".";
#ifdef INSPECT_INTERNAL
      s += "] ";
      // Player position:
      s += " pX,Y=("
        + to_string(fixed2double(TB->m_core->DESIGN->playerX)) + ", "
        + to_string(fixed2double(TB->m_core->DESIGN->playerY)) + ") ";
      s += " fX,Y=("
        + to_string(fixed2double(TB->m_core->DESIGN->facingX)) + ", "
        + to_string(fixed2double(TB->m_core->DESIGN->facingY)) + ") ";
      s += " vX,Y=("
        + to_string(fixed2double(TB->m_core->DESIGN->vplaneX)) + ", "
        + to_string(fixed2double(TB->m_core->DESIGN->vplaneY)) + ") ";
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

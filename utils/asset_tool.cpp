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
// #include <iostream>
// #include <string>
// using namespace std;

#include <SDL2/SDL.h>
#include <SDL2/SDL_image.h>


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
    load_image(texture_file, expect_width, expect_height);
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
    if (fmt != SDL_PIXELFORMAT_RGB24) { //NOTE: 24-bit, not 32-bit (i.e. no alpha channel).
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
  uint8_t* rgb(int x, int y) {
    return m_raw+((y*width)+x)*3;
  }
  uint8_t r(int x, int y) { return rgb(x,y)[0]; }
  uint8_t g(int x, int y) { return rgb(x,y)[1]; }
  uint8_t b(int x, int y) { return rgb(x,y)[2]; }
  // Returns 24-bit RGB value packed in a 32-bit uint: 0x00RRGGBB:
  uint32_t xrgb(int x, int y) {
    uint8_t* c = rgb(x, y);
    return (c[0]<<16) | (c[1]<<8) | c[2];
  }
  // Return a packed RGB222 pixel value, i.e. 0b00rrggbb
  uint8_t xrgb222(int x, int y) {
    return (r(x,y)&0xC0)>>2 | (g(x,y)&0xC0)>>4 | (b(x,y)&0xC0)>>6;
  }
};

int convert_base(const char *source, const char *target, int width, int height, bool is_map) {
  RawImage img;
  img.load_image(source, width, height);
  if (!img.valid) return 1;
  FILE* f = fopen(target, "w");
  // fprintf(f, "@00000000\n");
  int counter = 0;
  //NOTE: Output hex file runs by rows before columns:
  for (int x=0; x<width; ++x) {
    for (int y=0; y<height; ++y) {
      int c = img.xrgb222(x,y);
      if (is_map) {
        switch (c) {
          case 0b00000000:  c = 0b00; break;
          case 0b00000011:  c = 0b01; break;
          case 0b00110000:  c = 0b10; break;
          case 0b00111111:  c = 0b11; break;
          default:
          {
            printf("ERROR: Map uses invalid colour: %02X\n", c);
            fclose(f);
            return 1;
          }
        }
      }
      fprintf(f, "%02X%c", c, ((counter++ & 15) == 15) ? '\n' : ' ');
    }
  }
  fclose(f);
  return 0;
}


int convert_sprite  (const char *source, const char *target) { return convert_base(source, target,  64, 64, false); }
int convert_wall    (const char *source, const char *target) { return convert_base(source, target, 128, 64, false); }
int convert_map     (const char *source, const char *target) { return convert_base(source, target,  64, 64, true); }


int main(int argc, char **argv) {
  bool bad_args;
  char* cmd = argv[1];
  do {
    bad_args = true;
    if (argc!=4) break;
    if (0 == strcmp(cmd, "sprite")) {
      return convert_sprite(argv[2], argv[3]);
    } else if (0 == strcmp(cmd, "wall")) {
      return convert_wall(argv[2], argv[3]);
    } else if (0 == strcmp(cmd, "map")) {
      return convert_map(argv[2], argv[3]);
    } else {
      printf("ERROR: Unknown command: '%s'\n", cmd);
      break;
    }
  } while (false);
  if (bad_args) {
    printf(
      "Usage: %s command inputimage.png outputrom.hex\n"
      "where 'command' is one of:\n"
      "  sprite  = Convert single 64x64 sprite\n"
      "  wall    = Convert single 128x64 wall pair\n"
      "  map     = Convert a 64x64 map\n",
      *argv
    );
  }
}

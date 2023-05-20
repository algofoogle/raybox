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


int main(int argc, char **argv) {
    RawImage sprite;
    if (argc!=3) {
        printf("Usage: %s inputimage.png outputrom.hex\n", *argv);
    }
    sprite.load_image(argv[1], 64, 64);
    if (!sprite.valid) return 1;
    FILE* f = fopen(argv[2], "w");
    fprintf(f, "@00000000\n");
    int counter = 0;
    //NOTE: Output hex file runs by rows before columns:
    for (int x=0; x<sprite.width; ++x) {
        for (int y=0; y<sprite.height; ++y) {
            fprintf(f, "%02X%c", sprite.xrgb222(x,y), ((counter++ & 15) == 15) ? '\n' : ' ');
        }
    }
    fclose(f);
}

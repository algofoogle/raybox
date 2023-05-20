# Raybox Utils

Not much in here yet.

Currently there is `asset_tool` which is so far hard-coded to be used like this:

```bash
utils/asset_tool assets/mysprite.png assets/mysprite.hex
```

...which expects an input RGB888 (24-bit colour) PNG file that is 64x64, and will
crunch it down to RGB222, writing each pixel out as a HEX file byte (but running
by Y axis first, then X). This suits how Raybox is currently implemented
(but might change in future).

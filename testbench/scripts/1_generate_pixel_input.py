#!/usr/bin/env python3
"""Convert a 32x32 RGB PNG to the testbench's `pixel_input.txt` format.

Also saves `encoded_image.png` beside the pixel text file: a direct render of
the thermometer-coded values (linear scale 0→127 as 0→255) so you can see the
quantisation introduced by the encoder before running any simulation.

Output format (top-row major, one pixel per line):

    # Test image 32x32 RGB
    # Format: "C0 C1 C2" hex per pixel, top-row major.
    # Channel mapping: C0 = R, C1 = G, C2 = B.
    # Pixel order: (0,0), (0,1), ..., (0,31), (1,0), ..., (31,31)
    FF AA 33
    12 34 56
    ...

This is the file the VHDL testbench reads. The same file is also consumed
by the on-board notebook (it just packs the values into 32-bit DMA words),
so simulation and hardware test the exact same input.
"""

from __future__ import annotations

import argparse
import os
import sys

import numpy as np

# Project root one level up
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from PIL import Image                                                # noqa: E402

from lib.encoding  import thermometer_encode_array                  # noqa: E402
from lib.visualize import encoded_image_to_pil                      # noqa: E402


def write_pixel_input(png_path: str, out_path: str,
                      img_size: int = 32) -> None:
    img = Image.open(png_path).convert("RGB")
    if img.size != (img_size, img_size):
        # The shipped image is a 32x32 inside a white-padded canvas;
        # crop to top-left img_size×img_size as a safe default.
        if img.size[0] >= img_size and img.size[1] >= img_size:
            print(f"warning: input is {img.size}, cropping top-left "
                  f"{img_size}x{img_size}")
            img = img.crop((0, 0, img_size, img_size))
        else:
            print(f"warning: input is {img.size}, resizing to "
                  f"{img_size}x{img_size}")
            img = img.resize((img_size, img_size), Image.NEAREST)

    raw = np.array(img, dtype=np.uint8)                # (H, W, 3)
    pixels = [(int(raw[r, c, 0]), int(raw[r, c, 1]), int(raw[r, c, 2]))
              for r in range(img_size) for c in range(img_size)]

    # ── Thermometer-encode all channels ──────────────────────────────────────
    enc = thermometer_encode_array(raw)                # (H, W, 3), values 0-127
    unique_vals = sorted(set(int(v) for v in enc.flat))
    print(f"raw min/max  : {raw.min()}, {raw.max()}")
    print(f"enc unique   : {unique_vals}")

    # ── Write pixel_input.txt ─────────────────────────────────────────────────
    with open(out_path, "w") as f:
        f.write("# Test image 32x32 RGB\n")
        f.write("# Format: \"C0 C1 C2\" hex per pixel, top-row major.\n")
        f.write("# Channel mapping: C0 = R, C1 = G, C2 = B.\n")
        f.write("# Pixel order: (0,0), (0,1), ..., (row,col), ... (31,31)\n")
        for r, g, b in pixels:
            f.write(f"{r:02X} {g:02X} {b:02X}\n")
    print(f"wrote {len(pixels)} pixels  -> {out_path}")

    # ── Save encoded image (as-is: raw thermometer values, 0-127 -> 0-255) ──
    enc_img = encoded_image_to_pil(enc, as_is=True)
    enc_out = os.path.join(os.path.dirname(out_path), "encoded_image.png")
    # Save at a legible size
    enc_img.resize((img_size * 8, img_size * 8), Image.NEAREST).save(enc_out)
    print(f"encoded image (as-is, 8x scale)  -> {enc_out}")


def main() -> None:
    here = os.path.dirname(os.path.abspath(__file__))
    root = os.path.dirname(here)
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--png", default=os.path.join(root, "data",
                                                      "test_image_32x32_rgb.png"))
    parser.add_argument("--out", default=os.path.join(root, "sim",
                                                      "pixel_input.txt"))
    args = parser.parse_args()
    write_pixel_input(args.png, args.out)


if __name__ == "__main__":
    main()
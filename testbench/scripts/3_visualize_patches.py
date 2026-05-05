#!/usr/bin/env python3
"""Render parsed patches as images so the RTL output can be eyeballed.

Produces six artefacts in `sim/`:

  Inverse-decoded (bin_idx → centre of original 8-bit bin):
    patch_0.png          - first patch, scaled up. Should match top-left 7x7 of input.
    patch_grid.png       - all patches at their decoded (x,y) positions.
    patch_recon.png      - overlap-averaged stitch into a 32x32 reconstruction.

  As-is (raw thermometer value × 255/127, no inverse decode):
    patch_0_encoded.png  - first patch, as stored in the payload.
    patch_grid_encoded.png
    patch_recon_encoded.png

The "encoded" set shows exactly what the hardware produced, without any
approximation of the original pixel colours. The 8 distinct brightness levels
correspond to the 8 thermometer bins (0, 1, 3, 7, 15, 31, 63, 127).
"""

from __future__ import annotations

import argparse
import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from lib.payload import Patch, PS                                   # noqa: E402
from lib.visualize import (                                          # noqa: E402
    patch_to_image, patches_to_grid, reconstruct_image,
)


def load_patches(path: str):
    z = np.load(path)
    n = len(z["word_index"])
    return [
        Patch(
            word_index=int(z["word_index"][i]),
            x_pos_raw=int(z["x_pos_raw"][i]),
            y_pos_raw=int(z["y_pos_raw"][i]),
            x_index=int(z["x_index"][i]),
            y_index=int(z["y_index"][i]),
            c0=z["c0"][i],
            c1=z["c1"][i],
            c2=z["c2"][i],
        )
        for i in range(n)
    ]


def save(img, path: str, label: str, scale: int = 1) -> None:
    if scale > 1:
        img = img.resize((img.width * scale, img.height * scale))
    img.save(path)
    print(f"saved {path}  ({img.width}x{img.height})  [{label}]")


def main() -> None:
    here = os.path.dirname(os.path.abspath(__file__))
    root = os.path.dirname(here)
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--input", default=os.path.join(root, "sim",
                                                        "patches.npz"))
    parser.add_argument("--out-dir", default=os.path.join(root, "sim"))
    parser.add_argument("--cell", type=int, default=8,
                        help="canvas cell size for the grid views (default 8)")
    args = parser.parse_args()

    if not os.path.isfile(args.input):
        sys.exit(f"error: {args.input} not found — run script 2 first")

    patches = load_patches(args.input)
    print(f"loaded {len(patches)} patches")
    d = args.out_dir
    os.makedirs(d, exist_ok=True)

    p0 = patches[0]

    # ── Inverse-decoded outputs ───────────────────────────────────────────────
    print("\n── inverse-decoded (bin_idx → 8-bit centre) ──")
    save(patch_to_image(p0, scale=20),
         os.path.join(d, "patch_0.png"),
         f"patch 0 @ x={p0.x_index} y={p0.y_index}, decoded")

    save(patches_to_grid(patches, cell=args.cell, use_position=True, as_is=False),
         os.path.join(d, "patch_grid.png"),
         "all patches at decoded positions, decoded")

    save(reconstruct_image(patches, img_size=32, as_is=False),
         os.path.join(d, "patch_recon.png"),
         "32x32 reconstruction, decoded", scale=8)

    # ── As-is (raw thermometer value) outputs ────────────────────────────────
    print("\n── as-is (thermometer value × 255/127) ──")
    save(patch_to_image(p0, scale=20, as_is=True),
         os.path.join(d, "patch_0_encoded.png"),
         f"patch 0 @ x={p0.x_index} y={p0.y_index}, as-is")

    save(patches_to_grid(patches, cell=args.cell, use_position=True, as_is=True),
         os.path.join(d, "patch_grid_encoded.png"),
         "all patches at decoded positions, as-is")

    save(reconstruct_image(patches, img_size=32, as_is=True),
         os.path.join(d, "patch_recon_encoded.png"),
         "32x32 reconstruction, as-is", scale=8)


if __name__ == "__main__":
    main()
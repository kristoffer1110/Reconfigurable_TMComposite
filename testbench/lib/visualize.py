"""Patch visualisation — renders patches AS THEY APPEAR IN THE PAYLOAD.

The goal is verification, not pretty pictures: if `patch[row][col]` is read
from the payload exactly as packed by `axis_patch_out`, and we draw it with
row 0 on top and col 0 on the left, then the first patch must look like the
top-left ps×ps corner of the input image. Any rotation, mirror, or shift in
the rendering tells us something is wrong in the RTL or in the packing.
"""

from __future__ import annotations

from typing import List, Sequence, Tuple

import numpy as np
from PIL import Image

from .encoding import thermometer_to_intensity
from .payload import PS, ENC_BITS, Patch


# ── Two rendering modes ───────────────────────────────────────────────────────
#
# "decoded"  — bin-index inverse: maps each 7-bit thermometer code back through
#              popcount → bin_idx → centre of original 8-bit bin.  Closest to
#              the true pixel colour; used for visual plausibility checks.
#
# "as_is"    — linear scale only: value × 255 / 127. Shows exactly what the
#              hardware stores in the payload — no extra interpretation step.
#              Use this to verify the encoding itself; the 8 visible grey
#              levels are the 8 thermometer bins.
#
# Channel mapping is the same in both modes: C0 → R, C1 → G, C2 → B.

def channels_to_rgb(c0: np.ndarray, c1: np.ndarray, c2: np.ndarray,
                    enc_bits: int = ENC_BITS,
                    as_is: bool = False) -> np.ndarray:
    """Convert three thermometer-encoded channel arrays to an H×W×3 uint8 RGB.

    Parameters
    ----------
    c0, c1, c2 : ndarray
        7-bit thermometer values, shape (H, W).
    enc_bits : int
        Number of encoding bits (default 7, must match the IP generic).
    as_is : bool
        If False (default), decode through the inverse thermometer function so
        the output approximates the original pixel colour.
        If True, scale linearly: out = value * 255 // (2**enc_bits - 1).
        Use ``as_is=True`` to see the raw payload values without interpretation.
    """
    if as_is:
        scale = 255 / ((1 << enc_bits) - 1)
        def _conv(arr: np.ndarray) -> np.ndarray:
            return np.clip(np.round(arr.astype(np.float32) * scale),
                           0, 255).astype(np.uint8)
        rgb = np.stack([_conv(c0), _conv(c1), _conv(c2)], axis=-1)
    else:
        decode = np.vectorize(lambda v: thermometer_to_intensity(int(v), enc_bits),
                              otypes=[np.uint8])
        rgb = np.stack([decode(c0), decode(c1), decode(c2)], axis=-1)
    return rgb


# ── Encoded full image ────────────────────────────────────────────────────────
def encoded_image_to_pil(raw_image: np.ndarray,
                          enc_bits: int = ENC_BITS,
                          as_is: bool = True) -> Image.Image:
    """Render a thermometer-encoded H×W×3 image array as a PIL Image.

    ``raw_image`` should contain 7-bit thermometer values (dtype uint8), with
    channel order [R-channel, G-channel, B-channel] → [C0, C1, C2].

    By default uses ``as_is=True`` so each pixel colour reflects the stored
    thermometer code directly, with no extra inverse-decode step.
    """
    rgb = channels_to_rgb(raw_image[..., 0], raw_image[..., 1],
                          raw_image[..., 2],
                          enc_bits=enc_bits, as_is=as_is)
    return Image.fromarray(rgb, mode="RGB")


# ── Single patch ─────────────────────────────────────────────────────────────
def patch_to_image(patch: Patch, scale: int = 1,
                   as_is: bool = False) -> Image.Image:
    """Render one patch as it appears in the payload (row 0 on top, col 0 left).

    `scale` magnifies the result by an integer factor with nearest-neighbour
    interpolation so individual pixels stay visible.

    Set ``as_is=True`` to render raw thermometer values (linear 0–127 → 0–255)
    instead of applying the inverse thermometer decode.
    """
    rgb = channels_to_rgb(patch.c0, patch.c1, patch.c2, as_is=as_is)
    img = Image.fromarray(rgb, mode="RGB")
    if scale != 1:
        img = img.resize((PS * scale, PS * scale), Image.NEAREST)
    return img


# ── Grid of patches placed at their (x_index, y_index) ───────────────────────
def patches_to_grid(patches: Sequence[Patch],
                    cell: int = PS,
                    use_position: bool = True,
                    as_is: bool = False,
                    step: int = 7) -> Image.Image:
    """Tile patches into a single image.

    If `use_position` is True (default), only patches whose x_index and
    y_index are both multiples of `step` are kept, then placed adjacent to
    each other by normalising their positions to (x_index // step,
    y_index // step). With step=PS this gives a gapless non-overlapping
    reconstruction of the source image.

    If False, every nth patch in transmission order is packed in a square
    grid — useful when position decoding itself is suspect.

    ``as_is=True`` passes through to :func:`patch_to_image`.
    ``cell`` defaults to PS so each patch fills its canvas cell exactly.
    """
    if not patches:
        raise ValueError("no patches to render")

    if use_position:
        # Retain only patches that sit on the step-aligned grid so the
        # reconstruction is gap-free and non-overlapping.
        patches = [p for p in patches
                   if p.x_index % step == 0 and p.y_index % step == 0]
        if not patches:
            raise ValueError("no patches survive the step filter — "
                             "check that step divides into the patch positions")
        cols = max(p.x_index // step for p in patches) + 1
        rows = max(p.y_index // step for p in patches) + 1
    else:
        patches = list(patches)[::step]
        side = int(np.ceil(np.sqrt(len(patches))))
        cols = rows = side

    canvas = Image.new("RGB", (cols * cell, rows * cell), color=(0, 0, 0))
    for idx, p in enumerate(patches):
        if use_position:
            cx, cy = p.x_index // step, p.y_index // step
        else:
            cx, cy = idx % cols, idx // cols
        canvas.paste(patch_to_image(p, scale=max(1, cell // PS), as_is=as_is),
                     (cx * cell, cy * cell))
    return canvas


# ── Reconstructed full image (overlapping patches, average overlap) ──────────
def reconstruct_image(patches: Sequence[Patch],
                      img_size: int = 32,
                      as_is: bool = False) -> Image.Image:
    """Stitch overlapping patches into a single image of the original size.

    Each output pixel is the mean of all patches that cover it. If patches
    are top-row major and positions are correct, this should very closely
    resemble the test image (modulo thermometer quantisation).

    ``as_is=True`` renders with raw thermometer scaling instead of the
    inverse-decode path.
    """
    if not patches:
        raise ValueError("no patches to render")

    accum = np.zeros((img_size, img_size, 3), dtype=np.float32)
    count = np.zeros((img_size, img_size, 1), dtype=np.float32)

    for p in patches:
        rgb = channels_to_rgb(p.c0, p.c1, p.c2, as_is=as_is).astype(np.float32)
        y0, x0 = p.y_index, p.x_index
        if y0 + PS > img_size or x0 + PS > img_size:
            continue
        accum[y0:y0 + PS, x0:x0 + PS, :] += rgb
        count[y0:y0 + PS, x0:x0 + PS, :] += 1.0

    count = np.where(count == 0, 1.0, count)
    out = (accum / count).clip(0, 255).astype(np.uint8)
    return Image.fromarray(out, mode="RGB")
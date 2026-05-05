"""Thermometer encoder — bit-exact mirror of pixel_encoder.vhd.

VHDL reference (pixel_encoder.vhd):

    bin_idx := pixel_val srl (PX_BITS - clog2(ENC_BITS + 1))
    if bin_idx = 0 then
        encoded_val := (others => '0')
    else
        encoded_val := (1 sll bin_idx) - 1

For PX_BITS=8, ENC_BITS=7 -> clog2(8)=3, so bin_idx = pixel >> 5,
bin_idx in [0,7], producing the thermometer codes:

    bin_idx  pixel range   encoded (bin)   encoded (hex)
       0        0 -  31    0000000          0x00
       1       32 -  63    0000001          0x01
       2       64 -  95    0000011          0x03
       3       96 - 127    0000111          0x07
       4      128 - 159    0001111          0x0F
       5      160 - 191    0011111          0x1F
       6      192 - 223    0111111          0x3F
       7      224 - 255    1111111          0x7F
"""

from __future__ import annotations

import numpy as np


def clog2(n: int) -> int:
    """Mirror of the VHDL clog2 function in Functions.vhd."""
    if n <= 1:
        return 0
    v, r = n - 1, 0
    while v > 0:
        v //= 2
        r += 1
    return r


def thermometer_encode(value: int, px_bits: int = 8, enc_bits: int = 7) -> int:
    """Encode a single unsigned pixel value to its thermometer code."""
    if not 0 <= value < (1 << px_bits):
        raise ValueError(f"value {value} out of range [0, {1 << px_bits})")
    bin_idx = value >> (px_bits - clog2(enc_bits + 1))
    return 0 if bin_idx == 0 else (1 << bin_idx) - 1


def thermometer_encode_array(arr, px_bits: int = 8, enc_bits: int = 7):
    """Vectorised version. Accepts any array-like of integers."""
    a = np.asarray(arr, dtype=np.int32)
    bin_idx = a >> (px_bits - clog2(enc_bits + 1))
    out = np.where(bin_idx == 0, 0, (1 << bin_idx) - 1)
    return out.astype(np.uint8)


def thermometer_to_intensity(code: int, enc_bits: int = 7) -> int:
    """Approximate inverse: recover an 8-bit intensity from a thermometer code.

    Uses popcount to recover bin_idx, then maps to the centre of the original
    bin so visualisations look reasonable even though encoding is lossy.
    """
    bin_idx = bin(code & ((1 << enc_bits) - 1)).count("1")
    # bin_idx in [0, enc_bits]; map to centre of input bin width 2^(8-3) = 32
    return min(255, bin_idx * 32 + (16 if bin_idx > 0 else 0))


if __name__ == "__main__":
    # Sanity check: print the encoding table
    print("value  -> encoded (bin)        hex")
    for v in [0, 31, 32, 63, 64, 127, 128, 191, 192, 223, 224, 255]:
        c = thermometer_encode(v)
        print(f"  {v:3d}  -> {c:07b}              0x{c:02X}")
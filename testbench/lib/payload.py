"""Payload pack/unpack — mirrors axis_patch_out.vhd exactly.

Payload bit layout (1088 bits total; word 0 transmitted first occupies the MSB):

      bit 1087  ... bit 1059 : y_pos       (29 bits, one-hot accumulator)
      bit 1058  ... bit 1030 : x_pos       (29 bits, one-hot accumulator)
      bit 1029  ... bit    1 : pixels      (49 * 21 = 1029 bits)
      bit    0               : zero padding

Each pixel occupies 21 bits, ordered top-row major (i = row*PS + col,
i=0 is top-left). Inside one pixel slot, channels are interleaved C0|C1|C2,
each 7 bits, MSB first:

      pixel i:
          C0 -> [1029-21i : 1023-21i]
          C1 -> [1022-21i : 1016-21i]
          C2 -> [1015-21i : 1009-21i]

The position registers in patches_v5.vhd are implemented as one-hot shift
registers shifting in '1's at index 0, so they end up as a unary count of
the patch column / row. The number of '1' bits == column or row index.
"""

from __future__ import annotations

from dataclasses import dataclass
from typing import List

import numpy as np


# ── Layout constants (must match the VHDL generics) ──────────────────────────
PS              = 7
ENC_BITS        = 7
POS_BITS        = 29
WORDS_PER_PATCH = 34                      # ceil((2*POS_BITS + 3*PS*PS*ENC_BITS) / 32)
TOTAL_BITS      = WORDS_PER_PATCH * 32    # 1088
PIX_BITS        = 3 * ENC_BITS            # 21 bits per RGB pixel


@dataclass
class Patch:
    """Decoded patch as it appears in the payload."""
    word_index: int                       # which patch in the stream (0..N-1)
    x_pos_raw:  int                       # raw 29-bit one-hot register value
    y_pos_raw:  int
    x_index:    int                       # decoded column index (popcount)
    y_index:    int                       # decoded row index (popcount)
    c0:         np.ndarray                # shape (PS, PS), uint8, top-row major
    c1:         np.ndarray
    c2:         np.ndarray


# ── Word ⇄ payload ───────────────────────────────────────────────────────────
def words_to_payload(words) -> int:
    """Combine WORDS_PER_PATCH 32-bit words into a single 1088-bit int.
    Word 0 (transmitted first) goes to the MSB."""
    if len(words) != WORDS_PER_PATCH:
        raise ValueError(f"expected {WORDS_PER_PATCH} words, got {len(words)}")
    raw = 0
    for w in words:
        raw = (raw << 32) | (int(w) & 0xFFFFFFFF)
    return raw


def payload_to_words(raw: int) -> List[int]:
    """Inverse: split 1088-bit int into 34 32-bit words, MSB-word first."""
    return [(raw >> (32 * (WORDS_PER_PATCH - 1 - i))) & 0xFFFFFFFF
            for i in range(WORDS_PER_PATCH)]


# ── Payload ⇄ Patch ──────────────────────────────────────────────────────────
def unpack_payload(raw: int, word_index: int = 0) -> Patch:
    """Decode one payload integer into a Patch."""
    pos_mask    = (1 << POS_BITS) - 1
    enc_mask    = (1 << ENC_BITS) - 1

    y_pos = (raw >> (TOTAL_BITS -     POS_BITS)) & pos_mask
    x_pos = (raw >> (TOTAL_BITS - 2 * POS_BITS)) & pos_mask

    pixel_section_top = TOTAL_BITS - 2 * POS_BITS    # 1030

    c0 = np.zeros((PS, PS), dtype=np.uint8)
    c1 = np.zeros((PS, PS), dtype=np.uint8)
    c2 = np.zeros((PS, PS), dtype=np.uint8)

    for i in range(PS * PS):
        row, col = divmod(i, PS)                       # i=0 → top-left
        c0_shift = pixel_section_top - i * PIX_BITS - 1 * ENC_BITS
        c1_shift = c0_shift - ENC_BITS
        c2_shift = c1_shift - ENC_BITS
        c0[row, col] = (raw >> c0_shift) & enc_mask
        c1[row, col] = (raw >> c1_shift) & enc_mask
        c2[row, col] = (raw >> c2_shift) & enc_mask

    return Patch(
        word_index=word_index,
        x_pos_raw=x_pos,
        y_pos_raw=y_pos,
        x_index=bin(x_pos).count("1"),
        y_index=bin(y_pos).count("1"),
        c0=c0, c1=c1, c2=c2,
    )


def pack_patch(patch: Patch) -> int:
    """Inverse of unpack_payload — build a 1088-bit payload from a Patch.

    Useful for golden-model self-tests of the unpack code.
    """
    raw = 0
    raw |= (patch.y_pos_raw & ((1 << POS_BITS) - 1)) << (TOTAL_BITS - POS_BITS)
    raw |= (patch.x_pos_raw & ((1 << POS_BITS) - 1)) << (TOTAL_BITS - 2 * POS_BITS)
    pixel_section_top = TOTAL_BITS - 2 * POS_BITS
    enc_mask = (1 << ENC_BITS) - 1
    for i in range(PS * PS):
        row, col = divmod(i, PS)
        c0_shift = pixel_section_top - i * PIX_BITS - 1 * ENC_BITS
        c1_shift = c0_shift - ENC_BITS
        c2_shift = c1_shift - ENC_BITS
        raw |= (int(patch.c0[row, col]) & enc_mask) << c0_shift
        raw |= (int(patch.c1[row, col]) & enc_mask) << c1_shift
        raw |= (int(patch.c2[row, col]) & enc_mask) << c2_shift
    return raw


# ── High-level helpers ───────────────────────────────────────────────────────
def parse_patches_from_words(all_words) -> List[Patch]:
    """Parse a flat sequence of 32-bit words (length = N * WORDS_PER_PATCH)
    into a list of Patch objects."""
    arr = np.asarray(all_words, dtype=np.uint32)
    if arr.size % WORDS_PER_PATCH != 0:
        raise ValueError(
            f"length {arr.size} not divisible by WORDS_PER_PATCH={WORDS_PER_PATCH}"
        )
    n = arr.size // WORDS_PER_PATCH
    return [
        unpack_payload(words_to_payload(arr[p * WORDS_PER_PATCH:
                                            (p + 1) * WORDS_PER_PATCH]),
                       word_index=p)
        for p in range(n)
    ]


def parse_tb_output_file(path: str) -> List[Patch]:
    """Parse the testbench's tb_output.txt format:

        PATCH <n> WORD <w> DATA <hex> [TLAST]

    Returns a list of Patch objects in transmission order.
    """
    words: List[int] = []
    with open(path) as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith("#"):
                continue
            parts = line.split()
            # parts: PATCH n WORD w DATA hex [TLAST]
            try:
                data_idx = parts.index("DATA")
                words.append(int(parts[data_idx + 1], 16))
            except (ValueError, IndexError):
                continue
    return parse_patches_from_words(words)


# ── Self-test ────────────────────────────────────────────────────────────────
if __name__ == "__main__":
    # Round-trip test: build a synthetic patch, pack, unpack, check equality.
    rng = np.random.default_rng(0)
    p = Patch(
        word_index=0,
        x_pos_raw=0b101,
        y_pos_raw=0b11,
        x_index=2,
        y_index=2,
        c0=rng.integers(0, 128, (PS, PS), dtype=np.uint8),
        c1=rng.integers(0, 128, (PS, PS), dtype=np.uint8),
        c2=rng.integers(0, 128, (PS, PS), dtype=np.uint8),
    )
    payload = pack_patch(p)
    q = unpack_payload(payload)
    assert np.array_equal(p.c0, q.c0)
    assert np.array_equal(p.c1, q.c1)
    assert np.array_equal(p.c2, q.c2)
    assert p.x_pos_raw == q.x_pos_raw and p.y_pos_raw == q.y_pos_raw

    # Word splitting round-trip
    words = payload_to_words(payload)
    assert words_to_payload(words) == payload
    print("payload round-trip OK")
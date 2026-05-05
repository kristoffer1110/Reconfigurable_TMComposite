#!/usr/bin/env python3
"""Parse tb_output.txt into a list of Patch objects and save them.

Saves to a numpy .npz so that script 3 (or any other downstream tool) can
load the patches directly without re-parsing.
"""

from __future__ import annotations

import argparse
import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from lib.payload import parse_tb_output_file, WORDS_PER_PATCH       # noqa: E402


def main() -> None:
    here = os.path.dirname(os.path.abspath(__file__))
    root = os.path.dirname(here)
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--input", default=os.path.join(root, "sim",
                                                        "tb_output.txt"))
    parser.add_argument("--output", default=os.path.join(root, "sim",
                                                         "patches.npz"))
    args = parser.parse_args()

    if not os.path.isfile(args.input):
        sys.exit(f"error: {args.input} not found - run the simulator first")

    patches = parse_tb_output_file(args.input)
    print(f"parsed {len(patches)} patches "
          f"({len(patches) * WORDS_PER_PATCH} words)")

    if not patches:
        sys.exit("error: no patches parsed - check that tb_output.txt has "
                 "lines like 'PATCH n WORD w DATA <hex>'")

    # Pack into arrays (much faster to reload than re-parsing the text file)
    np.savez(
        args.output,
        word_index = np.array([p.word_index for p in patches]),
        x_pos_raw  = np.array([p.x_pos_raw  for p in patches]),
        y_pos_raw  = np.array([p.y_pos_raw  for p in patches]),
        x_index    = np.array([p.x_index    for p in patches]),
        y_index    = np.array([p.y_index    for p in patches]),
        c0         = np.stack([p.c0 for p in patches]),
        c1         = np.stack([p.c1 for p in patches]),
        c2         = np.stack([p.c2 for p in patches]),
    )
    print(f"saved -> {args.output}")

    # Quick summary of the first patch
    p0 = patches[0]
    print(f"\nfirst patch:")
    print(f"  position    : (x={p0.x_index}, y={p0.y_index})")
    print(f"  C0 top row  : {p0.c0[0].tolist()}")
    print(f"  C0 left col : {p0.c0[:, 0].tolist()}")


if __name__ == "__main__":
    main()
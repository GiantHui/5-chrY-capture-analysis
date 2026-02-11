#!/usr/bin/env python3
"""Normalize per-position depth by a sample's average depth.

This module is single-sample and can be imported or called via CLI.
"""

from __future__ import annotations

import argparse
import gzip
import os
from typing import Iterable, Tuple


def _iter_depth_rows(depth_path: str) -> Iterable[Tuple[str, str, float]]:
    """Yield (chrom, pos, raw_depth) rows from a depth.tsv.gz file."""
    with gzip.open(depth_path, "rt", encoding="utf-8") as handle:
        for line in handle:
            if not line or line.startswith("#"):
                continue
            parts = line.rstrip("\n").split("\t")
            if len(parts) < 3:
                continue
            chrom = parts[0]
            pos = parts[1]
            try:
                raw_depth = float(parts[2])
            except ValueError:
                continue
            yield chrom, pos, raw_depth


def run(
    *,
    sample_id: str,
    average_depth: float,
    depth_path: str,
    output_path: str,
    tmp_dir: str,
) -> str:
    """Normalize a single sample's depth file.

    Parameters
    ----------
    sample_id:
        Sample identifier used for logging/context.
    average_depth:
        Sample's average depth. Must be > 0.
    depth_path:
        Path to the input depth.tsv.gz file.
    output_path:
        Path to the final normalized output .tsv.gz file.
    tmp_dir:
        Directory for temporary files before atomic rename.

    Returns
    -------
    str
        The final output path.
    """
    if average_depth <= 0:
        raise ValueError(f"average_depth must be > 0 for sample {sample_id}")

    os.makedirs(os.path.dirname(output_path), exist_ok=True)
    os.makedirs(tmp_dir, exist_ok=True)

    tmp_path = os.path.join(tmp_dir, f"{sample_id}.normalized.tsv.gz.tmp")

    with gzip.open(tmp_path, "wt", encoding="utf-8") as out_handle:
        out_handle.write("#Chr\tPos\tRawDepth\tNormDepth\n")
        for chrom, pos, raw_depth in _iter_depth_rows(depth_path):
            norm_depth = raw_depth / average_depth
            out_handle.write(f"{chrom}\t{pos}\t{raw_depth:.6f}\t{norm_depth:.12f}\n")

    os.replace(tmp_path, output_path)
    return output_path


def _build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Normalize a single depth.tsv.gz file")
    parser.add_argument("--sample-id", required=True, help="Sample identifier")
    parser.add_argument(
        "--average-depth",
        required=True,
        type=float,
        help="Sample average depth (must be > 0)",
    )
    parser.add_argument("--depth-path", required=True, help="Path to depth.tsv.gz")
    parser.add_argument("--output-path", required=True, help="Output .normalized.tsv.gz path")
    parser.add_argument("--tmp-dir", required=True, help="Temporary directory path")
    return parser


def main() -> None:
    parser = _build_parser()
    args = parser.parse_args()
    run(
        sample_id=args.sample_id,
        average_depth=args.average_depth,
        depth_path=args.depth_path,
        output_path=args.output_path,
        tmp_dir=args.tmp_dir,
    )


if __name__ == "__main__":
    main()

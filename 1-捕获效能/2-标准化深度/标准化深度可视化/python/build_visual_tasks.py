#!/usr/bin/env python3
"""Build per-sample visualization tasks from normalized depth files."""

from __future__ import annotations

import argparse
import json
from dataclasses import dataclass
from glob import glob
import os
from typing import List, Tuple


@dataclass(frozen=True)
class Task:
    sample_id: str
    normalized_path: str
    uniformity_low: float
    uniformity_high: float
    position_bin_size: int
    position_smooth_window: int
    max_position: int
    gap_multiplier: float
    uniformity_path: str
    position_curve_path: str
    tmp_dir: str
    success_log: str


def _resolve(base_dir: str, path: str) -> str:
    return path if os.path.isabs(path) else os.path.normpath(os.path.join(base_dir, path))


def _sample_id_from_path(path: str) -> str:
    name = os.path.basename(path)
    suffix = ".normalized.tsv.gz"
    if name.endswith(suffix):
        return name[: -len(suffix)]
    return os.path.splitext(os.path.splitext(name)[0])[0]


def run(*, config_path: str, tasks_path: str) -> Tuple[int, str]:
    with open(config_path, "r", encoding="utf-8") as handle:
        config = json.load(handle)

    base_dir = os.path.dirname(os.path.abspath(config_path))
    project_dir = os.path.dirname(base_dir)

    normalized_depth_dir = _resolve(project_dir, config["normalized_depth_dir"])
    normalized_depth_pattern = config.get("normalized_depth_pattern", "*.normalized.tsv.gz")
    uniformity_low = float(config.get("uniformity_low", 0.5))
    uniformity_high = float(config.get("uniformity_high", 1.5))
    position_bin_size = int(config.get("position_bin_size", 20))
    position_smooth_window = int(config.get("position_smooth_window", 5))
    max_position = int(config.get("max_position", 0))
    gap_multiplier = float(config.get("gap_multiplier", 1.5))

    tmp_dir = _resolve(project_dir, config.get("tmp_dir", "tmp"))
    log_dir = _resolve(project_dir, config.get("log_dir", "log"))

    position_curve_dir = _resolve(project_dir, config.get("output_position_curve_dir", "data/position_curve_per_sample"))
    uniformity_dir = _resolve(project_dir, config.get("output_uniformity_dir", "data/uniformity_per_sample"))
    success_dir = os.path.join(log_dir, "success")

    os.makedirs(tmp_dir, exist_ok=True)
    os.makedirs(log_dir, exist_ok=True)
    os.makedirs(success_dir, exist_ok=True)
    os.makedirs(position_curve_dir, exist_ok=True)
    os.makedirs(uniformity_dir, exist_ok=True)
    os.makedirs(os.path.dirname(tasks_path) or ".", exist_ok=True)

    pattern = os.path.join(normalized_depth_dir, normalized_depth_pattern)
    normalized_files = sorted(glob(pattern))
    if not normalized_files:
        raise FileNotFoundError(f"No normalized depth files matched: {pattern}")

    tasks: List[Task] = []
    for normalized_path in normalized_files:
        sample_id = _sample_id_from_path(normalized_path)
        uniformity_path = os.path.join(uniformity_dir, f"{sample_id}.uniformity.tsv")
        position_curve_path = os.path.join(position_curve_dir, f"{sample_id}.pos_curve.tsv")
        success_log = os.path.join(success_dir, f"{sample_id}.visual.log")
        tasks.append(
            Task(
                sample_id=sample_id,
                normalized_path=normalized_path,
                uniformity_low=uniformity_low,
                uniformity_high=uniformity_high,
                position_bin_size=position_bin_size,
                position_smooth_window=position_smooth_window,
                max_position=max_position,
                gap_multiplier=gap_multiplier,
                uniformity_path=uniformity_path,
                position_curve_path=position_curve_path,
                tmp_dir=tmp_dir,
                success_log=success_log,
            )
        )

    with open(tasks_path, "w", encoding="utf-8", newline="") as handle:
        handle.write(
            "sample_id\tnormalized_path\tuniformity_low\tuniformity_high\t"
            "position_bin_size\tposition_smooth_window\tmax_position\tgap_multiplier\tuniformity_path\t"
            "position_curve_path\ttmp_dir\tsuccess_log\n"
        )
        for task in tasks:
            handle.write(
                f"{task.sample_id}\t{task.normalized_path}\t{task.uniformity_low}\t"
                f"{task.uniformity_high}\t{task.position_bin_size}\t"
                f"{task.position_smooth_window}\t{task.max_position}\t{task.gap_multiplier}\t{task.uniformity_path}\t"
                f"{task.position_curve_path}\t{task.tmp_dir}\t{task.success_log}\n"
            )

    return len(tasks), pattern


def _build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Build visualization task TSV from config.json")
    parser.add_argument("--config", required=True, help="Path to conf/config.json")
    parser.add_argument("--tasks", required=True, help="Path to write tasks.tsv")
    return parser


def main() -> None:
    parser = _build_parser()
    args = parser.parse_args()
    written, pattern = run(config_path=args.config, tasks_path=args.tasks)
    print(f"tasks_written={written}\tpattern={pattern}")


if __name__ == "__main__":
    main()

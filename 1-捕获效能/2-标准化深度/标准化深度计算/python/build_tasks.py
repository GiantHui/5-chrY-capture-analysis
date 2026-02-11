#!/usr/bin/env python3
"""Build a task table that maps each sample to its inputs and outputs.

This module is single-purpose glue and can be imported or called via CLI.
"""

from __future__ import annotations

import argparse
import csv
import json
import os
from dataclasses import dataclass
from typing import Dict, Iterable, List, Tuple


@dataclass(frozen=True)
class Task:
    sample_id: str
    average_depth: float
    depth_path: str
    output_path: str
    tmp_dir: str
    success_log: str


def _load_average_depths(average_depth_csv: str) -> Dict[str, float]:
    depths: Dict[str, float] = {}
    with open(average_depth_csv, "r", encoding="utf-8", newline="") as handle:
        reader = csv.reader(handle)
        header = next(reader, None)
        if header is None:
            raise ValueError("average_depth_csv is empty")
        for row in reader:
            if len(row) < 2:
                continue
            sample_id = row[0].strip()
            if not sample_id:
                continue
            try:
                avg = float(row[1])
            except ValueError:
                continue
            depths[sample_id] = avg
    if not depths:
        raise ValueError("No valid depths loaded from average_depth_csv")
    return depths


def _iter_depth_dirs(depth_dir_list_txt: str) -> Iterable[str]:
    with open(depth_dir_list_txt, "r", encoding="utf-8") as handle:
        for line in handle:
            path = line.strip()
            if not path or path.startswith("#"):
                continue
            yield path


def _sample_id_from_depth_dir(depth_dir: str) -> str:
    # Input lines look like: /path/<sample_id>/7.4m.bed
    parent = os.path.dirname(depth_dir.rstrip("/"))
    sample_id = os.path.basename(parent)
    if not sample_id:
        raise ValueError(f"Could not derive sample_id from depth_dir: {depth_dir}")
    return sample_id


def run(
    *,
    config_path: str,
    tasks_path: str,
) -> Tuple[int, int]:
    """Build a TSV task table for scheduling.

    Returns
    -------
    (int, int)
        (num_tasks_written, num_missing_average_depth)
    """
    with open(config_path, "r", encoding="utf-8") as handle:
        config = json.load(handle)

    average_depth_csv = config["average_depth_csv"]
    depth_dir_list_txt = config["depth_dir_list_txt"]
    depth_filename = config.get("depth_filename", "depth.tsv.gz")
    output_dir = config["output_dir"]
    tmp_dir = config.get("tmp_dir", "tmp")
    log_dir = config.get("log_dir", "log")

    os.makedirs(os.path.dirname(tasks_path) or ".", exist_ok=True)
    os.makedirs(tmp_dir, exist_ok=True)
    os.makedirs(log_dir, exist_ok=True)
    os.makedirs(os.path.join(log_dir, "success"), exist_ok=True)

    average_depths = _load_average_depths(average_depth_csv)

    missing_avg = 0
    tasks: List[Task] = []

    for depth_dir in _iter_depth_dirs(depth_dir_list_txt):
        sample_id = _sample_id_from_depth_dir(depth_dir)
        avg = average_depths.get(sample_id)
        if avg is None:
            missing_avg += 1
            continue
        depth_path = os.path.join(depth_dir, depth_filename)
        output_path = os.path.join(output_dir, f"{sample_id}.normalized.tsv.gz")
        success_log = os.path.join(log_dir, "success", f"{sample_id}.log")
        tasks.append(
            Task(
                sample_id=sample_id,
                average_depth=avg,
                depth_path=depth_path,
                output_path=output_path,
                tmp_dir=tmp_dir,
                success_log=success_log,
            )
        )

    with open(tasks_path, "w", encoding="utf-8", newline="") as handle:
        handle.write(
            "sample_id\taverage_depth\tdepth_path\toutput_path\ttmp_dir\tsuccess_log\n"
        )
        for task in tasks:
            handle.write(
                f"{task.sample_id}\t{task.average_depth}\t{task.depth_path}\t"
                f"{task.output_path}\t{task.tmp_dir}\t{task.success_log}\n"
            )

    return len(tasks), missing_avg


def _build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Build task TSV from config.json")
    parser.add_argument("--config", required=True, help="Path to conf/config.json")
    parser.add_argument("--tasks", required=True, help="Path to write tasks.tsv")
    return parser


def main() -> None:
    parser = _build_parser()
    args = parser.parse_args()
    written, missing = run(config_path=args.config, tasks_path=args.tasks)
    print(f"tasks_written={written}\tmissing_average_depth={missing}")


if __name__ == "__main__":
    main()

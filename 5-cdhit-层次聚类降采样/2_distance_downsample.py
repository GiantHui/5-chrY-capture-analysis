#!/usr/bin/env python3
"""基于 IQ-TREE 生成的 .mldist 距离矩阵对 Y 染色体序列进行距离聚类降采样。

处理流程：
    1. 读取 IQ-TREE 输出的成对距离矩阵（方阵文本格式）。
    2. 导入包含样本分组信息的元数据，标记需要强制保留的优先组（如 ChongqingHan）。
    3. 对距离矩阵执行层次聚类（默认 average linkage）。
    4. 逐步增加聚类阈值，直到“优先样本 + 各簇代表序列”数量不超过目标上限。
    5. 输出保留样本清单、聚类摘要，可选地导出对应的 FASTA 子集。

脚本仅依赖优先组标记进行筛选，确保降采样完全由序列间距离驱动。
"""

from __future__ import annotations

import argparse
import math
import sys
from collections import defaultdict
from pathlib import Path
from typing import Dict, Iterable, List, Sequence, Tuple

import numpy as np
from scipy.cluster.hierarchy import fcluster, linkage
from scipy.spatial.distance import squareform


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Select representative sequences using distance-based clustering",
        formatter_class=argparse.ArgumentDefaultsHelpFormatter,
    )
    parser.add_argument("--dist", required=True, type=Path, help="IQ-TREE .mldist file")
    parser.add_argument("--meta", required=True, type=Path, help="Two-column metadata file")
    parser.add_argument(
        "--fasta",
        required=True,
        type=Path,
        help="Aligned FASTA containing exactly the sequences listed in --dist",
    )
    parser.add_argument(
        "--priority",
        default="ChongqingHan",
        help="Sample group label whose members must always be retained",
    )
    parser.add_argument("--target", type=int, default=500, help="Maximum desired sample count")
    parser.add_argument(
        "--linkage",
        choices=["single", "complete", "average", "weighted", "centroid"],
        default="average",
        help="Linkage strategy for hierarchical clustering",
    )
    parser.add_argument(
        "--output-dir",
        type=Path,
        default=None,
        help="Directory for outputs (defaults to the .mldist parent directory)",
    )
    parser.add_argument(
        "--prefix",
        default="downsampled",
        help="Prefix for generated files (IDs list, cluster report, optional FASTA)",
    )
    parser.add_argument(
        "--write-fasta",
        action="store_true",
        help="Write a FASTA with the final selection (requires Biopython)",
    )
    parser.add_argument(
        "--max-threshold",
        type=float,
        default=None,
        help="Upper bound for distance threshold search (defaults to matrix max)",
    )
    args = parser.parse_args()
    return args


def read_meta(meta_path: Path) -> Dict[str, str]:
    mapping: Dict[str, str] = {}
    with meta_path.open("r", encoding="utf-8") as handle:
        for line in handle:
            line = line.strip()
            if not line:
                continue
            parts = line.split()
            if len(parts) < 2:
                continue
            sample_id, group = parts[0], parts[1]
            mapping[sample_id] = group
    if not mapping:
        raise ValueError(f"Metadata file {meta_path} is empty or malformed.")
    return mapping


def read_mldist(dist_path: Path) -> Tuple[List[str], np.ndarray]:
    with dist_path.open("r", encoding="utf-8") as handle:
        first = handle.readline()
        if not first:
            raise ValueError(f"Distance file {dist_path} appears to be empty.")
        n = int(first.strip())
        names: List[str] = []
        matrix = np.zeros((n, n), dtype=float)
        for i in range(n):
            line = handle.readline()
            if not line:
                raise ValueError(
                    f"Distance file {dist_path} ended prematurely (expected {n} rows)."
                )
            parts = line.strip().split()
            if not parts:
                raise ValueError(f"Encountered blank line while parsing {dist_path} at row {i}.")
            name = parts[0]
            values: List[str] = parts[1:]
            while len(values) < n:
                # 若行被换行拆分，则追加读取直至凑满 n 个距离值。
                extra = handle.readline()
                if not extra:
                    raise ValueError(
                        f"Could not gather {n} distances for row {name}."
                    )
                values.extend(extra.strip().split())
            row = np.array(values[:n], dtype=float)
            matrix[i, :] = row
            names.append(name)
        return names, matrix


def base_id(label: str) -> str:
    """去除第一个下划线后的字串，用于匹配元数据中的基础样本 ID。"""
    return label.split("_", 1)[0]


def medoid_index(full_matrix: np.ndarray, indices: Sequence[int]) -> int:
    """返回簇内距离总和最小的样本索引（medoid）。"""
    if len(indices) == 1:
        return indices[0]
    sub = full_matrix[np.ix_(indices, indices)]
    sums = sub.sum(axis=1)
    return indices[int(np.argmin(sums))]


def select_at_threshold(
    Z: np.ndarray,
    threshold: float,
    names: Sequence[str],
    dist_matrix: np.ndarray,
    required_mask: np.ndarray,
    required_indices: np.ndarray,
    target: int,
) -> Tuple[List[int], List[Dict[str, object]]]:
    cluster_labels = fcluster(Z, t=threshold, criterion="distance")
    clusters: Dict[int, List[int]] = defaultdict(list)
    for idx, cluster_id in enumerate(cluster_labels):
        clusters[int(cluster_id)].append(idx)

    selected: List[int] = []
    cluster_records: List[Dict[str, object]] = []
    for cluster_id, members in clusters.items():
        member_array = np.array(members, dtype=int)
        required_in_cluster = member_array[required_mask[member_array]]
        kept: List[int] = []
        if required_in_cluster.size:
            kept.extend(required_in_cluster.tolist())
        else:
            medoid = medoid_index(dist_matrix, member_array)
            kept.append(int(medoid))
        selected.extend(kept)
        cluster_records.append(
            {
                "cluster_id": cluster_id,
                "size": len(members),
                "required_count": int(required_in_cluster.size),
                "selected_ids": [names[i] for i in kept],
            }
        )

    selected_unique = sorted(set(selected))
    # 保留首次出现的顺序以保证后续 FASTA 提取可重复。
    selected_ordered = [idx for idx in range(len(names)) if idx in selected_unique]
    cluster_records.sort(key=lambda rec: rec["cluster_id"])
    return selected_ordered, cluster_records


def ensure_priority_subset(required_indices: np.ndarray, target: int) -> None:
    if required_indices.size > target:
        raise ValueError(
            f"Priority samples alone ({required_indices.size}) exceed target {target}."
        )


def write_ids(path: Path, indices: Sequence[int], names: Sequence[str]) -> None:
    with path.open("w", encoding="utf-8") as handle:
        for idx in indices:
            handle.write(f"{names[idx]}\n")


def write_cluster_report(
    path: Path,
    records: Sequence[Dict[str, object]],
    meta_map: Dict[str, str],
    priority_label: str,
) -> None:
    with path.open("w", encoding="utf-8") as handle:
        handle.write("cluster_id\tsize\trequired_count\tselected_ids\n")
        for rec in records:
            selected_ids = ",".join(rec["selected_ids"])  # type: ignore[index]
            handle.write(
                f"{rec['cluster_id']}\t{rec['size']}\t{rec['required_count']}\t{selected_ids}\n"
            )


def write_fasta_subset(
    fasta_path: Path,
    out_path: Path,
    keep_names: Sequence[str],
) -> None:
    from Bio import SeqIO  # type: ignore

    keep_set = set(keep_names)
    with fasta_path.open("r", encoding="utf-8") as in_handle, out_path.open(
        "w", encoding="utf-8"
    ) as out_handle:
        count = 0
        for record in SeqIO.parse(in_handle, "fasta"):
            if record.id in keep_set:
                SeqIO.write(record, out_handle, "fasta")
                count += 1
        if count != len(keep_set):
            raise RuntimeError(
                f"Expected to write {len(keep_set)} sequences, but wrote {count}."
            )


def main() -> None:
    args = parse_args()

    output_dir = args.output_dir or args.dist.parent
    output_dir.mkdir(parents=True, exist_ok=True)

    meta_map = read_meta(args.meta)

    names, dist_matrix = read_mldist(args.dist)
    n = len(names)
    name_to_index = {name: idx for idx, name in enumerate(names)}

    # 通过第一段样本 ID（下划线前）匹配元数据，标记优先保留的序列索引。
    priority_group = args.priority
    priority_ids = {sid for sid, grp in meta_map.items() if grp == priority_group}
    required_indices = np.array(
        [idx for idx, name in enumerate(names) if base_id(name) in priority_ids],
        dtype=int,
    )
    required_mask = np.zeros(n, dtype=bool)
    required_mask[required_indices] = True
    ensure_priority_subset(required_indices, args.target)

    # 将距离矩阵转换为上三角向量，为 SciPy linkage 做准备。
    condensed = squareform(dist_matrix, checks=False)
    if np.any(np.isnan(condensed)):
        raise ValueError("Distance matrix contains NaN values; please inspect the input.")

    # 先执行一次层次聚类，再在不同阈值处切割。
    Z = linkage(condensed, method=args.linkage)

    positive_distances = np.unique(condensed[condensed > 0])
    if positive_distances.size == 0:
        positive_distances = np.array([0.0])
    max_distance = positive_distances.max()
    if args.max_threshold is not None:
        max_distance = min(max_distance, args.max_threshold)

    candidate_thresholds = list(positive_distances)
    candidate_thresholds.append(max_distance + 1e-6)

    chosen_indices: List[int] | None = None
    chosen_records: List[Dict[str, object]] | None = None
    chosen_threshold: float | None = None

    for threshold in candidate_thresholds:
        indices, records = select_at_threshold(
            Z,
            threshold,
            names,
            dist_matrix,
            required_mask,
            required_indices,
            args.target,
        )
        if len(indices) <= args.target:
            chosen_indices = indices
            chosen_records = records
            chosen_threshold = threshold
            break

    if chosen_indices is None or chosen_records is None or chosen_threshold is None:
    # 兜底逻辑：使用最后一个阈值，即便超过目标数量（理论上不会触发）。
        chosen_indices, chosen_records = select_at_threshold(
            Z,
            candidate_thresholds[-1],
            names,
            dist_matrix,
            required_mask,
            required_indices,
            args.target,
        )
        chosen_threshold = candidate_thresholds[-1]

    selected_names = [names[idx] for idx in chosen_indices]

    ids_path = output_dir / f"{args.prefix}.ids.txt"
    write_ids(ids_path, chosen_indices, names)

    clusters_path = output_dir / f"{args.prefix}.clusters.tsv"
    write_cluster_report(clusters_path, chosen_records, meta_map, args.priority)

    if args.write_fasta:
        try:
            fasta_out = output_dir / f"{args.prefix}.fasta"
            write_fasta_subset(args.fasta, fasta_out, selected_names)
        except ImportError as exc:
            raise SystemExit(
                "Biopython is required for --write-fasta but is not installed."
            ) from exc

    print("=== Downsampling summary ===")
    print(f"Total sequences in distance matrix: {n}")
    print(f"Priority group '{args.priority}': {required_indices.size} samples")
    print(f"Target maximum: {args.target}")
    print(f"Selected threshold: {chosen_threshold:.6f}")
    print(f"Selected sample count: {len(selected_names)}")
    print(f"ID list: {ids_path}")
    print(f"Cluster report: {clusters_path}")
    if args.write_fasta:
        print(f"Subset FASTA: {fasta_out}")


if __name__ == "__main__":
    main()

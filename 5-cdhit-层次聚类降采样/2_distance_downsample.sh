#!/usr/bin/env bash
# 脚本运行需要的所有者: GiantHui
# 功能: 调用 2_distance_downsample.py 根据 IQ-TREE 距离矩阵执行距离聚类降采样。
# 使用前请确保已激活 GiantHui 环境(例: conda activate GiantHui)，且已安装 numpy、scipy、biopython。

set -euo pipefail

SCRIPT_DIR="$(dirname "$(realpath "$0")")"
PYTHON_SCRIPT="${SCRIPT_DIR}/2_distance_downsample.py"
PYTHON_BIN="${PYTHON_BIN:-python3}"

DIST="/data/liuyunhui/Han_Chongqing/iqtree/output/cq_matrix.mldist"
META="/data/liuyunhui/Han_Chongqing/fasta/conf/meta.txt"
FASTA="/data/liuyunhui/Han_Chongqing/fasta/output/cd-hit/dedup_sequences.prioritized.fasta"
OUTPUT_DIR="/data/liuyunhui/Han_Chongqing/fasta/output/cluster"
PREFIX="cq_400"
TARGET=400
PRIORITY_GROUP="ChongqingHan"
LINKAGE_METHOD="average"

mkdir -p "${OUTPUT_DIR}"

"${PYTHON_BIN}" "${PYTHON_SCRIPT}" \
  --dist "${DIST}" \
  --meta "${META}" \
  --fasta "${FASTA}" \
  --priority "${PRIORITY_GROUP}" \
  --target "${TARGET}" \
  --linkage "${LINKAGE_METHOD}" \
  --output-dir "${OUTPUT_DIR}" \
  --prefix "${PREFIX}" \
  --write-fasta

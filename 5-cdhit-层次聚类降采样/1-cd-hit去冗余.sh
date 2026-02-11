#!/usr/bin/env bash
set -euo pipefail

# Deduplicate sequences while keeping ChongqingHan samples whenever possible.

INPUT_FASTA="/data/liuyunhui/Han_Chongqing/fasta/data/cqHan.indel.lowq.het.dp2.mis0.05.mM2.ind0.05.mis0.05.mM2.fasta"
OUTPUT_PREFIX="/data/liuyunhui/Han_Chongqing/fasta/output/dedup_sequences"
META_FILE="/data/liuyunhui/Han_Chongqing/fasta/conf/meta.txt"
PRIORITY_LABEL="ChongqingHan"
THREADS=8
LOG_FILE="${OUTPUT_PREFIX}.log"

mkdir -p "$(dirname "${OUTPUT_PREFIX}")"

exec > >(tee -a "${LOG_FILE}") 2>&1
echo "[INFO] $(date '+%F %T') Starting cd-hit-est prioritised deduplication." \
    "Input: ${INPUT_FASTA}" "Meta: ${META_FILE}" "Output prefix: ${OUTPUT_PREFIX}" "Threads: ${THREADS}" | tr -s ' '

cd-hit-est -i "${INPUT_FASTA}" \
    -o "${OUTPUT_PREFIX}.fasta" \
    -c 0.999 -aS 0.99 -T "${THREADS}" -M 0 -d 0

export INPUT_FASTA
export META_FILE
export PRIORITY_LABEL
export CLSTR_PATH="${OUTPUT_PREFIX}.fasta.clstr"
export PRIORITIZED_FASTA="${OUTPUT_PREFIX}.prioritized.fasta"
export PRIORITIZED_IDS="${OUTPUT_PREFIX}.prioritized.ids.txt"
export LOG_FILE

python3 <<'PY'
import os
from collections import OrderedDict

input_fasta = os.environ["INPUT_FASTA"]
meta_file = os.environ["META_FILE"]
priority_label = os.environ["PRIORITY_LABEL"]
clstr_path = os.environ["CLSTR_PATH"]
prioritized_fasta = os.environ["PRIORITIZED_FASTA"]
prioritized_ids_path = os.environ["PRIORITIZED_IDS"]

priority_ids = set()
with open(meta_file, "r", encoding="utf-8") as meta:
    for line in meta:
        line = line.strip()
        if not line:
            continue
        parts = line.split()
        if len(parts) < 2:
            continue
        if parts[1] == priority_label:
            priority_ids.add(parts[0])

clusters = []
current = None
with open(clstr_path, "r", encoding="utf-8") as clstr:
    for raw in clstr:
        line = raw.strip()
        if not line:
            continue
        if line.startswith(">Cluster"):
            if current:
                clusters.append(current)
            current = {"members": [], "rep": None}
            continue
        if current is None:
            continue
        try:
            seq_part = line.split(">", 1)[1]
        except IndexError:
            continue
        seq_id = seq_part.split("...", 1)[0]
        current["members"].append(seq_id)
        if line.endswith("*"):
            current["rep"] = seq_id
    if current:
        clusters.append(current)

selected_ids = []
priority_hits = 0
for cluster in clusters:
    chosen = None
    for sid in cluster["members"]:
        if sid in priority_ids:
            chosen = sid
            priority_hits += 1
            break
    if not chosen:
        representative = cluster.get("rep") or cluster["members"][0]
        chosen = representative
    selected_ids.append(chosen)

with open(prioritized_ids_path, "w", encoding="utf-8") as handle:
    handle.write("\n".join(selected_ids) + "\n")

selected_set = set(selected_ids)
sequences = {}
header = None
seq_lines = []

def store_record(hdr, lines):
    if hdr is None:
        return
    seq_id = hdr[1:].split()[0]
    if seq_id in selected_set and seq_id not in sequences:
        sequences[seq_id] = (hdr, list(lines))

with open(input_fasta, "r", encoding="utf-8") as fasta:
    for line in fasta:
        if line.startswith(">"):
            store_record(header, seq_lines)
            header = line.rstrip("\n")
            seq_lines = []
        else:
            seq_lines.append(line.rstrip("\n"))
    store_record(header, seq_lines)

missing = [sid for sid in selected_ids if sid not in sequences]
if missing:
    raise RuntimeError(f"Missing sequences for: {', '.join(missing[:10])}")

with open(prioritized_fasta, "w", encoding="utf-8") as out_fasta:
    for sid in selected_ids:
        header_line, lines = sequences[sid]
        out_fasta.write(header_line + "\n")
        for seq_line in lines:
            out_fasta.write(seq_line + "\n")

total_clusters = len(selected_ids)
print(f"Selected {total_clusters} representative sequences.")
print(f"Clusters with {priority_label} retained: {priority_hits}.")
print(f"FASTA written to: {prioritized_fasta}")
print(f"Representative ID list: {prioritized_ids_path}")
print(f"Log file: {os.environ['LOG_FILE']}")
PY
cd-hit-est -i \
    /data/liuyunhui/Han_Chongqing/fasta/data/cqHan.indel.lowq.het.dp2.mis0.05.mM2.ind0.05.mis0.05.mM2.fasta \
    -o /data/liuyunhui/Han_Chongqing/fasta/output/dedup_sequences.fasta \
    -c 0.999 -aS 0.99 -T 8 -M 0 -d 0
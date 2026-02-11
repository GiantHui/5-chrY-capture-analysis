#!/usr/bin/env python3
import csv
import glob
import os
from collections import Counter
from pathlib import Path

# === 路径配置（直接在这里修改即可）===
INPUT_DIR = "/mnt/d/捕获体系/6-法医学参数/conf"
OUTPUT_DIR = "/mnt/d/捕获体系/6-法医学参数/output"
INPUT_PATTERNS = ["*.csv", "*.tsv", "*.txt"]
# 也可以指定具体文件：例如 ["/mnt/c/.../conf/数据1.csv", "/mnt/c/.../conf/数据2.csv"]
INPUT_FILES = ["/mnt/d/捕获体系/6-法医学参数/conf/单倍型.csv"]

# === 计算门槛（直接在这里修改即可）===
# 仅对“样本量 N > MIN_N_FOR_CALC” 的群体计算法医学参数（HMP/HD/DC）
# 例如设为 15，则 N=16 会计算，N=15 或更小会跳过
MIN_N_FOR_CALC = 15


def detect_dialect(sample_text):
    try:
        return csv.Sniffer().sniff(sample_text, delimiters=[",", "\t", ";", "|"])
    except csv.Error:
        class Fallback(csv.Dialect):
            delimiter = ","
            quotechar = '"'
            doublequote = True
            skipinitialspace = True
            lineterminator = "\n"
            quoting = csv.QUOTE_MINIMAL
        return Fallback()


def parse_table(path):
    with open(path, "r", newline="", encoding="utf-8-sig") as f:
        sample = f.read(4096)
        f.seek(0)
        dialect = detect_dialect(sample)
        reader = csv.DictReader(f, dialect=dialect)
        rows = list(reader)
        if not reader.fieldnames:
            raise ValueError("文件必须有表头，并包含 group,haplotype 两列。")
        fieldnames = [h.strip() for h in reader.fieldnames]
        return rows, fieldnames


def get_required_columns(fieldnames):
    # 统一做小写匹配，要求必须包含 group/haplotype
    lower_map = {name.lower(): name for name in fieldnames}
    missing = [col for col in ["group", "haplotype"] if col not in lower_map]
    if missing:
        raise ValueError(f"缺少必要列: {','.join(missing)}，必须包含 group,haplotype")
    return lower_map["group"], lower_map["haplotype"]


def compute_params_from_counts(counts):
    # counts: 每个单倍型在群体中的出现次数（可用 Counter.values() 得到）
    n = float(sum(counts))
    if n <= 1:
        raise ValueError("样本量 N 必须 > 1。")
    p = [c / n for c in counts if c > 0]
    k = len(p)
    hmp = sum(x * x for x in p)
    hd = n * (1.0 - hmp) / (n - 1.0)
    dc = k / n
    return n, k, hmp, hd, dc


def write_group_output(out_path, results):
    with open(out_path, "w", newline="", encoding="utf-8") as f:
        writer = csv.writer(f)
        writer.writerow(["Group", "Status", "HMP", "HD", "DC", "N", "k"])
        for g, (status, n, k, hmp, hd, dc) in results.items():
            if status == "OK":
                writer.writerow([g, status, f"{hmp:.6f}", f"{hd:.6f}", f"{dc:.6f}", f"{n:.6f}", f"{k}"])
            else:
                # 跳过计算时不输出 HMP/HD/DC（用空值表示）
                writer.writerow([g, status, "", "", "", f"{n:.6f}", f"{k}"])


def write_explain_md(out_path, base_name):
    # 结果说明文件（中英文 + 名词解释 + 解读）
    content = f"""# 法医学参数结果说明（Forensic Parameters Interpretation）

对应结果文件：`{base_name}_forensic_params_by_group.csv`

## 输入文件格式（Input）
必须包含两列并有表头：

- `group`：群体/人群名称（Population/Group）
- `haplotype`：单倍群/单倍型字符串（Haplogroup/Haplotype label）

说明：输入文件中**每一行代表一个个体样本**（同一群体中出现多次的 `haplotype` 会被统计为更高的计数）。

## 计算与输出列（Computation & Columns）
输出文件列含义如下：

- `Group`：群体名称
- `Status`：计算状态  
  - `OK`：样本量满足门槛，已计算 HMP/HD/DC  
  - `SKIPPED_SMALL_N`：样本量过小，仅输出 N 和 k，不计算 HMP/HD/DC
- `N`：样本量（Total sample size），等于该群体的行数
- `k`：单倍型种类数（Number of distinct haplotypes），等于该群体不同 `haplotype` 的数量

### 参数 1：单倍型匹配概率（Haplotype Match Probability, HMP）
- **公式**：HMP = Σ(pᵢ²)
- **符号**：pᵢ 为第 i 个单倍型在该群体中的频率（pᵢ = countᵢ / N）
- **名词解释**：随机抽取两名个体，其 Y-STR 单倍型相同的概率（在“单倍型频率”层面的衡量）
- **解读**：HMP **越小**，说明单倍型越分散、群体区分能力通常越好；HMP 越大，说明少数单倍型占比更高、重复更常见。

### 参数 2：单倍型差异度（Haplotype Diversity, HD）
- **公式**：HD = N × (1 − Σ(pᵢ²)) / (N − 1)
- **名词解释**：对单倍型多样性的无偏估计（类似 Nei’s gene diversity 的形式）
- **解读**：HD 越接近 1，说明多样性越高；HD 越低，说明多样性越低。注意当 N 很小时 HD 不稳定，因此本脚本设置了样本量门槛。

### 参数 3：分辨能力（Discrimination Capacity, DC）
- **公式（本脚本）**：DC = k / N
- **名词解释**：样本中“不同单倍型数”占“样本总数”的比例
- **解读**：DC 越高，说明样本中独特单倍型比例越高、区分能力越强；DC 越低，说明重复单倍型较多。

## 样本量门槛（Sample size threshold）
本脚本仅对 **N > {MIN_N_FOR_CALC}** 的群体计算 HMP/HD/DC。  
你可以在脚本开头修改 `MIN_N_FOR_CALC` 的数值。
"""
    with open(out_path, "w", encoding="utf-8") as f:
        f.write(content)


def main():
    # 收集输入文件
    inputs = []
    if INPUT_FILES:
        inputs = INPUT_FILES
    else:
        for p in INPUT_PATTERNS:
            inputs.extend(glob.glob(os.path.join(INPUT_DIR, p)))
        inputs = sorted(set(inputs))

    if not inputs:
        raise SystemExit("未找到输入文件，请检查 INPUT_DIR 或 INPUT_FILES。")

    os.makedirs(OUTPUT_DIR, exist_ok=True)

    for in_path in inputs:
        rows, fieldnames = parse_table(in_path)
        group_col, hap_col = get_required_columns(fieldnames)

        # 输入文件仅两列：group,haplotype
        # 每一行代表一个样本个体（该个体所属群体 + 单倍群/单倍型字符串）
        # 计算时按群体统计每种单倍型出现次数，再换算频率 p_i=count_i/N
        group_to_haplotypes = {}
        for r in rows:
            g = r.get(group_col, "").strip()
            h = r.get(hap_col, "").strip()
            if not g or not h:
                continue
            group_to_haplotypes.setdefault(g, []).append(h)

        # 逐群体计算（可设置最小样本量门槛）
        results = {}
        for g, haplotypes in group_to_haplotypes.items():
            counter = Counter(haplotypes)
            n = float(len(haplotypes))
            k = int(len(counter))

            # 仅对 N > MIN_N_FOR_CALC 的群体计算 HMP/HD/DC
            if n <= MIN_N_FOR_CALC:
                results[g] = ("SKIPPED_SMALL_N", n, k, None, None, None)
                continue

            counts = counter.values()
            n2, k2, hmp, hd, dc = compute_params_from_counts(counts)
            results[g] = ("OK", n2, k2, hmp, hd, dc)

        base = Path(in_path).stem
        out_path = os.path.join(OUTPUT_DIR, f"{base}_forensic_params_by_group.csv")
        write_group_output(out_path, results)

        explain_path = os.path.join(OUTPUT_DIR, f"{base}_forensic_params_说明.md")
        write_explain_md(explain_path, base_name=base)

        print(f"Input: {in_path}")
        print(f"Output: {out_path}")
        print(f"Explain: {explain_path}")
        for g, (status, n, k, hmp, hd, dc) in results.items():
            if status == "OK":
                print(f"[{g}] HMP={hmp:.6f}  HD={hd:.6f}  DC={dc:.6f}  N={n:.6f}  k={k}")
            else:
                print(f"[{g}] 跳过计算（N={n:.0f} <= {MIN_N_FOR_CALC}），仅输出 N/k")


if __name__ == "__main__":
    main()

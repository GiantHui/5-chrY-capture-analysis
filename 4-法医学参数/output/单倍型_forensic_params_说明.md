# 法医学参数结果说明（Forensic Parameters Interpretation）

对应结果文件：`单倍型_forensic_params_by_group.csv`

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
本脚本仅对 **N > 15** 的群体计算 HMP/HD/DC。  
你可以在脚本开头修改 `MIN_N_FOR_CALC` 的数值。

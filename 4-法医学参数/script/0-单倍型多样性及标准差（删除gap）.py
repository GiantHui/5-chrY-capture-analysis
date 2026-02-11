from Bio import SeqIO
from Bio.SeqRecord import SeqRecord
from Bio.Seq import Seq
import pandas as pd
import numpy as np
import os

# 文件路径
input_group_file = '/mnt/d/捕获体系/6-法医学参数/conf/单倍型_群体.txt'  # 群体信息文件，表头不要改
input_fasta_file = '/mnt/d/捕获体系/vcf-fasta/cqHan.indel.lowq.het.dp2.mis0.05.mM2.ind0.05.mis0.05.mM2.fasta'  # 原始FASTA文件
output_fasta_dir = '/mnt/d/捕获体系/6-法医学参数/output/无gap的群体fasta/'  # 清理后的FASTA按群体存储的目录
output_diversity_file = '/mnt/d/捕获体系/6-法医学参数/output/haplotype_diversity_results.csv'  # 多样性输出文件
output_haplotype_type_file = '/mnt/d/捕获体系/6-法医学参数/output/haplotype_type_by_sample.csv'  # 单倍型类型（按样本）输出文件
output_lengths_file = '/mnt/d/捕获体系/6-法医学参数/output/sequence_lengths_comparison.csv'  # 序列长度对比文件

# 创建输出目录
os.makedirs(output_fasta_dir, exist_ok=True)

def load_group_file(group_file):
    """
    加载群体信息文件，确保包含 'SampleID' 和 'Group' 列。
    """
    group_data = pd.read_csv(group_file, sep='\t', header=0)
    group_data['SampleID'] = group_data['SampleID'].astype(str)
    group_data['SampleID_Core'] = group_data['SampleID'].str.rsplit('_', n=1).str[0]
    return group_data

def load_fasta_file(fasta_file):
    """
    从FASTA文件加载序列数据。
    """
    def parse_record_id(record_id: str):
        if '_' not in record_id:
            return record_id, None
        sample_id, haplotype_type = record_id.rsplit('_', 1)
        return sample_id, haplotype_type

    sequences = []
    for record in SeqIO.parse(fasta_file, "fasta"):
        sample_id, haplotype_type = parse_record_id(record.id)
        sequences.append({
            'SampleID_Core': sample_id,
            'RecordID': record.id,
            'Haplotype_Type': haplotype_type,
            'Sequence': str(record.seq),
        })
    return pd.DataFrame(sequences)

def clean_fasta_per_group(group_data, sequence_data, output_dir):
    """
    按群体清理FASTA序列，删除每个群体中任何序列为'N'的所有位点。
    输出清理后的FASTA文件按群体存储，并返回清理前后长度对比。
    """
    merged_data = pd.merge(
        group_data,
        sequence_data,
        on='SampleID_Core',
        how='inner',
    )  # 合并群体和序列信息
    lengths_comparison = []

    for group, group_data in merged_data.groupby('Group'):
        print(f"Processing group: {group}")
        sequences = list(group_data['Sequence'])
        sample_ids = list(group_data['SampleID_Core'])
        record_ids = list(group_data['RecordID']) if 'RecordID' in group_data.columns else sample_ids

        # 转置序列矩阵（按位置分析）
        transposed = np.array([list(seq) for seq in sequences]).T
        non_n_positions = [i for i, column in enumerate(transposed) if 'N' not in column]  # 筛选没有N的位置

        # 清理后的序列
        cleaned_sequences = ["".join([seq[i] for i in non_n_positions]) for seq in sequences]

        # 保存清理结果
        cleaned_fasta_records = [
            SeqRecord(Seq(seq), id=record_id, description="") for record_id, seq in zip(record_ids, cleaned_sequences)
        ]
        group_fasta_path = os.path.join(output_dir, f"{group}_cleaned.fasta")
        SeqIO.write(cleaned_fasta_records, group_fasta_path, "fasta")
        print(f"Saved cleaned FASTA for group {group} to {group_fasta_path}")

        # 记录清理前后长度对比
        lengths_comparison.extend(
            [{'SampleID': seq_id, 'Group': group, 'Original_Length': len(sequences[0]), 'Cleaned_Length': len(seq)}
             for seq_id, seq in zip(sample_ids, cleaned_sequences)]
        )

    return pd.DataFrame(lengths_comparison)

def assign_haplotypes(sequence_data):
    """
    分配单倍型。
    """
    sequence_data['Haplotype'] = sequence_data['Sequence'].rank(method='dense').astype(int)
    return sequence_data

def calculate_haplotype_diversity(data, group_col='Group', haplotype_col='Haplotype'):
    """
    计算单倍型多样性和标准差。
    """
    diversity_results = []
    grouped = data.groupby(group_col)

    for group, group_data in grouped:
        n = len(group_data)
        if n < 2:
            haplotype_diversity = None
            standard_deviation = None
        else:
            haplotype_counts = group_data[haplotype_col].value_counts()
            frequencies = haplotype_counts / n
            sum_frequencies_squared = (frequencies ** 2).sum()

            # 单倍型多样性公式
            haplotype_diversity = (n / (n - 1)) * (1 - sum_frequencies_squared)

            # 标准差公式
            standard_deviation = np.sqrt(np.sum(frequencies ** 2 * (1 - frequencies) ** 2) / (n - 1))

        diversity_results.append({
            'Group': group,
            'Haplotype_Diversity': haplotype_diversity,
            'Standard_Deviation': standard_deviation,
            'Sample_Size': n
        })

    return pd.DataFrame(diversity_results)

def main():
    # 主流程
    group_data = load_group_file(input_group_file)
    sequence_data = load_fasta_file(input_fasta_file)

    lengths_comparison = clean_fasta_per_group(group_data, sequence_data, output_fasta_dir)
    lengths_comparison.to_csv(output_lengths_file, index=False)
    if lengths_comparison.empty:
        raise ValueError(
            "No samples were matched between group file and FASTA. "
            "Matching uses the core ID before the first '_' (SampleID_Core). "
            "Please check the group file 'SampleID' values and FASTA headers."
        )

    diversity_results_list = []
    haplotype_type_list = []

    for group in lengths_comparison['Group'].unique():
        group_fasta_path = os.path.join(output_fasta_dir, f"{group}_cleaned.fasta")
        group_sequences = load_fasta_file(group_fasta_path)
        group_sequences['Group'] = group

        group_haplotype_data = assign_haplotypes(group_sequences)
        haplotype_type_list.append(
            group_haplotype_data[['SampleID_Core', 'Haplotype_Type', 'Haplotype']]
        )

        diversity_results = calculate_haplotype_diversity(group_haplotype_data)
        diversity_results_list.append(diversity_results)

    final_diversity_results = pd.concat(diversity_results_list, ignore_index=True)
    final_diversity_results.to_csv(output_diversity_file, index=False)

    final_haplotype_type = pd.concat(haplotype_type_list, ignore_index=True)
    all_samples = group_data[['SampleID', 'SampleID_Core', 'Group']].drop_duplicates()
    final_haplotype_type = all_samples.merge(final_haplotype_type, on='SampleID_Core', how='left')

    final_haplotype_type['Haplotype'] = final_haplotype_type['Haplotype'].astype('Int64')
    final_haplotype_type = final_haplotype_type.rename(
        columns={
            'Haplotype_Type': 'Haplorgroup',
            'Haplotype': 'Haplotype_number',
        }
    )
    final_haplotype_type = final_haplotype_type[
        ['SampleID', 'Group', 'Haplorgroup', 'Haplotype_number']
    ]
    final_haplotype_type.to_csv(output_haplotype_type_file, index=False)

    total_n = len(all_samples)
    matched_n = int(final_haplotype_type['Haplotype_number'].notna().sum())
    missing_n = total_n - matched_n
    print(f"Group file samples: {total_n}; matched in FASTA: {matched_n}; missing in FASTA: {missing_n}")

    print("\nAnalysis completed successfully.")


if __name__ == "__main__":
    main()

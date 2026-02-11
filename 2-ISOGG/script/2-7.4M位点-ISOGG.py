#!/usr/bin/env python3
"""
脚本功能：检查all.csv中的位点是否在Y_8M.bed的范围内
作者：GitHub Copilot
日期：2025-10-23
"""

import csv
import sys
from typing import List, Tuple


def load_bed_ranges(bed_file: str) -> List[Tuple[int, int]]:
    """
    加载BED文件中的位点范围
    
    Args:
        bed_file: BED文件路径
        
    Returns:
        List[Tuple[int, int]]: 包含(start, end)位置的列表
    """
    ranges = []
    
    try:
        with open(bed_file, 'r', encoding='utf-8') as f:
            for line_num, line in enumerate(f, 1):
                line = line.strip()
                if not line:
                    continue
                    
                try:
                    # 解析格式：chrY,2655000-2669950
                    parts = line.split(',')
                    if len(parts) != 2:
                        print(f"警告：第{line_num}行格式不正确: {line}", file=sys.stderr)
                        continue
                    
                    chr_name, position_range = parts
                    if chr_name != 'chrY':
                        print(f"警告：第{line_num}行不是chrY: {line}", file=sys.stderr)
                        continue
                    
                    # 解析位置范围
                    start_str, end_str = position_range.split('-')
                    start_pos = int(start_str)
                    end_pos = int(end_str)
                    
                    ranges.append((start_pos, end_pos))
                    
                except (ValueError, IndexError) as e:
                    print(f"错误：解析第{line_num}行时出错: {line}, 错误: {e}", file=sys.stderr)
                    continue
                    
    except FileNotFoundError:
        print(f"错误：找不到文件 {bed_file}", file=sys.stderr)
        sys.exit(1)
    except Exception as e:
        print(f"错误：读取文件 {bed_file} 时出错: {e}", file=sys.stderr)
        sys.exit(1)
    
    # 按起始位置排序，便于后续查找
    ranges.sort()
    print(f"成功加载 {len(ranges)} 个位点范围", file=sys.stderr)
    return ranges


def is_position_in_ranges(position: int, ranges: List[Tuple[int, int]]) -> bool:
    """
    检查位点是否在任何一个范围内
    使用二分查找优化性能
    
    Args:
        position: 要检查的位点位置
        ranges: 已排序的位点范围列表
        
    Returns:
        bool: 如果位点在范围内返回True，否则返回False
    """
    left, right = 0, len(ranges) - 1
    
    while left <= right:
        mid = (left + right) // 2
        start, end = ranges[mid]
        
        if start <= position <= end:
            return True
        elif position < start:
            right = mid - 1
        else:
            left = mid + 1
    
    return False


def process_csv_stream(input_file: str, output_file: str, ranges: List[Tuple[int, int]]):
    """
    流式处理CSV文件，添加第四列标识位点是否在范围内
    
    Args:
        input_file: 输入CSV文件路径
        output_file: 输出CSV文件路径
        ranges: 位点范围列表
    """
    processed_count = 0
    match_count = 0
    
    try:
        with open(input_file, 'r', encoding='utf-8') as infile, \
             open(output_file, 'w', encoding='utf-8', newline='') as outfile:
            
            reader = csv.reader(infile)
            writer = csv.writer(outfile)
            
            # 处理表头
            try:
                header = next(reader)
                # 添加第四列表头
                header.append('InY8M')
                writer.writerow(header)
            except StopIteration:
                print("错误：输入文件为空", file=sys.stderr)
                return
            
            # 流式处理每一行
            for line_num, row in enumerate(reader, 2):  # 从第2行开始，因为第1行是表头
                try:
                    if len(row) < 3:
                        print(f"警告：第{line_num}行数据不完整: {row}", file=sys.stderr)
                        # 补充缺失的列
                        while len(row) < 3:
                            row.append('')
                    
                    # 获取位点位置（第三列，索引为2）
                    position_str = row[2].strip()
                    if not position_str:
                        row.append('No')  # 空位置视为不匹配
                        writer.writerow(row)
                        processed_count += 1
                        continue
                    
                    try:
                        position = int(position_str)
                    except ValueError:
                        print(f"警告：第{line_num}行位置格式不正确: {position_str}", file=sys.stderr)
                        row.append('No')  # 无效位置视为不匹配
                        writer.writerow(row)
                        processed_count += 1
                        continue
                    
                    # 检查位点是否在范围内
                    in_range = is_position_in_ranges(position, ranges)
                    row.append('Yes' if in_range else 'No')
                    
                    if in_range:
                        match_count += 1
                    
                    writer.writerow(row)
                    processed_count += 1
                    
                    # 每处理1000行输出一次进度
                    if processed_count % 1000 == 0:
                        print(f"已处理 {processed_count} 行，匹配 {match_count} 个位点", file=sys.stderr)
                        
                except Exception as e:
                    print(f"错误：处理第{line_num}行时出错: {row}, 错误: {e}", file=sys.stderr)
                    # 添加错误标记并继续处理
                    if len(row) >= 3:
                        row.append('Error')
                    else:
                        row.extend([''] * (3 - len(row)) + ['Error'])
                    writer.writerow(row)
                    processed_count += 1
                    continue
                    
    except FileNotFoundError:
        print(f"错误：找不到输入文件 {input_file}", file=sys.stderr)
        sys.exit(1)
    except Exception as e:
        print(f"错误：处理文件时出错: {e}", file=sys.stderr)
        sys.exit(1)
    
    print(f"\n处理完成！", file=sys.stderr)
    print(f"总共处理: {processed_count} 行", file=sys.stderr)
    print(f"匹配位点: {match_count} 个", file=sys.stderr)
    print(f"匹配率: {match_count/processed_count*100:.2f}%" if processed_count > 0 else "匹配率: 0%", file=sys.stderr)


def main():
    """主函数"""
    # 文件路径
    bed_file = "/mnt/d/捕获体系/2-ISOGG/conf/Y_7.4M.bed"
    input_csv = "/mnt/d/捕获体系/2-ISOGG/data/3_final_data.csv"
    output_csv = "/mnt/d/捕获体系/2-ISOGG/output/位点去重/ISOGG_in7.4M.csv"
    
    print("开始处理单倍群位点匹配...", file=sys.stderr)
    
    # 步骤1：加载BED文件中的位点范围
    print("正在加载Y_8M.bed文件...", file=sys.stderr)
    ranges = load_bed_ranges(bed_file)
    
    if not ranges:
        print("错误：没有找到有效的位点范围", file=sys.stderr)
        sys.exit(1)
    
    # 步骤2：流式处理CSV文件
    print("开始流式处理all.csv文件...", file=sys.stderr)
    process_csv_stream(input_csv, output_csv, ranges)
    
    print(f"结果已保存到: {output_csv}", file=sys.stderr)


if __name__ == "__main__":
    main()
# #!/usr/bin/env python3
# # -*- coding: utf-8 -*-
# """
# 数据处理脚本：为all_with_y8m.csv添加Y_YHSeq.pos位点标记
# 作者：GitHub Copilot
# 创建时间：2025-10-24

# 功能：
# 1. 读取Y_YHSeq.pos文件中的物理位置信息
# 2. 逐行处理all_with_y8m.csv文件
# 3. 在第5列添加标记：如果位点在Y_YHSeq.pos中则标记为"Yes"，否则为"No"
# 4. 使用流式处理以节约内存和时间
# """

# import os
# import sys
# from typing import Set

# def load_yhseq_positions(yhseq_file: str) -> Set[int]:
#     """
#     读取Y_YHSeq.pos文件中的物理位置信息
    
#     Args:
#         yhseq_file: Y_YHSeq.pos文件路径
        
#     Returns:
#         包含所有物理位置的集合
#     """
#     positions = set()
    
#     try:
#         with open(yhseq_file, 'r', encoding='utf-8') as f:
#             for line_num, line in enumerate(f, 1):
#                 line = line.strip()
#                 if not line:
#                     continue
                    
#                 try:
#                     # 分割行，获取第二列（物理位置）
#                     parts = line.split('\t')
#                     if len(parts) >= 2:
#                         position = int(parts[1])
#                         positions.add(position)
#                 except ValueError as e:
#                     print(f"警告：第{line_num}行位置格式错误，跳过: {line}")
#                     continue
                    
#         print(f"成功加载 {len(positions)} 个Y_YHSeq位点")
#         return positions
        
#     except FileNotFoundError:
#         print(f"错误：找不到文件 {yhseq_file}")
#         sys.exit(1)
#     except Exception as e:
#         print(f"错误：读取Y_YHSeq.pos文件时发生异常: {e}")
#         sys.exit(1)

# def process_csv_file(input_file: str, output_file: str, yhseq_positions: Set[int]):
#     """
#     流式处理CSV文件，添加Y_YHSeq位点标记
    
#     Args:
#         input_file: 输入CSV文件路径
#         output_file: 输出CSV文件路径
#         yhseq_positions: Y_YHSeq位点集合
#     """
#     processed_lines = 0
#     matched_count = 0
    
#     try:
#         with open(input_file, 'r', encoding='utf-8') as infile, \
#              open(output_file, 'w', encoding='utf-8') as outfile:
            
#             for line_num, line in enumerate(infile, 1):
#                 line = line.strip()
#                 if not line:
#                     continue
                
#                 try:
#                     # 分割CSV行
#                     parts = line.split(',')
                    
#                     if len(parts) < 3:
#                         print(f"警告：第{line_num}行数据列数不足，跳过: {line}")
#                         continue
                    
#                     # 获取第三列的物理位置
#                     try:
#                         position = int(parts[2])
#                     except ValueError:
#                         print(f"警告：第{line_num}行位置格式错误，跳过: {line}")
#                         continue
                    
#                     # 检查位点是否在Y_YHSeq.pos中
#                     if position in yhseq_positions:
#                         marker = "Yes"
#                         matched_count += 1
#                     else:
#                         marker = "No"
                    
#                     # 构建输出行：原有4列 + 新的第5列
#                     output_line = line + ',' + marker
#                     outfile.write(output_line + '\n')
                    
#                     processed_lines += 1
                    
#                     # 每处理10000行显示进度
#                     if processed_lines % 10000 == 0:
#                         print(f"已处理 {processed_lines} 行，匹配到 {matched_count} 个位点")
                        
#                 except Exception as e:
#                     print(f"警告：处理第{line_num}行时发生错误，跳过: {e}")
#                     continue
        
#         print(f"处理完成！")
#         print(f"总共处理 {processed_lines} 行")
#         print(f"匹配到 {matched_count} 个Y_YHSeq位点")
#         print(f"匹配率: {matched_count/processed_lines*100:.2f}%")
#         print(f"结果已保存到: {output_file}")
        
#     except FileNotFoundError:
#         print(f"错误：找不到输入文件 {input_file}")
#         sys.exit(1)
#     except Exception as e:
#         print(f"错误：处理CSV文件时发生异常: {e}")
#         sys.exit(1)

# def main():
#     """主函数"""
#     # 文件路径定义
#     yhseq_file = "/mnt/c/Users/Administrator/Desktop/ISOGG/conf/Y_YHSeq.pos"
#     input_csv = "/mnt/c/Users/Administrator/Desktop/ISOGG/data/merge_long_clean.csv"
#     output_csv = "/mnt/c/Users/Administrator/Desktop/ISOGG/output/merge_long_clean_yhseq.csv"
    
#     print("开始数据处理...")
#     print(f"Y_YHSeq位点文件: {yhseq_file}")
#     print(f"输入CSV文件: {input_csv}")
#     print(f"输出CSV文件: {output_csv}")
#     print("-" * 50)
    
#     # 检查输入文件是否存在
#     if not os.path.exists(yhseq_file):
#         print(f"错误：Y_YHSeq.pos文件不存在: {yhseq_file}")
#         sys.exit(1)
        
#     if not os.path.exists(input_csv):
#         print(f"错误：输入CSV文件不存在: {input_csv}")
#         sys.exit(1)
    
#     # 步骤1：加载Y_YHSeq位点信息
#     print("步骤1：加载Y_YHSeq位点信息...")
#     yhseq_positions = load_yhseq_positions(yhseq_file)
    
#     # 步骤2：流式处理CSV文件
#     print("\n步骤2：处理CSV文件...")
#     process_csv_file(input_csv, output_csv, yhseq_positions)

# if __name__ == "__main__":
#     main()

#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
数据处理脚本：为all_with_y8m.csv添加Y_YHSeq.pos位点标记
作者：GitHub Copilot
创建时间：2025-10-24

功能：
1. 读取Y_YHSeq.pos文件中的物理位置信息
2. 逐行处理all_with_y8m.csv文件
3. 在第5列添加标记：如果位点在Y_YHSeq.pos中则标记为"Yes"，否则为"No"
4. 使用流式处理以节约内存和时间
"""

import os
import sys
from typing import Set

def load_yhseq_positions(yhseq_file: str) -> Set[int]:
    """
    读取Y_YHSeq.pos文件中的物理位置信息
    
    Args:
        yhseq_file: Y_YHSeq.pos文件路径
        
    Returns:
        包含所有物理位置的集合
    """
    positions = set()
    
    try:
        with open(yhseq_file, 'r', encoding='utf-8') as f:
            for line_num, line in enumerate(f, 1):
                line = line.strip()
                if not line:
                    continue
                    
                try:
                    # 分割行，获取第二列（物理位置）
                    parts = line.split('\t')
                    if len(parts) >= 2:
                        position_str = parts[1].strip()
                        if position_str:  # 确保位置字符串不为空
                            position = int(position_str)
                            positions.add(position)
                        else:
                            print(f"警告：第{line_num}行位置为空，跳过: {line}")
                    else:
                        print(f"警告：第{line_num}行列数不足，跳过: {line}")
                except ValueError as e:
                    print(f"警告：第{line_num}行位置格式错误，跳过: {line} - 错误: {e}")
                    continue
                except Exception as e:
                    print(f"警告：第{line_num}行处理异常，跳过: {line} - 错误: {e}")
                    continue
                    
        print(f"成功加载 {len(positions)} 个Y_YHSeq位点")
        return positions
        
    except FileNotFoundError:
        print(f"错误：找不到文件 {yhseq_file}")
        sys.exit(1)
    except Exception as e:
        print(f"错误：读取Y_YHSeq.pos文件时发生异常: {e}")
        sys.exit(1)

def process_csv_file(input_file: str, output_file: str, yhseq_positions: Set[int]):
    """
    流式处理CSV文件，添加Y_YHSeq位点标记
    
    Args:
        input_file: 输入CSV文件路径
        output_file: 输出CSV文件路径
        yhseq_positions: Y_YHSeq位点集合
    """
    processed_lines = 0
    matched_count = 0
    
    try:
        with open(input_file, 'r', encoding='utf-8') as infile, \
             open(output_file, 'w', encoding='utf-8') as outfile:
            
            # 处理表头（第1行）
            header = infile.readline().strip()
            if header:
                # 添加新列名到表头
                header_output = header + ',Y_YHSeq_Marker'
                outfile.write(header_output + '\n')
                print(f"表头已处理: {header}")
            
            # 从第2行开始处理数据
            for line_num, line in enumerate(infile, 2):
                line = line.strip()
                if not line:
                    continue
                
                try:
                    # 分割CSV行
                    parts = line.split(',')
                    
                    if len(parts) < 3:
                        print(f"警告：第{line_num}行数据列数不足，跳过: {line}")
                        continue
                    
                    # 获取第三列的物理位置
                    try:
                        position_str = parts[2].strip()
                        if position_str:
                            position = int(position_str)
                        else:
                            print(f"警告：第{line_num}行位置为空，跳过: {line}")
                            continue
                    except ValueError:
                        print(f"警告：第{line_num}行位置格式错误，跳过: {line}")
                        continue
                    
                    # 检查位点是否在Y_YHSeq.pos中
                    if position in yhseq_positions:
                        marker = "Yes"
                        matched_count += 1
                    else:
                        marker = "No"
                    
                    # 构建输出行：原有4列 + 新的第5列
                    output_line = line + ',' + marker
                    outfile.write(output_line + '\n')
                    
                    processed_lines += 1
                    
                    # 每处理10000行显示进度
                    if processed_lines % 10000 == 0:
                        print(f"已处理 {processed_lines} 行，匹配到 {matched_count} 个位点")
                        
                except Exception as e:
                    print(f"警告：处理第{line_num}行时发生错误，跳过: {e}")
                    continue
        
        print(f"处理完成！")
        print(f"总共处理 {processed_lines} 行数据（不含表头）")
        print(f"匹配到 {matched_count} 个Y_YHSeq位点")
        if processed_lines > 0:
            print(f"匹配率: {matched_count/processed_lines*100:.2f}%")
        print(f"结果已保存到: {output_file}")
        
    except FileNotFoundError:
        print(f"错误：找不到输入文件 {input_file}")
        sys.exit(1)
    except Exception as e:
        print(f"错误：处理CSV文件时发生异常: {e}")
        sys.exit(1)

def main():
    """主函数"""
    # 文件路径定义
    yhseq_file = "/mnt/d/捕获体系/2-ISOGG/conf/Y_YHSeq.pos"
    input_csv = "/mnt/d/捕获体系/2-ISOGG/data/3_final_data.csv"
    output_csv = "/mnt/d/捕获体系/2-ISOGG/output/位点去重/ISOGG_inyhseq.csv"
    
    print("开始数据处理...")
    print(f"Y_YHSeq位点文件: {yhseq_file}")
    print(f"输入CSV文件: {input_csv}")
    print(f"输出CSV文件: {output_csv}")
    print("-" * 50)
    
    # 检查输入文件是否存在
    if not os.path.exists(yhseq_file):
        print(f"错误：Y_YHSeq.pos文件不存在: {yhseq_file}")
        sys.exit(1)
        
    if not os.path.exists(input_csv):
        print(f"错误：输入CSV文件不存在: {input_csv}")
        sys.exit(1)
    
    # 步骤1：加载Y_YHSeq位点信息
    print("步骤1：加载Y_YHSeq位点信息...")
    yhseq_positions = load_yhseq_positions(yhseq_file)
    
    # 步骤2：流式处理CSV文件
    print("\n步骤2：处理CSV文件...")
    process_csv_file(input_csv, output_csv, yhseq_positions)

if __name__ == "__main__":
    main()
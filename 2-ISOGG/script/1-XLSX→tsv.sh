#!/bin/bash

# 定义彩色输出函数
echo_cyan()   { echo -e "\033[1;36m$*\033[0m"; } 
echo_cyan   "青色"

# 定义输入目录（写死变量）
INPUT_DIR="/mnt/c/Users/Administrator/Desktop/ISOGG/data"
PYTHON_SCRIPT="/mnt/c/Users/Administrator/Desktop/ISOGG/script/1-XLSX→tsv.py"
# 定义输出目录（可以与输入相同，也可以单独指定）
OUTPUT_DIR="/mnt/c/Users/Administrator/Desktop/ISOGG/data"

# 遍历输入目录下所有 .xlsx 文件
for file in "$INPUT_DIR"/*.xlsx; do
    # 获取文件名（不包含路径与扩展名）
    filename=$(basename "$file" .xlsx)

    # 构造输出文件路径
    output_file="$OUTPUT_DIR/${filename}.tsv"

    echo_cyan "Converting $file -> $output_file"

    # 调用 Python 脚本进行转换
    python3 ${PYTHON_SCRIPT} \
        -input_file "$file" \
        -output_file "$output_file"
done

echo_cyan "[All conversions completed.]"

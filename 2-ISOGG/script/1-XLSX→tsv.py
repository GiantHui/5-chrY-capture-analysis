# %%
import pandas as pd
import argparse

# %%
# 定义命令行参数解析器
parser = argparse.ArgumentParser(description="Convert Excel file to TSV file.")
parser.add_argument('-input_file', type=str, required=True, help='Path to input Excel file')
parser.add_argument('-output_file', type=str, required=True, help='Path to output TSV file')

# 解析参数
args = parser.parse_args()

# %%
# 从命令行参数中读取文件路径
INPUTFILE = args.input_file
OUTPUTFILE = args.output_file

# %%
# 读取excel文件，并将其转为tsv文件
df = pd.read_excel(INPUTFILE)
df.to_csv(OUTPUTFILE, sep="\t", index=False)

#! python your_script.py -input_file ../data/A.xlsx -output_file ../data/A.tsv

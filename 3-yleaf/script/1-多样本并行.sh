#!/bin/bash

# ============================================================================
# Yleaf 并行分析脚本
# 创建日期: 2026年2月3日
# 功能: 支持并行处理、断点续跑、彩色输出、进度条
# ============================================================================

# 脚本运行需要的所有依赖 (GiantHui)
# 1. Yleaf 工具: /home/luolisiteng/.conda/envs/yleaf/bin/Yleaf
# 2. GNU parallel 命令行工具
# 3. bc 计算器 (用于进度计算)
# 4. tput 命令 (用于彩色输出)
# 5. pv 命令 (可选，用于更好的进度条显示)
# 6. 输入 BAM 文件目录及文件权限
# 7. 输出目录写入权限

set -euo pipefail

# ============================================================================
# 写死的配置变量
# ============================================================================

# Yleaf 可执行文件路径
YLEAF_BIN="/home/luolisiteng/.conda/envs/yleaf/bin/Yleaf"

# BAM 文件路径列表文件 (txt格式，每行一个BAM文件的绝对路径)
BAM_LIST_FILE="/data/liuyunhui/capture_7.4M/yleaf/conf/7038_7.4m_bam.txt"

# 输出根目录
OUTPUT_ROOT="/data/liuyunhui/capture_7.4M/yleaf/output"

# Yleaf 参数
REFERENCE_GENOME="hg19"
MIN_READS="10"
MIN_QUALITY="20"
MIN_BASE_QUALITY="90"
PROBABILITY_THRESHOLD="0.95"
THREADS_PER_SAMPLE="8"

# 并行作业数量
MAX_PARALLEL_JOBS="40"

# 日志和状态文件
LOG_DIR="${OUTPUT_ROOT}/logs"
PROGRESS_FILE="${LOG_DIR}/progress.txt"
COMPLETED_FILE="${LOG_DIR}/completed_samples.txt"
FAILED_FILE="${LOG_DIR}/failed_samples.txt"
SAMPLE_LIST_FILE="${LOG_DIR}/sample_list.txt"

# ============================================================================
# 颜色定义
# ============================================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
NC='\033[0m' # No Color

# ============================================================================
# 工具函数
# ============================================================================

# 彩色打印函数
print_info() {
    echo -e "${BLUE}[INFO]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

print_header() {
    echo -e "${MAGENTA}========================================${NC}"
    echo -e "${MAGENTA}$1${NC}"
    echo -e "${MAGENTA}========================================${NC}"
}

# 进度条函数
show_progress() {
    local current=$1
    local total=$2
    local percent=$((current * 100 / total))
    local completed=$((percent / 2))
    local remaining=$((50 - completed))
    
    printf "\r${CYAN}Progress: [${NC}"
    printf "%0.s#" $(seq 1 $completed)
    printf "%0.s-" $(seq 1 $remaining)
    printf "${CYAN}] %d%% (%d/%d)${NC}" $percent $current $total
}

# 清理函数 - 在脚本中断时调用
cleanup() {
    print_warning "脚本被中断，正在清理未完成的任务..."
    
    # 杀死所有并行作业
    if [[ -n "${PARALLEL_PID:-}" ]]; then
        pkill -P $PARALLEL_PID 2>/dev/null || true
    fi
    
    # 执行清理时，通过BAM文件路径查找输出目录
    if [[ -f "$SAMPLE_LIST_FILE" ]]; then
        while IFS= read -r bam_file; do
            if ! grep -Fxq "$bam_file" "$COMPLETED_FILE" 2>/dev/null; then
                local sample_name=$(basename "$bam_file" .bam)
                sample_output="${OUTPUT_ROOT}/${sample_name}"
                if [[ -d "$sample_output" ]]; then
                    print_warning "删除未完成的任务输出: $sample_name"
                    rm -rf "$sample_output"
                fi
            fi
        done < "$SAMPLE_LIST_FILE"
    fi
    
    print_info "清理完成，已保留完成的任务结果"
    exit 130
}

# 设置信号捕获
trap cleanup SIGINT SIGTERM

# ============================================================================
# 依赖检查
# ============================================================================

check_dependencies() {
    print_header "检查依赖"
    
    local deps_missing=0
    
    # 检查 Yleaf
    if [[ ! -x "$YLEAF_BIN" ]]; then
        print_error "Yleaf 不存在或不可执行: $YLEAF_BIN"
        deps_missing=1
    else
        print_success "Yleaf: $YLEAF_BIN"
    fi
    
    # 检查 parallel
    if ! command -v parallel &> /dev/null; then
        print_error "GNU parallel 未安装"
        deps_missing=1
    else
        print_success "GNU parallel: $(which parallel)"
    fi
    
    # 检查 bc
    if ! command -v bc &> /dev/null; then
        print_error "bc 计算器未安装"
        deps_missing=1
    else
        print_success "bc: $(which bc)"
    fi
    
    # 检查BAM文件列表
    if [[ ! -f "$BAM_LIST_FILE" ]]; then
        print_error "BAM文件列表不存在: $BAM_LIST_FILE"
        deps_missing=1
    elif [[ ! -s "$BAM_LIST_FILE" ]]; then
        print_error "BAM文件列表为空: $BAM_LIST_FILE"
        deps_missing=1
    else
        print_success "BAM文件列表: $BAM_LIST_FILE"
    fi
    
    if [[ $deps_missing -eq 1 ]]; then
        print_error "依赖检查失败，请安装缺失的依赖后重新运行"
        exit 1
    fi
    
    print_success "所有依赖检查通过"
}

# ============================================================================
# 初始化
# ============================================================================

initialize() {
    print_header "初始化工作环境"
    
    # 创建必要目录
    mkdir -p "$OUTPUT_ROOT" "$LOG_DIR"
    
    # 初始化状态文件
    touch "$COMPLETED_FILE" "$FAILED_FILE"
    
    # 检查BAM文件列表
    print_info "检查 BAM 文件列表: $BAM_LIST_FILE"
    
    if [[ ! -f "$BAM_LIST_FILE" ]]; then
        print_error "BAM文件列表不存在: $BAM_LIST_FILE"
        exit 1
    fi
    
    # 过滤掉空行和注释行，生成有效的BAM文件列表
    grep -v '^[[:space:]]*$' "$BAM_LIST_FILE" | grep -v '^[[:space:]]*#' > "$SAMPLE_LIST_FILE"
    
    local total_samples=$(wc -l < "$SAMPLE_LIST_FILE")
    print_success "找到 $total_samples 个BAM文件"
    
    if [[ $total_samples -eq 0 ]]; then
        print_error "没有找到有效的BAM文件！"
        exit 1
    fi
    
    # 显示BAM文件列表前5个
    print_info "BAM文件列表预览 (前5个):"
    head -5 "$SAMPLE_LIST_FILE" | while read -r bam_path; do
        echo -e "  ${WHITE}- $(basename "$bam_path")${NC}"
    done
    
    if [[ $total_samples -gt 5 ]]; then
        print_info "... 还有 $((total_samples - 5)) 个文件"
    fi
}

# ============================================================================
# Yleaf 分析函数
# ============================================================================

run_yleaf_analysis() {
    local bam_file=$1
    local sample_name=$(basename "$bam_file" .bam)
    local output_dir="${OUTPUT_ROOT}/${sample_name}"
    local log_file="${LOG_DIR}/${sample_name}.log"
    
    echo "[INFO] $sample_name - 使用BAM文件: $bam_file"
    
    # 检查是否已完成 - 通过检查BAM文件路径
    if grep -Fxq "$bam_file" "$COMPLETED_FILE" 2>/dev/null; then
        echo "[SKIP] $sample_name - 已完成"
        return 0
    fi
    
    # 检查 BAM 文件是否存在
    if [[ ! -f "$bam_file" ]]; then
        echo "[ERROR] $sample_name - BAM 文件不存在: $bam_file"
        echo "$bam_file" >> "$FAILED_FILE"
        return 1
    fi
    
    # 创建输出目录
    mkdir -p "$output_dir"
    
    # 运行 Yleaf
    echo "[START] $sample_name - 开始分析"
    
    if "$YLEAF_BIN" \
        -bam "$bam_file" \
        -o "$output_dir" \
        -rg "$REFERENCE_GENOME" \
        -r "$MIN_READS" \
        -q "$MIN_QUALITY" \
        -b "$MIN_BASE_QUALITY" \
        -pq "$PROBABILITY_THRESHOLD" \
        -t "$THREADS_PER_SAMPLE" \
        -force \
        > "$log_file" 2>&1; then
        
        echo "[SUCCESS] $sample_name - 分析完成"
        echo "$bam_file" >> "$COMPLETED_FILE"
        return 0
    else
        echo "[FAILED] $sample_name - 分析失败，详见日志: $log_file"
        echo "$bam_file" >> "$FAILED_FILE"
        # 清理失败的输出
        rm -rf "$output_dir"
        return 1
    fi
}

# 导出函数供 parallel 使用
export -f run_yleaf_analysis
export YLEAF_BIN REFERENCE_GENOME MIN_READS MIN_QUALITY MIN_BASE_QUALITY PROBABILITY_THRESHOLD THREADS_PER_SAMPLE
export OUTPUT_ROOT LOG_DIR COMPLETED_FILE FAILED_FILE BAM_LIST_FILE

# ============================================================================
# 主要处理流程
# ============================================================================

run_parallel_analysis() {
    print_header "开始并行分析"
    
    local total_samples=$(wc -l < "$SAMPLE_LIST_FILE")
    local completed_count=$(wc -l < "$COMPLETED_FILE" 2>/dev/null || echo 0)
    
    print_info "总BAM文件数: $total_samples"
    print_info "已完成: $completed_count"
    print_info "待处理: $((total_samples - completed_count))"
    print_info "并行作业数: $MAX_PARALLEL_JOBS"
    
    # 获取未完成的BAM文件
    local pending_files=$(mktemp)
    if [[ -s "$COMPLETED_FILE" ]]; then
        grep -Fxvf "$COMPLETED_FILE" "$SAMPLE_LIST_FILE" > "$pending_files" || true
    else
        cp "$SAMPLE_LIST_FILE" "$pending_files"
    fi
    
    local pending_count=$(wc -l < "$pending_files")
    
    if [[ $pending_count -eq 0 ]]; then
        print_success "所有BAM文件已完成分析！"
        rm -f "$pending_files"
        return 0
    fi
    
    print_info "开始处理 $pending_count 个待处理BAM文件..."
    
    # 使用 GNU parallel 进行并行处理
    parallel \
        --jobs "$MAX_PARALLEL_JOBS" \
        --progress \
        --line-buffer \
        --halt now,fail=10 \
        run_yleaf_analysis {} \
        :::: "$pending_files" &
    
    PARALLEL_PID=$!
    
    # 等待所有作业完成
    wait $PARALLEL_PID
    
    rm -f "$pending_files"
}

# ============================================================================
# 结果统计
# ============================================================================

generate_summary() {
    print_header "生成分析报告"
    
    local total_files=$(wc -l < "$SAMPLE_LIST_FILE")
    local completed_count=$(wc -l < "$COMPLETED_FILE" 2>/dev/null || echo 0)
    local failed_count=$(wc -l < "$FAILED_FILE" 2>/dev/null || echo 0)
    
    local summary_file="${OUTPUT_ROOT}/analysis_summary.txt"
    
    cat > "$summary_file" << EOF
Yleaf 分析总结报告
==================

分析时间: $(date '+%Y-%m-%d %H:%M:%S')
总BAM文件数: $total_files
成功完成: $completed_count
分析失败: $failed_count
成功率: $(if [ $total_files -eq 0 ]; then echo "N/A"; else echo "scale=2; $completed_count * 100 / $total_files" | bc; fi)%

配置参数:
- 参考基因组: $REFERENCE_GENOME
- 最小读段数: $MIN_READS  
- 最小质量: $MIN_QUALITY
- 最小碱基质量: $MIN_BASE_QUALITY
- 概率阈值: $PROBABILITY_THRESHOLD
- 每样本线程数: $THREADS_PER_SAMPLE
- 并行作业数: $MAX_PARALLEL_JOBS

输出目录: $OUTPUT_ROOT
日志目录: $LOG_DIR
EOF

    print_success "分析完成！"
    echo -e "${WHITE}总BAM文件数:${NC} $total_files"
    echo -e "${GREEN}成功完成:${NC} $completed_count"
    echo -e "${RED}分析失败:${NC} $failed_count"
    if [ $total_files -eq 0 ]; then
        echo -e "${CYAN}成功率:${NC} N/A (无文件)"
    else
        echo -e "${CYAN}成功率:${NC} $(echo "scale=1; $completed_count * 100 / $total_files" | bc)%"
    fi
    echo -e "${YELLOW}详细报告:${NC} $summary_file"
    
    if [[ $failed_count -gt 0 ]]; then
        print_warning "失败BAM文件列表: $FAILED_FILE"
        echo -e "${YELLOW}前3个失败文件:${NC}"
        head -3 "$FAILED_FILE" 2>/dev/null | while read -r bam_path; do
            echo -e "  ${RED}- $(basename "$bam_path")${NC}"
        done
    fi
}

# ============================================================================
# 主程序
# ============================================================================

main() {
    print_header "Yleaf 并行分析脚本启动"
    
    # 显示配置信息
    echo -e "${CYAN}配置信息:${NC}"
    echo -e "  BAM文件列表: ${WHITE}$BAM_LIST_FILE${NC}"
    echo -e "  输出目录: ${WHITE}$OUTPUT_ROOT${NC}" 
    echo -e "  并行作业: ${WHITE}$MAX_PARALLEL_JOBS${NC}"
    echo -e "  参考基因组: ${WHITE}$REFERENCE_GENOME${NC}"
    echo ""
    
    # 执行各步骤
    check_dependencies
    initialize
    run_parallel_analysis
    generate_summary
    
    print_success "脚本执行完成！"
}

# 运行主程序
main "$@"
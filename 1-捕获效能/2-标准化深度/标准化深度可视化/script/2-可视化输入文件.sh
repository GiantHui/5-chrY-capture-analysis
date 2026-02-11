#!/usr/bin/env bash
# 作用：整理“均一化计算”结果，生成 tidyplots 可直接使用的中间 CSV
# 输入：data/uniformity_per_sample、data/position_curve_per_sample、平均深度文件等
# 输出：visual_input_csv/ 下的统一 CSV
# 用法：
#   bash script/2-可视化输入文件.sh
#   bash script/2-可视化输入文件.sh /path/to/conf/config.json

set -euo pipefail

script_name="$(basename "$0")"
script_dir="$(cd "$(dirname "$0")" && pwd)"
project_dir="$(cd "$script_dir/.." && pwd)"
log_dir="$project_dir/log"
main_log="$log_dir/${script_name}.log"

mkdir -p "$log_dir" "$project_dir/tmp" "$log_dir/success"

timestamp() {
  date "+%Y-%m-%d %H:%M:%S"
}

log() {
  printf "[%s] %s\n" "$(timestamp)" "$*" | tee -a "$main_log" >&2
}

# 相对路径统一转为项目内的绝对路径
resolve_path() {
  local path="$1"
  if [[ -z "$path" ]]; then
    printf "" && return
  fi
  if [[ "$path" == /* || "$path" =~ ^[A-Za-z]: ]]; then
    printf "%s" "$path"
  else
    printf "%s/%s" "$project_dir" "$path"
  fi
}

CONFIG_PATH="${1:-$project_dir/conf/config.json}"

if [[ ! -f "$CONFIG_PATH" ]]; then
  log "ERROR missing config: $CONFIG_PATH"
  exit 1
fi

VISUAL_INPUT_DIR="$(python3 "$project_dir/python/read_config.py" --config "$CONFIG_PATH" --key visual_input_dir --default data/visual_input_csv)"
VISUAL_INPUT_DIR="$(resolve_path "$VISUAL_INPUT_DIR")"

AVG_DEPTH_PATH="$(python3 "$project_dir/python/read_config.py" --config "$CONFIG_PATH" --key average_depth_csv --default data/average_depth.csv)"
AVG_DEPTH_PATH="$(resolve_path "$AVG_DEPTH_PATH")"

TARGET_INTERVALS_PATH="$(python3 "$project_dir/python/read_config.py" --config "$CONFIG_PATH" --key target_intervals_tsv --default "")"
TARGET_INTERVALS_PATH="$(resolve_path "$TARGET_INTERVALS_PATH")"

MAX_POSITION="$(python3 "$project_dir/python/read_config.py" --config "$CONFIG_PATH" --key max_position --default 0)"
PLOT_STRATEGY="$(python3 "$project_dir/python/read_config.py" --config "$CONFIG_PATH" --key plot_sample_strategy --default random_n)"
PLOT_N="$(python3 "$project_dir/python/read_config.py" --config "$CONFIG_PATH" --key plot_sample_n --default 30)"
PLOT_SEED="$(python3 "$project_dir/python/read_config.py" --config "$CONFIG_PATH" --key plot_random_seed --default 42)"
DEPTH_BIN_SIZE="$(python3 "$project_dir/python/read_config.py" --config "$CONFIG_PATH" --key depth_bin_size --default 0)"
DEPTH_BIN_MIN="$(python3 "$project_dir/python/read_config.py" --config "$CONFIG_PATH" --key depth_bin_min --default 0)"
DEPTH_BIN_MAX="$(python3 "$project_dir/python/read_config.py" --config "$CONFIG_PATH" --key depth_bin_max --default 0)"
SAMPLES_PER_BIN="$(python3 "$project_dir/python/read_config.py" --config "$CONFIG_PATH" --key samples_per_bin --default 0)"
COLOR_BY_BIN="$(python3 "$project_dir/python/read_config.py" --config "$CONFIG_PATH" --key color_by_depth_bin --default false)"

MAX_POSITION="${MAX_POSITION:-0}"
PLOT_N="${PLOT_N:-0}"
PLOT_SEED="${PLOT_SEED:-42}"

UNIFORMITY_DIR="$(python3 "$project_dir/python/read_config.py" --config "$CONFIG_PATH" --key output_uniformity_dir --default data/uniformity_per_sample)"
POSITION_DIR="$(python3 "$project_dir/python/read_config.py" --config "$CONFIG_PATH" --key output_position_curve_dir --default data/position_curve_per_sample)"
UNIFORMITY_DIR="$(resolve_path "$UNIFORMITY_DIR")"
POSITION_DIR="$(resolve_path "$POSITION_DIR")"
AGG_SUCCESS_LOG="$log_dir/success/_prepare.visual_input.log"

log "START $script_name"
log "config=$CONFIG_PATH"
log "visual_input_dir=$VISUAL_INPUT_DIR"

if [[ ! -d "$UNIFORMITY_DIR" || ! -d "$POSITION_DIR" ]]; then
  log "ERROR 缺少计算结果目录：$UNIFORMITY_DIR 或 $POSITION_DIR"
  exit 1
fi

if [[ "$PLOT_STRATEGY" != "all" && "$PLOT_STRATEGY" != "top_n" && "$PLOT_STRATEGY" != "random_n" ]]; then
  log "ERROR plot_sample_strategy 仅支持 all/top_n/random_n"
  exit 1
fi

if [[ "$PLOT_STRATEGY" != "all" ]] && (( PLOT_N <= 0 )); then
  log "ERROR plot_sample_n 必须 >0（当 strategy!=all 时）"
  exit 1
fi

if (( DEPTH_BIN_SIZE < 0 )) || (( SAMPLES_PER_BIN < 0 )); then
  log "ERROR depth_bin_size 与 samples_per_bin 需为非负"
  exit 1
fi

if [[ -f "$AGG_SUCCESS_LOG" ]] && grep -q "^SUCCESS\b" "$AGG_SUCCESS_LOG"; then
  log "SKIP 准备可视化输入（已有成功标记）"
  exit 0
fi

log "RUN 生成可视化输入 CSV"
if Rscript "$project_dir/script/2-准备可视化输入.R" \
  --uniformity-dir "$UNIFORMITY_DIR" \
  --position-dir "$POSITION_DIR" \
  --average-depth "$AVG_DEPTH_PATH" \
  --target-intervals "$TARGET_INTERVALS_PATH" \
  --max-position "$MAX_POSITION" \
  --plot-sample-strategy "$PLOT_STRATEGY" \
  --plot-sample-n "$PLOT_N" \
  --plot-random-seed "$PLOT_SEED" \
  --depth-bin-size "$DEPTH_BIN_SIZE" \
  --depth-bin-min "$DEPTH_BIN_MIN" \
  --depth-bin-max "$DEPTH_BIN_MAX" \
  --samples-per-bin "$SAMPLES_PER_BIN" \
  --color-by-depth-bin "$COLOR_BY_BIN" \
  --out "$VISUAL_INPUT_DIR" >> "$main_log" 2>&1; then
  printf "SUCCESS prepare_visual_input\n" > "$AGG_SUCCESS_LOG"
  log "SUCCESS 生成可视化输入：$VISUAL_INPUT_DIR"
else
  exit_code=$?
  printf "FAIL prepare_visual_input exit_code=%s\n" "$exit_code" > "$AGG_SUCCESS_LOG"
  log "FAIL 准备可视化输入 exit_code=$exit_code"
  exit "$exit_code"
fi

log "DONE $script_name"

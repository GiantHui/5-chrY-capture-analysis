#!/usr/bin/env bash
# 作用：仅执行“均一化计算”（不做可视化，不生成中间 CSV）
# 输出：data/uniformity_per_sample、data/position_curve_per_sample 下的结果
# 用法：
#   bash script/1-均一化计算.sh
#   bash script/1-均一化计算.sh /path/to/conf/config.json

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

CONFIG_PATH="${1:-$project_dir/conf/config.json}"
TASKS_PATH="$project_dir/data/visual_tasks.tsv"

log "START $script_name"
log "config=$CONFIG_PATH"

if [[ ! -f "$CONFIG_PATH" ]]; then
  log "ERROR missing config: $CONFIG_PATH"
  exit 1
fi

build_output="$(python3 "$project_dir/python/build_visual_tasks.py" --config "$CONFIG_PATH" --tasks "$TASKS_PATH" 2>&1)" || {
  log "ERROR build_visual_tasks failed"
  log "$build_output"
  exit 1
}
log "build_visual_tasks: $build_output"

JOBS="$(python3 "$project_dir/python/read_config.py" --config "$CONFIG_PATH" --key jobs --default 8)"
FORCE="$(python3 "$project_dir/python/read_config.py" --config "$CONFIG_PATH" --key force --default false)"

log "jobs=$JOBS force=$FORCE"

run_one() {
  local sample_id="$1"
  local normalized_path="$2"
  local uniformity_low="$3"
  local uniformity_high="$4"
  local position_bin_size="$5"
  local position_smooth_window="$6"
  local max_position="$7"
  local gap_multiplier="$8"
  local uniformity_path="$9"
  local position_curve_path="${10}"
  local tmp_dir="${11}"
  local success_log="${12}"

  local sample_log="$log_dir/${sample_id}.visual.log"
  : > "$sample_log"

  if [[ "$FORCE" != "true" && -f "$success_log" ]] && grep -q "^SUCCESS\b" "$success_log"; then
    printf "[%s] SKIP sample=%s reason=success_log\n" "$(timestamp)" "$sample_id" | tee -a "$sample_log" >> "$main_log"
    return 0
  fi

  if [[ ! -f "$normalized_path" ]]; then
    printf "[%s] FAIL sample=%s reason=missing_normalized path=%s\n" "$(timestamp)" "$sample_id" "$normalized_path" | tee -a "$sample_log" >> "$main_log"
    printf "FAIL missing_normalized %s\n" "$normalized_path" > "$success_log"
    return 1
  fi

  printf "[%s] RUN sample=%s normalized=%s\n" "$(timestamp)" "$sample_id" "$normalized_path" | tee -a "$sample_log" >> "$main_log"

  if Rscript "$project_dir/script/2-均一化计算.R" \
    --sample-id "$sample_id" \
    --normalized-path "$normalized_path" \
    --uniformity-low "$uniformity_low" \
    --uniformity-high "$uniformity_high" \
    --position-bin-size "$position_bin_size" \
    --position-smooth-window "$position_smooth_window" \
    --max-position "$max_position" \
    --gap-multiplier "$gap_multiplier" \
    --uniformity-path "$uniformity_path" \
    --position-curve-path "$position_curve_path" \
    --tmp-dir "$tmp_dir" >> "$sample_log" 2>&1; then
    printf "SUCCESS sample=%s uniformity=%s pos_curve=%s\n" \
      "$sample_id" "$uniformity_path" "$position_curve_path" > "$success_log"
    printf "[%s] SUCCESS sample=%s\n" "$(timestamp)" "$sample_id" | tee -a "$sample_log" >> "$main_log"
  else
    local exit_code=$?
    printf "FAIL exit_code=%s\n" "$exit_code" > "$success_log"
    printf "[%s] FAIL sample=%s exit_code=%s\n" "$(timestamp)" "$sample_id" "$exit_code" | tee -a "$sample_log" >> "$main_log"
    return "$exit_code"
  fi
}

export project_dir log_dir main_log FORCE
export -f timestamp run_one

if command -v parallel >/dev/null 2>&1; then
  log "scheduler=gnu_parallel"
  parallel --colsep '\t' --jobs "$JOBS" --header : \
    run_one {sample_id} {normalized_path} {uniformity_low} {uniformity_high} {position_bin_size} {position_smooth_window} {max_position} {gap_multiplier} {uniformity_path} {position_curve_path} {tmp_dir} {success_log} \
    :::: "$TASKS_PATH" || log "WARN parallel reported failures"
else
  log "scheduler=xargs_P (parallel not found)"
  tail -n +2 "$TASKS_PATH" | \
    xargs -P "$JOBS" -n 12 bash -lc 'run_one "$@"' _ || log "WARN xargs reported failures"
fi

log "DONE $script_name"

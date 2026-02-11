#!/usr/bin/env bash
# 作用：批量并行执行“按样本平均深度标准化 depth.tsv.gz”的调度脚本
# 用法：
# 1) 直接使用默认配置（推荐先检查 conf/config.json）：
#    bash script/1-normalize-depth.sh
# 2) 指定配置文件路径：
#    bash script/1-normalize-depth.sh /path/to/your_config.json
# 关键输入配置位于：conf/config.json
# 关键日志输出位于：log/ 与 log/success/
set -euo pipefail

# ----------------------------
# 基础路径与主日志
# ----------------------------
script_name="$(basename "$0")"
script_dir="$(cd "$(dirname "$0")" && pwd)"
project_dir="$(cd "$script_dir/.." && pwd)"
log_dir="$project_dir/log"
main_log="$log_dir/${script_name}.log"

# 目录约定：log/ 记录日志；tmp/ 放临时文件；log/success/ 作为断点续跑依据
mkdir -p "$log_dir" "$project_dir/tmp" "$log_dir/success"

timestamp() {
  date "+%Y-%m-%d %H:%M:%S"
}

log() {
  printf "[%s] %s\n" "$(timestamp)" "$*" | tee -a "$main_log" >&2
}

# 配置文件：默认使用项目内 conf/config.json，也允许通过第1个参数覆盖
CONFIG_PATH="${1:-$project_dir/conf/config.json}"
# 任务表：由 build_tasks.py 生成，供 parallel/xargs 调度使用
TASKS_PATH="$project_dir/data/tasks.tsv"

log "START $script_name"
log "config=$CONFIG_PATH"

if [[ ! -f "$CONFIG_PATH" ]]; then
  log "ERROR missing config: $CONFIG_PATH"
  exit 1
fi

# 第一步：根据配置生成“任务表”（一行=一个样本的数据单元）
# 注意：这里只生成任务，不在 Python 里做批量调度（调度由 shell + parallel 负责）
build_output="$(python3 "$project_dir/python/build_tasks.py" --config "$CONFIG_PATH" --tasks "$TASKS_PATH" 2>&1)" || {
  log "ERROR build_tasks failed"
  log "$build_output"
  exit 1
}
log "build_tasks: $build_output"

# 从配置读取并行度与是否强制重跑（force=true 会忽略 success 日志）
JOBS="$(python3 "$project_dir/python/read_config.py" --config "$CONFIG_PATH" --key jobs --default 16)"
FORCE="$(python3 "$project_dir/python/read_config.py" --config "$CONFIG_PATH" --key force --default false)"

log "jobs=$JOBS force=$FORCE"

# ----------------------------
# 单样本计算模块（数据单元 = 1 个 sample）
# 说明：这里不做批量遍历，批量由调度器 parallel/xargs 完成
# ----------------------------
run_one() {
  local sample_id="$1"
  local average_depth="$2"
  local depth_path="$3"
  local output_path="$4"
  local tmp_dir="$5"
  local success_log="$6"

  # 每个样本独立日志，便于排查
  local sample_log="$log_dir/${sample_id}.log"
  : > "$sample_log"

  # 断点续跑规则（严格按要求）：
  # - 不通过扫盘/检查输出文件来判断是否完成
  # - 只看 log/success/<sample>.log 是否标记 SUCCESS
  if [[ "$FORCE" != "true" && -f "$success_log" ]] && grep -q "^SUCCESS\b" "$success_log"; then
    printf "[%s] SKIP sample=%s reason=success_log\n" "$(timestamp)" "$sample_id" | tee -a "$sample_log" >> "$main_log"
    return 0
  fi

  # 输入文件不存在时，写入失败原因到 success_log（便于下次继续/排查）
  if [[ ! -f "$depth_path" ]]; then
    printf "[%s] FAIL sample=%s reason=missing_depth path=%s\n" "$(timestamp)" "$sample_id" "$depth_path" | tee -a "$sample_log" >> "$main_log"
    printf "FAIL missing_depth %s\n" "$depth_path" > "$success_log"
    return 1
  fi

  printf "[%s] RUN sample=%s depth=%s\n" "$(timestamp)" "$sample_id" "$depth_path" | tee -a "$sample_log" >> "$main_log"

  # 真正的计算发生在 python/normalize_depth.py（单样本、可复用）
  if python3 "$project_dir/python/normalize_depth.py" \
    --sample-id "$sample_id" \
    --average-depth "$average_depth" \
    --depth-path "$depth_path" \
    --output-path "$output_path" \
    --tmp-dir "$tmp_dir" >> "$sample_log" 2>&1; then
    # 成功标记：仅通过该日志作为“完成依据”
    printf "SUCCESS sample=%s output=%s\n" "$sample_id" "$output_path" > "$success_log"
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

# ----------------------------
# 调度层：并行批量执行（GNU parallel 优先，xargs -P 降级）
# ----------------------------
if command -v parallel >/dev/null 2>&1; then
  log "scheduler=gnu_parallel"
  # --header : 允许按列名引用字段；--colsep '\t' 表示输入为 TSV
  parallel --colsep '\t' --jobs "$JOBS" --header : \
    run_one {sample_id} {average_depth} {depth_path} {output_path} {tmp_dir} {success_log} \
    :::: "$TASKS_PATH" || log "WARN parallel reported failures"
else
  log "scheduler=xargs_P (parallel not found)"
  # 去掉表头后，每6列作为一个样本任务喂给 run_one
  tail -n +2 "$TASKS_PATH" | \
    xargs -P "$JOBS" -n 6 bash -lc 'run_one "$@"' _ || log "WARN xargs reported failures"
fi

log "DONE $script_name"

#!/usr/bin/env bash
set -euo pipefail

# 依赖（GiantHui）：bash ≥4、GNU parallel、awk、sed、coreutils、bamdst 可执行
INPUT="/data/liuyunhui/Han_Chongqing/bam/conf/100_bam.txt"          # 每行一个 BAM 绝对路径
BED="/data/liuyunhui/Han_Chongqing/bam/conf/Y_7.4M.bed"
OUT_BASE="/data/liuyunhui/Han_Chongqing/bam/output/7.4M"         # 输出根目录
BAMDST="/home/wangzhiyong/software/bamdst/bamdst"
JOBS=20                                                      # 并行线程数
LOG="/data/liuyunhui/Han_Chongqing/bam/script/bamdst.run.log"
ACTIVE="$(mktemp)"

# 彩色输出
c_info=$(printf '\033[1;34m'); c_ok=$(printf '\033[1;32m'); c_warn=$(printf '\033[1;33m'); c_err=$(printf '\033[1;31m'); c_off=$(printf '\033[0m')
info(){ echo -e "${c_info}[$(date +%H:%M:%S)]$c_off $*"; }
ok(){ echo -e "${c_ok}[$(date +%H:%M:%S)]$c_off $*"; }
warn(){ echo -e "${c_warn}[$(date +%H:%M:%S)]$c_off $*"; }
err(){ echo -e "${c_err}[$(date +%H:%M:%S)]$c_off $*"; }

cleanup_unfinished() {
  warn "检测到中断，清理未完成任务..."
  while read -r outdir; do
    [[ -z "$outdir" ]] && continue
    if [[ -d "$outdir" && ! -f "$outdir/.done" ]]; then
      rm -rf "$outdir"
      warn "已删除未完成输出: $outdir"
    fi
  done < "$ACTIVE"
}
trap cleanup_unfinished INT TERM

export BED OUT_BASE BAMDST ACTIVE c_info c_ok c_warn c_err c_off LOG

run_one() {
  bam="$1"
  [[ -z "$bam" ]] && exit 0
  id="$(basename "$bam" .bam)"
  outdir="${OUT_BASE}/${id}"
  mkdir -p "$outdir"
  echo "$outdir" >> "$ACTIVE"
  if [[ -f "$outdir/.done" ]]; then
    ok "跳过已完成: $id"
    exit 0
  fi
  info "开始: $id"
  set +e
  "$BAMDST" -p "$BED" -o "$outdir" "$bam" 2>>"$LOG"
  status=$?
  set -e
  if [[ $status -eq 0 ]]; then
    touch "$outdir/.done"
    ok "完成: $id"
  else
    err "失败: $id (退出码 $status)"
    rm -rf "$outdir"
    exit $status
  fi
}

export -f run_one info ok warn err

# 并行运行，带进度条 --bar，joblog 记录，出现错误时尽早停止
info "开始并行处理，输入列表: $INPUT"
parallel --bar --halt soon,fail=1 --joblog "$OUT_BASE/parallel.joblog" -j "$JOBS" run_one :::: "$INPUT"
ok "全部完成"
rm -f "$ACTIVE"

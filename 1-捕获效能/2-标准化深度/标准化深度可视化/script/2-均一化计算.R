#!/usr/bin/env Rscript

# 单样本计算模块：
# 输入一个样本的 normalized depth 文件，输出：
# 1) 均一性指标（落在[low, high]的碱基比例）
# 2) 位置曲线（按物理位置 bin + 平滑）

suppressPackageStartupMessages({
  library(tidyverse)
})

script_path <- sub("^--file=", "", commandArgs(trailingOnly = FALSE)[grep("^--file=", commandArgs(trailingOnly = FALSE))])
script_dir <- if (length(script_path) == 0) getwd() else dirname(normalizePath(script_path))
source(file.path(script_dir, "arg_utils.R"))

read_normalized_depth <- function(path) {
  # 允许读取 .tsv.gz，跳过以 # 开头的注释行
  # 规范列名：Chr, Pos, RawDepth, NormDepth
  readr::read_tsv(
    file = path,
    comment = "#",
    col_names = c("Chr", "Pos", "RawDepth", "NormDepth"),
    col_types = cols(
      Chr = col_character(),
      Pos = col_double(),
      RawDepth = col_double(),
      NormDepth = col_double()
    ),
    progress = FALSE,
    show_col_types = FALSE
  )
}

compute_uniformity <- function(norm_depth, low, high) {
  total_bases <- length(norm_depth)
  if (total_bases == 0) {
    return(tibble(
      total_bases = 0,
      uniform_bases = 0,
      uniform_fraction = NA_real_,
      uniformity_low = low,
      uniformity_high = high
    ))
  }
  uniform_bases <- sum(norm_depth >= low & norm_depth <= high, na.rm = TRUE)
  tibble(
    total_bases = total_bases,
    uniform_bases = uniform_bases,
    uniform_fraction = uniform_bases / total_bases,
    uniformity_low = low,
    uniformity_high = high
  )
}

rolling_mean <- function(x, window) {
  # 简单滑动平均（居中窗口），用于平滑位置曲线
  n <- length(x)
  if (window <= 1 || n == 0) {
    return(x)
  }
  window <- min(window, n)
  if (window <= 1) {
    return(x)
  }
  stats::filter(x, rep(1 / window, window), sides = 2) %>% as.numeric()
}

compute_position_curve <- function(pos, norm_depth, bin_size, smooth_window) {
  # 目标：横轴为物理位置（bin中心），纵轴为标准化深度（bin均值+平滑）
  tbl <- tibble(Pos = pos, NormDepth = norm_depth) %>%
    filter(is.finite(Pos), is.finite(NormDepth))

  if (nrow(tbl) == 0) {
    return(tibble(
      pos_bin_center = numeric(),
      norm_mean = numeric(),
      norm_smooth = numeric(),
      bin_size = bin_size,
      smooth_window = smooth_window
    ))
  }

  min_pos <- min(tbl$Pos)
  tbl_binned <- tbl %>%
    mutate(
      pos_bin = floor((Pos - min_pos) / bin_size),
      pos_bin_center = min_pos + (pos_bin + 0.5) * bin_size
    ) %>%
    group_by(pos_bin, pos_bin_center) %>%
    summarise(norm_mean = mean(NormDepth, na.rm = TRUE), .groups = "drop") %>%
    arrange(pos_bin_center)

  tbl_binned %>%
    mutate(
      norm_smooth = rolling_mean(norm_mean, smooth_window),
      bin_size = bin_size,
      smooth_window = smooth_window
    ) %>%
    select(pos_bin_center, norm_mean, norm_smooth, bin_size, smooth_window)
}

atomic_write_tsv <- function(df, out_path, tmp_dir) {
  dir.create(dirname(out_path), recursive = TRUE, showWarnings = FALSE)
  dir.create(tmp_dir, recursive = TRUE, showWarnings = FALSE)
  tmp_path <- file.path(tmp_dir, paste0(basename(out_path), ".tmp"))
  readr::write_tsv(df, tmp_path)
  ok <- file.rename(tmp_path, out_path)
  if (!ok) {
    stop("原子写入失败：", out_path)
  }
}

run <- function(
  sample_id,
  normalized_path,
  uniformity_low,
  uniformity_high,
  position_bin_size,
  position_smooth_window,
  max_position,
  gap_multiplier,
  uniformity_path,
  position_curve_path,
  tmp_dir
) {
  depth_tbl <- read_normalized_depth(normalized_path)

  if (!is.na(max_position) && max_position > 0) {
    depth_tbl <- depth_tbl %>% filter(Pos <= max_position)
  }

  uniformity_tbl <- compute_uniformity(
    norm_depth = depth_tbl$NormDepth,
    low = uniformity_low,
    high = uniformity_high
  ) %>%
    mutate(sample_id = sample_id, .before = 1)

  position_curve_tbl <- compute_position_curve(
    pos = depth_tbl$Pos,
    norm_depth = depth_tbl$NormDepth,
    bin_size = position_bin_size,
    smooth_window = position_smooth_window
  ) %>%
    mutate(gap_multiplier = gap_multiplier, .before = 1) %>%
    mutate(sample_id = sample_id, .before = 1)

  atomic_write_tsv(uniformity_tbl, uniformity_path, tmp_dir)
  atomic_write_tsv(position_curve_tbl, position_curve_path, tmp_dir)

  invisible(list(
    uniformity_path = uniformity_path,
    position_curve_path = position_curve_path
  ))
}

main <- function() {
  args <- get_args(c(
    "--sample-id",
    "--normalized-path",
    "--uniformity-low",
    "--uniformity-high",
    "--position-bin-size",
    "--position-smooth-window",
    "--max-position",
    "--gap-multiplier",
    "--uniformity-path",
    "--position-curve-path",
    "--tmp-dir"
  ))

  run(
    sample_id = args$`sample-id`,
    normalized_path = args$`normalized-path`,
    uniformity_low = as.numeric(args$`uniformity-low`),
    uniformity_high = as.numeric(args$`uniformity-high`),
    position_bin_size = as.integer(args$`position-bin-size`),
    position_smooth_window = as.integer(args$`position-smooth-window`),
    max_position = as.integer(args$`max-position`),
    gap_multiplier = as.numeric(args$`gap-multiplier`),
    uniformity_path = args$`uniformity-path`,
    position_curve_path = args$`position-curve-path`,
    tmp_dir = args$`tmp-dir`
  )
}

if (identical(environment(), globalenv())) {
  main()
}

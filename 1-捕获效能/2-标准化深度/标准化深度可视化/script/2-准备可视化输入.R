#!/usr/bin/env Rscript

# 可视化输入数据准备模块：
# 读取单样本计算结果 + 元信息，并生成可复用的中间文件（CSV）

suppressPackageStartupMessages({
  library(tidyverse)
})

script_path <- sub("^--file=", "", commandArgs(trailingOnly = FALSE)[grep("^--file=", commandArgs(trailingOnly = FALSE))])
script_dir <- if (length(script_path) == 0) getwd() else dirname(normalizePath(script_path))
source(file.path(script_dir, "arg_utils.R"))

read_many_tsv <- function(dir_path, pattern) {
  files <- list.files(dir_path, pattern = pattern, full.names = TRUE)
  if (length(files) == 0) {
    stop("未找到输入文件：", dir_path, " pattern=", pattern)
  }
  purrr::map_dfr(
    files,
    ~ readr::read_tsv(.x, show_col_types = FALSE, progress = FALSE)
  )
}

read_target_intervals <- function(path) {
  if (is.null(path) || is.na(path) || path == "") {
    return(NULL)
  }
  if (!file.exists(path)) {
    return(NULL)
  }
  intervals <- readr::read_tsv(path, show_col_types = FALSE, progress = FALSE)
  required <- c("start", "end")
  if (!all(required %in% names(intervals))) {
    intervals <- readr::read_tsv(
      path,
      col_names = FALSE,
      show_col_types = FALSE,
      progress = FALSE,
      comment = "#"
    )
    if (ncol(intervals) < 3) {
      stop("target_intervals_tsv 需要至少3列：chr, start, end")
    }
    intervals <- intervals %>%
      transmute(
        label = if (ncol(intervals) >= 4) as.character(.data$X4) else "target",
        start = as.numeric(.data$X2),
        end = as.numeric(.data$X3)
      )
  }
  if (!("label" %in% names(intervals))) {
    intervals$label <- "target"
  }
  if (!("color" %in% names(intervals))) {
    intervals$color <- "#4C78A8"
  }
  intervals %>%
    mutate(
      start = as.numeric(start),
      end = as.numeric(end),
      label = as.character(label),
      color = as.character(color)
    )
}

read_average_depth <- function(path) {
  if (is.null(path) || is.na(path) || path == "") {
    return(NULL)
  }
  if (!file.exists(path)) {
    return(NULL)
  }
  avg_tbl <- readr::read_csv(path, show_col_types = FALSE, progress = FALSE)
  required <- c("SampleID", "Avg")
  if (!all(required %in% names(avg_tbl))) {
    stop("average_depth_csv 需要列：SampleID, Avg")
  }
  avg_tbl %>%
    transmute(sample_id = as.character(SampleID), avg_depth = as.numeric(Avg))
}

make_depth_bins <- function(df, bin_size, min_d, max_d) {
  if (bin_size <= 0 || nrow(df) == 0) {
    df$depth_bin <- NA_character_
    return(df)
  }
  max_d_num <- suppressWarnings(as.numeric(max_d))
  if (!is.finite(max_d_num) || max_d_num <= 0) {
    max_d_num <- max(df$avg_depth, na.rm = TRUE)
  }
  min_d_num <- suppressWarnings(as.numeric(min_d))
  if (!is.finite(min_d_num)) min_d_num <- 0
  breaks <- seq(min_d_num, max_d_num + bin_size, by = bin_size)
  labs <- paste0("[", head(breaks, -1), "-", tail(breaks, -1), ")")
  df %>%
    mutate(depth_bin = cut(avg_depth, breaks = breaks, labels = labs, include.lowest = TRUE, right = FALSE))
}

select_samples_for_curve <- function(uniformity_tbl, strategy, n, seed) {
  if (strategy == "all") {
    return(uniformity_tbl$sample_id)
  }
  if (strategy == "top_n") {
    return(
      uniformity_tbl %>%
        arrange(desc(uniform_fraction)) %>%
        slice_head(n = n) %>%
        pull(sample_id)
    )
  }
  set.seed(seed)
  uniformity_tbl %>%
    slice_sample(n = min(n, nrow(uniformity_tbl))) %>%
    pull(sample_id)
}

run <- function(
  uniformity_dir,
  position_dir,
  average_depth_path,
  target_intervals_path,
  max_position,
  plot_sample_strategy,
  plot_sample_n,
  plot_random_seed,
  depth_bin_size,
  depth_bin_min,
  depth_bin_max,
  samples_per_bin,
  color_by_depth_bin,
  out_dir
) {
  uniformity_tbl <- read_many_tsv(uniformity_dir, "\\.uniformity\\.tsv$")
  position_curve_tbl <- read_many_tsv(position_dir, "\\.pos_curve\\.tsv$")
  position_curve_tbl <- position_curve_tbl %>%
    mutate(
      pos_bin_center = as.numeric(pos_bin_center),
      norm_mean = as.numeric(norm_mean),
      norm_smooth = as.numeric(norm_smooth)
    )

  max_position_num <- suppressWarnings(as.numeric(max_position))
  if (is.finite(max_position_num) && max_position_num > 0) {
    position_curve_tbl <- position_curve_tbl %>%
      filter(pos_bin_center <= max_position_num)
  }

  avg_depth_tbl <- read_average_depth(average_depth_path)
  if (is.null(avg_depth_tbl)) {
    stop("average_depth_csv 未找到：", average_depth_path)
  }

  avg_depth_tbl <- make_depth_bins(
    df = avg_depth_tbl,
    bin_size = depth_bin_size,
    min_d = depth_bin_min,
    max_d = depth_bin_max
  )

  if (color_by_depth_bin) {
    position_curve_tbl <- position_curve_tbl %>%
      left_join(avg_depth_tbl %>% select(sample_id, depth_bin), by = "sample_id")
    uniformity_tbl <- uniformity_tbl %>%
      left_join(avg_depth_tbl %>% select(sample_id, depth_bin), by = "sample_id")
  }

  target_intervals <- read_target_intervals(target_intervals_path)
  if (!is.null(target_intervals) && is.finite(max_position_num) && max_position_num > 0) {
    target_intervals <- target_intervals %>% filter(start <= max_position_num)
  }

  if (!is.null(samples_per_bin) && samples_per_bin > 0 && !is.null(avg_depth_tbl$depth_bin)) {
    set.seed(plot_random_seed)
    selected_samples <- avg_depth_tbl %>%
      filter(!is.na(depth_bin)) %>%
      group_by(depth_bin) %>%
      mutate(.rand = runif(dplyr::n())) %>%
      slice_min(order_by = .rand, n = samples_per_bin, with_ties = FALSE) %>%
      ungroup() %>%
      pull(sample_id)
  } else {
    selected_samples <- select_samples_for_curve(
      uniformity_tbl = uniformity_tbl,
      strategy = plot_sample_strategy,
      n = plot_sample_n,
      seed = plot_random_seed
    )
  }

  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

  readr::write_csv(uniformity_tbl, file.path(out_dir, "uniformity_tbl.csv"))
  readr::write_csv(position_curve_tbl, file.path(out_dir, "position_curve_tbl.csv"))
  readr::write_csv(avg_depth_tbl, file.path(out_dir, "avg_depth_tbl.csv"))
  readr::write_csv(
    tibble(sample_id = selected_samples),
    file.path(out_dir, "selected_samples.csv")
  )
  if (!is.null(target_intervals)) {
    readr::write_csv(target_intervals, file.path(out_dir, "target_intervals.csv"))
  } else {
    readr::write_csv(tibble(), file.path(out_dir, "target_intervals.csv"))
  }

  invisible(out_dir)
}

main <- function() {
  # 参数在 shell 中解析后传入：目录与数值分开，方便手动调整 tidyplots
  args <- get_args(c(
    "--uniformity-dir",
    "--position-dir",
    "--average-depth",
    "--target-intervals",
    "--max-position",
    "--plot-sample-strategy",
    "--plot-sample-n",
    "--plot-random-seed",
    "--depth-bin-size",
    "--depth-bin-min",
    "--depth-bin-max",
    "--samples-per-bin",
    "--color-by-depth-bin",
    "--out"
  ))

  run(
    uniformity_dir = args$`uniformity-dir`,
    position_dir = args$`position-dir`,
    average_depth_path = args$`average-depth`,
    target_intervals_path = args$`target-intervals`,
    max_position = as.numeric(args$`max-position`),
    plot_sample_strategy = args$`plot-sample-strategy`,
    plot_sample_n = as.integer(args$`plot-sample-n`),
    plot_random_seed = as.integer(args$`plot-random-seed`),
    depth_bin_size = as.numeric(args$`depth-bin-size`),
    depth_bin_min = as.numeric(args$`depth-bin-min`),
    depth_bin_max = as.numeric(args$`depth-bin-max`),
    samples_per_bin = as.integer(args$`samples-per-bin`),
    color_by_depth_bin = as.logical(args$`color-by-depth-bin`),
    out_dir = args$out
  )
}

if (identical(environment(), globalenv())) {
  main()
}

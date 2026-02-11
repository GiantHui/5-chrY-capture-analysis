#!/usr/bin/env Rscript

# 标准化深度可视化（直接脚本版）
# - 不使用函数封装，便于逐段调试
# - 保持原有计算/绘图逻辑不变
# - 作图全部使用 tidyplots

library(tidyverse)
library(tidyplots)
library(ggthemes)

# ---- 固定路径 ----

project_dir <- normalizePath("/mnt/d/捕获体系/2-捕获效能/3-标准化深度/标准化深度可视化", mustWork = FALSE)
input_dir   <- file.path(project_dir, "input/visual_input_csv")
output_dir  <- file.path(project_dir, "output")
tmp_dir     <- file.path(project_dir, "tmp")

# ---- 读取输入 ----

uniformity_tbl <- readr::read_csv(file.path(input_dir, "uniformity_tbl.csv"), show_col_types = FALSE)
position_curve_tbl <- readr::read_csv(file.path(input_dir, "position_curve_tbl.csv"), show_col_types = FALSE)
avg_depth_tbl <- readr::read_csv(file.path(input_dir, "avg_depth_tbl.csv"), show_col_types = FALSE)

selected_samples <- if (file.exists(file.path(input_dir, "selected_samples.csv"))) {
  readr::read_csv(file.path(input_dir, "selected_samples.csv"), show_col_types = FALSE)
} else {
  tibble(sample_id = character())
}

target_intervals <- if (file.exists(file.path(input_dir, "target_intervals.csv"))) {
  readr::read_csv(file.path(input_dir, "target_intervals.csv"), show_col_types = FALSE)
} else {
  tibble()
}

# ---- 数据准备：均一性 ----

uniformity_dat <- uniformity_tbl |>
  left_join(avg_depth_tbl, by = "sample_id") |>
  filter(is.finite(avg_depth), avg_depth > 0, is.finite(uniform_fraction))

# ---- 数据准备：位置曲线 ----

# 重新按平均深度分箱：100 一个 bin，每个 bin 随机选 2 个样本
set.seed(42)
depth_bin_size <- 100
samples_per_bin <- 2

avg_depth_tbl <- avg_depth_tbl |>
  mutate(
    depth_bin = cut(
      avg_depth,
      breaks = seq(
        floor(min(avg_depth, na.rm = TRUE) / depth_bin_size) * depth_bin_size,
        ceiling(max(avg_depth, na.rm = TRUE) / depth_bin_size) * depth_bin_size + depth_bin_size,
        by = depth_bin_size
      ),
      include.lowest = TRUE,
      right = FALSE
    )
  )

position_ids <- position_curve_tbl |>
  distinct(sample_id) |>
  pull(sample_id)

selected_ids <- avg_depth_tbl |>
  filter(sample_id %in% position_ids) |>
  filter(!is.na(depth_bin)) |>
  group_by(depth_bin) |>
  group_modify(~ {
    n_take <- min(samples_per_bin, nrow(.x))
    dplyr::slice_sample(.x, n = n_take, replace = FALSE)
  }) |>
  ungroup() |>
  pull(sample_id)

if (length(selected_ids) == 0) {
  stop("没有选到样本：请检查 avg_depth_tbl/position_curve_tbl 与 depth_bin 划分是否正常")
}

message(
  sprintf(
    "Selected %d samples (samples_per_bin=%d, bins=%d).",
    length(selected_ids),
    samples_per_bin,
    n_distinct(avg_depth_tbl$depth_bin)
  )
)

smooth_col <- if ("norm_smooth" %in% names(position_curve_tbl)) "norm_smooth" else NULL

pos_dat <- position_curve_tbl |>
  filter(sample_id %in% selected_ids) |>
  select(-any_of("depth_bin")) |>
  left_join(avg_depth_tbl %>% select(sample_id, depth_bin), by = "sample_id")

if (!("depth_bin" %in% names(pos_dat))) {
  pos_dat$depth_bin <- NA_character_
}

pos_dat <- pos_dat |>
  mutate(
    norm_plot = dplyr::coalesce(
      if (!is.null(smooth_col)) if_else(is.finite(.data[[smooth_col]]), .data[[smooth_col]], NA_real_) else NA_real_,
      norm_mean
    ),
    color_group = as.character(depth_bin),
    group_key = as.character(depth_bin)
  )

legend_title <- "Depth Bin"
depth_palette <- c(
  "#1f78b4", "#33a02c", "#e31a1c", "#ff7f00",
  "#6a3d9a", "#b15928", "#a6cee3", "#fb9a99"
)

gap_min_mb <- 0.5

# ---- 相关性分析：Uniformity vs Avg Depth / log10 Avg Depth ----

corr_dat <- uniformity_dat |>
  transmute(
    uniform_fraction,
    avg_depth,
    log10_avg_depth = log10(avg_depth)
  ) |>
  filter(is.finite(uniform_fraction), is.finite(avg_depth), is.finite(log10_avg_depth))

run_cor_test <- function(x, y, method, pair_label) {
  ok <- is.finite(x) & is.finite(y)
  x <- x[ok]
  y <- y[ok]

  if (length(x) < 3) {
    return(tibble(
      pair = pair_label,
      method = method,
      n = length(x),
      estimate = NA_real_,
      p_value = NA_real_,
      conf_low = NA_real_,
      conf_high = NA_real_,
      note = "n<3"
    ))
  }

  ct <- suppressWarnings(
    cor.test(
      x,
      y,
      method = method,
      exact = if (method == "spearman") FALSE else NULL
    )
  )

  conf <- if (!is.null(ct$conf.int)) ct$conf.int else c(NA_real_, NA_real_)

  tibble(
    pair = pair_label,
    method = method,
    n = length(x),
    estimate = unname(ct$estimate),
    p_value = ct$p.value,
    conf_low = conf[1],
    conf_high = conf[2],
    note = NA_character_
  )
}

corr_results <- bind_rows(
  run_cor_test(
    corr_dat$uniform_fraction,
    corr_dat$avg_depth,
    "pearson",
    "uniformity vs avg_depth"
  ),
  run_cor_test(
    corr_dat$uniform_fraction,
    corr_dat$log10_avg_depth,
    "pearson",
    "uniformity vs log10_avg_depth"
  )
)

message("Correlation tests (uniformity vs depth):")
print(corr_results)

readr::write_csv(
  corr_results,
  file.path(output_dir, "uniformity_correlation_tests.csv")
)

format_p <- function(p) {
  if (is.na(p)) {
    return("p=NA")
  }
  if (p < 1e-3) {
    return("p<0.001")
  }
  paste0("p=", formatC(p, format = "g", digits = 3))
}

pearson_avg <- corr_results |> filter(pair == "uniformity vs avg_depth")
pearson_log <- corr_results |> filter(pair == "uniformity vs log10_avg_depth")

label_pearson_avg <- sprintf("Pearson r=%.3f, %s", pearson_avg$estimate, format_p(pearson_avg$p_value))
label_pearson_log <- sprintf("Pearson r=%.3f, %s", pearson_log$estimate, format_p(pearson_log$p_value))

label_x_avg <- quantile(uniformity_dat$avg_depth, 0.02, na.rm = TRUE)
label_y_avg <- 0.98
label_x_log <- quantile(log10(uniformity_dat$avg_depth), 0.02, na.rm = TRUE)
label_y_log <- 0.98

# ---- 作图 1：Uniformity vs Avg Depth ----

p_uniformity_avg <- uniformity_dat |>
  mutate(depth_axis = avg_depth) |>
  tidyplot(x = depth_axis, y = uniform_fraction, dodge_width = 0) |>
  add_data_points(color = "#0072b2") |>
  add(ggplot2::geom_smooth(method = "lm", se = TRUE, color = "#d55e00", fill = "#d55e00", alpha = 0.2, linewidth = 0.6)) |>
  add(ggplot2::annotate("text", x = label_x_avg, y = label_y_avg, label = label_pearson_avg, hjust = 0, vjust = 1, size = 3.5)) |>
  add_reference_lines(y = 0.6, linetype = "dashed", color = "#e6665dff") |>
  adjust_x_axis_title("Average Depth") |>
  adjust_y_axis_title("Uniformity (fraction)") |>
  adjust_y_axis(limits = c(0, 1)) |>
  theme_tidyplot()

p_uniformity_avg
# ---- 作图 2：Uniformity vs log10 Avg Depth ----

p_uniformity_log <- uniformity_dat |>
  mutate(depth_axis = log10(avg_depth)) |>
  tidyplot(x = depth_axis, y = uniform_fraction, dodge_width = 0) |>
  add_data_points(color = "#0072b2") |>
  add(ggplot2::geom_smooth(method = "lm", se = TRUE, color = "#d55e00", fill = "#d55e00", alpha = 0.2, linewidth = 0.6)) |>
  add(ggplot2::annotate("text", x = label_x_log, y = label_y_log, label = label_pearson_log, hjust = 0, vjust = 1, size = 3.5)) |>
  add_reference_lines(y = 0.6, linetype = "dashed", color = "#e6665dff") |>
  adjust_x_axis_title("log10(Average Depth)") |>
  adjust_y_axis_title("Uniformity (fraction)") |>
  adjust_y_axis(limits = c(0, 1)) |>
  theme_tidyplot()

p_uniformity_log
# ---- 作图 3：Position Curve ----
depth_levels <- pos_dat |>
  distinct(depth_bin = group_key) |>
  mutate(
    depth_low = readr::parse_number(stringr::str_extract(depth_bin, "^\\[[^,]+"))
  ) |>
  arrange(depth_low) |>
  pull(depth_bin)

pos_dat <- pos_dat |>
  mutate(
    group_key = factor(group_key, levels = depth_levels),
    color_group = factor(color_group, levels = depth_levels),
    depth_low = readr::parse_number(stringr::str_extract(as.character(color_group), "^\\[[^,]+"))
  )

pos_dat <- pos_dat |>
  group_by(sample_id) |>
  arrange(pos_bin_center, .by_group = TRUE) |>
  mutate(
    bin_size_val = if ("bin_size" %in% names(pos_dat)) {
      suppressWarnings(first(na.omit(bin_size)))
    } else {
      median(diff(pos_bin_center), na.rm = TRUE)
    },
    gap_multiplier_val = if ("gap_multiplier" %in% names(pos_dat)) {
      suppressWarnings(first(na.omit(gap_multiplier)))
    } else {
      3
    },
    gap_thresh = max(bin_size_val * gap_multiplier_val, gap_min_mb * 1e6),
    gap_flag = (pos_bin_center - lag(pos_bin_center)) > gap_thresh,
    gap_x = (pos_bin_center + lag(pos_bin_center)) / 2,
    segment_id = cumsum(if_else(isTRUE(gap_flag), 1L, 0L)) + 1L
  ) |>
  ungroup()

pos_plot_dat <- pos_dat |>
  mutate(group_id = paste(sample_id, segment_id, sep = "__")) |>
  arrange(desc(depth_low), sample_id, pos_bin_center)

p_position <- tidyplot(pos_plot_dat, x = pos_bin_center, y = norm_plot, color = color_group, group = group_id) |>
  add_area(alpha = 0.3) |>
  adjust_x_axis_title("Position (Mb)") |>
  adjust_y_axis_title("Normalized Coverage") |>
  adjust_x_axis(labels = scales::label_number(scale = 1e-6, accuracy = 1)) |>
  adjust_colors(new_colors = depth_palette)

p_ymin <- min(pos_dat$norm_plot, na.rm = TRUE)
p_ymax <- max(pos_dat$norm_plot, na.rm = TRUE)
p_yrng <- p_ymax - p_ymin
p_band_h <- max(p_yrng * 0.04, p_ymax * 0.02, 0.02)
p_band_gap <- max(p_yrng * 0.02, p_ymax * 0.01, 0.01)
p_band_ymax <- p_ymin - p_band_gap
p_band_ymin <- p_band_ymax - p_band_h
p_axis_ymin <- p_band_ymin - p_band_gap

p_position <- p_position |>
  adjust_y_axis(limits = c(p_axis_ymin, p_ymax))

if (!is.null(target_intervals) && nrow(target_intervals) > 0) {
  band <- target_intervals |>
    mutate(
      ymin = p_band_ymin,
      ymax = p_band_ymax,
      color = if ("color" %in% names(target_intervals)) dplyr::coalesce(.data$color, "#e6665dff") else "#e6665dff"
    )
  p_position <- p_position |>
    add(
      ggplot2::geom_rect(
        data = band,
        mapping = ggplot2::aes(xmin = start, xmax = end, ymin = ymin, ymax = ymax, fill = I(color)),
        inherit.aes = FALSE,
        alpha = 0.9
      )
    )
}

p_position

pos_raw_dat <- pos_dat |>
  mutate(norm_raw = norm_mean)

pos_raw_plot_dat <- pos_raw_dat |>
  mutate(group_id = paste(sample_id, segment_id, sep = "__")) |>
  arrange(desc(depth_low), sample_id, pos_bin_center)

p_position_raw <- tidyplot(pos_raw_plot_dat, x = pos_bin_center, y = norm_raw, color = color_group, group = group_id) |>
  add_line(alpha = 0.5, linewidth = 0.3) |>
  adjust_x_axis_title("Position (Mb)") |>
  adjust_y_axis_title("Normalized Coverage (raw)") |>
  adjust_x_axis(labels = scales::label_number(scale = 1e-6, accuracy = 1)) |>
  adjust_colors(new_colors = depth_palette)

p_position_raw

# p_position <- tidyplot(pos_dat, x = pos_bin_center, y = norm_plot, color = color_group) |>
#   add_mean_line(group = group_key, alpha = 0.5, linewidth = 0.2) |>
#   adjust_x_axis_title("Position (Mb)") |>
#   adjust_y_axis_title("Normalized Coverage") |>
#   adjust_x_axis(labels = scales::label_number(scale = 1e-6, accuracy = 1)) |>
#   adjust_legend_title(legend_title) |>
#   theme_tidyplot()

# if (!is.null(target_intervals) && nrow(target_intervals) > 0) {
#   band <- target_intervals |>
#     mutate(
#       ymin = min(pos_dat$norm_plot, na.rm = TRUE) * 0.92,
#       ymax = min(pos_dat$norm_plot, na.rm = TRUE) * 0.98,
#       color = if ("color" %in% names(target_intervals)) dplyr::coalesce(.data$color, "#e6665dff") else "#e6665dff"
#     )
#   p_position <- p_position |>
#     add(
#       ggplot2::geom_rect(
#         data = band,
#         mapping = ggplot2::aes(xmin = start, xmax = end, ymin = ymin, ymax = ymax, fill = I(color)),
#         inherit.aes = FALSE,
#         alpha = 0.9
#       )
#     )
# }

# ---- 保存输出 ----

#! 使用patchwork v1.3.0组合tidyplot对象需要使用如下代码
patchwork::wrap_plots(p_uniformity_avg, p_uniformity_log, p_position, p_position_raw) + 
    patchwork::plot_layout(ncol = 2) +
        patchwork::plot_annotation(tag_levels = "A") -> p_all


ggsave(filename = file.path(output_dir, "uniformity_visualization.pdf"), plot = p_all)


readr::write_csv(
  uniformity_dat %>% select(sample_id, uniform_fraction, avg_depth),
  file.path(output_dir, "uniformity_per_sample.csv")
)

writeLines(
  c(
    "Figure 1: Uniformity vs average depth (dashed line at 0.60).",
    "Figure 2: Uniformity vs log10 average depth (dashed line at 0.60).",
    "Figure 3: Normalized coverage across genomic positions (selected samples).",
    sprintf(
      "Summary (EN): Uniformity is positively correlated with average depth (Pearson r=%.3f, n=%d, %s). The correlation is stronger after log10 transform of average depth (Pearson r=%.3f, n=%d, %s).",
      pearson_avg$estimate,
      pearson_avg$n,
      format_p(pearson_avg$p_value),
      pearson_log$estimate,
      pearson_log$n,
      format_p(pearson_log$p_value)
    ),
    sprintf(
      "摘要（CN）：均一性与平均深度呈正相关（Pearson r=%.3f，n=%d，%s）。对平均深度取 log10 后相关性更强（Pearson r=%.3f，n=%d，%s）。",
      pearson_avg$estimate,
      pearson_avg$n,
      format_p(pearson_avg$p_value),
      pearson_log$estimate,
      pearson_log$n,
      format_p(pearson_log$p_value)
    ),
    "Figure 3 interpretation (EN): The position curve shows how normalized coverage changes along genomic positions; flatter curves indicate more uniform coverage, while systematic peaks/valleys suggest positional bias. The target intervals band marks regions of interest near the baseline for visual alignment.",
    "图3解读（CN）：位置曲线展示标准化覆盖在基因组位置上的变化；曲线越平坦代表覆盖越均一，系统性峰谷提示位置偏差。靠近基线的目标区间带用于标注关注区域。"
  ),
  file.path(output_dir, "figure_captions_en.txt")
)

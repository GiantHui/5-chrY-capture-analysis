#!/usr/bin/env Rscript

# 标准化深度可视化（直接脚本版）
# - 不使用函数封装，便于逐段调试
# - 保持原有计算/绘图逻辑不变
# - 作图全部使用 tidyplots

library(tidyverse)
library(tidyplots)
library(ggthemes)
library(ggrastr)
library(patchwork)

# ---- 固定路径 ----

project_dir <- normalizePath("/mnt/d/捕获体系/2-捕获效能/3-标准化深度/标准化深度可视化", mustWork = FALSE)
input_dir   <- file.path(project_dir, "input/visual_input_csv")
output_dir  <- file.path(project_dir, "output")
tmp_dir     <- file.path(project_dir, "tmp")

# ---- 读取输入 ----

uniformity_tbl <- readr::read_csv(file.path(input_dir, "uniformity_tbl.csv"), show_col_types = FALSE)
avg_depth_tbl <- readr::read_csv(file.path(input_dir, "avg_depth_tbl.csv"), show_col_types = FALSE)

# ---- 数据准备：均一性 ----

uniformity_dat <- uniformity_tbl |>
  left_join(avg_depth_tbl, by = "sample_id") |>
  filter(is.finite(avg_depth), avg_depth > 0, is.finite(uniform_fraction))

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

point_border_color <- "#539fcb"
point_fill_color <- scales::alpha("#539fcb", 0.8)
fit_line_color <- "#ef785c"
fit_ci_fill_color <- scales::alpha("#ef785c", 0.8)

# ---- 作图 1：Uniformity vs Avg Depth ----

p_uniformity_avg <- uniformity_dat |>
  mutate(depth_axis = avg_depth) |>
  tidyplot(x = depth_axis, y = uniform_fraction, dodge_width = 0) |>
  add(
    ggrastr::geom_point_rast(
      shape = 21,
      size = 1.8,
      stroke = 0.35,
      color = point_border_color,
      fill = point_fill_color,
      raster.dpi = 300
    )
  ) |>
  add(
    ggplot2::geom_smooth(
      method = "lm",
      se = TRUE,
      color = fit_line_color,
      fill = fit_ci_fill_color,
      alpha = 0.8,
      linewidth = 0.6
    )
  ) |>
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
  add(
    ggrastr::geom_point_rast(
      shape = 21,
      size = 1.8,
      stroke = 0.35,
      color = point_border_color,
      fill = point_fill_color,
      raster.dpi = 300
    )
  ) |>
  add(
    ggplot2::geom_smooth(
      method = "lm",
      se = TRUE,
      color = fit_line_color,
      fill = fit_ci_fill_color,
      alpha = 0.8,
      linewidth = 0.6
    )
  ) |>
  add(ggplot2::annotate("text", x = label_x_log, y = label_y_log, label = label_pearson_log, hjust = 0, vjust = 1, size = 3.5)) |>
  add_reference_lines(y = 0.6, linetype = "dashed", color = "#e6665dff") |>
  adjust_x_axis_title("log10(Average Depth)") |>
  adjust_y_axis_title("Uniformity (fraction)") |>
  adjust_y_axis(limits = c(0, 1)) |>
  theme_tidyplot()

p_uniformity_log

combined_plot <- patchwork::wrap_elements(full = p_uniformity_avg) +
  patchwork::wrap_elements(full = p_uniformity_log) +
  patchwork::plot_layout(ncol = 2) +
  patchwork::plot_annotation(tag_levels = "A")

# ---- 保存输出 ----

unlink(
  file.path(
    output_dir,
    c("uniformity_position_curve_54samples.pdf", "uniformity_position_curve_54samples.png")
  ),
  force = TRUE
)

ggsave(filename = file.path(output_dir, "uniformity_avg_scatter.pdf"), plot = p_uniformity_avg, width = 7, height = 5.2)
ggsave(filename = file.path(output_dir, "uniformity_avg_scatter.png"), plot = p_uniformity_avg, width = 7, height = 5.2, dpi = 300)

ggsave(filename = file.path(output_dir, "uniformity_log_scatter.pdf"), plot = p_uniformity_log, width = 7, height = 5.2)
ggsave(filename = file.path(output_dir, "uniformity_log_scatter.png"), plot = p_uniformity_log, width = 7, height = 5.2, dpi = 300)

ggsave(filename = file.path(output_dir, "uniformity_scatter_combined.pdf"), plot = combined_plot, width = 14, height = 5.2)
ggsave(filename = file.path(output_dir, "uniformity_scatter_combined.png"), plot = combined_plot, width = 14, height = 5.2, dpi = 300)


readr::write_csv(
  uniformity_dat %>% select(sample_id, uniform_fraction, avg_depth),
  file.path(output_dir, "uniformity_per_sample.csv")
)

writeLines(
  c(
    "Figure 1: Scatter plot of uniformity versus average depth, with rasterized points and a linear regression fit with 95% confidence interval.",
    "Figure 2: Scatter plot of uniformity versus log10-transformed average depth, with rasterized points and a linear regression fit with 95% confidence interval.",
    "Combined Figure: Figure 1 and Figure 2 are arranged side by side using patchwork and exported as a combined PDF/PNG.",
    "图注（CN）：图1为均一性与平均深度的散点图；图2为均一性与 log10 转换后平均深度的散点图。散点已栅格化以降低大规模位点绘图负担，并叠加线性拟合及 95% 置信区间；另导出 patchwork 横向拼接的合成图。"
  ),
  file.path(output_dir, "figure_captions_en.txt")
)

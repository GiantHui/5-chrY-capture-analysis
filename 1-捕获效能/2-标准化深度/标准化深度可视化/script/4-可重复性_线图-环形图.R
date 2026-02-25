#!/usr/bin/env Rscript

suppressPackageStartupMessages({
  library(data.table)
  library(tidyplots)
  library(ggplot2)
  library(stringr)
  library(patchwork)
  library(readr)
})

project_dir <- '/mnt/d/捕获体系/2-捕获效能/3-标准化深度/标准化深度可视化'
input_dir <- file.path(project_dir, 'input/visual_input_csv')
out_dir <- file.path(project_dir, 'output')

# ---- 输入 ----
sel <- fread(file.path(input_dir, 'selected_samples.csv'))
pos <- fread(file.path(input_dir, 'position_curve_tbl.csv'))
avg <- fread(file.path(input_dir, 'avg_depth_tbl.csv'))
target_intervals <- if (file.exists(file.path(input_dir, 'target_intervals.csv'))) fread(file.path(input_dir, 'target_intervals.csv')) else data.table()

# ---- 54样本 + 深度分箱 ----
avg <- avg[sample_id %in% sel$sample_id]
avg[, depth_bin := cut(avg_depth, breaks = seq(0, 900, 100), include.lowest = TRUE, right = FALSE)]

pos <- pos[sample_id %in% sel$sample_id]
val_col <- if ('norm_smooth' %in% names(pos)) 'norm_smooth' else 'norm_mean'
pos[, norm_plot := fcoalesce(get(val_col), norm_mean)]
pos <- pos[is.finite(norm_plot)]
pos <- merge(pos, avg[, .(sample_id, avg_depth, depth_bin)], by = 'sample_id', all.x = TRUE)
if ('depth_bin.y' %in% names(pos) || 'depth_bin.x' %in% names(pos)) {
  pos[, depth_bin := fcoalesce(as.character(get('depth_bin.y')), as.character(get('depth_bin.x')))]
  pos[, c('depth_bin.x', 'depth_bin.y') := NULL]
}

# ---- 强制断线区间 ----
force_break_start <- 10019879
force_break_end <- 13139879
pos <- pos[!(pos_bin_center >= force_break_start & pos_bin_center <= force_break_end)]

# ---- 缺口分段，确保断线 ----
gap_min_bp <- 0.5e6
setorder(pos, sample_id, pos_bin_center)
pos[, bin_size_val := if ('bin_size' %in% names(pos)) suppressWarnings(first(na.omit(bin_size))) else median(diff(pos_bin_center), na.rm = TRUE), by = sample_id]
pos[, gap_multiplier_val := if ('gap_multiplier' %in% names(pos)) suppressWarnings(first(na.omit(gap_multiplier))) else 3, by = sample_id]
pos[, gap_thresh := pmax(bin_size_val * gap_multiplier_val, gap_min_bp)]
pos[, gap_flag := (pos_bin_center - shift(pos_bin_center)) > gap_thresh, by = sample_id]
pos[, segment_id := cumsum(fifelse(is.na(gap_flag), FALSE, gap_flag)) + 1L, by = sample_id]
pos[, group_id := paste(sample_id, segment_id, sep = '__')]

# 深度分组排序：低深度先画，高深度后画（高深度在上层）
pos[, depth_low := readr::parse_number(str_extract(as.character(depth_bin), '^\\[[^,]+'))]
depth_levels <- pos[!is.na(depth_low), .(depth_low = min(depth_low)), by = depth_bin][order(depth_low)]$depth_bin
pos[, depth_bin := factor(depth_bin, levels = depth_levels)]
setorder(pos, depth_low, sample_id, pos_bin_center)

# 显式控制组绘制顺序：低深度组先绘制，高深度组后绘制（位于上层）
draw_order <- pos[order(depth_low, sample_id, segment_id), unique(group_id)]
pos[, group_id := factor(group_id, levels = draw_order)]

# ---- 图B：折线图（tidyplots） ----
p_line <- tidyplot(pos, x = pos_bin_center, y = norm_plot, color = depth_bin, group = group_id) |>
  add_line(linewidth = 0.42, alpha = 0.9) |>
  adjust_x_axis(
    breaks = seq(0, 30e6, by = 5e6),
    labels = scales::label_number(scale = 1e-6, accuracy = 1)
  ) |>
  adjust_x_axis_title('Position (Mb)') |>
  adjust_y_axis_title('Normalized Coverage') |>
  adjust_legend_title('Depth Bin (100x)') |>
  theme_tidyplot(fontsize = 10) |>
  adjust_size(width = 2.6, height = 0.92, unit = 'null')

# 单层地毯图
if (nrow(target_intervals) > 0) {
  target_rug <- unique(rbind(
    target_intervals[, .(x = start)],
    target_intervals[, .(x = end)]
  ))
  p_line <- p_line |>
    add(
      ggplot2::geom_rug(
        data = target_rug,
        mapping = ggplot2::aes(x = x),
        inherit.aes = FALSE,
        sides = 'b',
        alpha = 0.75,
        color = '#d55e00',
        linewidth = 0.22
      )
    )
}

# ---- 图A：环形图（tidyplots） ----
wide <- dcast(pos[, .(sample_id, pos_bin_center, norm_mean)], pos_bin_center ~ sample_id, value.var = 'norm_mean')
mat <- as.matrix(wide[, -1])
cor_mat <- cor(mat, use = 'pairwise.complete.obs', method = 'pearson')
r_vals <- cor_mat[upper.tri(cor_mat)]

donut_df <- data.table(r = r_vals)[, .(
  corr_band = fifelse(r >= 0.90, '>=0.90',
               fifelse(r >= 0.80, '0.80-0.90',
               fifelse(r >= 0.70, '0.70-0.80', '<0.70')))
)][, .N, by = corr_band]
donut_df[, proportion := N / sum(N)]

donut_df[, corr_band := factor(corr_band, levels = c('>=0.90', '0.80-0.90', '0.70-0.80', '<0.70'))]

p_donut <- donut_df |>
  tidyplot(y = proportion, color = corr_band) |>
  add_donut() |>
  adjust_legend_position('right') |>
  remove_x_axis() |>
  remove_y_axis() |>
  remove_x_axis_title() |>
  remove_y_axis_title() |>
  theme_tidyplot(fontsize = 10) |>
  adjust_size(width = 1.2, height = 0.92, unit = 'null')

# ---- 拼图（A=donut, B=line） ----
p_all <- p_donut + p_line +
  plot_layout(widths = c(1.2, 2.6)) +
  plot_annotation(tag_levels = 'A')

# 导出
pdf_out <- file.path(out_dir, 'reproducibility_line_donut_54samples.pdf')
png_out <- file.path(out_dir, 'reproducibility_line_donut_54samples.png')

ggsave(pdf_out, p_all, width = 13.5, height = 5.6)
ggsave(png_out, p_all, width = 13.5, height = 5.6, dpi = 300)

# summary输出
sum_df <- data.table(
  corr_band = c('>=0.90', '0.80-0.90', '0.70-0.80', '<0.70'),
  proportion = c(mean(r_vals >= 0.90), mean(r_vals >= 0.80 & r_vals < 0.90), mean(r_vals >= 0.70 & r_vals < 0.80), mean(r_vals < 0.70))
)
fwrite(sum_df, file.path(out_dir, 'reproducibility_donut_54samples_summary.csv'))

message('Done: combined tidyplots donut(A) + line(B) generated.')

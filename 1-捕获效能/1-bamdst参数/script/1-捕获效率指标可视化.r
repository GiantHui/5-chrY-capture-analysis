library(tidyverse)  # 数据处理
library(tidyplots)  # 可视化
library(patchwork)  # 拼图
library(ggthemes)  # 主题

# 设定工作区
setwd("/mnt/d/捕获体系/2-捕获效能/2-bamdst参数/script")

# 输入与输出路径（统一管理）
input_path <- "/mnt/d/捕获体系/2-捕获效能/0-深度原始数据/7.4M/7038_coverage_report.csv"
chrom_path <- "/mnt/d/捕获体系/2-捕获效能/0-深度原始数据/7.4M/7038_chromosomes_report.csv"

output_data <- "../output/捕获效率指标.csv"
output_summary <- "../output/捕获效率指标_均值中位数.csv"
output_plot <- "../output/捕获效率指标_拼图.pdf"
output_md <- "../output/捕获效率指标_图形解读.md"

# 需要提取的指标
cols <- c(
  "ID",
  # 上靶率（reads/data）
  "[Target] Fraction of Target Reads in all reads",
  "[Target] Fraction of Target Reads in mapped reads",
  "[Target] Fraction of Target Data in all data",
  "[Target] Fraction of Target Data in mapped data",
  # 覆盖与深度
  "[Target] Average depth",
  "[Target] Average depth(rmdup)",
  "[Target] Coverage (>0x)",
  "[Target] Coverage (>=4x)",
  "[Target] Coverage (>=10x)",
  "[Target] Coverage (>=30x)",
  "[Target] Coverage (>=100x)",
  "[Target] Fraction Region covered >= 4x",
  "[Target] Fraction Region covered >= 10x",
  "[Target] Fraction Region covered >= 30x",
  "[Target] Fraction Region covered >= 100x",
  # flank 相关（特异性）
  "[flank] Average depth",
  "[flank] Fraction of flank Reads in all reads",
  "[flank] Fraction of flank Reads in mapped reads",
  "[flank] Fraction of flank Data in all data",
  "[flank] Fraction of flank Data in mapped data"
)

# 读取并提取
raw <- read_csv(input_path, show_col_types = FALSE)
missing_cols <- setdiff(cols, names(raw))
if (length(missing_cols) > 0) {
  stop("Missing columns: ", paste(missing_cols, collapse = ", "))
}

df <- raw |>
  select(all_of(cols)) |>
  # 去除百分号并转为数值，统一为数值型
  mutate(across(-ID, ~ parse_number(as.character(.x))))


# 读取染色体报告并提取 Coverage%
chrom_raw <- read_csv(chrom_path, show_col_types = FALSE)
chrom_cov <- chrom_raw |>
  transmute(
    ID = .data[[names(chrom_raw)[1]]],
    ChromosomeCoverage = parse_number(as.character(.data[[names(chrom_raw)[6]]]))
  )

# 合并 Coverage% 到主表
df <- df |>
  left_join(chrom_cov, by = "ID")

# 保存提取后的指标表
write_csv(df, output_data)

# 统计每个指标的均值与中位数
summary_stats <- df |>
  pivot_longer(-ID, names_to = "metric", values_to = "value") |>
  group_by(metric) |>
  summarise(
    mean = mean(value, na.rm = TRUE),
    median = median(value, na.rm = TRUE),
    p25 = quantile(value, 0.25, na.rm = TRUE),
    p75 = quantile(value, 0.75, na.rm = TRUE),
    min = min(value, na.rm = TRUE),
    max = max(value, na.rm = TRUE),
    .groups = "drop"
  )

write_csv(summary_stats, output_summary)

# ---- 1) 特异性（base 层面）：tidyplot 分面直方图（颜色区分 + 保留图注） ----
base_spec_map <- c(
  "[flank] Fraction of flank Data in mapped data" = "FlankData/MappedData (Upper)",
  "[flank] Fraction of flank Data in all data" = "FlankData/AllData (Lower)",
  "[Target] Fraction of Target Data in mapped data" = "TargetData/MappedData (Strict)"
)

base_spec_long <- df |>
  select(ID, all_of(names(base_spec_map))) |>
  pivot_longer(-ID, names_to = "metric", values_to = "value") |>
  mutate(metric = factor(metric, levels = names(base_spec_map), labels = unname(base_spec_map)))

# 使用 tidyplot 逐项绘图（每个指标单独颜色），再拼图
base_xlim <- range(base_spec_long$value, na.rm = TRUE)
base_levels <- levels(base_spec_long$metric)
base_palette <- as.character(colors_discrete_metro)

p_base_list <- lapply(seq_along(base_levels), function(i) {
  m <- base_levels[i]
  col_i <- base_palette[(i - 1) %% length(base_palette) + 1]
  base_spec_long |>
    filter(metric == m) |>
    tidyplot(x = value) |>
    add_histogram(bins = 40, alpha = 0.6) |>
    adjust_x_axis(title = "Fraction (%)", limits = base_xlim) |>
    adjust_y_axis_title("Sample Count") |>
    adjust_colors(new_colors = col_i) |>
    theme_tidyplot()
})

p_base_spec <- wrap_plots(
  list(
    p_base_list[[1]], plot_spacer(),
    p_base_list[[2]], plot_spacer(),
    p_base_list[[3]]
  ),
  ncol = 1
) + plot_annotation(title = "Specificity (Base Level)")

# ---- 2) 特异性（reads 层面）：tidyplot 分面直方图（颜色区分 + 保留图注） ----
reads_spec_map <- c(
  "[flank] Fraction of flank Reads in mapped reads" = "FlankReads/MappedReads (Upper)",
  "[flank] Fraction of flank Reads in all reads" = "FlankReads/AllReads (Lower)",
  "[Target] Fraction of Target Reads in mapped reads" = "TargetReads/MappedReads (Strict)"
)

reads_spec_long <- df |>
  select(ID, all_of(names(reads_spec_map))) |>
  pivot_longer(-ID, names_to = "metric", values_to = "value") |>
  mutate(metric = factor(metric, levels = names(reads_spec_map), labels = unname(reads_spec_map)))

# 使用 tidyplot 逐项绘图（每个指标单独颜色），再拼图（不加图例面板）
reads_xlim <- range(reads_spec_long$value, na.rm = TRUE)
reads_levels <- levels(reads_spec_long$metric)
reads_palette <- as.character(colors_discrete_okabeito)

p_reads_list <- lapply(seq_along(reads_levels), function(i) {
  m <- reads_levels[i]
  col_i <- reads_palette[(i - 1) %% length(reads_palette) + 1]
  reads_spec_long |>
    filter(metric == m) |>
    tidyplot(x = value) |>
    add_histogram(bins = 40, alpha = 0.6) |>
    adjust_x_axis(title = "Fraction (%)", limits = reads_xlim) |>
    adjust_y_axis_title("Sample Count") |>
    adjust_colors(new_colors = col_i) |>
    theme_tidyplot()
})

p_reads_spec <- wrap_plots(
  list(
    p_reads_list[[1]], plot_spacer(),
    p_reads_list[[2]], plot_spacer(),
    p_reads_list[[3]]
  ),
  ncol = 1
) + plot_annotation(title = "Specificity (Reads Level)")

# ---- 3) 深度分布（Target / Flank）----
# 目标区深度：直方图
p_depth_target <- df |>
  tidyplot(x = `[Target] Average depth`) |>
  add_histogram(bins = 40, alpha = 0.65) |>  # 直方图显示分布
  adjust_x_axis_title("[Target] Average depth") |>
  adjust_y_axis_title("Sample Count") |>
  add_title("Target Depth Distribution") |>
  adjust_colors(new_colors = colors_continuous_viridis) |>
  theme_tidyplot()

# flank 平均深度：直方图
p_depth_flank <- df |>
  tidyplot(x = `[flank] Average depth`) |>
  add_histogram(bins = 40, alpha = 0.65) |>
  adjust_x_axis_title("Flank Avg Depth") |>
  adjust_y_axis_title("Sample Count") |>
  add_title("Flank Depth Distribution") |>
  adjust_colors(new_colors = colors_continuous_plasma) |>
  theme_tidyplot()

# ---- 3b) 染色体覆盖率分布（Coverage% 核密度）----
cov_vals <- df |>
  filter(!is.na(ChromosomeCoverage)) |>
  pull(ChromosomeCoverage)

# 若为百分数(0-100)则转换为0-1
cov_vals <- if (median(cov_vals, na.rm = TRUE) > 1) cov_vals / 100 else cov_vals

cov_density <- density(cov_vals, from = 0.96, to = 1.00, n = 200)
cov_df <- tibble(coverage = cov_density$x, density = cov_density$y)
rug_df <- tibble(coverage = cov_vals)
dens_max <- max(cov_df$density, na.rm = TRUE)
y_lower <- -0.05 * dens_max
rug_df <- tibble(coverage = cov_vals)

p_chrom_cov <- cov_df |>
  tidyplot(x = coverage, y = density) |>
  add_area(alpha = 0.4) |>
  add_line() |>  # 密度曲线
  add(ggplot2::geom_rug(
    data = rug_df,
    mapping = ggplot2::aes(x = coverage),
    sides = "b",
    alpha = 0.35,
    color = "gray30",
    inherit.aes = FALSE
  )) |>
  adjust_x_axis(
    title = "Chromosome Coverage",
    limits = c(0.96, 1.00),
    breaks = seq(0.96, 1.00, by = 0.02)
  ) |>
  adjust_y_axis(title = "Density", limits = c(y_lower, dens_max * 1.05)) |>
  add_title("Chromosome Coverage Distribution") |>
  adjust_colors(new_colors = colors_continuous_viridis) |>
  theme_tidyplot()

# ---- 4) 目标区覆盖（Coverage 阈值）----
coverage_map <- c(
  "[Target] Coverage (>0x)" = ">0x",
  "[Target] Coverage (>=4x)" = ">=4x",
  "[Target] Coverage (>=10x)" = ">=10x",
  "[Target] Coverage (>=30x)" = ">=30x",
  "[Target] Coverage (>=100x)" = ">=100x"
)

coverage_long <- df |>
  select(all_of(names(coverage_map))) |>
  pivot_longer(everything(), names_to = "metric", values_to = "value") |>
  mutate(metric = factor(metric, levels = names(coverage_map), labels = unname(coverage_map)))

coverage_ecdf <- coverage_long |>
  group_by(metric) |>
  arrange(value, .by_group = TRUE) |>
  mutate(ecdf = row_number() / n()) |>
  ungroup()

p_ref <- c(0.25, 0.5, 0.75, 0.9)
coverage_q <- coverage_long |>
  group_by(metric) |>
  summarise(
    x = list(quantile(value, probs = p_ref, na.rm = TRUE)),
    .groups = "drop"
  ) |>
  unnest_wider(x, names_sep = "_") |>
  pivot_longer(
    cols = starts_with("x_"),
    names_to = "p",
    values_to = "x"
  ) |>
  mutate(
    y = case_when(
      p == "x_1" ~ 0.25,
      p == "x_2" ~ 0.5,
      p == "x_3" ~ 0.75,
      TRUE ~ 0.9
    ),
    label = sprintf("%.2f", x),
    metric_index = as.numeric(factor(metric)),
    y_label = pmin(pmax(y + (metric_index - 2) * 0.012, 0.02), 0.98)
  )

p_coverage <- coverage_ecdf |>
  tidyplot(x = value, y = ecdf, color = metric) |>
  add_line() |>
  add_reference_lines(y = 0.25) |> # ECDF 展示分布
  add_reference_lines(y = 0.5) |>
  add_reference_lines(y = 0.75) |>
  add_reference_lines(y = 0.9) |>
  adjust_x_axis_title("Coverage (%)") |>
  adjust_y_axis_title("ECDF") |>
  add_title("Target Coverage Distribution") |>
  adjust_colors(new_colors = colors_discrete_friendly) |>
  theme_tidyplot()

for (i in seq_len(nrow(coverage_q))) {
  p_coverage <- p_coverage |>
    add_annotation_text(
      text = coverage_q$label[i],
      x = coverage_q$x[i],
      y = coverage_q$y_label[i],
      fontsize = 6
    )
}

# ---- 5) 区域覆盖均匀性（Region covered）----
region_map <- c(
  "[Target] Fraction Region covered >= 4x" = ">=4x",
  "[Target] Fraction Region covered >= 10x" = ">=10x",
  "[Target] Fraction Region covered >= 30x" = ">=30x",
  "[Target] Fraction Region covered >= 100x" = ">=100x"
)

region_long <- df |>
  select(all_of(names(region_map))) |>
  pivot_longer(everything(), names_to = "metric", values_to = "value") |>
  mutate(metric = factor(metric, levels = names(region_map), labels = unname(region_map)))

region_ecdf <- region_long |>
  group_by(metric) |>
  arrange(value, .by_group = TRUE) |>
  mutate(ecdf = row_number() / n()) |>
  ungroup()

region_q <- region_long |>
  group_by(metric) |>
  summarise(
    x = list(quantile(value, probs = p_ref, na.rm = TRUE)),
    .groups = "drop"
  ) |>
  unnest_wider(x, names_sep = "_") |>
  pivot_longer(
    cols = starts_with("x_"),
    names_to = "p",
    values_to = "x"
  ) |>
  mutate(
    y = case_when(
      p == "x_1" ~ 0.25,
      p == "x_2" ~ 0.5,
      p == "x_3" ~ 0.75,
      TRUE ~ 0.9
    ),
    label = sprintf("%.2f", x),
    metric_index = as.numeric(factor(metric)),
    y_label = pmin(pmax(y + (metric_index - 2) * 0.012, 0.02), 0.98)
  )

p_region <- region_ecdf |>
  tidyplot(x = value, y = ecdf, color = metric) |>
  add_line() |> 
  add_reference_lines(y = 0.25) |>
  add_reference_lines(y = 0.5) |>
  add_reference_lines(y = 0.75) |>
  add_reference_lines(y = 0.9) |>
  adjust_x_axis_title("Fraction (%)") |>
  adjust_y_axis_title("ECDF") |>
  add_title("Region Coverage Distribution") |>
  adjust_colors(new_colors = colors_discrete_seaside) |>
  theme_tidyplot()

for (i in seq_len(nrow(region_q))) {
  p_region <- p_region |>
    add_annotation_text(
      text = region_q$label[i],
      x = region_q$x[i],
      y = region_q$y_label[i],
      fontsize = 6
    )
}

# ---- 拼图与输出 ----
#! 使用patchwork v1.3.0组合tidyplot对象需要使用如下代码
patchwork::wrap_plots(p_base_spec, p_reads_spec, p_depth_target, p_depth_flank, p_chrom_cov, p_coverage, p_region) + 
  patchwork::plot_layout(ncol = 2) +
    patchwork::plot_annotation(tag_levels = "A") -> p_all

# 保存图像
ggsave(output_plot, p_all, width = 18, height = 22)

# ---- 图形解读说明 ----
fmt_table <- function(df) {
  lines <- c("| Metric | y=0.25 (x) | y=0.5 (x) | y=0.75 (x) | y=0.9 (x) |",
             "|---|---:|---:|---:|---:|")
  for (i in seq_len(nrow(df))) {
    r <- df[i,]
    lines <- c(lines, sprintf("| %s | %.2f | %.2f | %.2f | %.2f |",
                              r$metric, r$`x_1`, r$`x_2`, r$`x_3`, r$`x_4`))
  }
  lines
}

coverage_table <- coverage_q |>
  select(metric, p, x) |>
  pivot_wider(names_from = p, values_from = x) |>
  rename_with(~ sub("%", "", .x), starts_with("x_")) |>
  rename(x_1 = x_25, x_2 = x_50, x_3 = x_75, x_4 = x_90) |>
  mutate(metric = as.character(metric))

region_table <- region_q |>
  select(metric, p, x) |>
  pivot_wider(names_from = p, values_from = x) |>
  rename_with(~ sub("%", "", .x), starts_with("x_")) |>
  rename(x_1 = x_25, x_2 = x_50, x_3 = x_75, x_4 = x_90) |>
  mutate(metric = as.character(metric))

get_stats_lines <- function(keys) {
  summary_stats |>
    filter(metric %in% keys) |>
    mutate(line = sprintf("- %s：中位数 %.2f，IQR %.2f–%.2f，范围 %.2f–%.2f。",
                          metric, median, p25, p75, min, max)) |>
    pull(line)
}

md_lines <- c(
  "# 捕获效率指标图形解读",
  "",
  "本文件用于解释各图形的含义、坐标轴信息与结果解读。",
  "",
  "## A Specificity (Base Level)",
  "- 图形类型：直方图（Histogram）。",
  "- x 轴：Fraction (%)，样本在 base 层面的特异性比例。",
  "- y 轴：Sample Count，样本数量。",
  "- 说明：不同分面对应不同指标，分布集中表示样本一致性较高。",
  get_stats_lines(names(base_spec_map)),
  "",
  "## B Specificity (Reads Level)",
  "- 图形类型：直方图（Histogram）。",
  "- x 轴：Fraction (%)，样本在 reads 层面的特异性比例。",
  "- y 轴：Sample Count，样本数量。",
  "- 说明：与 A 类似，用于比较 reads 层面的特异性分布。",
  get_stats_lines(names(reads_spec_map)),
  "",
  "## C Target Depth Distribution",
  "- 图形类型：直方图（Histogram）。",
  "- x 轴：[Target] Average depth。",
  "- y 轴：Sample Count。",
  "- 说明：样本深度分布，峰值位置反映总体深度水平。",
  get_stats_lines(c("[Target] Average depth")),
  "",
  "## D Flank Depth Distribution",
  "- 图形类型：直方图（Histogram）。",
  "- x 轴：[flank] Average depth。",
  "- y 轴：Sample Count。",
  "- 说明：侧翼区域深度分布，用于比较与目标区的深度差异。",
  get_stats_lines(c("[flank] Average depth")),
  "",
  "## E Chromosome Coverage Distribution",
  "- 图形类型：核密度图（Kernel Density Plot）+ 地毯图（Rug）。",
  "- x 轴：Chromosome Coverage（0.96–1.00）。",
  "- y 轴：Density。",
  "- 说明：密度峰位置反映大多数样本覆盖率区间，地毯图显示样本在 x 轴的分布位置。",
  get_stats_lines(c("ChromosomeCoverage")),
  "",
  "## F Target Coverage Distribution",
  "- 图形类型：经验累积分布函数（Empirical Cumulative Distribution Function）。",
  "- x 轴：Coverage (%)。",
  "- y 轴：ECDF（累计比例）。",
  "- 说明：曲线越靠右说明覆盖率越高；横向虚线表示指定 y 值时的覆盖率水平。",
  "- ECDF 参考线：",
  fmt_table(coverage_table),
  "",
  "## G Region Coverage Distribution",
  "- 图形类型：经验累积分布函数（Empirical Cumulative Distribution Function）。",
  "- x 轴：Fraction (%)。",
  "- y 轴：ECDF（累计比例）。",
  "- 说明：用于评估覆盖均匀性，曲线陡峭说明样本分布更集中。",
  "- ECDF 参考线：",
  fmt_table(region_table),
  ""
)

write_lines(md_lines, output_md)

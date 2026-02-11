library(tidyverse)
library(tidyplots)
library(patchwork)

# 设定工作区
setwd("/mnt/d/捕获体系/2-yleaf/script")

# 创建输出目录
output_dir <- "../output"
if (!dir.exists(output_dir)) {
  dir.create(output_dir, recursive = TRUE)
}

# 读取数据
df <- read_tsv("../data/all_merge.tsv")

# 统计学检验部分
# 2. Spearman 秩相关检验
spearman_test <- cor.test(df$Valid_markers, df$Total_reads, method = "spearman")

# 3. Pearson 相关性检验（对数变换后）
pearson_test <- cor.test(log10(df$Valid_markers), log10(df$Total_reads), method = "pearson")

# 4. 线性回归（log-log）
fit <- lm(log10(Valid_markers) ~ log10(Total_reads), data = df)
fit_summary <- summary(fit)
r_squared <- fit_summary$r.squared

# 保存统计结果
statistical_results <- list(
  "Spearman_correlation" = list(
    "rho" = spearman_test$estimate,
    "p_value" = spearman_test$p.value,
    "method" = spearman_test$method
  ),
  "Pearson_correlation_log" = list(
    "correlation" = pearson_test$estimate,
    "p_value" = pearson_test$p.value,
    "method" = pearson_test$method
  ),
  "Linear_regression_log" = list(
    "R_squared" = r_squared,
    "coefficients" = fit$coefficients,
    "p_value" = fit_summary$coefficients[2,4]
  )
)

# 创建整齐的统计结果表格
stats_table <- tibble(
  Test = c("Spearman Correlation", "Pearson Correlation (log)", "Linear Regression (log)"),
  Statistic = c(
    paste0("rho = ", round(spearman_test$estimate, 4)),
    paste0("r = ", round(pearson_test$estimate, 4)),
    paste0("R² = ", round(r_squared, 4))
  ),
  P_value = c(
    format.pval(spearman_test$p.value),
    format.pval(pearson_test$p.value),
    format.pval(fit_summary$coefficients[2,4])
  ),
  Method = c(
    spearman_test$method,
    pearson_test$method,
    "Linear Model (log-log)"
  )
)

# 保存统计结果到TSV文件
write_tsv(stats_table, file.path(output_dir, "statistical_results.tsv"))

# 保存详细统计结果到文本文件
writeLines(capture.output(print(statistical_results)), 
           file.path(output_dir, "statistical_results_detailed.txt"))

# 打印统计结果
cat("=== 统计学检验结果 ===\n")
cat("Spearman相关系数: rho =", round(spearman_test$estimate, 4), 
    ", p =", format.pval(spearman_test$p.value), "\n")
cat("Pearson相关系数(log): r =", round(pearson_test$estimate, 4), 
    ", p =", format.pval(pearson_test$p.value), "\n")
cat("线性回归R²(log): R² =", round(r_squared, 4), 
    ", p =", format.pval(fit_summary$coefficients[2,4]), "\n\n")

# 绘图部分
# 1. Total_reads 分布直方图
p1 <- df |>
  tidyplot(x = Total_reads) |>
  add_histogram(bins = 50, fill = colors_discrete_friendly[1]) |>
  add_title("Total reads Distribution") |>
  adjust_x_axis_title("Total reads") |>
  adjust_y_axis_title("Count") |>
  theme_tidyplot()

# 2. Valid_markers 分布直方图  
p2 <- df |>
  tidyplot(x = Valid_markers) |>
  add_histogram(bins = 50, fill = colors_discrete_friendly[2]) |>
  add_title("Valid markers Distribution") |>
  adjust_x_axis_title("Valid markers") |>
  adjust_y_axis_title("Count") |>
  theme_tidyplot()

# 3. 散点图（原始坐标）
p3 <- df |>
  tidyplot(x = Total_reads, y = Valid_markers) |>
  add_data_points(alpha = 0.6, size = 0.8, color = colors_discrete_friendly[3]) |>
  add_title("Valid markers vs Total reads") |>
  adjust_x_axis_title("Total reads") |>
  adjust_y_axis_title("Valid markers") |>
  theme_tidyplot()

# 4. 散点图（对数坐标）+ 回归线
p4 <- df |>
  tidyplot(x = Total_reads, y = Valid_markers) |>
  add_data_points(alpha = 0.6, size = 0.8, color = colors_discrete_friendly[4]) |>
  add_curve_fit(method = "lm", formula = y ~ x, color = colors_discrete_friendly[5], size = 1) |>
  adjust_x_axis(trans = "log10") |>
  adjust_y_axis(trans = "log10") |>
  add_title(paste0("Valid markers vs Total reads (log-log)\nR² = ", 
                   round(r_squared, 4), ", ρ = ", round(spearman_test$estimate, 4))) |>
  adjust_x_axis_title("Total reads (log10)") |>
  adjust_y_axis_title("Valid markers (log10)") |>
  theme_tidyplot()

# 先保存各个单独的图片（修复尺寸问题）
p1 |> save_plot(file.path(output_dir, "total_reads_histogram.png"), 
                dpi = 300)
p2 |> save_plot(file.path(output_dir, "valid_markers_histogram.png"), 
                dpi = 300)
p3 |> save_plot(file.path(output_dir, "scatter_plot_original.png"), 
                dpi = 300)
p4 |> save_plot(file.path(output_dir, "scatter_plot_log_regression.png"), 
                dpi = 300)

# 使用patchwork拼接图片
#! 使用patchwork v1.3.0组合tidyplot对象需要使用如下代码
patchwork::wrap_plots(p1, p2, p3, p4) + 
  patchwork::plot_layout(ncol = 2) +
  patchwork::plot_annotation(tag_levels = "A") -> p_all

# 保存为PDF格式
pdf(file.path(output_dir, "combined_analysis.pdf"), width = 12, height = 10)
print(p_all)
dev.off()

# 保存为PNG格式（修夏尺寸问题）
p_all |> save_plot(file.path(output_dir, "combined_analysis.png"), 
                   width = 16, height = 12, dpi = 300)

cat("=== 分析完成 ===\n")
cat("所有图片和统计结果已保存到:", output_dir, "\n")
cat("生成的文件:\n")
cat("- combined_analysis.pdf (主要拼接图 - PDF格式)\n")
cat("- combined_analysis.png (主要拼接图 - PNG格式)\n")
cat("- statistical_results.tsv (统计结果表格 - TSV格式)\n")
cat("- statistical_results_detailed.txt (详细统计结果)\n")
cat("- total_reads_histogram.png (单独图片)\n")
cat("- valid_markers_histogram.png (单独图片)\n")
cat("- scatter_plot_original.png (单独图片)\n")
cat("- scatter_plot_log_regression.png (单独图片)\n")

# 显示统计结果表格
cat("\n=== 统计结果表格 ===\n")
print(stats_table)
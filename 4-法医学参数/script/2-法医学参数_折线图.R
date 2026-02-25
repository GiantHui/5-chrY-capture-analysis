library(tidyverse)
library(tidyplots)
library(patchwork)

base_dir <- '/mnt/d/捕获体系/6-法医学参数'
out_dir <- file.path(base_dir, 'output')
if (!dir.exists(out_dir)) dir.create(out_dir, recursive = TRUE)

haplo_file <- file.path(out_dir, '单倍群_forensic_params_by_group.csv')
haptype_file <- file.path(out_dir, '单倍型_forensic_params_by_group.csv')

read_ok_long <- function(path, type_label) {
  readr::read_csv(path, show_col_types = FALSE) |>
    dplyr::filter(Status == 'OK') |>
    dplyr::mutate(
      HMP = as.numeric(HMP),
      HD = as.numeric(HD),
      DC = as.numeric(DC),
      N = as.numeric(N),
      k = as.numeric(k),
      Type = type_label
    ) |>
    dplyr::select(Group, Type, HMP, HD, DC, N, k) |>
    tidyr::pivot_longer(cols = c(HMP, HD, DC), names_to = 'Metric', values_to = 'Value')
}

plot_one <- function(df_long, title_txt) {
  # 群体按HMP排序（低到高），保证三条线在同一坐标内可直接比较
  group_order <- df_long |>
    dplyr::filter(Metric == 'HMP') |>
    dplyr::distinct(Group, Value) |>
    dplyr::arrange(Value, Group) |>
    dplyr::pull(Group)

  df_long <- df_long |>
    dplyr::mutate(Group = factor(Group, levels = group_order))

  df_long |>
    tidyplot(x = Group, y = Value, color = Metric, dodge_width = 0) |>
    add_mean_line() |>
    add_mean_dot(size = 1.6) |>
    add_sem_errorbar(width = 0.15) |>
    add(ggplot2::scale_color_manual(values = c(HMP = '#1f77b4', HD = '#2ca02c', DC = '#ff7f0e'))) |>
    add(ggplot2::theme(
      axis.text.x = ggplot2::element_text(angle = 90, hjust = 1, vjust = 0.5, size = 7, margin = ggplot2::margin(t = 2)),
      plot.margin = ggplot2::margin(t = 8, r = 12, b = 30, l = 12)
    )) |>
    adjust_size(width = 100, height = 50) |>
    adjust_x_axis_title('Group') |>
    adjust_y_axis_title('Value') |>
    add_title(title_txt) |>
    theme_tidyplot()
}

haptype_long <- read_ok_long(haptype_file, 'Haplotype')
haplo_long <- read_ok_long(haplo_file, 'Haplogroup')

# 标记重庆汉用于后续结果复核
cq_summary <- bind_rows(haptype_long, haplo_long) |>
  dplyr::filter(Group == 'Han_Chongqing') |>
  dplyr::arrange(Type, Metric)
readr::write_csv(cq_summary, file.path(out_dir, 'forensic_lineplot_cq_values.csv'))

pA <- plot_one(haptype_long, 'A  Haplotype-level Forensic Parameters (OK groups)')
pB <- plot_one(haplo_long, 'B  Haplogroup-level Forensic Parameters (OK groups)')

p_all <- pA / pB + patchwork::plot_layout(heights = c(1, 1))

for (ext in c('png', 'pdf')) {
  ggsave(file.path(out_dir, paste0('forensic_tidyplots_line_haplotype.', ext)), pA,
         width = 20, height = 8.5, dpi = 300)
  ggsave(file.path(out_dir, paste0('forensic_tidyplots_line_haplogroup.', ext)), pB,
         width = 20, height = 8.5, dpi = 300)
  ggsave(file.path(out_dir, paste0('forensic_tidyplots_line_combined.', ext)), p_all,
         width = 20, height = 15.5, dpi = 300)
}

readr::write_csv(bind_rows(haptype_long, haplo_long), file.path(out_dir, 'forensic_tidyplots_line_input_OK.csv'))
message('Done: tidyplots line figures generated.')

library(tidyverse)
library(tidyplots)

# 设置工作目录
setwd("/mnt/d/捕获体系/2-ISOGG/script")

df <- read_csv("../output/位点去重/ISOGG_in7.4M.csv")


# 基于df进行统计，统计每个Macrohaplogroup下InY7.4M为Yes和No的数量
df |>
  select(`Macrohaplogroup`, InY7.4M) |>
  group_by(`Macrohaplogroup`) |>
  summarise(
    Yes_Count = sum(InY7.4M == "Yes", na.rm = TRUE),
    No_Count  = sum(InY7.4M == "No",  na.rm = TRUE)
  ) |>
  ungroup() -> df_summary
# 将df_summary从宽数据转为长数据
df_summary |>
    pivot_longer(
        cols = c(Yes_Count, No_Count),
        names_to = "Haplogroup_Status",
        values_to = "Count" 
    ) -> df_summary_long

df_summary_long
# 绘制水平堆积条形图，显示每个Macrohaplogroup下InY7.4M为Yes和No的数量
df_summary_long |>
    tidyplot(
        x = Count,
        y = Macrohaplogroup,
        color = Haplogroup_Status,
        label = Count
    ) |>
    add_barstack_absolute(reverse = TRUE) |>
    add_data_labels() -> p1
p1

# 对df进行另一个统计,先基于每个Macrohaplogroup，对其Haplogroup去重，得到唯一的Haplogroup列，如A宏单倍群下是A0000，A00；针对该Haplogroup，如A0000，只要对应InY7.4M有一个Yes时，则该A0000计为Yes，当该A0000所有均为No时，计为No。
df |>
  select(Macrohaplogroup, Haplogroup, InY7.4M) |>
  distinct() |>
  group_by(Macrohaplogroup, Haplogroup) |>
  summarise(
    Haplogroup_Status = ifelse(any(InY7.4M == "Yes"), "Yes", "No")
  ) |>
  ungroup() |>
  group_by(Macrohaplogroup) |>
  summarise(
    Yes_Haplogroups = sum(Haplogroup_Status == "Yes"),
    No_Haplogroups  = sum(Haplogroup_Status == "No")
  ) |>
  ungroup() -> df_summary_by_haplogroup

df_summary_by_haplogroup

# 将df_summary_by_haplogroup从宽数据转为长数据
df_summary_by_haplogroup |>
    pivot_longer(
        cols = c(Yes_Haplogroups, No_Haplogroups),
        names_to = "Haplogroup_Status",
        values_to = "Count" 
    ) -> df_summary_by_haplogroup_long

df_summary_by_haplogroup_long

# 绘制柱状图，显示每个Macrohaplogroup下唯一Haplogroup中InY8M为Yes和No的数量
df_summary_by_haplogroup_long |>
    tidyplot(
        x = Count,
        y = Macrohaplogroup,
        color = Haplogroup_Status,
        label = Count
    ) |>
    add_barstack_absolute() |>
    add_data_labels() -> p2
p2


# patchwork::wrap_plots(p1, p2) + 
#   patchwork::plot_layout(ncol = 2) +
#     patchwork::plot_annotation(tag_levels = "A") -> p_all

# p_all

# ggsave(p_all, 
#         filename = "../output/7.4M/p_all.pdf", 
#         width = 10, 
#         height = 5)



# 读取第二个数据表df2
df2 <- read_csv("../output/位点去重/ISOGG_inyhseq.csv")

# 基于df2进行统计，统计每个Macrohaplogroup下Y_YHSeq_Marker为Yes和No的数量
df2 |>
  select(`Macrohaplogroup`, Y_YHSeq_Marker) |>
  group_by(`Macrohaplogroup`) |>
  summarise(
    Yes_Count = sum(Y_YHSeq_Marker == "Yes", na.rm = TRUE),
    No_Count  = sum(Y_YHSeq_Marker == "No",  na.rm = TRUE)
  ) |>
  ungroup() -> df2_summary

# 将df2_summary从宽数据转为长数据
df2_summary |>
    pivot_longer(
        cols = c(Yes_Count, No_Count),
        names_to = "Haplogroup_Status",
        values_to = "Count" 
    ) -> df2_summary_long
# 绘制柱状图，显示每个Macrohaplogroup下Y_YHSeq_Marker为Yes和No的数量
df2_summary_long |>
    tidyplot(
        x = Count,
        y = Macrohaplogroup,
        color = Haplogroup_Status,
        label = Count
    ) |>
    add_barstack_absolute() |>
    add_data_labels() -> p3

p3

# 对df2进行另一个统计,先基于每个Macrohaplogroup，对其Haplogroup去重，得到唯一的Haplogroup列，如A宏单倍群下是A0000，A00；针对该Haplogroup，如A0000，只要对应Y_YHSeq_Marker有一个Yes时，则该A0000计为Yes，当该A0000所有均为No时，计为No。

df2 |>
  select(`Macrohaplogroup`, Haplogroup, Y_YHSeq_Marker) |>
  distinct() |>
  group_by(`Macrohaplogroup`, Haplogroup) |>
  summarise(
    Haplogroup_Status = ifelse(any(Y_YHSeq_Marker == "Yes"), "Yes", "No")
  ) |>
  ungroup() |>
  group_by(`Macrohaplogroup`) |>
  summarise(
    Yes_Haplogroups = sum(Haplogroup_Status == "Yes"),
    No_Haplogroups  = sum(Haplogroup_Status == "No")
  ) |>
  ungroup() -> df2_summary_by_haplogroup

df2_summary_by_haplogroup

# 将df2_summary_by_haplogroup从宽数据转为长数据
df2_summary_by_haplogroup |>
    pivot_longer(
        cols = c(Yes_Haplogroups, No_Haplogroups),
        names_to = "Haplogroup_Status",
        values_to = "Count" 
    ) -> df2_summary_by_haplogroup_long

df2_summary_by_haplogroup_long

# 绘制柱状图，显示每个Macrohaplogroup下唯一Haplogroup中Y_YHSeq_Marker为Yes和No的数量
df2_summary_by_haplogroup_long |>
    tidyplot(
        x = Count,
        y = Macrohaplogroup,
        color = Haplogroup_Status,
        label = Count
    ) |>
    add_barstack_absolute() |>
    add_data_labels() -> p4
p4


#! 使用patchwork v1.3.0组合tidyplot对象需要使用如下代码
patchwork::wrap_plots(p1, p2, p3, p4) + 
  patchwork::plot_layout(ncol = 2) +
    patchwork::plot_annotation(tag_levels = "A") -> p_all
    
p_all

ggsave(p_all, 
        filename = "../output/p_all.pdf", 
        width = 10, 
        height = 5)

# 生成4个统计原始宽数据的csv文件
write_csv(df_summary, "../output/Y7.4m_Haplogroup.csv")
write_csv(df_summary_by_haplogroup, "../output/Y7.4m_subhaplogroup.csv")
write_csv(df2_summary, "../output/YHseq_Haplogroup.csv")
write_csv(df2_summary_by_haplogroup, "../output/YHseq_subhaplogroup.csv")

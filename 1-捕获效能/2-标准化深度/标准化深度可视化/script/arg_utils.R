# 简易命令行参数解析（替代 optparse）
# 用法：get_args(c("--foo", "--bar")) -> list(foo=..., bar=...)

get_args <- function(keys) {
  args <- commandArgs(trailingOnly = TRUE)
  values <- list()
  i <- 1
  while (i <= length(args)) {
    key <- args[i]
    if (startsWith(key, "--")) {
      name <- sub("^--", "", key)
      if (i + 1 <= length(args) && !startsWith(args[i + 1], "--")) {
        values[[name]] <- args[i + 1]
        i <- i + 2
      } else {
        values[[name]] <- TRUE
        i <- i + 1
      }
    } else {
      i <- i + 1
    }
  }
  for (k in keys) {
    k2 <- sub("^--", "", k)
    if (is.null(values[[k2]])) {
      stop("缺少参数: ", k)
    }
  }
  values
}

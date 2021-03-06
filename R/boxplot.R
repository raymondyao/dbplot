#' Returns a dataframe with boxplot calculations
#'
#' @description
#'
#' Uses very generic dplyr code to create boxplot calculations.
#' Because of this approach,
#' the calculations automatically run inside the database if `data` has
#' a database or sparklyr connection. The `class()` of such tables
#' in R are: tbl_sql, tbl_dbi, tbl_spark
#'
#' It currently only works with Spark, Hive, and SQL Server connections.
#'
#' Note that this function supports input tbl that already contains
#' grouping variables. This can be useful when creating faceted boxplots.
#'
#' @param data A table (tbl), can already contain additional grouping vars specified
#' @param x A discrete variable in which to group the boxplots
#' @param var A continuous variable
#' @param coef Length of the whiskers as multiple of IQR. Defaults to 1.5
#'
#' @examples
#'
#' mtcars %>%
#'   db_compute_boxplot(am, mpg)
#' @export
db_compute_boxplot <- function(data, x, var, coef = 1.5) {
  x <- enquo(x)
  check_vars <- quo_get_expr(x)
  if (length(check_vars) > 1 && expr_text(check_vars[1]) == "vars()") {
    x <- eval_tidy(x)
  } else {
    x <- quos(!!x)
  }
  var <- enquo(var)
  var <- quo_squash(var)
  res <- group_by(data, !!!x, add = TRUE)
  res <- calc_boxplot(res, var)
  res <- mutate(res,
    iqr = (upper - lower) * coef,
    min_iqr = lower - iqr,
    max_iqr = upper + iqr,
    ymax = ifelse(max_raw > max_iqr, max_iqr, max_raw),
    ymin = ifelse(min_raw < min_iqr, min_iqr, min_raw)
  )
  res <- collect(res)
  ungroup(res)
}

calc_boxplot <- function(res, var) {
  UseMethod("calc_boxplot")
}

calc_boxplot.tbl <- function(res, var) {
  summarise(
    res,
    n = n(),
    lower = quantile(!!var, 0.25),
    middle = quantile(!!var, 0.5),
    upper = quantile(!!var, 0.75),
    max_raw = max(!!var, na.rm = TRUE),
    min_raw = min(!!var, na.rm = TRUE)
  )
}

calc_boxplot.tbl_spark <- function(res, var) {
  calc_boxplot_sparklyr(res, var)
}

calc_boxplot_sparklyr <- function(res, var) {
  summarise(
    res,
    n = n(),
    lower = percentile_approx(!!var, 0.25),
    middle = percentile_approx(!!var, 0.5),
    upper = percentile_approx(!!var, 0.75),
    max_raw = max(!!var, na.rm = TRUE),
    min_raw = min(!!var, na.rm = TRUE)
  )
}

`calc_boxplot.tbl_Microsoft SQL Server` <- function(res, var) {
  calc_boxplot_mssql(res, var)
}

calc_boxplot_mssql <- function(res, var) {
  res <- mutate(
    res,
    n = n(),
    lower = quantile(!!var, 0.25),
    middle = quantile(!!var, 0.5),
    upper = quantile(!!var, 0.75),
    max_raw = max(!!var, na.rm = TRUE),
    min_raw = min(!!var, na.rm = TRUE)
  )
  # This should preserve grouping columns
  res <- select(res, n, lower, middle, upper, max_raw, min_raw)
  distinct(res)
}

#' Boxplot
#'
#' @description
#'
#' Uses very generic dplyr code to aggregate data and then `ggplot2`
#' to create the boxplot  Because of this approach,
#' the calculations automatically run inside the database if `data` has
#' a database or sparklyr connection. The `class()` of such tables
#' in R are: tbl_sql, tbl_dbi, tbl_spark
#'
#' It currently only works with Spark and Hive connections.
#'
#' @param data A table (tbl)
#' @param x A discrete variable in which to group the boxplots
#' @param var A continuous variable
#' @param coef Length of the whiskers as multiple of IQR. Defaults to 1.5
#'
#' @seealso
#' \code{\link{dbplot_bar}}, \code{\link{dbplot_line}} ,
#'  \code{\link{dbplot_raster}}, \code{\link{dbplot_histogram}}
#'
#' @export
#'
#' mtcars %>%
#'   dbplot_boxplot(am, mpg)
#'
dbplot_boxplot <- function(data, x, var, coef = 1.5) {
  x <- enquo(x)
  var <- enquo(var)

  df <- db_compute_boxplot(
    data = data,
    x = !!x,
    var = !!var,
    coef = coef
  )

  colnames(df) <- c(
    "x", "n", "lower", "middle", "upper", "max_raw", "min_raw",
    "iqr", "min_iqr", "max_iqr", "ymax", "ymin"
  )

  ggplot(df) +
    geom_boxplot(
      aes(
        x = x,
        ymin = ymin,
        lower = lower,
        middle = middle,
        upper = upper,
        ymax = ymax,
        group = x
      ),
      stat = "identity"
    ) +
    labs(x = x)
}

globalVariables(c(
  "upper", "ymax", "weight", "x_", "y", "aes", "ymin", "lower",
  "middle", "upper", "iqr", "max_raw", "max_iqr", "min_raw",
  "min_iqr", "percentile_approx"
))

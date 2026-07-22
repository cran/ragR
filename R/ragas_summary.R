# R/ragas_summary.R

#' Summarize RAGAS metrics across QA pairs
#'
#' Computes mean, standard deviation, minimum, and maximum for each metric column
#' in a QA-metrics tibble.
#'
#' @param qa_metrics A tibble returned by [compute_ragas_metrics()] or
#'   [compute_ragas_metrics_llm()] with metric columns such as
#'   `context_precision`, `context_recall`, `answer_relevance`, `faithfulness`,
#'   and `ragas_overall`.
#'
#' @return A tibble with columns: `metric`, `mean`, `sd`, `min`, `max`.
#' @export
summarize_ragas <- function(qa_metrics) {
  # Always return the same column structure, even if empty.
  empty_out <- tibble::tibble(
    metric = character(),
    mean   = numeric(),
    sd     = numeric(),
    min    = numeric(),
    max    = numeric()
  )

  if (is.null(qa_metrics) || nrow(qa_metrics) == 0L) {
    return(empty_out)
  }

  if (!is.data.frame(qa_metrics)) {
    stop("qa_metrics must be a data frame / tibble.", call. = FALSE)
  }

  metric_cols <- c(
    "context_precision",
    "context_recall",
    "answer_relevance",
    "faithfulness",
    "ragas_overall"
  )

  metric_cols <- metric_cols[metric_cols %in% names(qa_metrics)]

  if (length(metric_cols) == 0L) {
    stop("qa_metrics contains no known metric columns to summarize.", call. = FALSE)
  }

  rows <- lapply(metric_cols, function(m) {
    x <- suppressWarnings(as.numeric(qa_metrics[[m]]))

    if (length(x) == 0L || all(is.na(x))) {
      tibble::tibble(
        metric = m,
        mean   = NA_real_,
        sd     = NA_real_,
        min    = NA_real_,
        max    = NA_real_
      )
    } else {
      tibble::tibble(
        metric = m,
        mean   = mean(x, na.rm = TRUE),
        sd     = stats::sd(x, na.rm = TRUE),
        min    = min(x, na.rm = TRUE),
        max    = max(x, na.rm = TRUE)
      )
    }
  })

  dplyr::bind_rows(rows)
}

#' Plot mean RAG evaluation metrics to a PNG
#'
#' Creates a bar chart of mean metric values and writes it to a PNG file.
#' The output path must be supplied explicitly.
#'
#' @param summary_df Output of [summarize_ragas()].
#' @param output_path Character scalar; path where the PNG file is written.
#' @param width,height Positive numeric values giving the plot dimensions in
#'   pixels.
#'
#' @return Invisibly, `output_path`.
#'
#' @examples
#' summary_df <- tibble::tibble(
#'   metric = c("Context precision", "Faithfulness"),
#'   mean = c(0.8, 0.9)
#' )
#'
#' output_path <- tempfile(fileext = ".png")
#'
#' plot_ragas_means(
#'   summary_df = summary_df,
#'   output_path = output_path
#' )
#'
#' file.exists(output_path)
#'
#' @export
plot_ragas_means <- function(
  summary_df,
  output_path,
  width = 1200,
  height = 700
) {
  if (
    is.null(summary_df) ||
      !is.data.frame(summary_df) ||
      nrow(summary_df) == 0L
  ) {
    stop(
      "summary_df must be a non-empty data frame or tibble.",
      call. = FALSE
    )
  }

  if (!all(c("metric", "mean") %in% names(summary_df))) {
    stop(
      "summary_df must have columns named 'metric' and 'mean'.",
      call. = FALSE
    )
  }

  if (
    missing(output_path) ||
      !is.character(output_path) ||
      length(output_path) != 1L ||
      is.na(output_path) ||
      !nzchar(output_path)
  ) {
    stop(
      "output_path must be supplied as a single non-empty character string.",
      call. = FALSE
    )
  }

  if (
    !is.numeric(width) ||
      length(width) != 1L ||
      is.na(width) ||
      width <= 0
  ) {
    stop("width must be a single positive number.", call. = FALSE)
  }

  if (
    !is.numeric(height) ||
      length(height) != 1L ||
      is.na(height) ||
      height <= 0
  ) {
    stop("height must be a single positive number.", call. = FALSE)
  }

  means <- suppressWarnings(
    as.numeric(summary_df$mean)
  )

  if (
    length(means) == 0L ||
      all(!is.finite(means))
  ) {
    stop(
      "summary_df$mean contains no finite values to plot.",
      call. = FALSE
    )
  }

  names(means) <- as.character(summary_df$metric)

  output_dir <- dirname(output_path)

  if (!dir.exists(output_dir)) {
    dir.create(
      output_dir,
      recursive = TRUE,
      showWarnings = FALSE
    )
  }

  grDevices::png(
    filename = output_path,
    width = width,
    height = height,
    res = 150
  )
  on.exit(grDevices::dev.off(), add = TRUE)

  old_par <- graphics::par(no.readonly = TRUE)
  on.exit(graphics::par(old_par), add = TRUE)

  graphics::par(
    mar = c(9, 5, 3, 1) + 0.1
  )

  y_max <- max(
    1,
    max(means, na.rm = TRUE)
  ) * 1.1

  bp <- graphics::barplot(
    height = means,
    las = 2,
    ylim = c(0, y_max),
    ylab = "Mean score",
    main = "RAG Evaluation Metric Means"
  )

  graphics::axis(
    side = 1,
    at = bp,
    labels = names(means),
    las = 2
  )

  graphics::grid(
    nx = NA,
    ny = NULL
  )

  invisible(output_path)
}

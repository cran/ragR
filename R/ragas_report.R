# R/ragas_report.R

#' Generate a RAG evaluation performance report
#'
#' Loads a question-answering log from disk, computes large language model
#' evaluation metrics, and writes:
#'
#' - metrics to an RDS file;
#' - a summary to `ragas_summary.csv`;
#' - a bar plot of mean metrics to `ragas_means.png`.
#'
#' All input and output locations must be supplied explicitly.
#'
#' @param qa_log_path Character scalar; path to the question-answering log
#'   RDS file.
#' @param qa_metrics_path Character scalar; path to the metrics RDS output
#'   file.
#' @param output_dir Character scalar; directory where the summary CSV and
#'   plot PNG are written.
#' @param judge_model Character scalar; large language model used to score
#'   the evaluation metrics.
#'
#' @return A list containing `status`, `n_qa`, `qa_metrics_path`,
#'   `summary_csv_path`, and `plot_path`.
#'
#' @export
generate_ragas_report <- function(
  qa_log_path,
  qa_metrics_path,
  output_dir,
  judge_model = "gpt-4o-mini"
) {
  if (
    missing(qa_log_path) ||
      !is.character(qa_log_path) ||
      length(qa_log_path) != 1L ||
      is.na(qa_log_path) ||
      !nzchar(qa_log_path)
  ) {
    stop(
      "qa_log_path must be supplied as a single non-empty character string.",
      call. = FALSE
    )
  }

  if (
    missing(qa_metrics_path) ||
      !is.character(qa_metrics_path) ||
      length(qa_metrics_path) != 1L ||
      is.na(qa_metrics_path) ||
      !nzchar(qa_metrics_path)
  ) {
    stop(
      paste0(
        "qa_metrics_path must be supplied as a single ",
        "non-empty character string."
      ),
      call. = FALSE
    )
  }

  if (
    missing(output_dir) ||
      !is.character(output_dir) ||
      length(output_dir) != 1L ||
      is.na(output_dir) ||
      !nzchar(output_dir)
  ) {
    stop(
      "output_dir must be supplied as a single non-empty character string.",
      call. = FALSE
    )
  }

  if (
    !is.character(judge_model) ||
      length(judge_model) != 1L ||
      is.na(judge_model) ||
      !nzchar(judge_model)
  ) {
    stop(
      "judge_model must be a single non-empty character string.",
      call. = FALSE
    )
  }

  qa_log <- load_qa_log(qa_log_path)

  metrics <- compute_ragas_metrics(
    qa_log,
    judge_model = judge_model
  )

  summary <- summarize_ragas(metrics)

  save_qa_metrics(
    qa_metrics = metrics,
    path = qa_metrics_path
  )

  if (!dir.exists(output_dir)) {
    dir.create(
      output_dir,
      recursive = TRUE,
      showWarnings = FALSE
    )
  }

  summary_csv_path <- file.path(
    output_dir,
    "ragas_summary.csv"
  )

  utils::write.csv(
    summary,
    file = summary_csv_path,
    row.names = FALSE
  )

  plot_path <- file.path(
    output_dir,
    "ragas_means.png"
  )

  plot_ragas_means(
    summary_df = summary,
    output_path = plot_path
  )

  list(
    status = "ok",
    n_qa = nrow(qa_log),
    qa_metrics_path = qa_metrics_path,
    summary_csv_path = summary_csv_path,
    plot_path = plot_path
  )
}


#' Generate a RAG evaluation report using large language model scoring
#'
#' This is an explicit alias for [generate_ragas_report()].
#'
#' All input and output locations must be supplied explicitly.
#'
#' @inheritParams generate_ragas_report
#'
#' @return A list containing `status`, `n_qa`, `qa_metrics_path`,
#'   `summary_csv_path`, and `plot_path`.
#'
#' @export
generate_ragas_report_llm <- function(
  qa_log_path,
  qa_metrics_path,
  output_dir,
  judge_model = "gpt-4o-mini"
) {
  generate_ragas_report(
    qa_log_path = qa_log_path,
    qa_metrics_path = qa_metrics_path,
    output_dir = output_dir,
    judge_model = judge_model
  )
}

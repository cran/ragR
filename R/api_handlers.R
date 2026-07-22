#' API handler: chat with the RAG pipeline
#'
#' This handler receives a parsed JSON request body, runs the RAG pipeline,
#' appends the interaction to the QA log, and returns the model answer.
#'
#' File locations must be supplied explicitly. The handler does not choose
#' default locations in the user's working directory.
#'
#' @param body Parsed JSON request body.
#' @param qa_log_path Character scalar; path to the QA log RDS file.
#' @param vectorstore_path Character scalar; path to the vector-store RDS file.
#'
#' @return A list suitable for JSON serialization.
#' @export
api_chat_handler <- function(
  body,
  qa_log_path,
  vectorstore_path
) {
  if (is.null(body) || !is.list(body)) {
    stop("Request body must be a JSON object.", call. = FALSE)
  }

  if (
    missing(qa_log_path) ||
      !is.character(qa_log_path) ||
      length(qa_log_path) != 1L ||
      !nzchar(qa_log_path)
  ) {
    stop(
      "qa_log_path must be supplied as a single non-empty character string.",
      call. = FALSE
    )
  }

  if (
    missing(vectorstore_path) ||
      !is.character(vectorstore_path) ||
      length(vectorstore_path) != 1L ||
      !nzchar(vectorstore_path)
  ) {
    stop(
      "vectorstore_path must be supplied as a single non-empty character string.",
      call. = FALSE
    )
  }

  question <- body$question

  if (
    is.null(question) ||
      !is.character(question) ||
      length(question) != 1L ||
      !nzchar(question)
  ) {
    stop(
      "Request body must include a non-empty 'question' field.",
      call. = FALSE
    )
  }

  collection <- body$collection %||% "default"
  top_k <- body$top_k %||% 5L
  score_threshold <- body$score_threshold %||% 0

  embedding_model <- body$embedding_model %||% "text-embedding-3-small"
  chat_model <- body$chat_model %||% "gpt-4o-mini"

  temperature <- body$temperature %||% 0
  max_output_tokens <- body$max_output_tokens %||% 10000L

  system_prompt <- body$system_prompt %||% "You are a helpful assistant."

  res <- query_rag(
    question          = question,
    collection        = collection,
    vectorstore_path  = vectorstore_path,
    top_k             = as.integer(top_k),
    embedding_model   = embedding_model,
    chat_model        = chat_model,
    temperature       = temperature,
    max_output_tokens = if (is.null(max_output_tokens)) {
      NULL
    } else {
      as.integer(max_output_tokens)
    },
    score_threshold   = score_threshold,
    system_prompt     = system_prompt
  )

  qa_log <- load_qa_log(qa_log_path)

  qa_log <- log_rag_interaction(
    qa_log          = qa_log,
    question        = question,
    rag_result      = res,
    collection      = collection,
    chat_model      = chat_model,
    embedding_model = embedding_model
  )

  save_qa_log(qa_log, qa_log_path)

  list(
    status    = "ok",
    qa_id     = tail(qa_log$qa_id, 1L),
    question  = question,
    answer    = res$answer,
    retrieved = res$retrieved
  )
}


#' API handler: clear a vector-store collection
#'
#' Deletes a collection from the R-native vector store. The request body may
#' specify a collection name; otherwise, `"default"` is used. The vector-store
#' path must be supplied explicitly.
#'
#' @param body A list parsed from a JSON request body, or `NULL`.
#' @param vectorstore_path Character scalar; path to the vector-store RDS file.
#'
#' @return A list suitable for JSON serialization, containing `status`,
#'   `collection`, and `message`.
#'
#' @examples
#' path <- tempfile(fileext = ".rds")
#'
#' api_clear_handler(
#'   body = list(collection = "example"),
#'   vectorstore_path = path
#' )
#'
#' @export
api_clear_handler <- function(
  body,
  vectorstore_path
) {
  if (!is.null(body) && !is.list(body)) {
    stop(
      "Request body must be a list parsed from JSON or NULL.",
      call. = FALSE
    )
  }

  if (
    missing(vectorstore_path) ||
      !is.character(vectorstore_path) ||
      length(vectorstore_path) != 1L ||
      is.na(vectorstore_path) ||
      !nzchar(vectorstore_path)
  ) {
    stop(
      paste0(
        "vectorstore_path must be supplied as a single ",
        "non-empty character string."
      ),
      call. = FALSE
    )
  }

  collection <- if (
    !is.null(body) &&
      !is.null(body$collection)
  ) {
    body$collection
  } else {
    "default"
  }

  if (
    !is.character(collection) ||
      length(collection) != 1L ||
      is.na(collection) ||
      !nzchar(collection)
  ) {
    stop(
      "collection must be a single non-empty character string.",
      call. = FALSE
    )
  }

  vectorstore_delete_collection(
    collection = collection,
    path = vectorstore_path
  )

  list(
    status = "ok",
    collection = collection,
    message = sprintf(
      "Collection '%s' cleared.",
      collection
    )
  )
}

#' API handler: clear the entire vector store
#'
#' Removes all collections and stored embeddings from the vector store.
#' The vector-store path must be supplied explicitly.
#'
#' @param vectorstore_path Character scalar; path to the vector-store RDS file.
#'
#' @return A list containing `status` and `message`.
#'
#' @examples
#' path <- tempfile(fileext = ".rds")
#'
#' api_clear_all_handler(
#'   vectorstore_path = path
#' )
#'
#' @export
api_clear_all_handler <- function(vectorstore_path) {
  if (
    missing(vectorstore_path) ||
      !is.character(vectorstore_path) ||
      length(vectorstore_path) != 1L ||
      is.na(vectorstore_path) ||
      !nzchar(vectorstore_path)
  ) {
    stop(
      paste0(
        "vectorstore_path must be supplied as a single ",
        "non-empty character string."
      ),
      call. = FALSE
    )
  }

  vectorstore_clear_all(
    path = vectorstore_path
  )

  list(
    status = "ok",
    message = "Vector store cleared: all collections removed."
  )
}

#' API handler: compute RAG evaluation metrics
#'
#' Loads a saved question-answering log, computes evaluation metrics, and
#' returns both the per-interaction metrics and their summary. The QA-log path
#' must be supplied explicitly.
#'
#' @param path Character scalar; path to the QA log RDS file.
#' @param judge_model Character scalar; large language model used to score the
#'   evaluation metrics.
#'
#' @return A list containing `status`, `n_qa`, `metrics`, and `summary`.
#'
#' @examples
#' path <- tempfile(fileext = ".rds")
#' save_qa_log(qa_log_empty(), path)
#'
#' api_ragas_handler(
#'   path = path,
#'   judge_model = "gpt-4o-mini"
#' )
#'
#' @export
api_ragas_handler <- function(
  path,
  judge_model = "gpt-4o-mini"
) {
  if (
    missing(path) ||
      !is.character(path) ||
      length(path) != 1L ||
      is.na(path) ||
      !nzchar(path)
  ) {
    stop(
      "path must be supplied as a single non-empty character string.",
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

  qa_log <- load_qa_log(path)

  if (nrow(qa_log) == 0L) {
    metrics <- qa_metrics_empty()
    summary <- summarize_ragas(metrics)

    return(
      list(
        status = "ok",
        message = "QA log is empty. No evaluation metrics were computed.",
        n_qa = 0L,
        metrics = metrics,
        summary = summary
      )
    )
  }

  metrics <- compute_ragas_metrics(
    qa_log,
    judge_model = judge_model
  )

  summary <- summarize_ragas(metrics)

  list(
    status = "ok",
    n_qa = nrow(qa_log),
    metrics = metrics,
    summary = summary
  )
}

#' API handler: generate a RAG evaluation performance report
#'
#' Loads a saved question-answering log, computes evaluation metrics, and
#' writes the metrics, summary CSV, and plot to explicitly supplied locations.
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
#'   `summary_csv_path`, and `plot_path`. If the QA log is empty, the returned
#'   list instead includes an explanatory `message`.
#'
#' @export
api_ragas_report_handler <- function(
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

  if (nrow(qa_log) == 0L) {
    return(
      list(
        status = "ok",
        message = "QA log is empty. No RAG evaluation report was generated.",
        n_qa = 0L
      )
    )
  }

  generate_ragas_report(
    qa_log_path = qa_log_path,
    qa_metrics_path = qa_metrics_path,
    output_dir = output_dir,
    judge_model = judge_model
  )
}

#' API handler: clear RAG evaluation files
#'
#' Clears the saved question-answering log, saved evaluation metrics, and
#' generated report directory. All locations must be supplied explicitly.
#'
#' @param qa_log_path Character scalar; path to the question-answering log
#'   RDS file.
#' @param qa_metrics_path Character scalar; path to the saved metrics RDS file.
#' @param output_dir Character scalar; directory containing generated report
#'   files.
#'
#' @return A list containing `status` and `message`.
#'
#' @examples
#' qa_log_path <- tempfile(fileext = ".rds")
#' qa_metrics_path <- tempfile(fileext = ".rds")
#' output_dir <- tempfile()
#'
#' save_qa_log(qa_log_empty(), qa_log_path)
#' save_qa_metrics(qa_metrics_empty(), qa_metrics_path)
#' dir.create(output_dir)
#'
#' api_ragas_clear_handler(
#'   qa_log_path = qa_log_path,
#'   qa_metrics_path = qa_metrics_path,
#'   output_dir = output_dir
#' )
#'
#' @export
api_ragas_clear_handler <- function(
  qa_log_path,
  qa_metrics_path,
  output_dir
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

  clear_qa_log(
    path = qa_log_path
  )

  clear_qa_metrics(
    path = qa_metrics_path
  )

  if (dir.exists(output_dir)) {
    unlink(
      output_dir,
      recursive = TRUE,
      force = TRUE
    )
  }

  list(
    status = "ok",
    message = paste0(
      "QA log, QA metrics, and RAG evaluation ",
      "report files were cleared."
    )
  )
}
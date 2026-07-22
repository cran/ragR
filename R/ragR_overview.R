# R/ragR_overview.R

#' ragR: Retrieval-Augmented Generation and Evaluation Tools
#'
#' @description
#' The **ragR** package provides tools for building and evaluating
#' retrieval-augmented generation systems in R. It includes:
#'
#' - A data-ingestion pipeline for PDF, text, and Word documents
#' - An R-native vector store for document chunks and embeddings
#' - A configurable retrieval-augmented generation pipeline
#' - Persistent question-answer logging for reproducible evaluation
#' - Large-language-model-scored evaluation metrics, including context
#'   precision, context recall, answer relevance, and faithfulness
#' - A Plumber-based HTTP API suitable for chatbot and evaluation frontends
#'
#' @section Architecture:
#'
#' The package is organized into several modules:
#'
#' - **Ingestion (`ingestion_files.R`)**
#'
#'   Extracts text from PDF, TXT, and DOCX files, divides the text into chunks,
#'   and prepares those chunks for embedding and storage. The vector-store path
#'   must be supplied explicitly by the caller.
#'
#' - **Embeddings and chat (`embeddings_openai.R`)**
#'
#'   Wraps the OpenAI REST API for embedding models, such as
#'   `"text-embedding-3-small"`, and chat models, such as `"gpt-4o-mini"`.
#'   The API key is read from the `OPENAI_API_KEY` environment variable.
#'
#' - **Vector store (`vectorstore_interface.R`)**
#'
#'   Implements an R-native vector store using tibbles and numeric matrices.
#'   Functions are provided to load the store, add or update records, retrieve
#'   similar chunks, delete collections, and clear the complete store.
#'
#'   All vector-store functions require an explicit storage path.
#'
#' - **Retrieval-augmented generation pipeline (`rag_pipeline.R`)**
#'
#'   Given a user question, the pipeline:
#'
#'   1. Computes an embedding for the question
#'   2. Retrieves similar chunks from the selected vector-store collection
#'   3. Builds a grounded, context-aware prompt
#'   4. Calls a chat model to generate an answer
#'
#' - **Question-answer logging and persistence
#'   (`qa_logging.R`, `qa_persistence.R`)**
#'
#'   Stores interactions including the question, model answer, retrieved
#'   chunks, final grounded prompt, model names, collection name, and
#'   timestamp. Helpers are provided to load, save, and clear logs.
#'
#'   Log locations must be supplied explicitly.
#'
#' - **Evaluation metrics and summaries
#'   (`ragas_metrics.R`, `ragas_summary.R`)**
#'
#'   Computes large-language-model-scored evaluation metrics, including
#'   context precision, context recall, answer relevance, faithfulness, and an
#'   overall score. Summary helpers aggregate metric results across
#'   question-answer pairs.
#'
#' - **Reports (`ragas_report.R`)**
#'
#'   Generates an evaluation report by:
#'
#'   - Computing metrics from a saved question-answer log
#'   - Saving the resulting metrics to an explicitly supplied RDS path
#'   - Writing a summary CSV to an explicitly supplied output directory
#'   - Writing a bar chart of mean metric values to that output directory
#'
#' - **API handlers (`api_handlers.R`)**
#'
#'   Connect the core package functions to HTTP endpoints. Storage paths are
#'   supplied by the server configuration rather than by client request bodies
#'   or hidden package defaults.
#'
#' @section HTTP API:
#'
#' The development server in `scripts/dev/run_api.R` exposes:
#'
#' - `POST /chat`
#'
#'   Runs the retrieval-augmented generation pipeline for a user question and
#'   appends the interaction to the configured question-answer log.
#'
#' - `GET /ragas`
#'
#'   Computes and returns evaluation metrics and a summary for the logged
#'   question-answer interactions.
#'
#' - `POST /ragas/report`
#'
#'   Computes metrics from the configured question-answer log and writes the
#'   metrics, summary CSV, and plot to server-configured locations.
#'
#' - `POST /ragas/clear`
#'
#'   Clears the configured question-answer log, metrics file, and report
#'   directory.
#'
#' - `POST /clear`
#'
#'   Clears one collection from the configured vector store.
#'
#' - `POST /clear_all`
#'
#'   Clears all collections from the configured vector store using
#'   [api_clear_all_handler()] and [vectorstore_clear_all()].
#'
#' The development server uses a temporary storage directory unless a
#' persistent location is supplied through the `RAGR_API_DATA_DIR`
#' environment variable.
#'
#' @section Usage:
#'
#' Programmatic usage inside R:
#'
#' ```r
#' library(ragR)
#'
#' vectorstore_path <- tempfile(fileext = ".rds")
#'
#' # Documents must first be ingested into this vector store.
#' res <- query_rag(
#'   question = "What is this document about?",
#'   collection = "default",
#'   vectorstore_path = vectorstore_path,
#'   top_k = 5L,
#'   embedding_model = "text-embedding-3-small",
#'   chat_model = "gpt-4o-mini",
#'   system_prompt = "You are a helpful assistant."
#' )
#'
#' cat(res$answer)
#' ```
#'
#' To run the development HTTP server from the project root:
#'
#' ```r
#' source("scripts/dev/run_api.R")
#' ```
#'
#' Interactive API documentation is then available at
#' `http://127.0.0.1:8000/__docs__/`.
#'
#' @keywords RAG NLP OpenAI RAGAS chatbot embeddings
#'
#' @importFrom utils tail
"_PACKAGE"

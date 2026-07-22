# ragR: Retrieval-Augmented Generation and Evaluation Tools in R

`ragR` is an R package for building, running, logging, and evaluating
retrieval-augmented generation workflows.

It provides:

- document-ingestion and chunking utilities;
- OpenAI-based embeddings and chat generation;
- an R-native vector store backed by local RDS files;
- a configurable retrieval-augmented generation pipeline;
- persistent question-answer logging;
- large-language-model-scored evaluation metrics inspired by Retrieval
  Augmented Generation Assessment (RAGAS); and
- Plumber handlers for chatbot and evaluation backends.

The package is designed for research, coursework, experimentation, and
reproducible retrieval-augmented generation evaluation workflows.

---

## Features

### Document ingestion

`ragR` can ingest documents, divide text into chunks, generate embeddings, and
store the chunks and embeddings in a local R-native vector store.

Supported file types depend on the available R and system dependencies. Plain
text ingestion is the simplest option. PDF ingestion may require the
`pdftools` R package and the Poppler system library.

The vector-store location must be supplied explicitly by the caller. For
example, a user may choose a persistent project location such as:

```text
db/vectorstore.rds
```

or a temporary location created with `tempfile()`.

Runtime vector-store files are not part of the installed package.

### Retrieval-augmented generation

For a user question, the retrieval-augmented generation pipeline:

1. embeds the question using an embedding model;
2. retrieves similar chunks from the selected vector-store collection;
3. builds a grounded prompt using the retrieved context;
4. sends the grounded prompt to a chat model; and
5. returns the answer, retrieved chunks, and final prompt.

The primary user-facing function is:

```r
query_rag()
```

The vector-store path must be supplied explicitly.

The API-level `system_prompt` is passed as a system message to the chat model.
It is not inserted into the constructed retrieval-augmented generation prompt.

### Persistent question-answer logging

`ragR` can log interactions to a user-selected RDS file.

Each logged row includes:

- `qa_id`;
- `question`;
- `prompt_final`;
- `answer_model`;
- `answer_reference`;
- `collection`;
- `retrieved_ids`;
- `retrieved_texts`;
- `chat_model`;
- `embedding_model`; and
- `timestamp`.

The `answer_reference` column is optional. It can be completed later for
controlled evaluation experiments. When it is absent or empty, some evaluation
functions may use `answer_model` where needed.

The package does not select a default question-answer log location. Paths must
be supplied explicitly to the persistence functions.

### Large-language-model-scored evaluation metrics

`ragR` computes evaluation metrics inspired by Retrieval Augmented Generation
Assessment, including:

- context precision;
- context recall;
- answer relevance;
- faithfulness; and
- an overall score.

The main metric functions are:

```r
compute_ragas_metrics()
compute_ragas_metrics_llm()
```

In the current package version, these metrics are scored using large language
models. Deterministic approximation metrics are not included.

Metric values may be `NA` when a score cannot be computed, required inputs are
unavailable, or external model scoring fails.

Metrics and reports are written only to locations explicitly supplied by the
caller.

### Plumber API backend

The source repository includes a development Plumber server for chatbot and
evaluation frontends.

Current routes are:

| Endpoint | Method | Purpose |
|---|---:|---|
| `/chat` | POST | Ask a retrieval-augmented generation question and log the interaction |
| `/ragas` | GET | Compute and return evaluation metrics and a summary |
| `/ragas/report` | POST | Compute metrics and save report artifacts |
| `/ragas/clear` | POST | Clear the question-answer log, metrics, and report files |
| `/clear` | POST | Clear one vector-store collection |
| `/clear_all` | POST | Clear the entire vector store |

There is no ingestion endpoint in the current minimal API. Document ingestion
is performed through package functions or development scripts.

The API server configures storage paths on the server side. File paths are not
accepted from client JSON request bodies.

---

## Installation

### From GitHub

```r
install.packages("remotes")
remotes::install_github("aimalrehman92/ragR")
```

### Local development installation

Clone the repository:

```bash
git clone https://github.com/aimalrehman92/ragR.git
cd ragR
```

Install development tools if needed:

```r
install.packages(c("pkgload", "testthat", "roxygen2"))
```

Load the package during development:

```r
pkgload::load_all()
```

Or install it locally:

```r
install.packages(".", repos = NULL, type = "source")
```

### Optional: restore the development environment

The GitHub repository may include development-environment files. When using
`renv`, restore the environment with:

```r
install.packages("renv")
renv::restore()
```

Depending on the operating system, some dependencies may require additional
system libraries. PDF ingestion through `pdftools`, for example, may require
Poppler.

---

## OpenAI API key

`ragR` reads the OpenAI API key from:

```text
OPENAI_API_KEY
```

The key can be added to a user-level `.Renviron` file:

```r
usethis::edit_r_environ("user")
```

Add a line such as:

```text
OPENAI_API_KEY=your_key_here
```

Restart R after editing the file.

Most package tests use synthetic data and do not require an OpenAI API key.
Functions that call OpenAI models require a valid API key and internet access.

---

## Usage from R

### Choose runtime paths

All runtime paths are selected explicitly.

The following example uses a temporary directory:

```r
library(ragR)

runtime_dir <- file.path(
  tempdir(),
  "ragR-example"
)

dir.create(
  runtime_dir,
  recursive = TRUE,
  showWarnings = FALSE
)

vectorstore_path <- file.path(
  runtime_dir,
  "vectorstore.rds"
)

qa_log_path <- file.path(
  runtime_dir,
  "qa_log.rds"
)

qa_metrics_path <- file.path(
  runtime_dir,
  "qa_metrics.rds"
)

report_dir <- file.path(
  runtime_dir,
  "reports"
)
```

For persistent work, replace `runtime_dir` with a directory chosen by the user.

### Ingest documents

```r
library(ragR)

input_paths <- c(
  "data-raw/my_document.txt"
)

ingest_documents(
  paths = input_paths,
  vectorstore_path = vectorstore_path,
  collection = "default",
  embedding_model = "text-embedding-3-small"
)
```

For PDF ingestion, use a PDF path such as:

```r
input_paths <- c(
  "data-raw/my_document.pdf"
)
```

PDF ingestion may require `pdftools` and Poppler.

### Ask retrieval-augmented generation questions

```r
library(ragR)

res <- query_rag(
  question = "What is this document about?",
  collection = "default",
  vectorstore_path = vectorstore_path,
  top_k = 5L,
  embedding_model = "text-embedding-3-small",
  chat_model = "gpt-4o-mini",
  temperature = 0,
  max_output_tokens = 300L,
  system_prompt = "You are a helpful assistant."
)

cat(res$answer)
```

The result includes:

- `answer`;
- `retrieved`;
- `prompt`; and
- model metadata.

### Save and load question-answer logs

```r
library(ragR)

qa_log <- qa_log_empty()

qa_log <- log_rag_interaction(
  qa_log = qa_log,
  question = "What is this document about?",
  rag_result = res,
  collection = "default",
  chat_model = "gpt-4o-mini",
  embedding_model = "text-embedding-3-small"
)

save_qa_log(
  qa_log = qa_log,
  path = qa_log_path
)

qa_log <- load_qa_log(
  path = qa_log_path
)
```

### Compute evaluation metrics

```r
library(ragR)

qa_log <- load_qa_log(
  path = qa_log_path
)

qa_metrics <- compute_ragas_metrics(
  qa_log,
  judge_model = "gpt-4o-mini",
  embedding_model = "text-embedding-3-small"
)

save_qa_metrics(
  qa_metrics = qa_metrics,
  path = qa_metrics_path
)

summary_tbl <- summarize_ragas(
  qa_metrics
)

print(summary_tbl)
```

### Generate an evaluation report

```r
library(ragR)

generate_ragas_report(
  qa_log_path = qa_log_path,
  qa_metrics_path = qa_metrics_path,
  output_dir = report_dir,
  judge_model = "gpt-4o-mini"
)
```

This writes:

```text
<qa_metrics_path>
<report_dir>/ragas_summary.csv
<report_dir>/ragas_means.png
```

All three locations are controlled by the caller.

### Clear saved state

Clear a question-answer log:

```r
clear_qa_log(
  path = qa_log_path
)
```

Clear saved metrics:

```r
clear_qa_metrics(
  path = qa_metrics_path
)
```

Clear one vector-store collection:

```r
vectorstore_delete_collection(
  collection = "default",
  path = vectorstore_path
)
```

Clear the entire vector store:

```r
vectorstore_clear_all(
  path = vectorstore_path
)
```

---

## Running the development API backend

The source repository includes:

```text
scripts/dev/run_api.R
```

Run it from the project root:

```bash
Rscript scripts/dev/run_api.R
```

By default, the server stores runtime files under a temporary directory.

To use a persistent directory, set `RAGR_API_DATA_DIR` before starting the
server.

On macOS or Linux:

```bash
export RAGR_API_DATA_DIR="/path/to/ragR-api-data"
Rscript scripts/dev/run_api.R
```

From R:

```r
Sys.setenv(
  RAGR_API_DATA_DIR = "/path/to/ragR-api-data"
)

source("scripts/dev/run_api.R")
```

The local backend runs at:

```text
http://127.0.0.1:8000
```

Interactive Swagger documentation is available at:

```text
http://127.0.0.1:8000/__docs__/
```

The development server uses the configured data directory to construct:

```text
vectorstore.rds
qa_log.rds
qa_metrics.rds
ragas/
```

---

## API examples

### POST `/chat`

Ask a retrieval-augmented generation question and log the interaction.

Example request body:

```json
{
  "question": "What is the document about?",
  "collection": "default",
  "top_k": 5
}
```

Example R request:

```r
library(httr2)

resp <- request(
  "http://127.0.0.1:8000/chat"
) |>
  req_method("POST") |>
  req_body_json(
    list(
      question = "What is the document about?",
      collection = "default",
      top_k = 5
    )
  ) |>
  req_perform()

resp_body_json(
  resp,
  simplifyVector = TRUE
)
```

The interaction is appended to the question-answer log configured by the
server.

### GET `/ragas`

Compute evaluation metrics from the configured question-answer log and return
the metrics and summary.

```r
library(httr2)

resp <- request(
  "http://127.0.0.1:8000/ragas"
) |>
  req_method("GET") |>
  req_perform()

resp_body_json(
  resp,
  simplifyVector = TRUE
)
```

### POST `/ragas/report`

Compute metrics and save report artifacts to server-configured locations.

```r
library(httr2)

resp <- request(
  "http://127.0.0.1:8000/ragas/report"
) |>
  req_method("POST") |>
  req_perform()

resp_body_json(
  resp,
  simplifyVector = TRUE
)
```

### POST `/ragas/clear`

Clear the configured question-answer log, saved metrics, and report directory.

```r
library(httr2)

resp <- request(
  "http://127.0.0.1:8000/ragas/clear"
) |>
  req_method("POST") |>
  req_perform()

resp_body_json(
  resp,
  simplifyVector = TRUE
)
```

### POST `/clear`

Clear one vector-store collection.

Example request body:

```json
{
  "collection": "default"
}
```

When `collection` is omitted, `"default"` is used.

### POST `/clear_all`

Clear all collections from the configured vector store.

```r
library(httr2)

resp <- request(
  "http://127.0.0.1:8000/clear_all"
) |>
  req_method("POST") |>
  req_perform()

resp_body_json(
  resp,
  simplifyVector = TRUE
)
```

---

## Development scripts

The source repository includes development scripts under `scripts/dev/`.
They are intended for local experimentation and reproducibility and are
excluded from the package build.

### General development scripts

```text
scripts/dev/demo_clear_collection.R
scripts/dev/demo_clear_db.R
scripts/dev/demo_ingest.R
scripts/dev/demo_rag.R
scripts/dev/run_api.R
```

### Question-answer and evaluation scripts

```text
scripts/dev/qa/clear_qa_state.R
scripts/dev/qa/collect_qa.R
scripts/dev/qa/compute_metrics.R
scripts/dev/qa/export_for_ragas_python.R
scripts/dev/qa/insert_gt.R
scripts/dev/qa/run_eval_loop.R
scripts/dev/qa/run_eval_pipeline.R
scripts/dev/qa/visualize_metrics.R
```

Some evaluation scripts are intended for controlled experiments in which
`answer_reference` has already been populated. The API workflow does not
require `answer_reference`.

---

## Project structure

```text
ragR/
├── DESCRIPTION
├── NAMESPACE
├── README.md
├── .Rbuildignore
├── .gitignore
├── R/
├── inst/
│   └── api/
├── man/
├── tests/
└── scripts/
    └── dev/
```

Runtime artifacts may be stored in any user-selected directory. Common
development locations include:

```text
db/
reports/ragas/
data-raw/
```

These are development or runtime folders and are not package data.

---

## Testing

Load the local package and run the tests:

```r
pkgload::load_all()
testthat::test_dir("tests/testthat")
```

Run an R package check with:

```r
rcmdcheck::rcmdcheck(
  args = "--as-cran"
)
```

When `devtools` is available, the equivalent commands are:

```r
devtools::test()
devtools::check(args = "--as-cran")
```

The package tests use synthetic data and avoid requiring an OpenAI API key or
internet access.

---

## Local and generated files

Runtime files should generally not be committed unless they are intentionally
included for reproducibility.

Examples include:

```text
vectorstore.rds
qa_log.rds
qa_metrics.rds
ragas_summary.csv
ragas_means.png
```

The exact locations are selected by the user or server configuration.

---

## License

GPL-3

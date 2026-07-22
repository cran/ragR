# R/vectorstore_interface.R
#
# R-native vector store backend using an RDS file.
# This avoids any external DB, Python, or HTTP dependency.
#
# Data model:
# A tibble with columns:
# - collection : character
# - id         : character
# - text       : character (chunk text)
# - embedding  : list-column of numeric vectors
# - metadata   : list-column (e.g., list(path=..., chunk_index=..., ...))


#' Load the R-native vector store
#'
#' Loads the current contents of an R-native vector store from an RDS file.
#' If the file does not exist, the function returns an empty tibble with the
#' expected columns: `collection`, `id`, `text`, `embedding`, and `metadata`.
#'
#' The vector-store path must be supplied explicitly.
#'
#' @param path Character scalar; path to the vector-store RDS file.
#'
#' @return A tibble with one row per stored chunk, or zero rows if the store
#'   does not yet exist.
#'
#' @examples
#' path <- tempfile(fileext = ".rds")
#'
#' vectorstore_load(path)
#'
#' @export
vectorstore_load <- function(path) {
  if (
    missing(path) ||
      !is.character(path) ||
      length(path) != 1L ||
      !nzchar(path)
  ) {
    stop(
      "path must be supplied as a single non-empty character string.",
      call. = FALSE
    )
  }

  if (!file.exists(path)) {
    return(
      tibble::tibble(
        collection = character(),
        id         = character(),
        text       = character(),
        embedding  = list(),
        metadata   = list()
      )
    )
  }

  store <- readRDS(path)

  if (!is.data.frame(store)) {
    stop(
      "Vector store file is not a data frame or tibble.",
      call. = FALSE
    )
  }

  required_cols <- c(
    "collection",
    "id",
    "text",
    "embedding",
    "metadata"
  )

  missing_cols <- setdiff(required_cols, names(store))

  if (length(missing_cols) > 0L) {
    stop(
      "Vector store is missing required columns: ",
      paste(missing_cols, collapse = ", "),
      call. = FALSE
    )
  }

  tibble::as_tibble(store)
}


# Internal helper: save the vector store
vectorstore_save <- function(store, path) {
  if (
    missing(path) ||
      !is.character(path) ||
      length(path) != 1L ||
      !nzchar(path)
  ) {
    stop(
      "path must be supplied as a single non-empty character string.",
      call. = FALSE
    )
  }

  dir_path <- dirname(path)

  if (!dir.exists(dir_path)) {
    dir.create(
      dir_path,
      recursive = TRUE,
      showWarnings = FALSE
    )
  }

  saveRDS(store, file = path)

  invisible(path)
}


#' Upsert embeddings into the R-native vector store
#'
#' Adds new records to a vector store or replaces existing records having the
#' same collection and identifier. The vector-store path must be supplied
#' explicitly.
#'
#' @param collection Character scalar; name of the collection.
#' @param ids Character vector of identifiers, one for each embedding.
#' @param embeddings Numeric matrix or data frame; one row per identifier.
#' @param documents Character vector of document text, one element per
#'   embedding.
#' @param metadatas Optional list or data frame containing metadata for each
#'   row.
#' @param path Character scalar; path to the vector-store RDS file.
#'
#' @return Invisibly, `TRUE` on success.
#'
#' @examples
#' path <- tempfile(fileext = ".rds")
#'
#' embeddings <- matrix(
#'   c(
#'     1, 0,
#'     0, 1
#'   ),
#'   nrow = 2,
#'   byrow = TRUE
#' )
#'
#' vectorstore_upsert(
#'   collection = "example",
#'   ids = c("doc_1", "doc_2"),
#'   embeddings = embeddings,
#'   documents = c("First document", "Second document"),
#'   path = path
#' )
#'
#' vectorstore_load(path)
#'
#' @export
vectorstore_upsert <- function(
  collection,
  ids,
  embeddings,
  documents,
  metadatas = NULL,
  path
) {
  if (!is.character(collection) || length(collection) != 1L || !nzchar(collection)) {
    stop("collection must be a single non-empty character string.", call. = FALSE)
  }

  if (!is.character(ids) || length(ids) == 0L) {
    stop("ids must be a non-empty character vector.", call. = FALSE)
  }

  if (any(is.na(ids)) || any(!nzchar(ids))) {
    stop("ids must not contain NA or empty strings.", call. = FALSE)
  }

  if (!is.matrix(embeddings) && !is.data.frame(embeddings)) {
    stop("embeddings must be a numeric matrix or data frame.", call. = FALSE)
  }

  if (!is.character(documents)) {
    stop("documents must be a character vector.", call. = FALSE)
  }

  if (
    missing(path) ||
      !is.character(path) ||
      length(path) != 1L ||
      !nzchar(path)
  ) {
    stop(
      "path must be supplied as a single non-empty character string.",
      call. = FALSE
    )
  }

  n <- length(ids)

  if (nrow(embeddings) != n) {
    stop("embeddings must have one row per id.", call. = FALSE)
  }

  if (length(documents) != n) {
    stop("documents must have length equal to length(ids).", call. = FALSE)
  }

  if (any(is.na(documents))) {
    stop("documents must not contain NA values.", call. = FALSE)
  }

  if (!is.null(metadatas) && length(metadatas) != n) {
    stop("metadatas must have length equal to length(ids).", call. = FALSE)
  }

  emb_mat <- as.matrix(embeddings)
  storage.mode(emb_mat) <- "double"

  if (anyNA(emb_mat)) {
    stop("embeddings must not contain NA values.", call. = FALSE)
  }

  emb_list <- lapply(seq_len(n), function(i) {
    as.numeric(emb_mat[i, ])
  })

  if (is.null(metadatas)) {
    metadatas <- replicate(n, list(), simplify = FALSE)
  }

  if (is.data.frame(metadatas)) {
    metadatas <- split(metadatas, seq_len(nrow(metadatas)))
  }

  new_rows <- tibble::tibble(
    collection = rep(collection, n),
    id         = ids,
    text       = documents,
    embedding  = emb_list,
    metadata   = metadatas
  )

  store <- vectorstore_load(path)

  if (nrow(store) > 0L) {
    store <- store[
      !(store$collection == collection & store$id %in% ids),
      ,
      drop = FALSE
    ]
  }

  store <- dplyr::bind_rows(store, new_rows)

  vectorstore_save(store, path)

  invisible(TRUE)
}


# Internal: cosine similarity between a matrix of embeddings and a single vector.
cosine_similarity <- function(emb_mat, q) {
  q <- as.numeric(q)
  emb_mat <- as.matrix(emb_mat)
  storage.mode(emb_mat) <- "double"

  if (ncol(emb_mat) != length(q)) {
    stop("Embedding dimension mismatch between stored embeddings and query.", call. = FALSE)
  }

  dots <- as.numeric(emb_mat %*% q)
  emb_norms <- sqrt(rowSums(emb_mat^2))
  q_norm <- sqrt(sum(q^2))

  denom <- emb_norms * q_norm
  sims <- dots / denom

  sims[!is.finite(sims)] <- 0
  sims
}

#' Query the R-native vector store for nearest neighbors
#'
#' Retrieves the stored chunks whose embeddings have the highest cosine
#' similarity to a supplied query embedding. The vector-store path must be
#' supplied explicitly.
#'
#' @param collection Character scalar; name of the collection.
#' @param query_embedding Numeric vector representing the query.
#' @param path Character scalar; path to the vector-store RDS file.
#' @param top_k Integer; maximum number of neighbors to retrieve.
#'
#' @return A tibble with columns `collection`, `id`, `text`, `score`, and
#'   `metadata`.
#'
#' @examples
#' path <- tempfile(fileext = ".rds")
#'
#' embeddings <- matrix(
#'   c(
#'     1, 0,
#'     0, 1
#'   ),
#'   nrow = 2,
#'   byrow = TRUE
#' )
#'
#' vectorstore_upsert(
#'   collection = "example",
#'   ids = c("doc_1", "doc_2"),
#'   embeddings = embeddings,
#'   documents = c("First document", "Second document"),
#'   path = path
#' )
#'
#' vectorstore_query(
#'   collection = "example",
#'   query_embedding = c(1, 0),
#'   path = path,
#'   top_k = 1L
#' )
#'
#' @export
vectorstore_query <- function(
  collection,
  query_embedding,
  path,
  top_k = 4L
) {
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

  if (
    !is.numeric(query_embedding) ||
      length(query_embedding) == 0L
  ) {
    stop(
      "query_embedding must be a non-empty numeric vector.",
      call. = FALSE
    )
  }

  if (anyNA(query_embedding)) {
    stop(
      "query_embedding must not contain NA values.",
      call. = FALSE
    )
  }

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
    !is.numeric(top_k) ||
      length(top_k) != 1L ||
      is.na(top_k) ||
      top_k <= 0
  ) {
    stop(
      "top_k must be a positive integer.",
      call. = FALSE
    )
  }

  top_k <- as.integer(top_k)

  store <- vectorstore_load(path)
  subset <- store[store$collection == collection, , drop = FALSE]

  if (nrow(subset) == 0L) {
    return(
      tibble::tibble(
        collection = character(),
        id = character(),
        text = character(),
        score = numeric(),
        metadata = list()
      )
    )
  }

  emb_mat <- do.call(
    rbind,
    lapply(subset$embedding, as.numeric)
  )

  sims <- cosine_similarity(
    emb_mat,
    query_embedding
  )

  subset$score <- sims

  subset <- subset[
    order(subset$score, decreasing = TRUE),
    ,
    drop = FALSE
  ]

  if (nrow(subset) > top_k) {
    subset <- subset[
      seq_len(top_k),
      ,
      drop = FALSE
    ]
  }

  tibble::tibble(
    collection = subset$collection,
    id = subset$id,
    text = subset$text,
    score = subset$score,
    metadata = subset$metadata
  )
}


#' Delete a collection from the R-native vector store
#'
#' Removes all stored records belonging to a specified collection. The
#' vector-store path must be supplied explicitly.
#'
#' @param collection Character scalar; name of the collection to delete.
#' @param path Character scalar; path to the vector-store RDS file.
#'
#' @return Invisibly, `TRUE` on success.
#'
#' @examples
#' path <- tempfile(fileext = ".rds")
#'
#' embeddings <- matrix(c(1, 0), nrow = 1)
#'
#' vectorstore_upsert(
#'   collection = "example",
#'   ids = "doc_1",
#'   embeddings = embeddings,
#'   documents = "Example document",
#'   path = path
#' )
#'
#' vectorstore_delete_collection(
#'   collection = "example",
#'   path = path
#' )
#'
#' vectorstore_load(path)
#'
#' @export
vectorstore_delete_collection <- function(
  collection,
  path
) {
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

  store <- vectorstore_load(path)

  if (nrow(store) == 0L) {
    return(invisible(TRUE))
  }

  store <- store[
    store$collection != collection,
    ,
    drop = FALSE
  ]

  vectorstore_save(store, path)

  invisible(TRUE)
}

#' Delete all collections from the R-native vector store
#'
#' Replaces the vector store with an empty tibble. The vector-store path must
#' be supplied explicitly.
#'
#' @param path Character scalar; path to the vector-store RDS file.
#'
#' @return Invisibly, `TRUE`.
#'
#' @examples
#' path <- tempfile(fileext = ".rds")
#'
#' embeddings <- matrix(c(1, 0), nrow = 1)
#'
#' vectorstore_upsert(
#'   collection = "example",
#'   ids = "doc_1",
#'   embeddings = embeddings,
#'   documents = "Example document",
#'   path = path
#' )
#'
#' vectorstore_clear_all(path)
#' vectorstore_load(path)
#'
#' @export
vectorstore_clear_all <- function(path) {
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

  empty <- tibble::tibble(
    collection = character(),
    id = character(),
    text = character(),
    embedding = list(),
    metadata = list()
  )

  vectorstore_save(empty, path)

  invisible(TRUE)
}
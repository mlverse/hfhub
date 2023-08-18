#' Queries information about Hub repositories
#'
#' @inheritParams hub_download
#' @param files_metadata Obtain files metadata information when querying repository information.
#' @export
hub_repo_info <- function(repo_id, ..., repo_type = NULL, revision = NULL, files_metadata = FALSE) {
  if (is.null(repo_type) || repo_type == "model") {
    path <- glue::glue("https://huggingface.co/api/models/{repo_id}")
  } else {
    path <- glue::glue("https://huggingface.co/api/{repo_type}s/{repo_id}")
  }

  if (!is.null(revision)) {
    path <- glue::glue("{path}/revision/{revision}")
  }

  params <- list()
  if (files_metadata) {
    params$blobs <- TRUE
  }

  headers <- hub_headers()

  results <- httr::GET(
    path,
    query = params,
    httr::add_headers(.headers = headers)
  )

  httr::content(results)
}

#' @describeIn hub_repo_info Query information from a Hub Dataset
#' @export
hub_dataset_info <- function(repo_id, ..., revision = NULL, files_metadata = FALSE) {
  hub_repo_info(
    repo_id,
    revision = revision,
    repo_type = "dataset",
    files_metadata = files_metadata
  )
}


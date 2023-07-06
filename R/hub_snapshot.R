#' Snapshot the entire repository
#'
#' Downloads and stores all files from a Hugging Face Hub repository.
#' @inheritParams hub_download
#' @param allow_patterns A character vector containing patters that are used to
#'   filter allowed files to snapshot.
#' @param ignore_patterns A character vector contaitning patterns to reject files
#'   from being downloaded.
#'
#' @export
hub_snapshot <- function(repo_id, ..., revision = "main", repo_type = "model",
                         local_files_only = FALSE, force_download = FALSE,
                         allow_patterns = NULL, ignore_patterns = NULL) {
  info <- hub_repo_info(repo_id, repo_type = repo_type)
  all_files <- sapply(info$siblings, function(x) x$rfilename)

  allowed_files <- all_files
  if (!is.null(allow_patterns)) {
    allowed_files <- lapply(allow_patterns, function(x) {
      all_files[grepl(allow_patterns, all_files)]
    })
    allowed_files <- unique(unlist(allowed_files))
  }

  files <- allowed_files
  if (!is.null(ignore_patterns)) {
    for (pattern in ignore_patterns) {
      files <- files[!grepl(pattern, files)]
    }
  }

  id <- cli::cli_progress_bar(
    name = "Downloading files",
    type = "tasks",
    total = length(files),
    clear = FALSE
  )

  i <- 0
  cli::cli_progress_step("Snapshotting files {i}/{length(files)}")
  for (i in seq_along(files)) {
    d <- hub_download(
      repo_id = repo_id,
      filename = files[i],
      revision = info$sha,
      repo_type = repo_type,
      local_files_only = local_files_only,
      force_download = force_download
    )
  }

  attr(d, "snapshot_path")
}

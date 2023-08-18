#' Downloads files from HuggingFace repositories
#'
#' @param repo_id The repository identifier, eg `"bert-base-uncased"` or `"deepset/sentence_bert"`.
#' @param filename Filename to download from the repository. Example `"config.json"`.
#' @param revision Revision (branch, tag or commitid) to download the file from.
#' @param repo_type The type of the repository. Currently only `"model"` is supported.
#' @param local_files_only Only use cached files?
#' @param force_download For re-downloading of files that are cached.
#' @param ... currenytly unused.
#'
#' @returns The file path of the downloaded or cached file. The snapshot path is returned
#'   as an attribute.
#' @examples
#' try({
#' withr::with_envvar(c(HUGGINGFACE_HUB_CACHE = tempdir()), {
#' path <- hub_download("gpt2", "config.json")
#' print(path)
#' str(jsonlite::fromJSON(path))
#' })
#' })
#'
#' @export
hub_download <- function(repo_id, filename, ..., revision = "main", repo_type = "model", local_files_only = FALSE, force_download = FALSE) {
  cache_dir <- HUGGINGFACE_HUB_CACHE()
  storage_folder <- fs::path(cache_dir, repo_folder_name(repo_id, repo_type))

  # revision is a commit hash and file exists in the cache, quicly return it.
  if (grepl(REGEX_COMMIT_HASH(), revision)) {
    pointer_path <- get_pointer_path(storage_folder, revision, filename)
    if (fs::file_exists(pointer_path)) {
      return(pointer_path)
    }
  }

  url <- hub_url(repo_id, filename, revision = revision, repo_type = repo_type)

  etag <- NULL
  commit_hash <- NULL
  expected_size <- NULL

  if (!local_files_only) {
    tryCatch({
      metadata <- get_file_metadata(url)

      commit_hash <- metadata$commit_hash
      if (is.null(commit_hash)) {
        cli::cli_abort("Distant resource does not seem to be on huggingface.co (missing commit header).")
      }

      etag <- metadata$etag
      if (is.null(etag)) {
        cli::cli_abort("Distant resource does not have an ETag, we won't be able to reliably ensure reproducibility.")
      }

      # Expected (uncompressed) size
      expected_size <- metadata$size

      # In case of a redirect, save an extra redirect on the request.get call,
      # and ensure we download the exact atomic version even if it changed
      # between the HEAD and the GET (unlikely, but hey).
      # Useful for lfs blobs that are stored on a CDN.
      if (metadata$location != url) {
        url <- metadata$location
      }
    })
  }

  # etag is NULL == we don't have a connection or we passed local_files_only.
  # try to get the last downloaded one from the specified revision.
  # If the specified revision is a commit hash, look inside "snapshots".
  # If the specified revision is a branch or tag, look inside "refs".
  if (is.null(etag)) {
    # Try to get "commit_hash" from "revision"
    commit_hash <- NULL
    if (grepl(REGEX_COMMIT_HASH(), revision)) {
      commit_hash <- revision
    } else {
      ref_path <- fs::path(storage_folder, "refs", revision)
      if (fs::file_exists(ref_path)) {
        commit_hash <- readLines(ref_path)
      }
    }

    # Return pointer file if exists
    if (!is.null(commit_hash)) {
      pointer_path <- get_pointer_path(storage_folder, commit_hash, filename)
      if (fs::file_exists(pointer_path)) {
        return(pointer_path)
      }
    }

    if (local_files_only) {
      cli::cli_abort(paste0(
        "Cannot find the requested files in the disk cache and",
        " outgoing traffic has been disabled. To enable hf.co look-ups",
        " and downloads online, set 'local_files_only' to False."
      ))
    } else {
      cli::cli_abort(paste0(
        "Connection error, and we cannot find the requested files in",
        " the disk cache. Please try again or make sure your Internet",
        " connection is on."
      ))
    }
  }

  if (is.null(etag)) cli::cli_abort("etag must have been retrieved from server")
  if (is.null(commit_hash)) cli::cli_abort("commit_hash must have been retrieved from server")

  blob_path <- fs::path(storage_folder, "blobs", etag)
  pointer_path <- get_pointer_path(storage_folder, commit_hash, filename)

  fs::dir_create(fs::path_dir(blob_path))
  fs::dir_create(fs::path_dir(pointer_path))

  # if passed revision is not identical to commit_hash
  # then revision has to be a branch name or tag name.
  # In that case store a ref.
  # we write an alias between revision and commit-hash
  if (revision != commit_hash) {
    ref_path <- fs::path(storage_folder, "refs", revision)
    fs::dir_create(fs::path_dir(ref_path))
    fs::file_create(ref_path)
    writeLines(commit_hash, ref_path)
  }

  if (fs::file_exists(pointer_path) && !force_download) {
    return(pointer_path)
  }

  if (fs::file_exists(blob_path) && !force_download) {
    fs::link_create(blob_path, pointer_path)
    return(pointer_path)
  }

  withr::with_tempfile("tmp", {
    lock <- filelock::lock(paste0(blob_path, ".lock"))
    on.exit({filelock::unlock(lock)})
    tryCatch({
      bar_id <- cli::cli_progress_bar(
        name = filename,
        total = if (is.numeric(expected_size)) expected_size else NA,
        type = "download",
      )
      progress <- function(down, up) {
        if (down[1] != 0) {
          cli::cli_progress_update(total = down[1], set = down[2], id = bar_id)
        }
        TRUE
      }
      handle <- curl::new_handle(noprogress = FALSE, progressfunction = progress)
      curl::handle_setheaders(handle, .list = hub_headers())
      curl::curl_download(url, tmp, handle = handle, quiet = FALSE)
      cli::cli_progress_done(id = bar_id)
    }, error = function(err) {
      cli::cli_abort("Error downloading from {.url {url}}", parent = err)
    })
    fs::file_move(tmp, blob_path)

    # fs::link_create doesn't work for linking files on windows.
    try(fs::file_delete(pointer_path), silent = TRUE) # delete the link to avoid warnings
    file.symlink(blob_path, pointer_path)
  })

  pointer_path
}

hub_url <- function(repo_id, filename, ..., revision = "main", repo_type = "model") {
  if (repo_type == "model") {
    glue::glue("https://huggingface.co/{repo_id}/resolve/{revision}/{filename}")
  } else {
    glue::glue("https://huggingface.co/{repo_type}s/{repo_id}/resolve/{revision}/{filename}")
  }
}

get_pointer_path <- function(storage_folder, revision, relative_filename) {
  snapshot_path <- fs::path(storage_folder, "snapshots", revision)
  pointer_path <- fs::path(snapshot_path, relative_filename)
  attr(pointer_path, "snapshot_path") <- snapshot_path
  pointer_path
}

repo_folder_name <- function(repo_id, repo_type = "model") {
  repo_id <- gsub(pattern = "/", x = repo_id, replacement = REPO_ID_SEPARATOR())
  glue::glue("{repo_type}s{REPO_ID_SEPARATOR()}{repo_id}")
}

hub_headers <- function() {
  headers <- c("user-agent" = "hfhub/0.0.1")

  token <- Sys.getenv("HUGGING_FACE_HUB_TOKEN", unset = "")
  if (!nzchar(token))
    token <- Sys.getenv("HUGGINGFACE_HUB_TOKEN", unset = "")

  if (nzchar(token)) {
    headers["authorization"] <- paste0("Bearer ", token)
  }

  headers
}

#' @importFrom rlang %||%
get_file_metadata <- function(url) {

  headers <- hub_headers()
  headers["Accept-Encoding"] <- "identity"

  req <- reqst(httr::HEAD,
    url = url,
    httr::config(followlocation = FALSE),
    httr::add_headers(.headers = headers),
    follow_relative_redirects = TRUE
  )
  list(
    location = grab_from_headers(req, "location") %||% req$url,
    commit_hash = grab_from_headers(req, "x-repo-commit"),
    etag = normalize_etag(grab_from_headers(req, c(HUGGINGFACE_HEADER_X_LINKED_ETAG(), "etag"))),
    size = as.integer(grab_from_headers(req, "content-length"))
  )
}

grab_from_headers <- function(req, nms) {
  headers <- req$all_headers
  for (nm in nms) {
    nm <- tolower(nm)

    for(h in headers) {
      header <- h$headers
      names(headers) <- tolower(headers)

      if (!is.null(header[[nm]]))
        return(header[[nm]])
    }
  }
  NULL
}

normalize_etag <- function(etag) {
  if (is.null(etag)) return(NULL)
  etag <- gsub(pattern = '"', x = etag, replacement = "")
  etag <- gsub(pattern = "W/", x = etag, replacement = "")
  etag
}

REPO_ID_SEPARATOR <- function() {
  "--"
}
HUGGINGFACE_HUB_CACHE <- function() {
  # we use the same cache structure as the Python library - which is useful for
  # numerous reasons. Thus we don't use R's tools for cache handling such as
  # rappdirs or R_user_dir.
  path <- Sys.getenv("HUGGINGFACE_HUB_CACHE", "~/.cache/huggingface/hub")
  fs::path_expand(path)
}
REGEX_COMMIT_HASH <- function() {
  "^[0-9a-f]{40}$"
}

#' Weight file names in HUB
#'
#' @describeIn WEIGHTS_NAME Name of weights file
#'
#' @returns A string with the default file names for indexes in the Hugging Face Hub.
#' @examples
#' WEIGHTS_NAME()
#' WEIGHTS_INDEX_NAME()
#' @export
WEIGHTS_NAME <- function() "pytorch_model.bin"
#' @export
#' @describeIn WEIGHTS_NAME Name of weights index file
WEIGHTS_INDEX_NAME <- function() "pytorch_model.bin.index.json"

HUGGINGFACE_HEADER_X_LINKED_ETAG <- function() "X-Linked-Etag"

reqst <- function(method, url, ..., follow_relative_redirects = FALSE) {
  if (follow_relative_redirects) {
    r <- reqst(method, url, ..., follow_relative_redirects = FALSE)
    if (r$status_code >= 300 && r$status_code <= 399) {
      redirect_url <- urltools::url_parse(httr::headers(r)$location)
      if (is.na(redirect_url$domain)) {
        p <- urltools::url_parse(url)
        p$path <- redirect_url$path
        url <- urltools::url_compose(p)
        return(reqst(method, url, ..., follow_relative_redirects = TRUE))
      }
    }
  }
  method(url, ...)
}

utils::globalVariables("tmp")


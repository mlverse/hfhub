#' Upload files to a Hugging Face repository
#'
#' Uploads a file or a whole directory to a repository on the Hugging Face
#' Hub over the HTTP(S) LFS protocol - no `git` or `git-lfs` binary
#' required. Large files (safetensors, bin, etc.) are stored with Git LFS
#' via presigned S3 uploads (single-part below 5 GB, multipart above);
#' small files ride inline in the commit.
#'
#' @param repo_id The repository identifier, e.g. `"username/repo"`.
#' @param path Path to a local file or directory to upload.
#' @param path_in_repo Destination path within the repository. For a
#'   directory upload this is the destination folder (default: repo
#'   root); for a single file it is the destination path (default: the
#'   file's basename).
#' @param ... Currently unused.
#' @param repo_type The repository type: `"model"` (default), `"dataset"`
#'   or `"space"`.
#' @param revision The branch to commit to (default `"main"`).
#' @param commit_message Commit summary. A sensible default is generated.
#' @param commit_description Longer commit description (optional).
#' @param token A Hugging Face token with write access. Defaults to the
#'   `HF_TOKEN` / `HUGGING_FACE_HUB_TOKEN` / `HUGGINGFACE_HUB_TOKEN`
#'   environment variables.
#'
#' @return Invisibly, the list of repository paths that were committed.
#'
#' @examples
#' \dontrun{
#' hub_upload("username/model", "model.safetensors")
#' hub_upload("username/dataset", "local_dir", repo_type = "dataset")
#' }
#'
#' @export
hub_upload <- function(repo_id, path, path_in_repo = NULL, ...,
                       repo_type = c("model", "dataset", "space"),
                       revision = "main", commit_message = NULL,
                       commit_description = "", token = hub_token()) {
  repo_type <- match.arg(repo_type)
  if (!nzchar(token)) {
    cli::cli_abort(c("A Hugging Face token with write access is required.",
      "i" = "Pass {.arg token} or set the {.envvar HF_TOKEN} environment variable."))
  }
  path <- normalizePath(path, mustWork = TRUE)

  # resolve the local files and their destination paths in the repo
  if (fs::is_dir(path)) {
    files <- list.files(path, recursive = TRUE, full.names = TRUE)
    files <- files[!fs::is_dir(files)]
    rel <- fs::path_rel(files, path)
    repo_paths <- if (!is.null(path_in_repo)) fs::path(path_in_repo, rel) else rel
  } else {
    files <- path
    repo_paths <- path_in_repo %||% basename(path)
  }
  files <- as.character(files)
  repo_paths <- as.character(repo_paths)

  # classify + hash
  sizes <- file.size(files)
  is_lfs <- sizes >= LFS_THRESHOLD | grepl(LFS_EXTENSIONS, files, ignore.case = TRUE)
  oids <- vapply(seq_along(files), function(i) if (is_lfs[i])
    digest::digest(file = files[i], algo = "sha256") else NA_character_,
    character(1))

  # upload LFS objects, then commit (LFS refs + inline small files)
  upload_lfs_objects(repo_id, files[is_lfs], oids[is_lfs], sizes[is_lfs],
    repo_type = repo_type, revision = revision, token = token)

  operations <- lapply(seq_along(files), function(i) {
    if (is_lfs[i]) {
      list(key = "lfsFile", value = list(path = repo_paths[i], algo = "sha256",
        oid = oids[i], size = sizes[i]))
    } else {
      list(key = "file", value = list(path = repo_paths[i], encoding = "base64",
        content = jsonlite::base64_enc(readBin(files[i], "raw", sizes[i]))))
    }
  })
  if (is.null(commit_message)) {
    commit_message <- sprintf("Upload %d file%s with hfhub", length(files),
      if (length(files) == 1) "" else "s")
  }
  hub_commit(repo_id, operations, repo_type = repo_type, revision = revision,
    commit_message = commit_message, commit_description = commit_description,
    token = token)
  invisible(repo_paths)
}

#' Delete files from a Hugging Face repository
#'
#' @inheritParams hub_upload
#' @param paths Character vector of repository paths to delete.
#'
#' @return Invisibly, `paths`.
#'
#' @examples
#' \dontrun{
#' hub_delete("username/model", "old_weights.safetensors")
#' }
#'
#' @export
hub_delete <- function(repo_id, paths, ...,
                       repo_type = c("model", "dataset", "space"),
                       revision = "main", commit_message = NULL,
                       token = hub_token()) {
  repo_type <- match.arg(repo_type)
  if (!nzchar(token)) {
    cli::cli_abort("A Hugging Face token with write access is required.")
  }
  operations <- lapply(paths, function(p)
    list(key = "deletedFile", value = list(path = p)))
  if (is.null(commit_message)) {
    commit_message <- sprintf("Delete %d file%s with hfhub", length(paths),
      if (length(paths) == 1) "" else "s")
  }
  hub_commit(repo_id, operations, repo_type = repo_type, revision = revision,
    commit_message = commit_message, token = token)
  invisible(paths)
}

# ---- internals -------------------------------------------------------------

LFS_THRESHOLD <- 10 * 1024^2  # HF stores files >= 10 MB with LFS
LFS_EXTENSIONS <- paste0("\\.(safetensors|bin|pt|pth|ckpt|h5|onnx|msgpack|",
  "npz|npy|gguf|tflite|arrow|parquet|pickle|model|tar|gz|zip|7z|wasm)$")

# token, matching hfhub's env-var precedence plus HF_TOKEN
hub_token <- function() {
  for (v in c("HF_TOKEN", "HUGGING_FACE_HUB_TOKEN", "HUGGINGFACE_HUB_TOKEN")) {
    tok <- Sys.getenv(v, unset = "")
    if (nzchar(tok)) return(tok)
  }
  ""
}

upload_auth <- function(token, ...) {
  c(list(Authorization = paste("Bearer", token)), list(...))
}

# cli_abort with the response body on any non-2xx (HF messages are useful)
check_response <- function(resp, what) {
  if (httr::status_code(resp) >= 300) {
    body <- substr(httr::content(resp, as = "text", encoding = "UTF-8"), 1, 600)
    cli::cli_abort(c("{what} failed (HTTP {httr::status_code(resp)}).",
      "x" = "{body}"))
  }
  resp
}

repo_prefix <- function(repo_type) {
  switch(repo_type, model = "", dataset = "datasets/", space = "spaces/")
}

# Register + upload the LFS objects for `files`, skipping any the server
# already has (content-addressed dedup).
upload_lfs_objects <- function(repo_id, files, oids, sizes, repo_type,
                               revision, token) {
  if (!length(files)) return(invisible())
  batch_url <- glue::glue(
    "https://huggingface.co/{repo_prefix(repo_type)}{repo_id}.git/info/lfs/objects/batch")
  body <- list(operation = "upload", transfers = list("multipart", "basic"),
    hash_algo = "sha256", ref = list(name = revision),
    objects = unname(Map(function(o, s) list(oid = o, size = s), oids, sizes)))
  resp <- httr::POST(batch_url, body = jsonlite::toJSON(body, auto_unbox = TRUE),
    do.call(httr::add_headers, upload_auth(token,
      Accept = "application/vnd.git-lfs+json",
      `Content-Type` = "application/vnd.git-lfs+json")))
  check_response(resp, "LFS batch")
  # git-lfs replies as application/vnd.git-lfs+json (httr won't auto-parse)
  batch <- jsonlite::fromJSON(httr::content(resp, as = "text",
    encoding = "UTF-8"), simplifyVector = FALSE)

  by_oid <- stats::setNames(seq_along(oids), oids)
  for (obj in batch$objects) {
    i <- by_oid[[obj$oid]]
    up <- obj$actions$upload
    if (is.null(up)) next  # already present
    if (!is.null(up$header) && !is.null(up$header[["chunk_size"]])) {
      upload_lfs_multipart(files[i], up, obj$oid, token)
    } else {
      hdr <- if (!is.null(up$header)) unlist(up$header) else character(0)
      check_response(httr::PUT(up$href, body = httr::upload_file(files[i]),
        httr::add_headers(.headers = hdr)), "LFS upload")
    }
  }
  invisible()
}

# Multipart: PUT each chunk to its presigned part URL, collect ETags,
# POST complete_multipart to finalize.
upload_lfs_multipart <- function(file, up, oid, token) {
  chunk_size <- as.numeric(up$header[["chunk_size"]])
  part_keys <- sort(grep("^[0-9]+$", names(up$header), value = TRUE))
  con <- file(file, "rb")
  on.exit(close(con))
  parts <- lapply(part_keys, function(k) {
    chunk <- readBin(con, "raw", n = chunk_size)
    pr <- check_response(httr::PUT(up$header[[k]], body = chunk),
      paste0("LFS part ", k))
    list(partNumber = as.integer(k), etag = httr::headers(pr)[["etag"]])
  })
  check_response(httr::POST(up$href,
    body = jsonlite::toJSON(list(oid = oid, parts = parts), auto_unbox = TRUE),
    do.call(httr::add_headers, upload_auth(token,
      `Content-Type` = "application/json"))),
    "complete multipart")
}

# Post an NDJSON commit (a header line plus one line per operation).
hub_commit <- function(repo_id, operations, repo_type, revision,
                       commit_message, commit_description = "", token) {
  commit_url <- glue::glue(
    "https://huggingface.co/api/{repo_type}s/{repo_id}/commit/{revision}")
  header <- list(key = "header", value = list(summary = commit_message,
    description = commit_description))
  lines <- vapply(c(list(header), operations),
    function(x) jsonlite::toJSON(x, auto_unbox = TRUE), character(1))
  resp <- httr::POST(commit_url, body = paste(lines, collapse = "\n"),
    do.call(httr::add_headers, upload_auth(token,
      `Content-Type` = "application/x-ndjson")))
  check_response(resp, "commit")
  invisible(jsonlite::fromJSON(httr::content(resp, as = "text",
    encoding = "UTF-8"), simplifyVector = FALSE))
}

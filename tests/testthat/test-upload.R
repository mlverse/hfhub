test_that("hub_token resolves the env-var precedence", {
  withr::with_envvar(c(HF_TOKEN = "a", HUGGING_FACE_HUB_TOKEN = "b",
    HUGGINGFACE_HUB_TOKEN = "c"), expect_equal(hub_token(), "a"))
  withr::with_envvar(c(HF_TOKEN = "", HUGGING_FACE_HUB_TOKEN = "b"),
    expect_equal(hub_token(), "b"))
  withr::with_envvar(c(HF_TOKEN = "", HUGGING_FACE_HUB_TOKEN = "",
    HUGGINGFACE_HUB_TOKEN = ""), expect_equal(hub_token(), ""))
})

test_that("upload without a token errors clearly", {
  withr::with_envvar(c(HF_TOKEN = "", HUGGING_FACE_HUB_TOKEN = "",
    HUGGINGFACE_HUB_TOKEN = ""),
    expect_error(hub_upload("x/y", tempfile()), "token"))
})

test_that("repo_prefix maps repo types", {
  expect_equal(repo_prefix("model"), "")
  expect_equal(repo_prefix("dataset"), "datasets/")
  expect_equal(repo_prefix("space"), "spaces/")
})

# 12 synthetic parts, no bytes uploaded: the ordering is pure header
# bookkeeping, so it is testable without a multi-hundred-MB file. Under
# the old sort() this returned 1, 10, 11, 12, 2, 3, ... and every chunk
# past the first went to the wrong presigned URL.
test_that("multipart part keys order numerically, not lexicographically", {
  header <- c(list(chunk_size = "10485760"),
    stats::setNames(as.list(paste0("https://s3/part", 1:12)),
      as.character(1:12)))
  keys <- lfs_part_keys(header)
  expect_equal(keys, as.character(1:12))
  expect_equal(as.integer(keys), 1:12)
  expect_false(identical(keys, sort(as.character(1:12))))  # the old behaviour
  # chunk_size and any other non-numeric header name stays out
  expect_false("chunk_size" %in% keys)
})

test_that("an LFS batch error aborts instead of reading as dedup", {
  failed <- list(oid = "abc123",
    error = list(code = 422, message = "Object is invalid"))
  expect_error(lfs_upload_action(failed), "abc123")
  expect_error(lfs_upload_action(failed), "Object is invalid")

  # no actions and no error really does mean the server already has it
  expect_null(lfs_upload_action(list(oid = "abc123")))
  # and a normal upload action comes back untouched
  act <- list(href = "https://s3/put", header = list(a = "b"))
  expect_equal(lfs_upload_action(list(oid = "abc123",
    actions = list(upload = act))), act)
})

test_that("empty uploads and deletions are refused, not sent as empty commits", {
  dir <- withr::local_tempdir()
  expect_error(hub_upload("x/y", dir, token = "t"), "Nothing to upload")

  # a directory holding only git metadata is equally empty as far as the
  # Hub is concerned
  dir.create(file.path(dir, ".git"))
  writeLines("cfg", file.path(dir, ".git", "config"))
  expect_error(hub_upload("x/y", dir, token = "t"), "Nothing to upload")

  expect_error(hub_delete("x/y", character(0), token = "t"), "empty")
})

test_that("directory uploads carry dotfiles but never .git", {
  dir <- withr::local_tempdir()
  writeLines("a", file.path(dir, "a.txt"))
  writeLines("attrs", file.path(dir, ".gitattributes"))
  dir.create(file.path(dir, ".git"))
  writeLines("cfg", file.path(dir, ".git", "config"))

  listed <- list.files(dir, recursive = TRUE, full.names = TRUE,
    all.files = TRUE)
  listed <- listed[!fs::is_dir(listed)]
  kept <- basename(listed[!grepl("(^|/)\\.git/", listed)])
  expect_true(".gitattributes" %in% kept)
  expect_true("a.txt" %in% kept)
  expect_false("config" %in% kept)
})

# Live round-trip: set HFHUB_TEST_UPLOAD_REPO to a repo you can write to
# (plus a write token), otherwise skipped. Exercises inline + LFS files
# (a .safetensors is LFS by extension even when tiny), then cleans up.
test_that("upload + delete round-trip on the Hub", {
  skip_on_cran()
  repo <- Sys.getenv("HFHUB_TEST_UPLOAD_REPO", "")
  repo_type <- Sys.getenv("HFHUB_TEST_UPLOAD_TYPE", "model")
  skip_if(!nzchar(repo) || !nzchar(hub_token()),
    "set HFHUB_TEST_UPLOAD_REPO and a write token to run")

  dir <- withr::local_tempdir()
  writeLines("hello from hfhub", file.path(dir, "readme.txt"))     # inline
  writeBin(as.raw(0:255), file.path(dir, "tiny.safetensors"))      # LFS by ext

  paths <- hub_upload(repo, dir, path_in_repo = "_hfhub_test",
    repo_type = repo_type, commit_message = "hfhub upload test")
  # Register cleanup the moment the files exist. Deleting at the end of
  # the block leaks _hfhub_test onto a real repo whenever an assertion
  # below fails, which is exactly when someone is debugging.
  withr::defer(try(hub_delete(repo, paths, repo_type = repo_type,
    commit_message = "hfhub upload test cleanup"), silent = TRUE))
  expect_setequal(paths, c("_hfhub_test/readme.txt", "_hfhub_test/tiny.safetensors"))

  # both land, and the LFS oid matches
  info_url <- glue::glue(
    "https://huggingface.co/api/{repo_type}s/{repo}/tree/main/_hfhub_test")
  tree <- jsonlite::fromJSON(httr::content(httr::GET(info_url,
    do.call(httr::add_headers, upload_auth(hub_token()))), as = "text"),
    simplifyVector = FALSE)
  remote <- vapply(tree, function(e) e$path, character(1))
  expect_true(all(paths %in% remote))
  lfs <- Filter(function(e) !is.null(e$lfs), tree)[[1]]
  expect_equal(lfs$lfs$oid,
    digest::digest(file = file.path(dir, "tiny.safetensors"), algo = "sha256"))
})

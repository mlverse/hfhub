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

  hub_delete(repo, paths, repo_type = repo_type,
    commit_message = "hfhub upload test cleanup")
})

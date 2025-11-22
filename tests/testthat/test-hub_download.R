skip_on_cran()

test_that("hub_download", {
  withr::local_envvar(list(HF_HUB_DISABLE_SYMLINKS_WARNING = "1"))

  file <- hub_download("gpt2", filename = "config.json")

  expect_equal(
    jsonlite::fromJSON(file)$architectures,
    "GPT2LMHeadModel"
  )

  file <- hub_download("gpt2", filename = "config.json", force_download = TRUE)
  expect_equal(
    jsonlite::fromJSON(file)$architectures,
    "GPT2LMHeadModel"
  )

  file <- hub_download("gpt2", filename = "config.json", local_files_only = TRUE)
  expect_equal(
    jsonlite::fromJSON(file)$architectures,
    "GPT2LMHeadModel"
  )

  tmp <- tempfile()
  dir.create(tmp)
  withr::with_envvar(c(HUGGINGFACE_HUB_CACHE = tmp), {
    file <- hub_download("gpt2", filename = "config.json")
  })
  expect_equal(list.files(tmp), "models--gpt2")
  # Make sure the config.json exists (detect broken symlink support in Windows)
  expect_length(
    Sys.glob(file.path(tmp, "models--gpt2", "snapshots", "*", "config.json")),
    1
  )
})

test_that("can download from private repo", {

  skip_if_no_token()

  expect_error(regexp = NA, {
    hub_download(
      repo_id = "dfalbel/test-hfhub",
      filename = ".gitattributes",
      force_download = TRUE
    )
  })

  expect_error(regexp = NA, {
    hub_download(
      repo_id = "dfalbel/test-hfhub",
      filename = "hello.safetensors",
      force_download = TRUE
    )
  })

})

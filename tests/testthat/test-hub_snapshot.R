skip_on_cran()

test_that("snapshot", {
  expect_snapshot({
    p <- hub_snapshot("dfalbel/cran-packages", repo_type = "dataset", allow_patterns = "\\.R")
  },
  transform = function(x) {
    sub("\\[[0-9\\.]+[a-z]+\\]", "[0ms]", x = x)
  })

  expect_true(length(fs::dir_ls(p)) >= 4)
})

test_that("can snapshot private repositories", {

  skip_if_no_token()

  expect_error(regexp=NA, {
    hub_snapshot("dfalbel/test-hfhub", repo_type = "model", force_download = TRUE)
  })

})

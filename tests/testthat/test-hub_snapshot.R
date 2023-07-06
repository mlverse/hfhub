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

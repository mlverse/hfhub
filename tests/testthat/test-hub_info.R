skip_on_cran()

test_that("dataset info", {
  info <- hub_dataset_info("dfalbel/cran-packages")
  expect_equal(info$author, "dfalbel")
  expect_true(length(info$siblings) >= 13)
})

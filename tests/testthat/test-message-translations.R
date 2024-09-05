test_that("R-level cli_abort messages are correctly translated in FR", {
  skip_if_no_token()
  withr::with_envvar(c(HUGGINGFACE_HUB_CACHE = tempdir()), {
    try({
      withr::with_language(
        lang = "fr",
        expect_error(
          hub_download(
            repo_id = "dfalbel/test-hfh",
            filename = ".gitattributes",
            force_download = TRUE
          ),
          regexp = "La ressource ne semble pas être disponible sur",
        )

      )
    })
  })

})

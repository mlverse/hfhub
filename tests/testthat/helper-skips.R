skip_if_no_token <- function() {
  token <- Sys.getenv("HUGGINGFACE_HUB_TOKEN", "")
  if (token == "") {
    token <- Sys.getenv("HUGGING_FACE_HUB_TOKEN", "")
  }

  if (token == "")
    skip("No auth token set.")
}

# Snapshot the entire repository

Downloads and stores all files from a Hugging Face Hub repository.

## Usage

``` r
hub_snapshot(
  repo_id,
  ...,
  revision = "main",
  repo_type = "model",
  local_files_only = FALSE,
  force_download = FALSE,
  allow_patterns = NULL,
  ignore_patterns = NULL
)
```

## Arguments

- repo_id:

  The repository identifier, eg `"bert-base-uncased"` or
  `"deepset/sentence_bert"`.

- ...:

  currenytly unused.

- revision:

  Revision (branch, tag or commitid) to download the file from.

- repo_type:

  The type of the repository. Currently only `"model"` is supported.

- local_files_only:

  Only use cached files?

- force_download:

  For re-downloading of files that are cached.

- allow_patterns:

  A character vector containing patters that are used to filter allowed
  files to snapshot.

- ignore_patterns:

  A character vector contaitning patterns to reject files from being
  downloaded.

## Value

A string with the path to the snapshot directory containing all
downloaded files.

## Examples

``` r
try({
withr::with_envvar(c(HUGGINGFACE_HUB_CACHE = tempdir()), {
path <- hub_snapshot("gpt2", allow_patterns = "config.json")
list.files(path)
})
})
#> ℹ Snapshotting files 0/6
#> ✔ Snapshotting files 6/6 [326ms]
#> 
#> [1] "config.json"            "generation_config.json" "onnx"                  
#> [4] "tokenizer_config.json" 
```

# Queries information about Hub repositories

Queries information about Hub repositories

## Usage

``` r
hub_repo_info(
  repo_id,
  ...,
  repo_type = NULL,
  revision = NULL,
  files_metadata = FALSE
)

hub_dataset_info(repo_id, ..., revision = NULL, files_metadata = FALSE)
```

## Arguments

- repo_id:

  The repository identifier, eg `"bert-base-uncased"` or
  `"deepset/sentence_bert"`.

- ...:

  currenytly unused.

- repo_type:

  The type of the repository. Currently only `"model"` is supported.

- revision:

  Revision (branch, tag or commitid) to download the file from.

- files_metadata:

  Obtain files metadata information when querying repository
  information.

## Functions

- `hub_dataset_info()`: Query information from a Hub Dataset

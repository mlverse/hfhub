
# hfhub

<!-- badges: start -->
[![R-CMD-check](https://github.com/mlverse/hfhub/actions/workflows/R-CMD-check.yaml/badge.svg)](https://github.com/mlverse/hfhub/actions/workflows/R-CMD-check.yaml)
<!-- badges: end -->

hfhub is a minimal port of [huggingface_hub](https://github.com/huggingface/huggingface_hub) that allows downloading files from Hugging Face Hub and caching them with the same structure used in the original implementation.

## Installation

`hfhub` can be installed from CRAN with:

```
install.packages("hfhub")
```

You can install the development version of hfhub like so:

``` r
remotes::install_github("mlverse/hfhub")
```

## Example

`hub_download` the the only exported function in the package and can be used to
download and cache a file from any Hugging Face Hub repository. It returns a
path to the file.

``` r
library(hfhub)
path <- hub_download("gpt2", "config.json")
str(jsonlite::fromJSON(path))
```

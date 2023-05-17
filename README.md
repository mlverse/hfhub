
# hfhub

<!-- badges: start -->
<!-- badges: end -->

hfhub is a minimal port of [huggingface_hub](https://github.com/huggingface/huggingface_hub) and allows downloading files from HuggingFace Hub and caching them with the same structure the Python
counterpart. 

## Installation

You can install the development version of hfhub like so:

``` r
remotes::install_github("mlverse/hfhub")
```

## Example

This is a basic example which shows you how to solve a common problem:

``` r
library(hfhub)
path <- hub_download("gpt2", "config.json")
str(jsonlite::fromJSON(path))
```

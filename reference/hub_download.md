# Downloads files from HuggingFace repositories

Downloads files from HuggingFace repositories

## Usage

``` r
hub_download(
  repo_id,
  filename,
  ...,
  revision = "main",
  repo_type = "model",
  local_files_only = FALSE,
  force_download = FALSE
)
```

## Arguments

- repo_id:

  The repository identifier, eg `"bert-base-uncased"` or
  `"deepset/sentence_bert"`.

- filename:

  Filename to download from the repository. Example `"config.json"`.

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

## Value

The file path of the downloaded or cached file. The snapshot path is
returned as an attribute.

## Examples

``` r
try({
withr::with_envvar(c(HUGGINGFACE_HUB_CACHE = tempdir()), {
path <- hub_download("gpt2", "config.json")
print(path)
str(jsonlite::fromJSON(path))
})
})
#> /tmp/RtmpAF05fw/models--gpt2/snapshots/607a30d783dfa663caf39e06633721c8d4cfcd7e/config.json
#> List of 22
#>  $ activation_function   : chr "gelu_new"
#>  $ architectures         : chr "GPT2LMHeadModel"
#>  $ attn_pdrop            : num 0.1
#>  $ bos_token_id          : int 50256
#>  $ embd_pdrop            : num 0.1
#>  $ eos_token_id          : int 50256
#>  $ initializer_range     : num 0.02
#>  $ layer_norm_epsilon    : num 1e-05
#>  $ model_type            : chr "gpt2"
#>  $ n_ctx                 : int 1024
#>  $ n_embd                : int 768
#>  $ n_head                : int 12
#>  $ n_layer               : int 12
#>  $ n_positions           : int 1024
#>  $ resid_pdrop           : num 0.1
#>  $ summary_activation    : NULL
#>  $ summary_first_dropout : num 0.1
#>  $ summary_proj_to_labels: logi TRUE
#>  $ summary_type          : chr "cls_index"
#>  $ summary_use_proj      : logi TRUE
#>  $ task_specific_params  :List of 1
#>   ..$ text-generation:List of 2
#>   .. ..$ do_sample : logi TRUE
#>   .. ..$ max_length: int 50
#>  $ vocab_size            : int 50257
```

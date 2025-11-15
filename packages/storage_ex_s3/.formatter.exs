[
  import: [Path.expand("../../.formatter.exs", __DIR__)],
  inputs: [
    "{mix,.formatter}.exs",
    "{config,lib,test}/**/*.{ex,exs}"
  ]
]

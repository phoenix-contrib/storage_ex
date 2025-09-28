[
  import: [Path.expand("../../.formatter.exs", __DIR__)],
  import_deps: [:phoenix, :plug],
  inputs: [
    "{mix,.formatter}.exs",
    "{config,lib,test}/**/*.{ex,exs}"
  ]
]

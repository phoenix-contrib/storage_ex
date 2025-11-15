[
  import: [Path.expand("../../.formatter.exs", __DIR__)],
  import_deps: [:ecto, :ecto_sql, :phoenix],
  inputs: [
    "{mix,.formatter}.exs",
    "{config,lib,test}/**/*.{ex,exs}"
  ]
]

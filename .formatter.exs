[
  import_deps: [:ecto, :ecto_sql, :oban, :plug],
  inputs: [
    "{mix,.formatter}.exs",
    "{config,lib,test}/**/*.{ex,exs}",
    "priv/repo/migrations_infra/*.exs"
  ],
  subdirectories: ["components/substrate"]
]

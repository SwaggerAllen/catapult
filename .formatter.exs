[
  # `:phoenix` and `:phoenix_live_view` are imported for the macros
  # design authors under `storybook/**` — `attr`/`slot` and the `~H`
  # sigil format as markup rather than being reflowed as ordinary
  # calls, which is the difference between a readable component and a
  # diff nobody can review.
  import_deps: [:ecto, :ecto_sql, :oban, :phoenix, :phoenix_live_view, :plug],
  inputs: [
    "{mix,.formatter}.exs",
    "{config,lib,storybook,test}/**/*.{ex,exs}",
    "priv/repo/migrations_infra/*.exs"
  ],
  subdirectories: ["components/substrate"]
]

# `:live` tests cross a real network to the deployed reference instance,
# so they are excluded here and run only at the milestone boundary
# (conventions §9's one unconditional rule: no network in per-ticket CI,
# ever). `mix test --only live` re-includes them — that is the entire
# cadence mechanism, and it is why the boundary's command needs no
# project-specific flag (systems/foundation.md).
ExUnit.start(exclude: [:live])
Ecto.Adapters.SQL.Sandbox.mode(Catapult.Repo, :manual)

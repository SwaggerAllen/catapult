# `:live` tests cross a real network to the deployed reference instance,
# so they are excluded here and run only at the milestone boundary
# (conventions §9's one unconditional rule: no network in per-ticket CI,
# ever). `mix test --only live` re-includes them — that is the entire
# cadence mechanism, and it is why the boundary's command needs no
# project-specific flag (systems/foundation.md).
#
# `:live_todo_app_proof` is the same discipline for a second, disjoint
# reason: not only does it cross the network, but running it in the
# same `mix test --only live` batch as the boundary suite would race
# it for the one `:active` test-project slot
# (`Catapult.Generation.TodoAppProofLiveTest`'s own moduledoc,
# `systems/delivery.md`'s ORC-216 entry). Excluded by default here,
# re-included on its own by `mix test --only live_todo_app_proof` —
# the command `docs/build-plan.md`'s Phase 5 section names as still
# needing a `pipeline-live-suite.yml` dispatch input to select it.
ExUnit.start(exclude: [:live, :live_todo_app_proof])
Ecto.Adapters.SQL.Sandbox.mode(Catapult.Repo, :manual)

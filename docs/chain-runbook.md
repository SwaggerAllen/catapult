# Chain runbook (author, hand-driven)

**Deliberately temporary.** This is not the product interface —
Phase 4 builds that (`docs/build-plan.md`: tracker + host ports,
states projected to Linear, PR-based review). Until then, this is
how an author drives a chain run by hand against the toy seed, reads
what it produced, and resets the fixture repo. Every command below
runs from this repo's root, with a Postgres reachable the way
`config/test.exs` expects (`PGHOST`/`PGUSER`/`PGPASSWORD`, database
`catapult_test` — the same environment `mix test` itself uses).

## What the toy seed is

`test/catapult/generation/fixtures/toy_seed/` (`Catapult.ToySeed`):
a small internal link-shortener ("Signpost") with input documents in
every registered role (`project_doc`, `non_goals`, `behavior_docs`,
`mocks`, `invariants`, `capability_inventories`,
`forward_strategies` — the intake role list named across
`docs/dsl-syntax.md` §7.2 and `docs/v5-design-decisions.md`; there is
no code-level registry until Phase 5, so this list *is* the registry
for now) and a `catapult-dispatch.yml` workflow fixture, pushed
verbatim to the bound fixture repo (`SwaggerAllen/catapult-test`) by
`Catapult.Delivery.HostPort.reset_repo/2` — never placed at a real
`.github/workflows/**` path in *this* repo (agents' push tokens carry
no `workflow` scope; `systems/README.md`).

`test/catapult/generation/toy_seed_chain_test.exs` is the offline,
scripted version of everything below: read it before hand-driving
anything, since it names every tier and edge-type gap this seed's
content runs into (feature_expansion's `input.*` readiness gap, the
fanout-mint-identity gap, the third-tier-authored-edge gap, `ref`'s
scope-key gap — all in that test's own moduledoc, none fixed here).

## Driving a run offline (no network, no real agent)

The offline chain test *is* this — reading it end to end is the
fastest way to see the whole shape. To do the same thing from an
`iex -S mix` session instead, mirror the test's own sequence:

```elixir
{:ok, loaded} = Catapult.Dsl.load(".")
project_id = "hand-run-#{System.unique_integer([:positive])}"

# feature_expansion can't be *selected* by ReadyScopes today
# (input.project_doc never resolves — docs/non-goals.md's ORC-10
# entry) — build its candidate by hand, the same shape ReadyScopes
# would hand a dispatch worker if it could select it:
candidate = %Catapult.Engine.Store.Node{
  id: "virtual:feature_expansion:#{inspect(%{})}",
  project_id: project_id,
  tier: "feature_expansion",
  scope_key: %{},
  parent_node_id: nil,
  status: :absent
}

Application.put_env(:catapult, :fake_dispatch_result, fn _request ->
  %{
    status: :success,
    body: File.read!("test/catapult/generation/fixtures/toy_seed/feature_expansion.xml"),
    credential_used: "claude_code_oauth_token"
  }
end)

{:ok, request} =
  Catapult.Generation.ContextAssembly.build(loaded.chain, project_id, "feature_expansion", candidate)

{:ok, %{run_key: run_key}} = Catapult.Delivery.HostPort.Fake.dispatch_run(request)

Catapult.Engine.Store.get_node(project_id, "feature_expansion")
```

From there, every tier reachable by `Catapult.Engine.Projections
.ReadyScopes.ready/3` needs only `ContextAssembly.build/4` +
`HostPort.Fake.dispatch_run/1` with the matching canned body from
`test/catapult/generation/fixtures/toy_seed/*.xml` — the offline
test's own `ready_one!`/`commit!`/`review!`/`approve_real!` helpers
are the readable version of that loop.

## Driving a run live (real dispatch, real GitHub)

**Reset the bound repo first** — it has to carry
`.github/workflows/catapult-dispatch.yml` before GitHub accepts a
`workflow_dispatch` against it at all:

```elixir
Catapult.Delivery.Store.put_project_binding(project_id, "SwaggerAllen", "catapult-test")
Catapult.Delivery.HostPort.Actions.reset_repo(project_id, Catapult.ToySeed.reset_files())
```

This needs `DELIVERY_GITHUB_TOKEN` set to a real credential with
`Contents: read and write` on `SwaggerAllen/catapult-test`
(`systems/delivery.md`'s ORC-10 entry) — `config/test.exs` only
defaults it to a fake string, on purpose, so the offline suite never
needs one.

**Dispatch a real run** the same way the offline example built
`request` above, except through the real adapter:

```elixir
{:ok, %{run_key: run_key}} = Catapult.Delivery.HostPort.Actions.dispatch_run(request)
```

This *triggers* a real GitHub Actions run and returns as soon as
GitHub accepts the dispatch — it does not wait for the run to
finish (`test/catapult/generation/toy_seed_chain_live_test.exs`'s own
moduledoc: closing that loop from this process would write the
dispatch-run correlation row into a database the deployed instance's
own callback can never see, so nothing here can honestly poll for a
result — v5 §7.12.1's `catapult-dispatch.yml` fixture's own harness
step is itself an unpinned placeholder as of ORC-10, which is the
other reason a real run doesn't finish yet).

## Reading a run's output

- **The dispatch record**: `Catapult.Delivery.Store.get_dispatch_run(run_key)`
  — `status` (`:dispatched` / `:context_fetched` / `:completed` /
  `:failed`), `repo_owner`/`repo_name`, the `rendered_prompt` that was
  served.
- **On GitHub**: the triggered run lives under the bound repo's
  Actions tab (`workflow_dispatch` → `catapult-dispatch`), named by
  its own `run-name: "catapult dispatch: <run_key>"` — search by the
  `run_key` above.
- **A committed draft**: once a run reports success,
  `Catapult.Engine.Store.get_node(project_id, node_id).body_sha` and
  `Catapult.Delivery.get_draft_body(project_id, node_id)` — the same
  two reads the offline test's own assertions use.

## Resetting

Re-run the reset call above — it overwrites the bound repo's fixture
content from this repo's own `test/catapult/generation/fixtures/toy_seed/`
files again, unconditionally (`Catapult.Delivery.HostPort`'s own
moduledoc: idempotent, one file's failure doesn't roll back an
earlier one — re-running is the recovery). It never touches a
generated artifact; those live only in the plane's own store,
reached through `Catapult.Engine.Store`/`Catapult.Delivery` above,
never written back to the bound repo.

## What's missing here on purpose

- The pinned runner harness invocation inside `catapult-dispatch.yml`
  is a named placeholder, not a real one — `systems/generation.md`'s
  own standing decision is that this repo consumes orchestration's
  harness as a pinned dependency rather than reimplementing it, and
  that pin doesn't exist yet as of ORC-10. A real live run today gets
  as far as `report_result` with `other_failure` and stops there.
- Nothing here creates a project or binds a repo through any surface
  but direct `iex` calls — there is no dashboard, no CLI, no HTTP
  endpoint for either yet (Phase 4/7).

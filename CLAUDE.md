# Catapult — repo specifics

What only this repo can say. The pipeline protocol (roles, states,
markers, mutex, file maps) is injected into every agent run from the
pipeline checkout (`.pipeline/prompts/repo-context.md`) — none of it
is restated here, and where that file and this one disagree about
protocol, that file wins.

## What this is

The Catapult platform: an Elixir control plane (Commanded + Oban)
that runs a documentation-generation chain and a ticket-delivery
pipeline for the projects it builds. Design source of truth:
`docs/v5-design-decisions.md`. Build sequencing:
`docs/build-plan.md`. Coding rules with rationale:
`docs/conventions.md` — read it before writing code; every rule
carries its reason. Negative space: `docs/non-goals.md` — proposing
against it means arguing with a recorded decision, and saying so.
Architecture: `systems/*.md`, one doc per system with a file map.
DSL grammar: `docs/dsl-syntax.md` (normative; wins over the v4 spec).

## Toolchain

Pinned in `.tool-versions` (Elixir 1.17.3-otp-27 / OTP 27.2); CI
enforces it. Dep series are temporarily pinned to what an older
interim toolchain compiles (see the debt milestone) — don't bump
them piecemeal.

## Layout

- `lib/catapult/` — plane systems (see `systems/*.md` for the map).
- `components/substrate/` — the shipped platform substrate: a
  separate mix project, path-dep'd, **with its own test/format/credo
  suite that CI runs separately** — run both.
- `bundles/` — DSL bundle content (platform layer + default chain).
- `priv/repo/migrations_infra/` — infrastructure migrations
  (Oban, EventStore); per-store migrations compose in as stores land.

## Verification (run all before claiming done)

```
mix format --check-formatted
mix credo --strict
mix compile --warnings-as-errors     # boundary compiler is in the set
mix catapult.audit
mix test                             # needs Postgres; sandbox, async
cd components/substrate && mix format --check-formatted && \
  mix credo --strict && mix compile --warnings-as-errors && mix test
```

Tests: no network, ever (fakes per conventions §9); `mix test`
creates/migrates `catapult_test` via the alias. `:live`-tagged tests
run only at milestone boundaries — never add one to the default
suite path.

## Load-bearing invariants (the ones agents trip on)

- Every component adopts `use Catapult.Component` and registers its
  claims; the composer fails the boot **and** the audit on collision.
- Public functions on a component's boundary use `defexport`
  (telemetry rides it; permissions will).
- No `DateTime.utc_now` in domain code (inject `Catapult.Clock`);
  no bare `name: __MODULE__` (register via `processes/0`). The audit
  greps; `catapult:allow <check>` on the same line is the visible
  escape.
- The plane makes no LLM calls and holds no working copies —
  generation is dispatched agent runs (conventions §11). A model
  call in plane code is an architecture violation.
- Root artifacts (supervisor, routers) are composed from component
  declarations, never hand-edited.
- The license split is load-bearing (`LICENSING.md`):
  `components/**` and `bundles/**` are Apache-2.0 and ship into
  generated projects — never copy plane code (AGPL) into them and
  never add a copyleft dependency there. New files take their
  directory's license.

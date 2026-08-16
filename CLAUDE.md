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

Pinned in `.tool-versions` (Elixir 1.17.3-otp-27 / OTP 27.3.4 —
27.2 and earlier reject builds.hex.pm's TLS cert with
`key_usage_mismatch`); CI enforces it, and `mix.exs` floors match
(`~> 1.17`). Dep series ride current stable — the `deps.audit` gate
forced the bump the day it armed (the old interim pins are retired;
ORC-3's coherence pass, done ahead of the pipeline). An out-of-band
toolchain older than the pin cannot compile the deps; the pinned
toolchain is the only supported one.

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
mix deps.get --check-locked
mix deps.audit                       # hex.audit runs first, inside the alias
mix format --check-formatted
mix credo --strict
mix compile --warnings-as-errors     # boundary compiler is in the set
mix xref graph --format cycles --fail-above 0
mix xref graph --label compile-connected --fail-above 0   # the ratchet
mix catapult.audit                   # root project ONLY — see below
mix test                             # needs Postgres; sandbox, async
cd components/substrate && mix deps.get --check-locked && \
  mix hex.audit && mix format --check-formatted && \
  mix credo --strict && mix compile --warnings-as-errors && \
  mix xref graph --format cycles --fail-above 0 && \
  mix xref graph --label compile-connected --fail-above 0 && \
  mix catapult.audit && mix test
```

Both blocks are the whole of conventions §2, per project — not a
subset. The gate set is a property of a mix project, not of the repo
(`systems/substrate.md`): the audit's globs are rooted at the working
directory — deliberately, since the task ships into every generated
project — so `mix catapult.audit` at the root never sees
`components/substrate/lib/**`. Run it in both, or run
`mix catapult.audit.all` from the root, which is the alias that does
exactly that (and needs `components/substrate/deps` resolved; it exits
1 rather than skipping if they are not). A new mix project brings its
own gate block here.

The two blocks differ on one line only, and deliberately: the root's
`mix deps.audit` is an alias running `hex.audit` first and `mix_audit`
second (ORC-37), while substrate must not take an audit *dependency*
(`systems/substrate.md`), so there it is `mix hex.audit` on its own.

Every line in both blocks is armed in CI as of ORC-49 — `ci.yml`'s
`substrate suite` step carries the full set, and `qualityGates` runs
`mix catapult.audit.all` rather than the root-only task. So this block
is the local mirror of what CI runs, not the only thing running any of
it. The compile-connected line is v5 §2.14's second half (ORC-21); the
number's home is `pipeline.config.json` → `qualityGates` and `ci.yml`,
both author-owned by construction, which is what makes "raising it
needs a reviewed change" literal rather than aspirational and why a
ticket cannot arm or raise it (`docs/non-goals.md`,
`systems/foundation.md`). It is `0` in both projects; every later value
is a concession.

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
  no bare `name: __MODULE__` (register via `processes/0`); no
  unwrapped `Catapult.Config.Secret` inside a `Logger` call. The audit
  parses rather than greps (ORC-21), so a string that spells a ban is
  a string. The escape is a **comment** — `# catapult:allow <check>`,
  on the offending line or the comment line directly above it, and one
  written inside a string literal excuses nothing. A tag covering no
  violation is itself reported, so the escape list prunes itself.
- A `secret: true` config value comes back wrapped; `Catapult.Config
  .Secret.unwrap/1` at the call site is the only way to its contents,
  and it is meant to be visible in review.
- VM guardrails on `processes/0` are applied by the process, in
  `init/1`, via `Catapult.Guardrails.apply!/2` — the composer never
  threads them into a child spec, and the audit reports a guardrail
  declared and never applied. `max_heap_size:` is VM-enforced;
  `message_queue_alarm_len:` is sampled and reported, never enforced.
- An `errors/0` kind is built with the component's generated
  `use Catapult.Error` struct (`Engine.Error.new/2`), which is what
  makes the declaration the only vocabulary. The audit reports a kind
  declared and never constructed.
- An external application the plane calls is named in `lib/catapult.ex`
  `deps:` or the boundary compiler fails the build (the app list is in
  `mix.exs`). Pure Erlang applications cannot be restrained — that gap
  is `systems/foundation.md`'s and is deliberate, not forgotten.
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

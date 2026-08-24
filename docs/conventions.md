# Catapult — coding conventions and standards

The rules for code in this repository, each with its reason. This
document is written for every session — human or agent — that touches
the codebase; a rule without its rationale is a rule the next session
will violate reasonably (orchestration's style requirement, adopted
repo-wide). Design rationale at the system level lives in
`docs/v5-design-decisions.md` (*v5 §n*) and `systems/*.md`; this
document is the code-facing projection.

Catapult honors the v5 convention corpus on itself wherever the
convention doesn't presuppose the doc chain — because Catapult is
exactly the kind of app the corpus protects: an Elixir system
delivered by an unattended pipeline. Where a rule below restates v5
§2, that is deliberate: this file is what a working session reads.

---

## 1. Toolchain and dependencies

- **Elixir 1.17+ / OTP 27. Phoenix 1.8+, LiveView 1.2+.** Pin exact
  versions in `.tool-versions`; CI uses the same file. Rationale: one
  toolchain source of truth; drift between dev and CI is a class of
  flake we refuse to debug.
- **Adopted, blessed libraries** — use these, don't substitute
  without a systems-doc decision: **Commanded** (event sourcing),
  **Oban** (jobs), **Vapor** (config), **Boundary** (isolation),
  **libgraph** (graph checks), **Solid** (Liquid templates), **Req**
  (HTTP), **PromEx** (metrics), **FunWithFlags** (flags, when
  needed), **ex_machina** (factories). Rationale: every additional
  way to do the same thing is a review burden and a drift surface;
  the blessed list is small on purpose.
- **A new dependency is a decision, not a port** (v5 §2.8's rule).
  Name it in the ticket/sketch with its reason. `mix.lock` churn from
  transitive updates is accepted; new direct deps are not silent.
- Type checking: **the native set-theoretic checker, via
  warnings-as-errors** (v5 §2.13 — settled; Dialyzer stays out).
  Add typespecs on boundary exports, where they are documentation
  and now enforcement; don't add `@spec`s you don't maintain
  elsewhere.

## 2. Formatting, linting, compilation

All of these are CI gates from day one, because reconciliation trusts
green (v5 §2.13):

- `mix format --check-formatted` — no exceptions, no `# noqa`-style
  escape.
- `mix credo --strict` — disagreements with a check are resolved by
  config change in a reviewed commit, never by inline disable
  accumulation.
- `mix compile --warnings-as-errors` — a warning is a future bug
  report with the timestamp removed.
- `mix boundary` (via compiler) — see §4.
- Migration lint (safety checks) — see §6.
- `mix deps.get --check-locked` — lockfile integrity is a **hard**
  gate, never softened: a silently drifting lockfile is a supply
  surface and a reproducibility lie (v5 §2.14).
- `mix hex.audit` — **the supply gate**: known-vulnerable and retired
  deps blocked at the door; the plane's maintenance watcher handles
  what's already in. Built into Hex, so nothing is added to `deps` to
  get it, and its data rides the registry fetch `deps.get
  --check-locked` already made — a fetch it could not perform fails
  the build one step earlier instead of passing here. (Advisory data
  fetches like deps fetch — the no-network rule governs the test
  suite, not toolchain fetches.)
- `mix deps.audit` — **a second opinion, not the signal** (ORC-37).
  It reads the GitHub Advisory Database via a third-party git mirror,
  which is genuinely a different source and earned its keep the day
  it armed by catching the postgrex advisory (ORC-3) — so it stays.
  What it cannot see, verified against `cowlib 2.19.0` rather than
  assumed, and the reason it is no longer the gate:
  - **Retirement: never, at any version.** `mix_audit` has no
    retirement check at all. Until `hex.audit` joined the set, the
    line above claiming retired deps were blocked was false.
  - **Advisories with no patched release.** The mirror's range for
    `GHSA-g2wm-735q-3f56` stops at `<= 2.16.1` where the advisory
    says "affects from 2.9.0" with no fix, so 2.19.0 does not match.
  - **Advisories filed under another package.** `GHSA-w4f7-4cxr-rv3c`
    is filed under `gun`; a `cowlib` dependency never matches it.
  - **Its own fetch failing.** `MixAudit.Repo.synchronize/0` discards
    the `git clone`/`pull` exit status, then globs an empty directory
    — a failed clone prints "No vulnerabilities found." and exits 0.
    This is the one that decides it: a gate whose failure mode is a
    clean report is worse than no gate, because it converts "we
    check" into a false all-clear on the supply surface.
  Accepted residue, recorded so it is not rediscovered: an advisory
  that reaches the GitHub database and not Hex's feed, on a run where
  the mirror clone also failed, still reports clean.
- Advisories with **no release to move to** are acknowledged per ID in
  `mix.exs` (`hex: [ignore_advisories: [...]]`), never per package and
  never by softening the gate. Hex prints them under *Ignored
  advisories*: the exit code matches a clean run, the epistemic status
  does not, and that is the whole point — "No vulnerabilities found."
  becomes a named list with an author behind it. It stays honest both
  ways: an advisory not on the list still fails, and an entry matching
  nothing warns that it can be removed, so acknowledgements expire by
  themselves when the dependency is bumped.
- `mix xref graph --format cycles --fail-above 0` — compile-
  dependency cycles prohibited.
- `mix xref graph --label compile-connected --fail-above 0` — the
  ratchet, v5 §2.14's second half. It does **not** join via the audit:
  ORC-21 reversed that, and `docs/non-goals.md` names "a module
  attribute in the audit" as one of the homes it refuses. The number
  lives in `pipeline.config.json` → `qualityGates` and in `ci.yml`,
  both author-owned by construction, which is what makes "raising it
  needs a reviewed change" literal rather than aspirational. Armed at
  `0` in both projects (ORC-49) — the strongest cap it will ever have,
  and the only moment arming it was free.
- `mix catapult.audit` — grows over time; whatever checks exist, run.
  Its greps are `Path.wildcard("lib/**/*.ex")`, rooted at the working
  directory and deliberately kept there (the task ships into every
  generated project; `systems/substrate.md`). So this bullet, like every
  other in this list, is a claim about **one mix project** — the set
  runs per project, and a new mix project brings its own gate block
  (ORC-30, `systems/substrate.md`). The audit is the only one of these
  whose absence is invisible — `mix credo` at the root plainly checks
  the root, while `mix catapult.audit` at the root reads as though it
  audits the repository — so it is the one that earns an invoker:
  `mix catapult.audit.all` in the root `mix.exs` runs it once per
  project here.

At the root, `mix hex.audit` runs as the first element of the
`deps.audit` alias in `mix.exs`, so the existing `mix deps.audit` gate
— already in `pipeline.config.json` and already a `ci.yml` step — runs
both audits, Hex first. Nothing protected was touched to arm it: the
gate name stayed and its content grew (ORC-37).

Substrate's suite is the whole list too, as of ORC-49. ORC-30 made
`--check-locked`, `mix hex.audit`, xref cycles and `mix catapult.audit`
runnable and green from that directory and left the arming to the
author; ORC-21 did the same for the compile-connected ratchet in both
projects. They ran nowhere automated in between, which is the gap this
paragraph used to describe at length and no longer needs to: the
`substrate suite` block in `ci.yml` now carries every line above, and
`qualityGates` runs `mix catapult.audit.all` rather than the root-only
task.

## 3. The naming spine

A component's slug mechanically derives every name it claims
(v5 §2.1). For a component slugged `engine`:

| Surface | Derivation |
|---|---|
| Namespace | `Catapult.Engine` |
| Boundary | `Catapult.Engine` (the module *is* the boundary) |
| Store | `Catapult.Engine.Store` |
| Tables | `engine_*` |
| Env vars | `ENGINE_*` (declared in the component's `config/0`; off-spine names need `external: true` — ORC-4) |
| PubSub topics | `engine:*` via `Catapult.Engine.Topics` functions |
| Oban queues | `:engine_*` |
| Telemetry | `[:catapult, :engine, ...]` |
| Events (ES) | declared in `Catapult.Engine.Events`, registered |
| Docs | `docs/` folder inside the component directory |
| Mutex label | `system:engine` (delivery-side, derived) |

Rationale: hand-maintained mappings drift; derivations can't. Never
invent a name off-spine — if a name doesn't fit the table, the
component decomposition is wrong, not the table.

Slugs are renamed only through the rename flow (v5 §2.1): every
derivation registers its rename transform — codemod or generated
migration — and a rename ticket composes them. A slug change
outside that flow is an audit failure, because table renames on an
unattended pipeline must be mechanical or forbidden.

## 4. Boundaries and component structure

- **Every component and subcomponent is a Boundary** with an explicit
  export list. Single OTP app + Boundary; no umbrella. Nested
  boundaries for subcomponents; component-level exports are the only
  cross-component surface. Rationale: compiler-enforced isolation is
  what makes the mutex partition, the pubapi contract, and AI-driven
  refactoring safe (v5 §2.3).
- **Standard component skeleton:** public interface module (the
  boundary export), `Config` (the `config/0` declarations and their
  casts — ORC-4), `Supervisor`
  (children composed into the root via the behaviour), `Store`
  subcomponent (see §6), `TestSupport` (boundary-exported, test env
  only — factories and fakes), `docs/`.
- **Cross-component calls go through exports. No cross-boundary
  schema access, no cross-boundary Repo queries.** Read models that
  genuinely span components are their own component with declared
  dependencies.
- **The component behaviour** (`use Catapult.Component`, substrate
  Phase 1) declares the registries: `config/0`, `pubsub_topics/0`,
  `oban_queues/0`, `telemetry_events/0`, `events/0` (ES components),
  `processes/0`, `seeds/0`, `errors/0` (boundary failure vocabulary
  with remedies, v5 §2.2), `externals/0` (wrapped third-party
  services, v5 §2.2). The root composer collision-checks at
  compile time. A new registered name is a decision; it shows in the
  diff.
- **Root artifacts are composed, never edited** (v5 §2.7): router,
  root supervisor, API/admin routes compose from component
  declarations. If a ticket edits root glue by hand, the composition
  mechanism is missing a feature — fix that instead.

## 5. Processes and state

- **Every named process is registered via `processes/0`** with a
  placement category: `:local`, `:singleton`, `:sharded`. No bare
  `name: __MODULE__` outside the registry — the audit greps for it.
  Rationale: the innocently-named GenServer is the classic
  single-node landmine; registration makes placement a reviewed
  decision (v5 §2.5).
- **Processes are never the state of record.** State of record lives
  in Postgres; every process must be killable and rebuildable from
  persistent state; ETS caches declare a rebuild path and an
  invalidation topic. Catapult runs `topology: single` today — the
  discipline is what makes a later flip mechanical, so it is not
  optional at n=1.
- Registered processes may declare **VM guardrails** (v5 §2.5) —
  `max_heap_size`, message-queue bounds — enforced by the BEAM
  itself; legal because processes are never the state of record.
- Commanded's and Oban's internal processes and tables are
  infrastructure — exempt from the registries, reached only through
  their APIs (v5 §2.4).

## 6. Persistence

- **One Repo** (`Catapult.Repo`), owned by the foundation component.
  Stores own schemas, queries, and migrations — never connections.
- **Store exports are function-shaped** (`Store.get_project/1`,
  `Store.insert_claim/2`), never generic CRUD. The store is the
  named seam between domain logic and Ecto, not a DAO ceremony.
- **Every table has exactly one owner** — a component's store, or a
  registered infrastructure library under its reserved prefix
  (`oban_*`, `eventstore.*`, `fun_with_flags_*`). The audit
  enumerates tables and fails on orphans. Table names carry the
  component prefix.
- **Migrations live per-store** (composed `ecto_migrations` paths)
  and pass the migration-safety lint. Rationale: merges deploy
  unattended; an unsafe migration is an outage nobody approved.
- **Seeds are idempotent by construction** (upserts, stable natural
  keys), declared via `seeds/0`, composed by a release task. There
  is no fresh-database moment; seeds run against live state.
- **Event-sourced components follow the ES store family** (v5 §2.4):
  append-only insert paths; deterministic projection functions;
  `events/0` registry; the **purity floor** — no clocks, randomness,
  or generated ids inside aggregate/fold/projection code (inject
  them at the command edge); env-switched event-store adapter
  (in-memory dev/test, persistent prod, identical aggregates).
  Catapult's own engine is the family's first consumer; the reducer's
  rebuild-from-zero property is a standing test, not a hope.
- **Event shapes are immutable contracts** (v5 §2.4): a change —
  additive included — is a new version with a **pure upcaster**
  applied on read; the log is never rewritten. `events/0` registers
  versions; the replay suite keeps fixture logs of every historical
  shape, so rebuild-from-zero is tested against real old events.
- **ES invariants are property-tested** (v5 §2.4): reducers ship a
  replay-determinism property, workers an idempotency property,
  upcasters a round-trip property (StreamData). Examples supplement;
  the property is the floor.

## 7. Cross-component effects

- **Default: eventual, via Oban in the same transaction** — insert
  the job through the target's exported enqueue function inside the
  local transaction (the outbox for free; v5 §2.6).
- **Every worker is replay-safe**: idempotent effects, unique-job
  keys on the spine. A worker that can't survive a duplicate run is
  a bug even if Oban never duplicates it.
- **Same-transaction coupling across components requires a declared
  edge**: boundary-exported `Ecto.Multi`-fragment functions, and the
  coupling named in the owning system doc. An undeclared
  cross-boundary Multi is an audit finding.
- **Serial pipelines are enqueue-on-completion chains with
  log-derived progress** — no stored cursors, no process-held
  sequence state; a resumed pipeline re-derives its position from
  what's recorded (v5 §10.1, from Polyphony).

## 8. Errors and failure surfaces

- Expected failures return tagged tuples with typed reasons
  (`{:error, %Engine.Error{kind: :grammar_invalid, ...}}` or a
  documented atom vocabulary per export); exceptions are for bugs.
  Rationale: callers pattern-match on failures; prose reasons can't
  be matched and become logs nobody reads.
- **LLM/generation failures follow the three-way taxonomy** (v5
  §10.1): refusal → editable; transport → retryable; schema-invalid
  → cancel. Generation failures are **domain read models with
  affordances, never crash reports** — a failed generation is a
  fact about the work, not a fault in the system.
- Every boundary export's failure modes are part of its contract:
  documented at the export, tested at the boundary.
- **Deliberate error kinds are registered** (`errors/0`, v5 §2.2):
  spine-prefixed, each with a one-line meaning and a remedy
  (minimally "what to do" prose; gradable to a runbook ref or admin
  link). Declared↔constructed checked both ways; the error catalog
  generates from the registry. Scope: what crosses `defexport` —
  internal tagged tuples stay unceremonied, and **crashes are out**
  (exceptions are for bugs; bug-shapes are not inventoriable).

## 9. Testing

Test determinism is a protocol requirement, not a virtue: the
pipeline escalates two CI reds to a human, so a flaky suite
mechanically defeats the automation (v5 §2.8).

- **No network in per-ticket CI. Ever.** Every external system sits
  behind a port/behaviour with two implementations: real, and an
  in-memory fake (Tracker, Host, Deploy, LLM Provider —
  orchestration's own pattern, which this codebase re-expresses in
  Elixir). Ticket CI uses fakes; the fake ships with the port, not
  with the test file. Each wrapped external is registered via
  `externals/0` (v5 §2.2) — adapter, fake, kill-switch — so the
  audit can hold the line mechanically.
- **The `:live` suite is the exception, on a cadence, not a gate.**
  Tests tagged `:live` (real providers, real tracker/host against
  scratch projects, deployed surfaces) are excluded from ticket CI
  and run once per milestone, gating that milestone's own `main →
  retro` queue transition (v5 §2.8, §7.8 — revised at ORC-105 from
  "at the milestone boundary — after the boundary ticket is created,
  before the author's pass," a proxy-ticket mechanism this repo's own
  container model no longer has) — so the true end-to-end sanity
  check happens exactly once per milestone, with results on the
  milestone and failures held open as a `retro`-blocking condition.
  Rationale: per-ticket determinism is what the escalation rules
  depend on; a live check that never runs is how "merged and green"
  quietly diverges from "actually works against the world." Both
  properties, each at its own cadence.
- **Ecto sandbox, async by default.** A test that can't run async
  documents why in a comment.
- **Injected clock** (`Catapult.Clock` behaviour; `DateTime.utc_now`
  is banned in domain code by grep-audit), **seeded randomness**,
  no reliance on generated-id ordering.
- **Test at the boundary.** Default: exercise the export module;
  internal tests are exceptional and justified. Rationale: internal
  tests churn on refactors even when behavior holds — exactly what
  makes automated refactoring expensive.
- **Structural coverage, not line coverage:** every boundary export
  has at least one test referencing it (audit-checked). No coverage
  percentage gates — they're gameable, especially by an LLM.
- `@tag :skip` requires an annotation with a ticket key; CI rejects
  bare skips.
- **Factories in `TestSupport`**, boundary-exported for test env
  only. Cross-component test data goes through that door, not
  through direct schema access.
- LiveView/screens: storybook variations are render tests; every
  declared state has a variation (state names *are* variation
  names — v5 §4.3, enforced by the storybook export build).

## 10. Observability

- **Structured JSON logs to stdout**, standard metadata (component,
  event sequence, trace id). Content-bearing data never enters the
  operational log channel (v5 §2.11); Catapult's plane logs contain
  project/scope identifiers, not artifact bodies.
- **Logs are write-only** (v5 §2.11): nothing parses, alerts on, or
  derives state from a log — alerting rides telemetry; replayable
  facts are events. Ad hoc logging is legitimate *because* of that
  fence; the export macro sets Logger metadata at boundary entry so
  ad hoc logs still arrive structured. Secret-flagged config values
  (v5 §2.2) never appear in logs or error payloads — audit-checked.
- **Instrument the boundary:** the export macro auto-emits telemetry
  spans (start/stop/exception) per exported function — latency,
  throughput, error rate at every public surface, for free. Custom
  events are registered via `telemetry_events/0`, spine-named; the
  audit checks declared↔emitted both directions.
- **Trace context threads through the async seams** — the platform's
  enqueue/broadcast wrappers carry it through Oban jobs and PubSub
  invisibly. Never hand-thread it; never drop it.
- The health endpoint (`/health`) reports git SHA + per-component
  readiness derived from the registries. Deploy detection and ops
  read the same facts.

## 11. LLM usage

- **The plane makes no model calls, ever** (v5 §1.2: agents
  end-to-end). Generation is dispatched agent runs; the plane
  renders context, dispatches, and validates commits. No Anthropic
  key exists on the plane's box. A model call appearing in plane
  code is an architecture violation, not a style issue.
- **Target apps and the runtime**: all model calls go through the
  provider behaviour (LLM adapter component, Phase 8). No direct API
  calls anywhere else — not in scripts, not in tests, not "just this
  once." The adapter carries the fakes (no-network CI), the metering
  (cost caps), the routing, and the failure taxonomy; a bypassed
  call has none of them.
- **Deterministic fakes for all test paths** — for the plane, the
  agent-port fake (canned bodies through the real commit path); for
  the runtime, the adapter fake. Live tests are the `:live` suite.
- Prompts are bundle content (Liquid), never inline strings in code.
  Prompt changes are reviewed diffs like any artifact.

## 12. Git, commits, and docs upkeep

Pre-pipeline (Phases 0–2) this is discipline; post-hookup,
orchestration enforces its own protocol and this section defers to it.

- Small, single-intent commits; imperative first line; body says why.
- **`systems/*.md` carry standing decisions and file maps — no code
  inventory, no state sections** (orchestration's rule: the code is
  the inventory; docs that mirror code drift silently). Amend the
  owning system doc in the same change that moves a boundary.
- A convention change is a change to *this file*, in a reviewed
  commit, with its rationale — never a silent divergence that a
  later session codifies by imitation.

## 13. What Catapult deliberately does not honor on itself

Recorded so nobody "fixes" it (see also `docs/non-goals.md`):

- **No self-bootstrap; no doc chain over Catapult's own repo** (v5
  §1.3). `systems/*.md` are hand-maintained under orchestration's
  protocol.
- **No product tier for the dashboard** — dashboard screens go
  through orchestration's screen machinery (screens/*.md, stateless
  components, storybook).
- **Per-component admin surfaces are subsumed by the dashboard**;
  the docs-site composition is deferred until the platform docs need
  it.
- Feature flags arrive when the delivery loop lands multi-ticket
  features on the reference deployment, not before.

# Catapult — build plan

How Catapult itself gets built. Companion to
`docs/v5-design-decisions.md` (cited as *v5 §n*), which holds the
design; this document holds the sequencing and its rationale. Same
style rule: every ordering states its reason.

**Standing decisions for the build:**

- **Orchestration (the Go pipeline) delivers Catapult** (v5 §1.3).
  Catapult is not built from its own doc graph; it honors the v5
  convention corpus wherever the convention doesn't presuppose the
  doc chain, because it is exactly the kind of app the corpus
  protects: an Elixir system delivered by an unattended pipeline.
- **Polyphony is frozen on orchestration and becomes the end-to-end
  test case.** No code reuse: the rebuild is seeded from Polyphony's
  documentation and Linear project only. Rationale: if the chain
  needs the old code to rebuild the app, the doc chain failed — the
  documentation-only seed is the honest test of intake.
- **The authoring loop is front-loaded** (Phase 4), ahead of the
  machinery that could fully exercise it. Rationale: Linear + PR
  review is the working interface; without it, feeding input and
  reviewing chain output is painful enough to distort every later
  phase's testing. Build the interface early; let later phases arrive
  into it.
- **A shared component is built when its first consumer's tickets
  need it, and the plane is made the first consumer wherever
  possible.** Dogfooding is the scheduler, not a virtue: LLM adapters
  before identity (the plane's doc generation consumes them),
  identity before the runtime (the dashboard consumes it), the
  runtime when Polyphony's rebuild forces it.
- **Catapult's dashboard is LiveView + daisyUI and goes through
  orchestration's native screen machinery** (`screens/*.md`,
  stateless components, storybook, screen labels) — not through
  Catapult's product tier, which doesn't apply to Catapult itself.
- Catapult's own runtime topology starts `single` (v5 §2.5's
  discipline/runtime split applied to ourselves); the placement
  discipline is honored from the first process.

---

## Phase 0 — Foundation documents (Claude drafts, author reviews)

The bootstrap material orchestration needs to adopt a repo is
`systems/*.md` with file maps plus recorded conventions — so writing
these documents is not preparation for the work; it *is*
orchestration's onboarding artifact.

1. **`docs/conventions.md`** — coding conventions and standards:
   style, adopted patterns (Commanded usage rules, purity floors,
   Boundary discipline, the naming spine, test rules), each with its
   rationale.
2. **`systems/*.md`** — Catapult's own architecture: one doc per
   system with a file map, standing decisions, and initial-vs-target
   state made explicit (stubs are legitimate when argued — v5 §1.1).
3. **`docs/non-goals.md`** — the negative space, per v5 §1.1's
   doctrine, eaten by us first.

Exit: author has reviewed and signed off all three.

## Phase 1 — Skeleton and substrate (attended)

Repo layout; CI with the full gate set **from day one** (format,
credo, warnings-as-errors, boundary check, migration lint — the gates
must predate the pipeline because reconciliation trusts green); the
component behaviour macros and registries (topics, queues, events,
processes, config via Vapor); the boundary-export macro (telemetry
now, permissions later — both ride the same macro, built once); test
harness conventions (fakes infrastructure, sandbox, factories,
injected clock); health endpoint (SHA + per-component readiness);
`mix catapult.audit` v0 (whichever checks exist); a simple deploy
loop.

Exit: an empty-but-enforced application — every convention that can
be checked is checked, on a repo that does nothing yet.

## Phase 1.5 — Ticket the work (attended)

Before orchestration can deliver anything, the work must exist as
tickets — orchestration's rule is that issues are created only on
the author's ask, so populating the backlog is an attended pass
(author + assistant), not machinery.

- **Grain: whole-deliverable tickets** (v5 §7.2's large-ticket rule,
  applied to our own backlog): one ticket per coherent system slice
  — "the DSL loader," "the reducer + projections," "the authoring
  loop's tracker port" — not per-function shards. Rationale as
  recorded: reconciliation verifies a diff against an argument, and
  a deliverable-sized argument is what it's built to check; AI time
  makes the deliverable the natural unit.
- **Format: orchestration's issue shape** (its DESIGN §4): imperative
  title; description carrying the argument (what's wrong with the
  current state, why the change is worth making), what it touches,
  and open questions stated rather than smoothed over. Descriptions
  are immutable once work starts — write them as the measuring stick
  reconciliation will use.
- **Milestones map to build-plan phases** (Phase 3 = the engine,
  Phase 4 = the authoring loop, …), ordered by the dependency
  structure above; blocking relations carry the intra-phase
  ordering. Orchestration's debt/product alternation applies from
  the start — early debt milestones will be thin or empty, which its
  protocol explicitly prefers to padding ("an honest empty beats a
  padded one").
- Tickets for phases far out stay coarse (a Phase 7 epic-shaped
  placeholder beats twenty speculative shards that Phase 4's
  learnings will invalidate); each milestone gets fully ticketed as
  it approaches, at the boundary's grooming pass.

Exit: the backlog exists in Linear, milestoned and ordered; the
Phase 2 milestone is fully ticketed and pulled to Todo.

## Phase 2 — Orchestration hookup

Pipeline config, Linear project, stub workflows, storybook + preview
for dashboard screens, deploy detection. Orchestration-side work
items (its build is not finished): remaining milestones, plus a
**generic health-endpoint deploy adapter** (reads §2.13's contract;
provider-independent, covers any target) in preference to a
provider-specific one, plus a **boundary live-suite step**: at
milestone boundary, after the boundary ticket is created and before
the author's pass, run the project's `:live`-tagged suite (real
network, real providers) and post results on the boundary ticket —
failures file as blockers against the milestone through the existing
blocking rule. The flag flip sits strictly downstream of a green
live run.

Exit: a trivial ticket flows through design → dev → reconcile →
deploy on the Catapult repo. From here, phases 3+ are
orchestration-delivered tickets.

## Phase 3 — The engine

In dependency order: `core.dsl` (loader, core vocabulary, extension
registry per v5 §9, libgraph validation) → `core.engine` (event log,
reducer, projections, reactive scheduler — **the first consumer of
the ES store family**: purity floors and the `events/0` registry are
proven on ourselves) → **LLM adapters** (first shared component:
provider behaviour, deterministic fakes, model routing, metering,
failure taxonomy — the plane's doc generation is its first consumer)
→ design-dialect generation (Liquid render → provider → grammar
validation → events) → **the siege prompt port**.

Exit: the chain generates and validates artifacts for a toy seed,
offline against fakes and live against a provider.

## Phase 4 — The authoring loop (front-loaded Linear-as-UI)

The interaction surface, built before the machinery that fully
exercises it: tracker + host ports with memory fakes (orchestration's
port pattern, in Elixir); the feature-ticket lifecycle subset —
states projected to Linear, `Product design → Product review →
Architecting → Architecture review` with gate skip-on-no-diff;
bodies committed to a feature branch with one PR; gate review via PR
diff; decline harvesting (review comments since last gate, bucketed
by artifact file span, threaded as regen feedback); dashboard v0
(the debugging minimum: event log inspection, ready_scopes
explain-why).

Exit: the author files a feature ticket in Linear, watches states
move, reviews the doc diff in a PR, declines with line comments,
and the chain regenerates with that feedback — end to end, with no
delivery machinery existing yet.

## Phase 5 — Product tier and intake

Journey/screen grammars, UX/IA prompts, the frontend-architecture
tiers, input-document roles (including `non_goals`), the intake
role list from the Polyphony pass (behavior docs, invariants,
capability inventories, forward strategies).

Exit criterion — the first big one: **Catapult scaffolds Polyphony's
document graph from its documentation seed**, reviewed through the
Phase 4 loop. The doc chain producing reviewed architecture is a
usable product before any delivery machinery exists.

## Phase 6 — Prompt harness v0

SiegeEngine's cohort machinery re-platformed (v5 §10.2): cohorts,
fresh-vs-review modes, score aggregation, registry-pinned baselines,
offline mode via the adapter fakes. Placed here because Phase 5's
output makes prompt iteration the main activity; pull it earlier if
the ported prompts demand tuning sooner.

## Phase 7 — Delivery

Ticket minting at the Building transition; the two-grain machinery
(spawn, child lifecycle, mutex from doc-graph scopes, auto-bounce);
agent dispatch; reconciliation; the validation loop (v5 §7.11).
Alongside, the consumer-driven components: **identity** (dashboard
login internally, Polyphony's auth externally), registry-as-service,
and the **React pass + `platform-client-ts`** (must precede
Polyphony's frontend tickets).

Exit: a feature ticket on a test project goes gate → children →
merged → validated → shipped, unattended except at the gates.

## Phase 8 — The rebuild

Generation runtime app dialect (v5 §10.1 — Polyphony's beat loop is
the forcing consumer); client corpus completion; observability full
build. **Acceptance test: Polyphony rebuilt end-to-end from its
documentation**, delivered by Catapult, running on DOKS.

---

## Open within the plan

- Whether harness v0 pulls forward into Phase 5 (decide when the
  ported prompts meet the Polyphony seed).
- Orchestration finish-line inventory (Phase 2) — enumerate against
  its PLAN.md when hookup starts.
- ~~Where Catapult's reference instance deploys~~ **Settled: DO App
  Platform.** DOKS was blessed for *generated projects* (v5 §2.5);
  Catapult is not a Catapult project — its plane is IO-bound
  coordination (agent compute lives on runners), needs no
  clustering, and App Platform is near-zero ops with orchestration's
  deploy adapter already built, making Phase 2's hookup the shortest
  path. Known cost, accepted: ephemeral disk means the git clone
  cache rebuilds per deploy — it is a cache, refetchable; it is also
  the canary. **Revisit when the DOKS manifests skeleton ships
  (Phase 7)**: migrating then is cheap (OTP release + env + Postgres;
  the health contract keeps deploy detection indifferent) and buys
  dogfooding of the deliverable — decide with data on whether the
  App Platform pain points materialized.

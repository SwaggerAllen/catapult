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
  machinery that could fully exercise it. Rationale: a working
  interface has to exist before later phases are testable at all;
  without it, feeding input and reviewing chain output is painful
  enough to distort every later phase's testing. Build the interface
  early; let later phases arrive into it. **Which interface, restated**
  (v5 §7.17): the working interface is **Catapult's own surface plus
  PR review**, not a third-party tracker. The sequencing argument is
  unchanged and the consequence is a real one — UI v1
  (`docs/ui-spec.md` §5) is part of this phase's floor, because there
  is no borrowed surface to defer it behind. Orchestration builds
  Catapult and orchestration uses Linear; that is a different system
  and not this phase's interface.
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

- **Tickets are exclusively work orchestration will deliver.**
  Pre-pipeline setup (Phase 2) cannot be tickets — the pipeline
  doesn't run until it's done — so it lives in `SETUP.md` as a
  runbook. The backlog starts at Phase 3 (plus debt items and the
  Phase 2 verification ticket, which the pipeline itself works).

- **Grain: whole-deliverable tickets** (v5 §7.2's large-ticket rule,
  applied to our own backlog): one ticket per coherent system slice
  — "the DSL loader," "the reducer + projections," "UI v1's working
  surface" — not per-function shards. Rationale as
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

Exit: the backlog exists in Linear, milestoned and ordered; Phase 3
is fully ticketed; the Phase 2 verification ticket is ready to file
once SETUP.md completes.

## Phase 2 — Orchestration hookup (attended, per SETUP.md)

A runbook, not tickets: `SETUP.md` at the repo root. Already in
place: the Linear team/project with states and labels (shared with
orchestration's test project), and the Cloudflare Worker metronome
(Cloudflare side — our side is a config value and one action run).
Remaining attended work: the App Platform deploy artifacts and app,
`pipeline.config.json`, stub workflows + secrets + branch
protection, and the agent-facing CLAUDE.md **copied from
orchestration's template** — maintained there, because orchestration
runs the agents; this repo hosts the copy.

Orchestration-side items (its build is not finished): the **generic
health-endpoint deploy adapter** (off Catapult's critical path — the
App Platform adapter covers the reference instance; still wanted for
DOKS-target projects), remaining PLAN milestones. Settled: `preview`
stays mandatory (optional-now-mandatory-later is the painful
direction) — Catapult ships a placeholder export per SETUP.md. The
**boundary live-suite step** is done (shipped with the live-suite
change).

Exit: a trivial ticket flows through design → dev → reconcile →
deploy on the Catapult repo. From here, phases 3+ are
orchestration-delivered tickets.

## Phase 3 — The engine

In dependency order: `core.dsl` (loader, core vocabulary, extension
registry per v5 §9, libgraph validation) → `core.engine` (event log,
reducer, projections, reactive scheduler — **the first consumer of
the ES store family**: purity floors and the `events/0` registry are
proven on ourselves) → **the agent-dispatch generation executor**
(v5 §1.2: agents end-to-end — dispatch via the host port, the
runner-side harness that fetches rendered context, runs the agent,
commits, reports; in-process fake through the same commit path) →
design-dialect generation (readiness-driven dispatch, Liquid render
served to agents, grammar validation at commit) → **the siege prompt
port**. The LLM adapter component moves to Phase 8 with its consumer
(the runtime); Catapult's chain never calls it.

Exit: the chain generates and validates artifacts for a toy seed,
offline against the agent-port fake and live against real dispatched
runs.

## Phase 4 — The authoring loop

The interaction surface, built before the machinery that fully
exercises it: the host port with its in-memory fake (orchestration's
port pattern, in Elixir); the feature-ticket lifecycle projection —
states rendered on Catapult's own surface (`screens/board.md`,
`screens/ticket.md`, `screens/my-queue.md`), gate states drawn from
the ticket type's own declaration (v5 §7.16;
`bundles/default-flow/types/feature.yaml`) with gate skip-on-no-diff;
bodies committed to a feature branch with one PR; gate review on the
native `document-review` screen, at sentence granularity (v5 §7.17;
`screens/document-review.md`); decline harvesting (comments since the
gate's last resolution, threaded as regen feedback — bucketed per
node today, not per sentence; `systems/engine.md`'s ORC-34 entry);
UI v1, the working surface (event log inspection, ready_scopes
explain-why, and the screens above — `docs/ui-spec.md` §5).

Exit: the author files a feature ticket on Catapult's own surface,
watches states move, reviews the doc diff on the document-review
screen, declines with anchored comments, and the chain regenerates
with that feedback — end to end, with no delivery machinery existing
yet.

## Phase 5 — Product tier and intake

Journey/screen grammars, UX/IA prompts, `frontend_sysarch`, and the
UI and screen collection families (v5 §5.1) — the client family
lands in Phase 7, with its consumer (`systems/client_ts.md`). Also
here: the platform's input-document role vocabulary — `project_doc`,
`mocks`, `non_goals`, `design_system` (`chain.md` #19).

Exit criterion — the first big one: **a small todo application,
scaffolded from spec documents written for the purpose, produces a
reviewed architecture chain through the Phase 4 loop.** The doc chain
producing reviewed architecture is a usable product before any
delivery machinery exists.

Not Catapult's own `docs/`/`systems/`, and not because that raft is
unavailable: the claim under test is mechanism — fan-out, gates, and
a decline visibly changing what comes back — and that claim is
size-independent, so a large seed buys review load rather than
evidence. Phase 5's own tiers are product tiers (journeys, screens,
mocks, `design_system`, the UI and screen collection families), and a
small application with mocks exercises every one of them, where a
control plane's own design record barely reaches them. The reviewer
knowing the right answer is what a mechanism proof wants — a wrong
fan-out is visible at a glance — and that holds for any seed the
reviewer wrote, not only a self-referential one. `systems/*.md` is
the architecture the chain exists to produce; reading it back in as
`input.behavior_docs` would make `sysarch` a paraphrase of its own
input. And the seed doubles as Phase 6's first cohort fixture: small
enough for an agent to evaluate, which is the property that harness
needs from day one.

The seed is a second fixture beside `toy_seed` — spec documents
carrying the same file-per-role shape `toy_seed`'s own raft already
uses (`role: Path.rootname(filename)`, `Store.pin_input_documents/3`):
`project_doc`, `non_goals` and `mocks` are platform roles
(`chain.md` #19), and `behavior_docs`, `invariants`,
`capability_inventories`, `forward_strategies` are the same
project-declared names `toy_seed`'s own fixture files already carry
— a project's own role name is that project's declaration, not
platform vocabulary, and an unread one is simply never walked
(`chain.md` #19). It carries no canned tier bodies — it only ever
runs live, and `toy_seed` stays the offline fixture, untouched. The
spec names the three to five components it intends the chain to
mint, so the proof checks the fan-out against those names rather than
against a count — and at that size, the run goes to `impl` for every
one of them, across all three families Phase 5 reaches (backend,
UI-collection, screen-collection; the client family is Phase 7's,
with its consumer, per v5 §5.1). Reviewing every subcomponent this
seed mints is not a cost that scales with the raft: the seed's small
footprint is what makes exhaustive review the bound. Somewhere in that
run, at least one decline has to harvest into a regeneration that
visibly answers it.

The run is against a fresh project, never the reference instance's
own: a fresh `project_id` keeps the run's evidence out of any graph
the instance later runs for real, and costs a binding row and a bound
repo. Every engine table already keys by `(project_id, id)`, and
`FeatureLifecycle`'s own process-manager identity is the composited
pair `(project_id, flow_id)` (`systems/engine.md`,
`systems/delivery.md`) — a fresh `project_id` gets its own key space
and its own process managers by construction, with no second
deployment involved.

Concretely, the seed's project is a **test project** in
`systems/delivery.md`'s ORC-216 sense: provisioned through
`Catapult.Delivery.Provisioning`'s `POST /dispatch/test-project`
(which binds it to `catapult-test` and intakes the todo-app raft at
the ref that call produces), carried forward by the sweeper as gates
pass, released through `POST
/dispatch/test-project/:project_id/release` once the author is done
reviewing, and later deleted like the boundary's own test project —
the lifecycle already supports exactly this.

Dispatch runs through the harness `systems/generation.md`'s ORC-215
entry built, not a placeholder: the seed project's bindings carry the
ordered credential pair, the bound repo (`catapult-test`) carries
those credentials as Actions secrets, the run executes in that repo's
dispatched workflow, and the classified outcome (`success |
limit_class_failure | other_failure`, plus which credential served)
reports back to the plane that issued it.

The proof itself is not a `:live` test — its middle is the author
reviewing and declining through `document-review` across hours or
days, which no bounded test spans. What starts it is the provisioning
call above, posting the todo-app fixture and leaving the project
active; the sweeper carries the chain forward as gates pass, the
author reviews and declines at each one, and releases the project
when the proof is done. What triggers the provisioning call is a
dispatch input on `pipeline-live-suite.yml` selecting this proof
rather than the boundary suite; that file is author-owned
(`systems/README.md`).

Nothing the run produces reaches the tree: the run still commits —
every scope's `CommitDraft` lands exactly as it does for any other
project — but nothing it commits is a second, generated copy of
anything landing in this repo.

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
and the **React pass + `platform-client-ts` + the client family**
(v5 §5.1, §5.6 — must precede Polyphony's frontend tickets).

Exit: a feature ticket on a test project goes gate → children →
merged → validated → shipped, unattended except at the gates.

## Phase 8 — The rebuild

Generation runtime app dialect (v5 §10.1 — Polyphony's beat loop is
the forcing consumer) **including the LLM adapter component** (the
synchronous-completion layer, built here with its first real
consumer; Catapult's own chain is agents end-to-end and never uses
it); client corpus completion; observability full build.
**Acceptance test: Polyphony rebuilt end-to-end from its
documentation**, delivered by Catapult, running on DOKS.

---

## Open within the plan

- Whether harness v0 pulls forward into Phase 5 (decide when the
  ported prompts meet the Polyphony seed).
- Orchestration finish-line inventory (Phase 2) — enumerate against
  its PLAN.md when hookup starts.
- Where Catapult's reference instance deploys — **settled: DO App
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

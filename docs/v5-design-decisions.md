# Catapult v5 — design decisions (working notes)

**Status:** working notes from an ongoing design conversation. This
document records decisions made and their rationale; it is not yet a
spec. It supersedes specific parts of the v4 spec
(`seed-docs/catapult-spec-v4.md` in the SiegeEngine repo) where noted,
and leaves one seam — the delivery/ticket model (§7) — deliberately
open, because it is the next conversation and may reshape adjacent
decisions.

**Style requirement (inherited from orchestration's DESIGN.md):** every
rule states its rationale inline. The sessions that build this system
are re-instantiated with no memory; a rule without its reason is a rule
the next session will violate reasonably.

**Source material:**

- `catapult-spec-v4.md` (SiegeEngine repo, `seed-docs/`) — the platform
  spec this document amends: bundle DSL, reactive engine, projections,
  flows. Still authoritative wherever this document is silent.
- Orchestration repo, branch `claude/workflow-orchestration-design-0dt4rl`
  — `DESIGN.md` (the delivery protocol: state machine, label mutex,
  sketch, reconciliation, milestone boundary) and the Go control plane
  that implements it.
- SiegeEngine — the predecessor chain whose prompts, grammars, and
  per-tier context discipline port into the default bundle.

---

## 1. Mission and scope decisions

### 1.1 What Catapult v5 is

A union of SiegeEngine's document chain and orchestration's delivery
protocol, run by an Elixir control plane (Commanded + Oban) instead of
Claude-Code-drives-everything (SiegeEngine's model) or GitHub Actions
(orchestration's model). The pipeline: ingest a raft of design
documents → product definition (UX/IA) → architecture chain (ported
siege prompts) → mint implementation tickets in Linear → deliver them
orchestration-style → deliver ongoing work by combining the label mutex
with the document state machine.

**Target class:** single-author / small teams shipping enterprise-scale
systems. The design-heavy front half exists because AI-delivered
projects hit code-scaling failure (architectural erosion, undeclared
coupling) within weeks even without automation; with automation it
arrives faster. Every convention in §2 is chosen to convert a class of
erosion from "hope review catches it" into structure.

**The tech-debt theory (load-bearing for the whole shape):** debt
happens *because* systems ship feature by feature — interfaces get
renegotiated per feature, abstractions leak, and nobody re-reviews the
whole. Properly located, the mechanism is **contract renegotiation**,
which pins where the cure lives: architect the *total* end state once,
upfront (architecture through subcomparch, unphased, every pubapi
complete), and protect the contracts *structurally* — Boundary
enforcement, frozen total pubapis, the pubapi-drift audit,
single-owner tables, declared coupling, reconciliation against the
sketch. Delivery batching is not the defense; structure is. Honest
limit: this buys a debt-free starting position for the initial feature
list, not immunity — post-launch drift pressure is met by the standing
machinery (staleness cascades, upward absorption, re-evaluation, the
audit, every milestone's own `cleanup` and `prep` queues — §7.8,
revised at ORC-105 from an earlier, since-reversed design where debt
accrued to alternating whole milestones instead), and the residual
risk of
feature-sized delivery (private-side entropy inside clean contracts)
is exactly what boundary-level testing, the debt scan, and the
refactor flow exist for.

**The negative-space doctrine (from the Haven and Polyphony gap
passes; carrier settled in the non-goals design pass):** the graph
records what is deliberately *not* built and *not yet* decided, with
its argument, and every generator and planner reads it. **The
carrier is policy nodes — non-goals are negative policies** (§4.5):
same lifecycle, same three-grain scoping (project-global is the
default and is what "off to the side" means as a first-class thing),
same enforcement ladder — a non-goal's natural grade is `prose`
(reconciliation refusing to re-admit the excluded thing IS the
enforcement; the cautionary tale: a regeneration that can't see the
non-asks rebuilds the exact feature a standing decision ruled out),
promotable where an audit check can pin it. **Derived at intake, not
read from an assumed file**: input docs are free-form, so a
distillation pass extracts candidate non-goal policies from the
*whole raft* — an explicit non-goals document is strong signal,
never a requirement — and the author reviews the extracted set like
any tier output. No walk may require a role's presence (§6-adjacent
readiness rule in `dsl-syntax.md` §7): a missing role is an empty
collection, never a readiness block. Post-intake, new non-goals
enter as new policy nodes via tickets, like all graph change (the
seed raft is frozen, §1.1 below). **Argued deferrals are the same
node shape**: "total architecture" means every *contract* complete
(seams, pubapis, entity models), not every implementation detail
pre-decided; a deferral is a negative policy carrying a revisit
condition ("never, argued" and "not until X" differ by one field),
with the stub grade (§2.16) attaching when the deferral is
implementation-shaped. An unargued deferral is a §2.8-class
violation.

**Input documents freeze at intake** (from the docs review pass).
The seed raft is read by the intake/scaffold pass and never again:
`input.<role>` walks resolve to the version pinned at intake, and a
later edit to an input file **stales nothing and changes nothing** —
deliberately. Rationale: input docs are the likeliest duplication
surface against the tree, and if their edits propagated, the system
would be committed to keeping arbitrary prose synchronized with the
graph — the exact upward-propagation burden the meaning-engine
prompts are designed to avoid (downstream regeneration is the sync
mechanism; upward absorption is the exception, not the contract).
Post-intake, the graph is the only truth: a change of intent enters
as a ticket (feature, policy, ref) like any other change. The inert
edit is answered **loudly**: the base-check sweep detects a diff
under a registered input path and the plane files a Triage notice —
"input docs are frozen; this edit affects nothing" — naming the two
real moves (revert it, or bring the content into the graph via a
ticket). Corollary, the repo-prose taxonomy: every prose artifact in
a project repo is graph body (generated, lifecycle-managed), a ref
(registered, hint-staleness), a frozen input doc, or generated
output (docs site) — a hand-maintained document outside those
categories is the drift surface this rule exists to close.
Consequence for the negative space: the raft seeds it through the
intake distillation (non-goals extracted as negative policy nodes,
above), and post-intake non-goals accrue as new policy nodes;
prompts and reconciliation read the live graph, never an evolving
side file.

### 1.2 The inversion of v4 commitment #2

v4 committed to "the server is pure state; CC drives; Catapult never
calls LLMs; Oban never runs the chain." **Reversed.** The Elixir app is
an active control plane. Rationale: the delivery half (ticket routing,
mutex enforcement, escalation, reconciliation dispatch) is a heavier
orchestration lift than v4's design-only scope, benefits from event
sourcing, and matches orchestration's philosophy — agents are dispatched
compute; the control plane owns the loop.

What survives the inversion untouched: the bundle DSL, reducer/
projection machinery, context walks, grammars, the `ready_scopes`
projection. The cleanest statement of the change: **`ready_scopes`
stops being something an agent polls and becomes something that
enqueues Oban jobs.**

**Catapult is agents end-to-end, for its full lifespan** (settled
after deliberation; supersedes the earlier two-substrate assignment
that put doc-tier generation on in-plane API calls). Every
generation — doc tiers and ticket delivery alike — is a dispatched
agent session on a runner. Three reasons, in order of weight:

1. **The plane never holds a working copy.** In-plane generation
   would mean writing bodies to ephemeral storage, then owning
   branch and PR management, with multiple working trees per project
   on local disk. Agents-end-to-end deletes the whole persistence
   class: the runner's checkout is the working copy; the plane's git
   surface shrinks to read-at-SHA for validation and projection
   (possibly servable via the host API with no local clones at all).
2. **Architecture and spec-integration tiers are assumed to need web
   search and file access.** There is no separate doc-lookup step,
   and adding one is more machinery than using the agent capability
   that already exists.
3. **One execution path**, proven in production by orchestration's
   Go pipeline, extended rather than duplicated.

The plane renders context and serves it; agents fetch, generate,
commit, and report; the plane validates at commit. **Latency doctrine:
if generation is slow, the answer is an autoscaling worker pool
pulling from our queue — never moving generation in-plane.** The
synchronous-completion substrate still exists, but its customer is
the generation runtime (target apps, §10.1) — Catapult's own chain
never uses it. Noted without irony: this lands closer to v4's
"the server is pure state" commitment than the interim design did —
the plane coordinates and validates; it does not generate.

### 1.3 Self-bootstrapping: descoped

Self-bootstrapping required SiegeEngine to produce byte-identical
artifacts to
running Catapult, then Catapult to ingest its own body files and become
self-hosting. **Dropped.** Orchestration (the Go pipeline, as-is, plus
bug fixes) builds and maintains Catapult.

Rationale, in order of weight:

1. The byte-identity invariant was already invalidated by §1.2 — it
   only made sense when both systems ran identical prompts through an
   identical agent driver. The premise dissolved with the inversion.
2. Self-modification crash risk: a bad Catapult deploy that bricks the
   tool you'd fix it with is an unacceptable failure mode for a
   one-author operation.
3. Catapult is much smaller than its target class; self-hosting proves
   little. Its biggest parts are the default bundle + prompts (refs
   anyway) and the shared components (§3), which don't fit its own
   model well and don't need to.
4. Historically, the self-bootstrap requirement is a large part of why
   v4 never shipped.

**What is lost and the replacement:** byte-identity was the forcing
function for spec honesty. The replacement is the first real delivered
project — project #1 through Catapult is part of Catapult's acceptance,
chosen small and real. Catapult still dogfoods the shared components
(§3) as an ordinary library consumer — auth for its dashboard,
observability for its control plane — which is the sane kind of
self-hosting: eating the library cooking without the ouroboros risk.

Consequence: Catapult's own repo follows orchestration's conventions
(`systems/*.md` docs with file maps), not the bundle model.

### 1.4 Target opinionation

- **Backends: Elixir only**, with the non-Elixir escape hatch now
  defined in two grains (§2.15): in-repo foreign-language
  subcomponents (Rust crates as NIFs/WASM) and out-of-envelope
  services.
- **Frontends: Phoenix LiveView + daisyUI, or React. One product
  tier; one frontend stack per *target*; V1 targets exactly one.**
  The product tier (§4) doesn't know which frontend exists; the fork
  appears at the frontend-architecture tiers (§5) and in delivery
  conventions. The blessed React shape is **React hosted by Phoenix**
  (live_react-style: SSR for public content, hydrate + client-locus
  components for the authed app) — every project already runs a
  Phoenix app, and a separate SPA host is a second deployment
  envelope for no benefit. Recorded leaning for the multi-target
  future (React Native at a project's V2): extend to multi-target
  rather than a second project — a second project would split the
  product tier and fight staleness propagation; shared client-locus
  components already hold what a native target needs shared. Decide
  when a V2 arrives.
- The domain/presentational component distinction and the fanin
  synthesis tier from SiegeEngine are **removed** (§4, §5). Their jobs
  are absorbed by the product tier, the frontend tiers' ordinary
  dependency edges, and platform conventions (admin/docs surfaces,
  §2.9, §2.11).

---

## 2. The platform convention corpus (the "elixir-target layer")

These are platform-level invariants baked into the elixir-target bundle
layer (§6), not per-project bundle content. The recurring move: each
convention deletes a judgment call from the design tier, a hand-
maintained declaration from delivery config, or a "left to discipline"
row from orchestration §9 — and gives the impl-tier prompts a fixed
skeleton, which is where v4 was thinnest.

### 2.1 The slug spine (the meta-convention)

A component scope's slug mechanically derives: its Elixir namespace,
its Boundary, env-var prefix, table-name prefix, pubsub/queue/telemetry/
flag/permission prefixes, docs path, admin mount point, and mutex
label. One slug, all derivations, zero hand-maintained mappings.
Rationale: orchestration's open item — "the mutex's quality is the
partition's quality" — is answered by making the partition declared
once (at sysarch/comparch approval) and everything downstream derived
and compiler-checked. Hand-maintained mappings drift; derivations
can't.

**Renames run through a rename system, never drive-by** (docs
review pass). Every derivation the spine produces registers, beside
the derivation itself, its **rename transform**: a codemod for
code-shaped consumers (namespace, topics, queues, telemetry, flags,
permissions, docs path, admin mount, mutex label) and a generated,
lint-gated migration for data-shaped ones (table prefixes — live
data on an unattended pipeline). A slug rename is a maintenance-flow
ticket that composes and executes every registered transform; a
slug change appearing outside that flow is an audit failure.
Rationale: the spine is exactly what makes renames *enumerable* —
the registry that derives every name knows every consumer — and a
data-bearing rename must be mechanical or forbidden; "an agent
improved a name in passing" is the forbidden thing.

### 2.2 Component behaviour and registries

Every component adopts a platform behaviour (`use Catapult.Component`,
name TBD) with callbacks that register claims on shared root
resources, aggregated by a compile-time root composer that fails the
build on collision:

- `config/0` — Vapor provider; per-component `.env`, prefixed env
  vars. Entries may carry **`secret: true`** (ops-enforcement pass):
  the audit forbids secret-flagged values in logs and error
  payloads; settings surfaces mask them by construction.
- `pubsub_topics/0` — topics as functions (`Comp.Topics.user_updated(id)`),
  never raw strings.
- `oban_queues/0` — queue and worker names. Periodic schedules are
  declared here too (cron annotations on queue entries) — what runs
  on a timer is diffable, never buried in plugin config.
- `telemetry_events/0` — see §2.11.
- `feature_flags/0` — see §2.10.
- `permissions/0` — see §2.9.
- `errors/0` (ops-enforcement pass) — the component's **deliberate
  failure vocabulary at its boundary**: spine-prefixed kinds, each
  with a one-line meaning and a **remedy** — minimally "what to do
  about it" prose, gradable up to a runbook ref or an admin-surface
  link (the policy ladder's promote-from-prose instinct). Scope
  lines that make it workable: it governs what crosses `defexport`,
  never every internal tagged tuple; and **crashes are out** —
  exceptions are for bugs, and registering bug-shapes is
  inventorying the unknowable. Checked declared↔constructed both
  directions (the telemetry check's shape). Payoffs: the docs-site
  **error catalog generates** from the registry (never
  hand-written); `defexport` spans key error-rate metrics by kind —
  **cardinality-safe because the vocabulary is closed**; OpenAPI
  and channel contracts enumerate the kinds, so clients get typed
  errors carrying their remedies; and every deliberate error in a
  hosted customer's log links its runbook — the support envelope's
  difference between a screenshot and an open runbook. The LLM
  failure taxonomy becomes the adapter component's registered
  vocabulary; "generation failures as domain read models with
  affordances" — the affordance is the remedy pointer made live.
- `externals/0` (ops-enforcement pass) — every third-party service
  the component wraps (§2.12): the adapter module, its fake, its
  kill-switch flag, a data-classification note. The enumeration
  that makes the adapter convention *enforceable*: the audit checks
  every HTTP-client usage sits inside a registered adapter (with
  Boundary's externals mode as the compile-grade half), the
  kill-switch is tied to the thing it switches instead of a naming
  convention, and the generated "what does this app talk to" page
  is the compliance inventory — and, in the hosted shape, the
  customer's egress inventory.
- `processes/0` — see §2.5.
- `seeds/0` — see §2.12.
- `api_surface/0` — see §4.4. Sibling: `cli/0` (same pattern, escript
  composer; spec'd now, built later).
- `admin/0` — routes/LiveViews mounted by the root admin router. Every
  component publishes its own admin surface.
- docs — every component/subcomponent carries a `docs/` folder composed
  into a documentation site served alongside the frontend.

Rationale for registries generally: collisions between components on
shared names are exactly the class of bug AI codegen introduces
silently; compile-time registration makes them impossible, and the
registry diff makes orchestration's §2.8 rule ("a new component, token,
context, table or dependency is a decision, not a port") CI-diffable —
a new topic/queue/flag/permission is visible in the diff the sketch
must have named.

Rationale for admin + docs as conventions: these were the original
reason for domain→presentational feed-forward (backend components
needed a way to surface detail to designed frontends). As mechanical
conventions they need no design pass, which is what lets the
domain-parent machinery die.

### 2.3 Boundary and isolation

Every component and subcomponent is a Boundary with an explicit public
interface module. Single OTP app + Boundary (not umbrella): umbrellas
give physical isolation with config/deps/tooling tax; Boundary gives
enforcement without it. Nested boundaries handle subcomponents;
comp-level exports are the only cross-component surface.

This is the keystone convention: it makes the mutex partition
compiler-enforced ("no path in two file maps" becomes automatic —
namespace ownership is exclusive), makes reconciliation's
structure-as-sketched check a mechanical diff, and makes the pubapi
fragment literal — comparch's `<pubapi>` is the spec for the boundary's
export module, and drift between them is checkable.

### 2.4 Persistence

- **Persistence is always its own subcomponent** (`Comp.Store`): owns
  the component's schemas, queries, and migrations behind a nested
  boundary; the domain logic is its only caller. Always — no size
  floor. Rationale: uniformity beats saved boilerplate when code is
  machine-generated, the audit wants one rule, and the skeleton is
  templated anyway. (A single project-wide persistence component is
  ruled out: every ticket would share its mutex label and serialize
  the pipeline — orchestration §14's failure mode by construction.)
- **One Repo**, owned by the platform foundation component. Stores own
  schemas and queries, not connections. Store exports are
  function-shaped (the data half of a Phoenix context made explicit),
  never generic repository CRUD — a named seam, not a DAO ceremony.
- **Single-owner tables:** every table maps to exactly one owner — a
  component's store, or a registered self-persisting library. The
  audit enumerates tables and fails on orphans. Table prefixes on the
  slug spine now; per-component Postgres schemas are a considered
  fork, not the default.
- **Infrastructure persistence** (Oban, FunWithFlags, and anything
  that manages its own tables): migrations ship via the platform
  foundation component; tables live under a reserved prefix;
  coordination happens only through the registries (queue names, flag
  names) — application code never queries an infra library's tables.
- Migrations live per-store (composed migration paths); a migration-
  safety linter is a required gate because merges auto-deploy with no
  human in the loop.
- **Event-sourced persistence is a platform store family** (from the
  gap passes: Haven's signed-log mailboxes and Polyphony's Commanded
  domain are one family, two grades). Shared core, regardless of
  grade: append-only insert path, deterministic projection functions,
  replay-safe consumers, an **`events/0` registry** (event types
  declared by the owning component, collision-checked, sketch-
  nameable — §2.2's "a new name is a decision" applied to the one
  vocabulary ES apps contract on), and the **purity-floor audit** (no
  clocks, randomness, or generated ids in fold/projection code;
  call-graph checked — a property of replay itself, not of any one
  project, so it ships with the family). The grades: **bare log
  store** (the log is domain content written by external actors —
  Haven's signed client messages) and **Commanded aggregate store**
  (the app validates commands — **Commanded is the blessed
  event-sourcing machinery for target apps**; the control plane
  already runs it, so patterns and expertise are house knowledge).
  The event store itself is infrastructure persistence (reserved
  schema; app code reaches it only through its API). Test convention:
  env-switched adapter — in-memory for dev/test so the domain runs
  offline, persistent in prod, identical aggregates either way.
  **Versioning and upcasting are built into the family, not added
  when needed** (docs review pass): events are immutable contracts;
  a shape change — additive included — is a **new version** with a
  **pure upcaster** registered beside the reducer, applied on read;
  the log is never rewritten. `events/0` carries versions, and the
  replay test suite retains fixture logs of **every historical
  shape ever committed** (the format zoo), so rebuild-from-zero is
  proven against real old events, not just current ones. Rationale:
  replay-from-zero means old events live forever; without this
  discipline the first post-launch schema change either breaks
  replay or gets handled ad hoc per project — the classic ES cliff,
  cheap to preempt in the substrate and miserable to retrofit.
  **Property tests are the family's testing grade** (sleeper pass):
  the family's invariants are property-shaped by nature, so every
  reducer ships a replay-determinism property, every worker an
  idempotency/double-delivery property, every upcaster a round-trip
  property (StreamData; templates ship with the family). Example
  tests supplement, never substitute — an example proves one replay;
  the property is the floor the family stands on.

### 2.5 Distribution by default

libcluster + Horde are platform defaults. Rationale: the BEAM's
horizontal scalability across a large modular monolith is a primary
reason for targeting Elixir; clustering on by default surfaces the
classic AI-codegen landmine (the innocent single-node stateful
GenServer) on day one instead of at the first scale event.

- **Placement discipline:** every named process registers via
  `processes/0` with a declared category — `:local` (every node),
  `:singleton` (cluster-wide, Horde), `:sharded` (keyed via Horde
  registry). No global atom names outside the registry; the audit
  greps for unregistered `name:` options. Subcomparch's grammar grows
  a process-inventory section so placement is designed and reviewed,
  not improvised at impl time.
- **Processes are never the state of record.** State of record lives in
  the store; every registered process must be killable and rebuildable
  from persistent state; node-local caches declare their invalidation
  topic. Rationale: Horde hand-off and split-brain are manageable for
  coordinators and caches, catastrophic for sole copies of state.
- **Registered processes may declare VM guardrails** (sleeper pass):
  optional `max_heap_size` and message-queue bounds on a
  `processes/0` entry, and the BEAM itself enforces them — a runaway
  process dies before it takes the node. `runtime`-grade enforcement
  on the §4.5 ladder for the cost of a registry field, and legal
  precisely because processes are never the state of record.
- Known tax, accepted: projects run this machinery at n=1–2 nodes for
  a while. Retrofitting placement discipline into a live system is the
  week-to-month rewrite this exists to preempt; dev-mode ergonomics
  (single-node topology, identical behavior) get deliberate attention
  in the skeleton.
- **§2.5 splits into discipline and runtime** (the Polyphony pass's
  over-fit finding, adopted): the *discipline* — `processes/0`
  registry, placement categories, processes-never-state-of-record,
  the subcomparch process inventory — is **mandatory**; the *runtime*
  is a declared project option, `topology: single | clustered`. The
  discipline is what makes a later flip mechanical, which is the
  actual insurance; the runtime tax is only worth charging where
  scale exists. Commanded's and Oban's own process registration gets
  the infra exemption, like their tables.
- **Blessed deploy target: DOKS.** Settled. Rationale: k8s manifests
  are portable across providers in a way platform-specific specs
  never are, and clustering becomes a replica-count question rather
  than a capability question — both topologies are legal on one
  target. Accepted cost: real ops overhead at a one-person budget
  (node upgrades, ingress, cert-manager); mitigation: the platform
  ships the manifests/Helm skeleton as a convention deliverable, so
  projects inherit ops posture the way they inherit everything else.
  The health-endpoint contract (§2.13) keeps deploy detection
  provider-independent regardless.

### 2.6 Cross-component writes

Two-tier rule:

1. **Default: cross-component effects are eventual, via Oban in the
   same transaction.** Insert a job (through the target's exported
   enqueue function) inside the local transaction — the transactional
   outbox pattern for free, since Oban is Postgres-backed. Atomic
   locally, at-least-once delivery, identical on one node or twenty.
   Corollary: every worker is replay-safe (idempotent, unique-job keys
   on the spine) — required anyway by unattended deploys.
2. **Exception: same-transaction coupling requires a declared edge.**
   Where a genuine invariant spans components, boundary-exported
   `Ecto.Multi`-fragment functions may compose one transaction — but
   the coupling is declared in the doc graph as a dependency edge
   annotated `consistency: transactional` (default `eventual`).

Rationale: AI-delivered projects die of undeclared coupling
accumulating faster than a human can track. Boundary handles the
module-graph version; single-owner tables handle the schema version;
the declared-consistency edge handles the transaction version — an
undeclared cross-boundary Multi is "a mutex nobody took" in
data-consistency form, and the enumerable coupling set is what makes a
future store split a query instead of archaeology.

### 2.7 Root artifacts are composed, not edited

Per-component router modules composed into a trivial root router;
`children/0` composed into a trivial root supervisor; admin and API
routes composed the same way. Rationale: orchestration names the
router and manifests as files owned by no system, caught only
textually. Composition makes the root files generated glue tickets
never touch. What remains genuinely shared: `mix.exs` / `mix.lock` —
deps stay a named-decision rule rather than per-component manifests
(machinery not worth its weight); lockfile churn is accepted textual-
conflict territory.

### 2.8 Testing

Framing: orchestration escalates two CI reds on a branch to `Blocked`
(a human). **Test determinism is therefore a protocol requirement, not
a virtue** — flaky tests mechanically drag the author into the loop
the pipeline exists to keep them out of. Hence: no network in
per-ticket CI (fakes per §2.12), Ecto sandbox async-by-default,
injected clock, seeded randomness.

**The `:live` suite is the deliberate exception, on a cadence rather
than a gate.** A `:live`-tagged suite (real providers, real external
services, deployed surfaces) is excluded from ticket CI and runs once
per milestone — **settled at ORC-105: at the milestone level
specifically, gating that milestone's own `main → retro` transition
(§7.8)**, not at the project level and not at every nesting level a
future container kind might add. Results post on the milestone,
failures file as milestone blockers held against `retro`'s declared
`blocks:` relation to `main` (§7.8, `dsl-syntax.md` §15.7), and the
flag flip (§7.8) stays strictly downstream of a green run. A
project's own queues are too coarse-grained a cadence for this check
(`build-out` and `iteration` each span many milestones) and nothing
nests inside a milestone today for a finer one to attach to; the
question stays open only for whatever container kind eventually
nests there. Rationale for the cadence itself, unchanged: per-ticket
determinism is what the escalation rules depend on, but a live check
that never runs is how "merged and green" quietly diverges from
"works against the world"; both properties hold, each at its own
cadence. (Orchestration-side: the identical cadence, absorbed by its
own boundary ticket's step-comment resume machinery — a different
system running a different loop, `systems/delivery.md`.)

- Test ownership mirrors the mutex: `test/<comp>/` mirrors
  `lib/<comp>/`; derived file maps include test paths. A thin
  `test/integration/` is the router-analog: owned by nobody, named in
  sketches, small.
- **Test at the boundary.** Default is testing through the export
  module; internal tests are exceptional. Rationale: internal tests
  churn on every structural change even when behavior held, which is
  what makes AI refactor flows expensive.
- **Structural coverage, not line coverage:** every boundary export has
  at least one test referencing it — audit-checkable, not gameable by
  an LLM padding assertions.
- **The impl tier's `<tests>` block is normative:** named test
  descriptions are the acceptance criteria; reconciliation checks the
  named tests exist and pass. This is the backend sibling of
  orchestration's "every state the issue named exists, named as
  asked," and gives reconcile a mechanical check where it's currently
  weakest.
- `@tag :skip` requires a ticket key; CI rejects bare skips — keeps
  `retro`'s debt-scan input trustworthy (`boundary`, ORC-105's
  retired predecessor, did this job under the older name).
- Factories (ex_machina) per component, exported via a boundary-
  exported `Comp.TestSupport` (test env only) — cross-component test
  data through a declared door, not a hole in isolation.
- Frontend: storybook export build doubles as render-test-per-declared-
  state (orchestration's existing trick, kept). React side: backend
  controller tests validate against the open_api_spex schema; frontend
  tests mock the client generated from the same schema — the suites
  agree on the contract without booting each other.

### 2.9 Auth and identity

- **Permissions are code; roles are data.** Permissions: compile-time
  atoms declared by the owning component (`permissions/0`), on the
  spine, collision-checked. Roles: product-level aggregations as rows
  in the auth component's store, platform-seeded defaults, edited via
  the auth component's admin surface (which is therefore the
  role-editor UI for free). Rationale for the split: a permission is
  component-local fact; a role is product policy no single component
  has standing to define — roles-as-code would make every permission
  ticket touch a shared file (mutex serialization).
- **Enforcement at the boundary, declared:** `@requires_permission`
  on exports via a platform macro that both enforces and registers the
  function→permission mapping. Deny-by-default: the audit flags
  exported mutating functions with no declaration, dead permissions,
  and undeclared atoms.
- **Docs split by altitude:** the permission taxonomy and role
  semantics are design-tier standing decisions (comparch grows a
  `<permissions>` block); the function→permission→role matrix is
  generated from extracted metadata + live rows, never hand-written
  (orchestration's "no code inventory in docs" rule applied).
- **phx.gen.auth verdict:** runtime-scalable (stateless plumbing over
  Postgres — fine clustered), feature-insufficient (no SSO/MFA/orgs/
  authz), and philosophically wrong for a platform (generate-and-own
  means N projects with drifting unpatchable auth code). Therefore:
  **a platform-maintained identity component** (§3) — phx.gen.auth's
  patterns as starting material, versioned and upgraded centrally.
  Core: magic link + password, DB sessions, MFA/TOTP, API tokens,
  org/membership/invitations. Enterprise: SSO as OIDC client (assent);
  SAML explicitly deferred (painful, shrinking share). External IdP
  (Keycloak/WorkOS) rejected as default: ops dependency + off-platform
  system of record, against self-hosted grain.
- **Backend platform-maintained; frontend project-generated.** Auth and
  admin screens must be customizable/skinnable, so the shared
  component ships headless and its UI arrives via the UI contract
  (§3.3) — required screens and component collections the project's
  chain generates against the shared backend's pubapi.
- **Tenancy:** org/tenant model lives in the identity component;
  single-vs-multi is a design-time option on the external dependency
  (§3.4), not a runtime flag — it changes schemas, scoping, and screen
  inventory. Multi-tenant projects get the scoped-repo rule
  (Phoenix 1.8 scope pattern threaded down; an Ecto `prepare_query`
  hook that raises on unscoped access to tenant-owned tables) —
  promoting the worst auth bug class from review-hope to runtime
  guarantee + audit check. Default-on vs opt-in: **open**.
- **Consolidated identity design (from both gap passes + author
  additions):**
  - **Consumption is optional; the principal is pluggable.** Shared
    components are dependencies a project declares, not obligations.
    `@requires_permission` and role rows bind to a principal
    *behaviour* the identity component implements by default and a
    project may substitute (Haven: member identity is client-held
    keypairs, a Haven domain component; the platform component serves
    the ops/admin plane only).
  - **Option vocabulary grows:** `passwords: on | off` (passwordless
    magic-link-only is a legitimate resolve), `registration: open |
    invite_gated | invite_only`, and **versioned consent** in the
    identity core (signup gating needs it; a future compliance
    component consumes rather than owns it; version bump →
    re-consent). The §3.3 UI contract's required-screen list varies
    with resolved options — no password screens in a passwordless
    resolve.
  - **Invite links are first-class**: single-use or reusable,
    revocable, and **role-carrying** (an admin mints a link that
    grants a named role on redemption). This is the dependency-free
    staff-onboarding floor — no SSO, no email-domain rules, a link
    with a role on it — with OIDC as the tier above.
  - **Bootstrap pattern absorbed into the core:** first account is
    superadmin, pinned by partial unique index (a race cannot mint a
    second), un-demotable, never assignable by promotion.

### 2.10 Feature flags

Rationale first: main is production, merges are unattended, there is
no staging — so any feature spanning multiple tickets has partial
state on prod mid-milestone. Orchestration never addresses this;
Catapult minting whole batches of tickets makes it untenable. Flags
are the platform primitive that makes the deploy model safe:

- FunWithFlags (Ecto-backed, actor/group targeting, admin UI slots
  into the admin-surface convention).
- Flags registered via `feature_flags/0`, spine-named, collision-
  checked; a new flag is a §2.8 named decision.
- **Lifecycle from existing machinery:** a feature's tickets land
  behind the feature's flag; a milestone's `retro` queue closing (the
  author's manual pass — already the only manual-testing point —
  revised at ORC-105 from "the milestone boundary") is the natural
  flip point; flag *removal* is gating debt — `retro`'s debt scan gets
  a bounded input "flags fully-on for > N milestones" and files
  cleanup proposals into `cleanup`/the next milestone's `prep`
  (§4.5, §7.8).
- **Flags partially substitute for staging:** the author's pass
  exercises flagged-off features on production via actor targeting.
  Not a full substitute (schema changes and deploy-time behavior still
  hit prod raw) but covers review-before-users-see-it, which is most
  of what staging was for.
- **Delivery-model update (§7.5, §7.8):** deploys are per-feature
  (feature PR squash-merges to main), so "partial feature on prod"
  mostly evaporates; flags earn their keep as staged rollout,
  kill-switch, the author's flagged-in prod validation, and the
  milestone flip — a milestone "ships" by aggregating and flipping
  its features' flag set once `retro` closes clean (§7.8).
- Scope discipline: release flags only, plus ops kill-switches owned
  by the component wrapping an external dependency. No percentage
  rollouts/experimentation — machinery without a customer at this
  scale.
- React reach: flag state is part of the standard API surface.

### 2.11 Observability

A shared component (§3): telemetry core, provider subcomponents as
adapters (pluggable backends). Backends live **outside the deployment
envelope** — the system that reports failures must not share a failure
domain with the system it reports on; users likely want external
providers anyway.

- **PromEx** as the metrics engine: Prometheus exposition, plugins for
  Phoenix/Ecto/Oban/LiveView, and Grafana dashboard provisioning as
  code — each component's registered events generate a per-component
  dashboard (the ops sibling of the admin surface).
- **Instrument the boundary:** the same macro layer that carries
  `@requires_permission` auto-emits telemetry spans for every exported
  function — every component gets latency/throughput/error-rate at its
  public surface with zero per-ticket work. Highest-leverage single
  convention in the set: AI code will never instrument itself
  consistently.
- Events registered (`telemetry_events/0`, `[:app, :comp, :event]`);
  audit checks declared↔emitted in both directions.
- **Logs: structured JSON to stdout, and stop there.** Shipping is a
  collector's job outside the envelope. Reference stack prefers Loki
  over ELK (pairs with the required Prometheus/Grafana, label-indexed,
  far lighter); ELK is just another provider adapter.
- **Logs are write-only, with a metadata floor — and deliberately
  unregistered** (ops-enforcement pass). No log registry, because
  anything worth replaying is an event and anything worth counting
  or alerting on is registered telemetry — logs are the residue,
  human-readable forensic context, and ad hoc is *correct* for
  residue. The fence that makes ad hoc safe: **nothing may depend
  on a log** — no parsing, no log-pattern alerting, no log-derived
  state; a consumer reading logs back is the tell that the signal
  belongs in telemetry or the event log. (Orchestration's marker
  rule inverted: it made comments parseable because they were
  load-bearing; we make logs explicitly not.) The floor: the
  boundary macro sets Logger metadata (component, trace id) at
  every export entry, so even a one-off log inside a component
  arrives structured and greppable at zero per-call cost.
- **Content-log channel split** (Polyphony pass): the logging
  convention supports a declared split between operational logs and
  content-bearing logs (user data, transcripts), the latter on its
  own channel with a declared retention window and a project-supplied
  redaction policy. Boundary auto-instrumentation must never route
  content through the operational channel by default.
- **Thread trace context now, export later:** platform enqueue/
  broadcast wrappers carry trace ids through Oban jobs and PubSub
  invisibly; the OTLP exporter is a later provider subcomponent.
  Cheap now, miserable to retrofit at a hundred workers.
- Error tracking via `tower` (backend-pluggable) as one more adapter.
- Reference stack ships as a docker-compose (Prometheus + Grafana +
  Loki, dashboards provisioned), documented to run anywhere that isn't
  the app's host. The app's contract: `/metrics`, structured stdout,
  `/health` (§2.13).
- Dogfood note: the Catapult control plane uses this component, so
  pipeline health (tickets in Blocked past threshold, stale claims,
  deploy timeouts) becomes Prometheus metrics — closing orchestration's
  "no alerting anywhere" open item as a side effect.

### 2.12 External data

Three classes, different rules:

- **Reference/seed data:** per-store `Comp.Seeds` composed by a root
  release task; **idempotent by construction** (upserts, stable
  natural keys) — forced by the deploy model: one environment, no
  fresh-database moment, seeds run repeatedly against live prod.
- **External services:** every third-party dependency wrapped in its
  own component/subcomponent; standard adapter behaviour with two
  shipped implementations — real client (Req) and in-memory fake —
  selected via Vapor. This is orchestration's own port/adapter/
  memory-fake architecture imported into target apps (one pattern for
  prompts to carry), and it's what makes no-network tests possible:
  CI and reconciliation run without third-party creds and merge to
  prod on green. Pull-based syncs are Oban jobs on registered queues.
- **Uploaded/user data:** just schema (§2.4). A platform-blessed
  storage component (S3-compatible) is a likely future shared
  component, not designed here.

### 2.13 Deploy and health

Standard health endpoint on every generated app: git SHA + per-
component readiness (from the registries). Rationale: makes delivery's
post-deploy check provider-independent (one HTTP GET, SHA-ancestry
against the merge commit) and gives ops and the pipeline the same
facts. Quality gates are platform-fixed, not per-project config:
format, credo, warnings-as-errors, boundary check, registry-collision
check, migration lint, pubapi-drift check, storybook export build —
shipped as **`mix catapult.audit`**, the target-project counterpart of
orchestration's `pipeline audit`, checking compiler-backed facts
instead of YAML. The reconcile agent runs the same task — keeps its
verification honest across projects. **Type checking: the native
set-theoretic checker, not Dialyzer** (sleeper pass — resolves the
former open item): Elixir's built-in gradual type checker runs
*inside* `mix compile`, so `--warnings-as-errors` — already a gate —
makes it an enforcement organ with zero added latency, and it
strengthens with every Elixir release. Boundary exports carry
typespecs (they're documentation there anyway); signature drift on a
pubapi becomes a compile failure. Dialyzer stays out: its CI-loop
cost buys mostly overlap now, and the overlap grows.

### 2.14 The audit as the enforcement organ

Accumulated `mix catapult.audit` checks, gathered because each is
invisible from where it applies: boundary partition matches doc-graph
scopes; registry collisions (topics/queues/flags/permissions/events/
env prefixes); single-owner tables, no orphans; unregistered process
names; undeclared cross-boundary Multi (transaction audit); exported
mutating functions without permission declarations; dead/undeclared
permission atoms; declared↔emitted telemetry both directions; every
boundary export has a test; bare `@tag :skip`; migration safety; docs
folder and admin surface present; pubapi fragment ↔ boundary exports
drift; UI-collection files containing backend calls (§5.4); OpenAPI
diff vs prior release for undeclared breaking changes (§4.4).

Delivery-side promotion (§7.5): a ticket's diff touching files
outside its Boundary-derived file map is an **automatic bounce** —
plane-authored marker comment naming the paths, `Ready for rework`,
no human involved. Orchestration's mutex audit promoted from
CI-blocking finding to auto-routing.

Additions from the gap passes: the ES family's purity-floor
call-graph check and `events/0` collision check (§2.4); foreign-
language subcomponent gates (`cargo test`/`clippy`, §2.15); the
client-side audit (declared-slot checks, no-backend-calls-in-UI-
collections, §5.6); OpenAPI *and* channel-contract diffs vs prior
release for undeclared breaking changes; the stub inventory and its
ticket-sync check — every `implementation: stubbed` scope has exactly
one open `Stubbed` swap ticket, and a swapped or deleted scope's
ticket closes with a comment (§2.16, §7.10); the enforcement-gap
inventory and its ticket-sync check — every policy×scope missing its
declared-grade artifact has exactly one open enforcement ticket
(§4.5).

**Sleeper-check additions (ecosystem pass — adopted wholesale):**

- **Dependency vulnerability + retirement checks** (`mix deps.audit`,
  `mix hex.audit`) as the CI-side floor beneath §7.10's maintenance
  watcher: the watcher files upgrade tickets for what's already in;
  this blocks a merge *introducing* a known-bad dep. (Advisory data
  fetches like deps fetch — §2.8's no-network rule governs the test
  suite, not the toolchain's package and advisory fetches.)
- **Sobelow** on every Phoenix-bearing project — security static
  analysis as a stock gate; arms when a web layer exists.
- **`mix xref` graph gates**: compile-dependency cycles prohibited,
  plus a **ratcheting compile-connected cap** — the erosion metric
  for §1's coupling theory, from a stock command; the cap may never
  rise without a reviewed change.
- **Lockfile integrity is a hard gate** (`deps.get --check-locked`,
  never softened) — a lockfile that drifts silently is a supply
  surface and a reproducibility lie.
- **The grep checks graduate to AST-grade custom Credo checks**
  (`utc_now`, unregistered `name:`, raw topic strings): no false
  positives from comments and strings, IDE-surfaced, and
  `catapult:allow` implemented as a real mechanism rather than
  same-line text.
- **Boundary's external-dependency mode** promotes adapter
  conventions from prose/grep to compile grade: only `Store`
  subcomponents may depend on Ecto, only the outbox wrapper on
  Oban's insert surface, only adapters on Req — and no model-call
  library anywhere in plane code, making conventions §11 a compile
  error rather than an architecture-review catch.

**Registry-completeness additions (ops-enforcement pass):** the
`errors/0` declared↔constructed check plus remedy presence (a
registered kind with no remedy is an audit failure); every
external-HTTP usage inside a registered `externals/0` adapter;
secret-flagged config values never appearing in logs or error
payloads; cron schedules declared on queue entries, never bare in
plugin config.

### 2.15 Non-Elixir components (the escape hatch, defined)

Two grains, replacing §1.4's "shape TBD":

- **Foreign-language subcomponent** (library grain): the crate lives
  *inside* a component's file map; the component's Elixir wrapper
  module is its Boundary export and pubapi; the slug spine derives
  the crate name; the audit runs the foreign toolchain's checks. The
  same crate's WASM build is consumed by client-locus components
  (§5.6) as an external node — one source, two build targets (Haven's
  Rust crypto: NIF server-side, WASM client-side).
- **Service grain**: lives outside the deployment envelope entirely,
  wrapped in-app per §2.12's adapter convention — the observability
  pattern (§2.11) generalized (Haven's Go transparency log, if not
  descoped).

Vetted third-party crypto ships as **external nodes** (§3.2), which
makes "AI wraps, never implements" structural: the dev agent cannot
edit what is outside the repo tree and the file maps. Review-pending
*compositions* (project-owned crypto-adjacent code) use the
`enforcement:` mechanism (§6): `codegen: restricted` on the scope.

### 2.16 Stub grade: gates gate the swap, not the pipeline

A scope may declare **`implementation: stubbed`** (comparch grammar,
§6): the real, reviewed pubapi over a deliberately hollow
implementation — identity-function crypto, map-backed credentials.
Founding case: scopes whose real implementation waits on an external
human timeline (professional cryptographic review); the pattern is
general (legal sign-off, compliance, absent partner credentials).
Rationale for existing at all: the human gates run on a different
clock than the pipeline, and shipping-with-declared-stubs beats not
shipping.

- **A stub contains no restricted content, so `codegen: restricted`
  does not apply to it.** The stub runs the ordinary pipeline; the
  gate rides the *swap ticket* (§7.10). The pipeline never stalls on
  a human timeline; the only work that waits is the work that
  genuinely needs the human. (This is Haven's federation-readiness
  doctrine — architect totally, stub the deferred arms — applied to
  the crypto core, and §1.1's argued-deferral rule with teeth.)
- **The stub implements the reviewed contract verbatim, types
  included**: opaque newtypes from day one (`Ciphertext` that happens
  to wrap plaintext, `Credential` that happens to wrap a map), so
  every call site is already shaped for the real thing and the swap
  is implementation-only. Convenience leaks are the drift disease;
  the pubapi-drift audit checks the signatures for free.
- **The lie must be loud.** `implementation: stubbed` flows into the
  handle, per-component readiness (§2.13), the admin surface, and —
  for security properties — the UI contract, so honest state is
  renderable. The audit maintains a stub inventory in every release.
  Consent is product-side but mandatory in spirit: nobody discovers
  a stub by being burned by it.
- **The exit plan is declared at stub time**, in the deferral's
  argument: `swap: transparent | migration | reset`. For stubbed
  E2EE the caveat is epistemic, not mechanical: data created under
  the stub was server-readable, and no later migration retroactively
  unsees it — the guarantees hold only *forward* from the swap. The
  exit plan must say what happens to stub-era data (wipe, or
  grandfather with permanent disclosure).
- **The stub is the fake.** The runtime stub and the port's test fake
  are the same module; the contract suite written against the stub is
  the swap verification — the real implementation must pass it
  unchanged, plus its property-specific tests.

Deliberately **not ported to orchestration's Go protocol**: it has no
implementation contracts to hold a stub's shape against, and the
stubs in Catapult's own build are small and short-lived. Catapult
delivery machinery only.

---

## 3. Shared components and the registry

### 3.1 The registry

**Git for distribution; public hex.pm for public publishing.**
Revised from the original `mini_repo` decision (self-hosted
hex-compatible registry, packages published from the monorepo rather
than hex.pm), which is struck rather than deleted because the
reasoning is worth keeping: it was made for *components*, and it
silently became the assumed answer for bundles and policy packs,
which were never in the registry's artifact list at all.

The two things hex does that git cannot are **retirement and advisory
signalling** (`mix hex.audit`, armed in CI and load-bearing) and
**real version resolution across a diamond**. Both matter for public
code consumed by strangers. Neither earns its keep here: §3.1's
single release train designs the diamond away (*"which auth works
with which catapult"* is a non-question by construction), and
Catapult's own components appear in no advisory database — third-
party deps, which remain ordinary hex packages, keep their audit
coverage untouched. What hex was being bought for — **private,
org-blessed registries** — git provides as ordinary private repos,
so that argument never favored hex to begin with.

What git adds is the thing the artifacts actually need: **fork, tailor,
and merge upstream later.** Hex has no merge story; a fork is a
permanent exile. That lifecycle is normal for bundles and policy
packs, and — see §3.5 — legitimate for components too.

**Public artifacts still publish to hex.pm**, where ecosystem
discovery, `hex.audit` for consumers, and docs hosting are real and
free. The split is by *audience*, not by artifact kind: public goes
to hex, everything internal and org-private lives in git.

**Distribution is independent of the forge** (§7.17). Git-based
distribution works on whatever forge a customer already uses and does
**not** require Gitea; the two decisions were briefly entangled and
are hereby separated. Keeping the registry off the forge is what
keeps the forge a cheap swap — an artifact store riding the forge
would relocate every customer's artifacts on a forge migration, not
just their code.

**Monorepo, single release train, per-component semver.** All shared
components live in the Catapult repo; every release publishes all
packages plus their extracted handle artifacts, tested as a set.
Rationale: the components' schemas, handles, bundle grammars, and the
reducer have compatibility relationships; a monorepo makes them tested
together per release instead of managed via a version matrix
("which auth works with which catapult" is permanently a non-question).
Repo-per-package (the hex.pm-shaped temptation) is explicitly
rejected. Shared components are ordinary orchestration *systems*
(`systems/auth.md`, file maps, mutex labels) in Catapult's own
delivery; the registry is purely a distribution seam.

### 3.2 External nodes in the DSL

New generator type **`external`**: a node present in a project's
graph, content-bearing, participating in context walks like any
upstream node, whose content resolves from the registry at a pinned
version. Lifecycle maps onto existing machinery:

- "Approval" is version pinning (dependency declaration in
  `catapult.yaml` / the bundle).
- **Staleness is a version bump** → the existing downward-propagation
  flow, seeded by the new version, generates per-scope upgrade plans →
  tickets. "Platform ships an auth security patch; every project
  receives a designed, reviewed, ticketed upgrade through its own
  pipeline" is the downward flow with an external seed — near-free.
- The handle is **extracted, not authored twice**: the shared
  component's docs folder + boundary exports + permission registry +
  config surface are the source; its build publishes the handle
  (pubapi, permission vocabulary, config surface, upgrade notes)
  alongside the package.
- **`external` is one of two modes** (§3.5). A component may instead
  be **adopted**: its documents enter the graph as ordinary generated
  nodes and its code is generated into the tree. The transition is
  explicit, recorded, and one-way in practice — an adopted component
  stops receiving the version-bump staleness above and receives
  handle-diff-seeded absorption tickets instead. Nothing else in this
  section changes: an unadopted external node behaves exactly as
  described.

Upgrades have two channels: **codemods for the mechanical part**
(dep bump, renames — Igniter is the candidate framework, run inside
the ticket, deterministic) and **doc-chain regeneration for the
designed part** (project-owned screens re-drafted against the new
handle, reviewed like any design change). Structured upgrade docs ship
with each release as the propagation flow's planning context.

### 3.3 UI contracts

A shared component with project-generated frontend declares in its
handle: **required screens** (login, invite, MFA enrollment — arriving
as externally-seeded screen nodes with states and affordances fixed,
grouping only *suggested*) and **required component collections**
(avatar, user-menu — collection nodes whose UI pubapi the contract
specifies, implementation project-generated against the shared
backend's pubapi). Skinnability falls out: the project designs the
skin; the contract fixes coverage.

### 3.4 Options (design-time configuration axes)

External dependencies carry options from a closed vocabulary declared
in the shared component's manifest (`tenancy: single | multi`,
`sso: none | oidc`). The resolved handle varies by option (schemas,
scoping rules, screen inventory); downstream generation reads the
resolved shape and never sees the other variant. Changing an option
later is a version-bump-shaped event (staleness cascade → upgrade
flow). Options are runtime-invisible and closed-vocabulary — the same
discipline as the predicate language, deliberately not expressions.

### 3.5 Governance

- **A component has two consumption modes, and adoption is an
  explicit, recorded, one-way act.**
  - **Dependency** (the default): the component resolves into
    `deps/`, outside the repo tree and outside file maps, and appears
    in the graph as an `external` node (§3.2) whose content is
    read-only and whose "approval" is version pinning. Here the
    standing guarantee holds — **the dev agent never edits
    shared-component code, structurally**. That guarantee rests on
    *being a dependency*, not on being a hex one, so it survives
    §3.1's move to git unchanged: a mix git dep resolves into `deps/`
    exactly as a hex package does.
  - **Adopted**: the component's *documents* enter the project's
    graph as ordinary generated nodes, and its code is generated into
    the tree like any other component's. Agents edit it because it is
    now the project's, and it passes the same review gates as
    everything else.
- **Adoption is the fork, and it is legitimate.** An earlier draft
  called forking pathological and then tried to save the claim with
  an org-versus-project distinction. Both were wrong. `LICENSING.md`
  puts `components/**` under Apache-2.0 *precisely* so it ships into
  generated projects; §2.9 already builds in a pluggable principal;
  and the org/project split does no work at this target class, where
  an enterprise-scale monorepo means one org routinely has exactly
  one project. Auth is the likeliest adoption of all — bespoke SSO,
  legacy password hashes, jurisdictional requirements. Adoption works
  *because* these components are Catapult-shaped: comparch documents,
  file maps, handles, conventions. They slot into a graph natively in
  a way no ordinary dependency could.
- **The merge target is the documents, never the code.** This is what
  makes adoption survivable rather than a one-time copy. Regenerated
  code does not correspond to upstream's code, so merging upstream
  *code* into it is either perpetual conflict or meaningless; merging
  upstream's comparch and impl *documents* into the graph works, and
  regeneration follows. **The upgrade path is therefore already
  built:** an upstream release produces a handle diff, the handle diff
  seeds an **absorption ticket** (§7.3), and the ticket runs the
  upward flow — documents absorb reality, walking upward only as far
  as the change argues. Same machinery as an out-of-band commit;
  different trigger.
- **What adoption costs, stated rather than hidden:** you own that
  component's security patches, §2.9's central-propagation argument
  stops protecting you for it, and the handle is now yours — upstream
  handle diffs become advisory rather than authoritative. §2.9 still
  refuses *accidental* generate-and-own ("N projects with drifting
  unpatchable auth code"); what it never refused is a deliberate,
  recorded divergence that someone chose with the bill in view.
- **This is not the absorption `docs/non-goals.md` refuses.** That
  entry rejects ingesting *existing outside codebases*, on the stated
  grounds that "the platform's structure is narrow by design and
  existing apps won't conform to it." A Catapult component conforms
  by construction — it is the structure. The reason does not reach
  this case, which is why the resemblance is worth a sentence.
- Push-back channel: a project's pipeline discovering a shared
  component is wrong files a **cross-project upward finding** — an
  issue against Catapult's own tracker. Designed escape hatch, not
  improvisation.
- **Handle semver:** pubapi + UI contract + permission vocabulary is
  the ABI; breaking changes to any of the three are major versions.
  The registry diffs handles across versions mechanically — the diff
  is the upgrade flow's seed and the breaking-change detector.
- Compliance components are the strongest case for all of this
  (audit logging, retention, consent/export/deletion screens,
  push-based upgrades when regulation shifts) and need zero new
  machinery.

---

## 4. The product tier (UX/IA)

### 4.1 Product, not architecture

The UX/IA tier is **product definition**. The three-way split that
replaces domain/presentational + fanin:

1. **Screen definitions** — product tier: surfaces, states,
   affordances, shown data, IA graph. No visuals, no components.
2. **Backend components** — architecture tier (the ported siege
   chain), never seeing screens directly.
3. **Frontend components** — architecture tier (§5), downstream of
   both screens and backend pubapis.

The acyclicity argument, stated as the spec rationale: **backend
depends on what users can do; frontend depends on how the backend does
it.** Backend→screen routes upward through resp → feat → journey/
screen (the bridge); frontend→backend routes through pubapi handles.
The arrows never meet head-on. The bridge routing is defended
specifically (against the future "just let sysarch read screens"
simplification): it preserves the meaning-engine rotation — backend
receives capability demands with presentation already rotated out, so
screen cosmetics stale nothing backend.

Chain placement: `inputs → feature_expansion → journeys → screens →
requirements → sysarch → …`. UX/IA before requirements grounds the
rotation tier in concrete surfaces — historically the mushiest tier.

**Screens-first and hybrid intake: one chain, always downward**
(mocks pass). Many projects now arrive screens-first — the author
worked the idea out as mocks or a vibe-coded prototype, and the
feature list lives in those screens. Supported without a second
traversal mode: **mocks are raft members** (an optional `mocks`
input role as classification signal; free-form, frozen at intake
like every input), and generation stays top-down — deliberately no
upward intake variant. Two tiers read the evidence: **feature
expansion** (the feature list may come *out of* the screens; mock
evidence and prose docs are weighed together, which makes the
hybrid case native rather than special — mocks-only is just a raft
thin on prose) and **the screens tier directly** (so visual and
state evidence shapes definitions without having to survive two
abstraction rotations first). Agents-end-to-end makes mocks
*runnable* evidence — the intake agent renders and interacts with a
prototype rather than squinting at its source. Two disciplines
carry the weight: extraction prompts **complete the negative
space** — mock sets show happy paths, and proposing the missing
empty/error/loading/denied states is the chain improving the mocks,
not transcribing them — and **mock code is evidence, never copied**:
the fresh-scaffold rule holds. Standing visual guidance for the
delivery-time design pass rides refs (§4.5), hint-staleness as
ever; a supplied design system rides §5.4's `design_system` node.

### 4.2 Journeys

First-class nodes between features and screens. Grammar: argument,
manifested features, ordered screen walk, and a **journey state
block** — what's carried, what creates/completes it, what abandonment
means. Rationale: journey-scoped state (cart, wizard progress, draft)
is a distinct persistence class invisible in a screens-only model —
its lifecycle is the journey's, not any screen's and not yet a domain
concept's. The block rotates into responsibilities as first-class
persistence demands and lands on a store convention (journey stores
with declared TTL/abandonment). Settles mechanically: state surviving
navigation lives in a store; state that doesn't lives in assigns.

Responsibilities prefer journey references over screen references —
journey-level aggregation lets the rotation see transactions and
lifecycles instead of bags of per-screen actions. Standalone screens
are legal (settings); the bridge falls back to screen refs.
Cardinality: journey manifests ≥1 feature; screen belongs to 0..n
journeys.

### 4.3 Screen definitions

Grammar: slug (the spine — derives the `screen:<slug>` mutex label,
file map, component module, story file), purpose/argument, manifested
features, **named state list**, **affordance list** (action, intent,
data in/out), displayed data, navigation edges, screen group.

- **State names are storybook variation names** — orchestration's rule,
  pulled up to the product tier: decided once at definition; the
  delivery-time screen doc, stories, CI variation audit, and
  reconciliation all inherit it.
- **Affordances are the contract check:** reconciliation verifies the
  landed screen exposes declared affordances; the audit verifies each
  affordance maps to a reachable backend export (and flags capability
  with no surface / surface with no capability).
- **Navigation edges are cyclic and never readiness-bearing.** Users
  navigate back and forth — no `acyclic` constraint — and if nav edges
  fed readiness, a two-screen loop would deadlock the scheduler.
  Stated explicitly so no bundle author wires them into a context
  walk's readiness path.
- **Two design moments per screen, kept distinct:** the *definition*
  (product tier, pre-implementation: states, affordances, IA) and the
  *visual design* (delivery time, per ticket: classes, layout,
  stateless component, stories). The definition node seeds the
  delivery-time `screens/<slug>.md`; the design pass narrows to
  appearance and interaction against a fixed contract. Two reviews,
  different questions, no overlap.

### 4.4 API surface: thin wrapper, no API tier

The public API is **not** a frontend and not a tier. It hangs off the
backend component as a behaviour (`api_surface/0`), declaring entries
`{exported_function, path, verb, version, audience}`. The macro
accepts only boundary-exported function references — **thin-wrapper
enforced structurally; there is nowhere to put logic.** Rationale
stated aggressively: any logic living only in the API layer is drift
by construction — behavior external callers get that internal callers
don't, invisible to the component's tests. A composition worth
exposing is a read-model component (§2.6) — which then gets its own
thin wrapper. The escape hatch is therefore already spelled inside the
system; no second path, no full-API-component tier.

- Root API router composes declarations like admin routes; open_api_spex
  generates the OpenAPI document from declarations + typed contracts.
- **Convergence:** the OpenAPI artifact is the same one the React
  frontend consumes as its generated client; `audience`
  (`internal | public | partner`) separates exposure levels.
  Versioning discipline applies to `public`.
- Versioning sugar: path-versioned; new version required only on
  breaking change to a public entry; the audit detects breaking-vs-
  additive by diffing generated OpenAPI across releases (same
  handle-diff machinery as §3.5). Deprecation is entry metadata →
  docs site (generated) + telemetry (deprecated-endpoint call counts —
  "can we remove v1" becomes a Grafana query).
- The *decision* to offer an API is product-tier (a feature; optionally
  a machine-audience journey when a partner flow is real); the *shape*
  is architecture-tier (comparch declares which exports go public).
  The UX/IA tier stays purely human surfaces.
- CLI distribution: same behaviour pattern, escript composer, built
  later.
- **The realtime section (unified across both gap passes — one
  mechanism, two very different consumers as its proof):**
  `api_surface/0` grows declared **topic families** parameterized by
  `(resource, lens)`, each with: a **per-family authz predicate and a
  server-side filter hook** the project plugs a pure predicate into
  (Polyphony plugs per-character visibility; Haven plugs partition-key
  membership over opaque blobs — the platform enforces *by shape*
  that the transport can never deliver more than the declared
  projection); **message classes with declared cursor participation**
  (content events carry the catch-up cursor; framing/progress do
  not); a **filtered catch-up RPC** for reconnect (replay runs
  server-side through the filter hook — the client is never the
  filter); and **retraction** as a first-class message class ("the
  server says forget X"). Channels compose into the root socket the
  way routes compose into the root router (§2.7), emitting a typed
  client the frontend tiers consume alongside the OpenAPI client;
  contract diffs vs prior release feed the same breaking-change
  detection as REST.

---

### 4.5 Supporting tiers: refs, app prompts, policies

**The v4 supporting tiers (`ref`, `vocab`, `policy`) carry forward**
into the default bundle; this section records their v5 form (from
the refs/policies design pass).

**Refs** — project-local supplemental content (runbooks, style
guides, implementation guides, app prompt text, user-supplied mocks
kept as delivery-time visual guidance — anything the graph
should hold that no dedicated tier models): singleton pool, `id`
identity, full draft→review→approve lifecycle, attached via
reference edges, consumed comparch-and-below. Out-of-cycle iteration
is re-approval + staleness, and staleness *hints, never cascades*:
a ref edit surfaces its consumers in the staleness
projection (§7.11 — stale is derived, never stored; no node is
flagged); regeneration is chosen, not triggered, and choosing it
means filing a ticket. **Refs are the one deliberate escape hatch,
and stay general on purpose**: no per-use kinds, no special-case
lifecycles — an escape hatch that accretes special cases becomes N
more mechanisms. A ref type system is future design, taken up when
real usage shows what types would need to mean. (External components
are the sanctioned exception, and are by now their own mechanism
rather than a ref variant.)

**Policies** (siege's "invariants," orchestration's "standing
decisions," v4's policy tier — one concept, one name now) are
first-class nodes. **Non-goals are policies with negative content**
(§1.1's carrier decision): "we do not build X" is a policy like any
other — `prose` grade by default (reconciliation's refusal to
re-admit the exclusion is the enforcement), promotable, scoped by
the same three grains, seeded by the intake distillation and grown
by tickets. Deferrals ride the same shape with a **revisit
condition** ("never, argued" vs "not until X" is one field); an
implementation-shaped deferral additionally carries the stub grade
(§2.16). No new node kind, deliberately — a separate non-goal tier
would be the policy tier with the sign flipped and a second
lifecycle to maintain. Two additions beyond v4:

- **An enforcement grade per node**, a promote-from-prose ladder:
  `prose` (reconciliation's standing-decision check — exists),
  `test` (the policy names the tests that pin it; the audit checks
  they exist — Polyphony's membership-parity test pinned to the
  irony seam is the archetype), `audit` (a registered check via the
  §6 enforcement-profile mechanism), `runtime` (a guard in code —
  the tenancy `prepare_query` hook shape). Framework invariants stay
  conventions; *project* policies are nodes with declared grades.
- **Scoping at three grains**: project-global; **through
  responsibilities** — the load-bearing choice: a policy bound to
  resps binds to *what the system does*, not how it's decomposed,
  so it survives refactors, with components inheriting through
  `fulfills` (the `policy_application` type's reachability
  semantics); and direct component links for genuinely structural
  policies.

**Enforcement gaps are plane-filed tickets, instantly visible.**
When a policy node is approved, or an `applies_to` edge newly
attaches a policy to a scope, the plane files an **enforcement
ticket** (machinery-filed, like swap and maintenance tickets):
bring this policy to its declared grade on this scope — or, for an
ungraded policy, decide the grade as the ticket's first act. The
audit keeps tickets in lockstep with the enforcement-gap inventory,
the same mechanism as stub↔swap tickets: every policy×scope whose
declared grade lacks its artifact (the named test, the registered
audit check, the runtime guard) has exactly one open ticket;
`prose`-grade policies carry no gap (reconciliation's check is
inherent). Rationale: for what policies are being asked to do,
a policy whose enforcement silently doesn't exist is worse than no
policy — it's confidence without coverage; the standing ticket list
is the visibility that keeps the gap honest.

**Enforcement tickets route by a per-policy attribute**, three
lanes, author-overridable per ticket:

- **`urgent`** — files with the `Urgent` modifier (§7.3's existing
  preemption, no new machinery). Compliance and structural
  guarantees the automation or safety posture depends on.
- **`feature`** — rides the work that created the gap: a policy
  newly attached during a feature's cascade files as a **blocking
  child of the introducing feature ticket** — the feature cannot
  pass `Validating` without the enforcement, because for a
  product-load-bearing policy (Polyphony's visibility guarantee is
  the archetype) the enforcement is part of what "the feature
  works" means. A policy created against already-shipped scopes
  files into the current milestone directly.
- **`debt`** — **revised at ORC-105**, since there is no next debt
  milestone to accumulate to: the same gating test that used to sort
  "next debt milestone" from "backlog" now sorts the *current*
  milestone's `cleanup` queue from the *next* milestone's `prep` queue
  (§7.8) — "does the next milestone get materially harder without
  this" routes to `prep`; everything else lands in this milestone's
  own `cleanup` rather than an indefinite backlog. Code style and
  non-load-bearing conventions.

The default policy set ships with routings (structural/`fixed`
leans `urgent`; style leans `debt`); registry policies declare
theirs; and since defaults arrive with their enforcement, routing
matters only for the gaps that actually occur — project-added
policies and raised grades.

**External policies are a registry artifact kind**: a policy that
ships *with its enforcement* — node content in the handle, audit
checks via the extension mechanism, runtime guards as a
shared-component dep where needed, test templates. Compliance is
the founding case: regulation changes propagate through the same
upgrade flow as any external node.

**The convention corpus ships as the default policy set** (author
proposal, adopted): the elixir-target conventions become external
policy nodes — each with its enforcement attached (the substrate's
audit checks and macros are the artifacts), consumed by every
project as defaults. Three payoffs: the policy mechanism gets its
first consumer on every project's day one rather than at
compliance-someday; convention revisions reach existing projects as
governed upgrades (version bump → staleness → reviewed ticket)
instead of silent substrate drift; and deviation becomes a reviewed
graph change to a visible node instead of a forked doc
(`catapult:allow` stays as the line-level point exception). Each
policy carries a **mutability grade**, the `tunable` idiom
generalized: `fixed` (automation-load-bearing — the pipeline's
correctness depends on it; overriding is a load error: single-owner
tables, registry collisions, test determinism, file-map honesty,
marker discipline — enumeration illustrative, finalized with the
policy-set build), `tunable` (declared parameters within a shape),
`optional` (default-on, replaceable with a declared substitute).
Strengthening is always allowed; weakening only within declared
mutability. Because defaults arrive *with* their enforcement,
consuming the set files zero enforcement-gap tickets — gaps appear
only for project-added policies and raised grades, exactly when a
human should see one. Known drift risk, recorded: `conventions.md`
governs Catapult's own repo (no doc graph); the policy set governs
target projects; both derive from this document — eventually the
conventions doc's target-relevant sections should *generate from*
the policy set, per the no-hand-maintained-inventories doctrine.

## 5. Frontend architecture

### 5.1 Two collection kinds, six architecture tiers

Frontend components split into **screen collections** (pages/LiveViews
hosting screens, grouped by IA region) and **UI component collections**
(reusable widgets — auth's avatar, orders' order-card). Rationale:
(a) shared-widget work doesn't mutex-serialize with screen work
(different labels); (b) screens consuming another area's widgets is
the system working, not entanglement, once the layering rule holds;
(c) collections-as-nodes (vs. a runtime registry pattern) keep edges
declared, so widget changes stale exactly the consuming screens —
a registry would give composition while hiding the edges (no
staleness, no mutex adjacency, no reconciliation check). Written down
because a registry will look simpler to every future design pass.

These are **separate tiers, not kinds on one tier** — three families:
backend `comp/comparch/subcomp/subcomparch/impl_backend`, UI
`ui_coll/ui_collarch/ui_subcomp/ui_subcomparch/impl_ui`, screen
`screen_coll/screen_collarch/screen_subcomp/screen_subcomparch/
impl_screen`. The decisive argument: **type-level acyclicity makes the
layering rule a bundle-load guarantee** — with distinct tiers, a
backwards edge (UI collection → screen collection) is inexpressible;
with kind-flags it's a same-tier edge policed by weaker instance-level
machinery. Secondary arguments: per-family prompts, grammars, handles,
and review criteria all genuinely differ; tiers are cheap by the DSL's
own design ("adding a tier is a bundle edit"). Shared prompt content
is handled by Liquid partials (§6), not by merging tiers.

### 5.2 The layering rule

> Screen collections may depend on any component collection. Component
> collections never depend on screen collections — only on backend
> pubapis (shapes) and the design system.

Pages depend on widgets; widgets never know about pages.

### 5.3 Minting

**`frontend_sysarch`** — new singleton tier, sibling of sysarch: reads
journeys + screens + the backend sysarch handle; fans out both
collection tiers in one pass (the grouping decisions interact; one
design pass should see the whole frontend). Grouping arguments live
here as standing decisions.

- **Screen collections: derived-ish, grouped by IA region** (shared
  layout shell, auth context, navigation neighborhood) — *not* gated
  on journeys: login/signup share a shell and no journey; a single
  journey may legitimately cross collections. Journeys are a signal,
  not a gate. Audit findings, not blocks: singleton collections
  flagged (collections must earn their existence); a journey scattered
  across 3+ collections flagged (usually wrong, occasionally right).
- **Component collections: designed, seeded three ways** — backend
  comps (orders → order widgets), journeys (checkout widgets rendering
  journey state), and recurrence across screen definitions (the same
  card in four screens is a collection trying to exist). One of the
  few frontend places worth generation over templating.
- External UI contracts demand screens and collections but only
  suggest grouping; `frontend_sysarch` decides.

### 5.4 Shapes vs. calls

**UI collections depend on backend shapes, not backend calls.**
Orchestration requires presentational components stateless (that's
what makes the storybook export reviewable without a socket), so a UI
collection's edge to a backend comp is a `uses_shapes` dependency
(types/handle shapes only); **screen collections own all `calls`
edges** (LiveViews load data and dispatch actions against boundary
exports, hand assigns down). Audit check: a backend function
invocation inside a UI collection's file map is a layering violation.
Storybook-compatibility preserved by construction.

Frontend edge inventory: `screen_coll → screen` (hosts),
`screen_coll → ui_coll` (renders), `screen_coll → backend comp`
(calls), `screen_coll → journey` (consumes journey state),
`ui_coll → backend comp` (shapes), `ui_coll → design_system`
(primitives), plus same-tier `dependency` edges within families.

**`design_system` may be supplied, not generated** (mocks pass): a
user arriving with a design system pins it — an external or
vendored node like any §3.2 external — and the UI tiers design
against its primitives instead of deriving them. The Polyphony
pass's single-source kit-with-drift-test stance (§5.5) is the
maintenance discipline either way.

Per-family handles: backend pubapi = exported functions; UI-collection
pubapi = exported function components with assigns/slots contracts;
screen-collection handle = routes, layout slots, journey-state
consumption.

Mutex mapping: individual screens keep `screen:<slug>`; backend comps,
UI collections, and screen collections all take `system:` labels with
family-prefixed slugs (`system:ui-avatar`, `system:scr-account`).
Cross-family staleness (collection change staling screens) routes
through re-evaluation flags, not mutex blocks — the mutex prevents
file collisions; re-evaluation handles semantic downstream impact.
Both mechanisms already exist in orchestration.

### 5.5 The React fork

Identical screen definitions and dependency shape; the fork is only
which pubapi representation the frontend tiers consume (in-process
boundary exports vs. the generated OpenAPI client) and which delivery
conventions apply (phoenix_storybook vs Storybook JS; tokens in theme
file vs Tailwind config). The product tier doesn't know which frontend
exists. Whether React is a first-class peer or tolerated variant:
effectively answered as *peer with shared spine*, but the React
convention set is less developed and needs its own pass. The blessed
shape for that pass is settled (§1.4): React hosted by Phoenix, SSR
for public content, hydrate for the authed app; Node workers under
the supervision tree, inside the observability and health
conventions. Carry-in from the Polyphony pass: the single-source
design-kit-with-drift-test stance.

### 5.6 Client-locus components and the client corpus

**`locus: server | client`** is a platform attribute on the
backend-component family. Client-locus components are domain
components that deploy into the client bundle: they own client-side
state, persistence, protocol machinery, and sync; screen collections'
`calls` edges target their pubapis; **the UI tiers stay thin** and
never learn what sits behind the pubapi (crypto, caches, cursors).
The thickest code in a client gets the full architecture treatment —
comparch, pubapi fragments, store subcomponent, boundary-level tests
against fakes.

**`platform-client-ts` is a platform-layer deliverable** (author
call), seeded by Haven (the stress case) and Polyphony (the median
case). Its slots, consolidated from both passes — and the governing
rule, forced by Polyphony's no-client-held-unsaved-work standing
decision: **slots are declared capabilities, not mandates; the audit
checks what a project declares**:

- **Persistence convention** (client store; must support
  **retraction** — "forget X" — as a first-class store operation,
  not just append/update).
- **Persisted outbox** (optional; offline/optimistic sends).
- **Import-boundary lint** — the Boundary analog; enforces
  shapes-vs-calls (§5.4) in TS: UI collections import types only,
  screen collections own calls to the generated clients.
- **Composed client root + lifecycle contract** — every client-locus
  component declares init/restore/flush hooks; remount must restore
  everything (mobile OS tab-kill is the design case; Haven's
  key-restore and Polyphony's remount-resync are the same hook).
  Includes **URL-as-view-state**: Back works, a link names a place.
- **Typed realtime client** — the client half of §4.4's realtime
  section: topic families, cursor classes, catch-up, retraction.
- **Client-side audit** — declared-slot checks, storybook
  render-test-per-declared-state, no-backend-calls-in-UI-collections.
- **SSR/hydration boundary guidance** — which slots apply on the
  public (server-rendered, no channel client) vs authed side.
- **WASM externals** — vetted foreign-language builds (§2.15)
  consumed as external nodes; the client twin of the NIF rule.

---

## 6. DSL delta vs. the v4 spec (accumulating)

- **New generator types:** `external` (§3.2 — registry-resolved at
  pinned version) and `template` (deterministic scaffold with slots
  filled from upstream handles, no LLM, same grammar validation — for
  store subcomparchs, skeletons, and other tiers where templating
  beats designing; cheaper, byte-reproducible, nothing to review).
- **Bundle layering:** `extends:` — a `platform-elixir` base layer
  (conventions, grammars for permission/process-inventory blocks,
  template tiers, external-node declarations, audit grammar) that
  project bundles inherit and overlay. Without it every project forks
  the convention corpus.

  **`extends:` is chain-axis only** (§7.8, §7.18). Delivery ships no
  layer on the workflow axis: its default gates and environments are a
  **template** a project's workflow bundle forks, never something a
  loader composes at runtime. The reason the two axes are separate at
  all is untouched by that — shipping delivery from the language layer
  would tie the workflow vocabulary to one target stack, and the point
  of the split is that one organization's workflow spans decompositions
  differing by stack.
- **Liquid partials** (`{% include %}` / shared snippet files) — one
  source for shared prompt framing across the six architecture tiers;
  per-tier files for what differs. (Siege's `_shared.py` pattern,
  moved into the bundle.)
- **Edge annotations:** `consistency: transactional | eventual` on
  dependency edges (§2.6).
- **Options on external dependencies** (§3.4): closed vocabulary,
  declared in the shared component's manifest.
- **Grammar growth:** comparch gains `<permissions>`; subcomparch
  gains a process inventory; impl's `<tests>` block becomes normative
  (§2.8); journey and screen grammars per §4.2/§4.3; comparch gains a
  per-scope **`enforcement:` block** naming platform-defined
  enforcement profiles — `codegen: restricted` (human gate at child
  reconcile + auto-bounce without an override label), `purity:
  replay_floor` (call-graph audit), and whatever comes next: one
  grammar slot instead of accreting one-off markers. The
  backend-component family gains **`locus: server | client`** (§5.6)
  and the ES store family declares its grade (§2.4). Scopes also
  declare **`implementation: stubbed | real`** with a `swap:` exit
  plan (§2.16) — the stub grade that decouples externally-gated work
  from the pipeline's clock.
- **The core/extension mechanism (§9)** — the DSL has a frozen core
  and platform-registered extensions; the delivery annotations, flow
  ticket faces, enforcement profiles, `ticket.findings` context
  source, and the generation-runtime profile are all instances of it.
- **Nav edges:** cyclic-legal, never readiness-bearing (§4.3).
- **A delivery section** — ships from the platform layer, sharing the
  node vocabulary with the design graph. Now specifiable per §7: the
  shared status vocabulary and the two lifecycles (feature + child)
  with the type-invariance sharing test; per-flow entry-tier mappings
  and which gates each entry skips; the plan-tier → child-spawn-list
  join point; mutex-label derivation from scopes; the branch/PR
  topology (child PR → feature branch, feature PR → main); gate → CI
  label mappings. Shape settled in §7.10: tier-side `delivery:`
  annotations and flow ticket faces extend the existing syntax
  (membership declared at the member, protocol defining only the
  slots); spawn is a plane rule, keyed to the plan naming its own
  children rather than to a status transition (§7.10's own amendment);
  only `states.yaml` / `types.yaml` / `escalation.yaml` remain
  standalone — the files with no design-graph counterpart.

**Bundle evolution over a populated graph is a cutover, not an
edit** (docs review pass). Additive changes — new tiers, new edges —
are free: a fresh walk populates them. Anything destructive
(removals, renames, restructures, merges) requires a **cutover
ticket** with four ordered acts: (1) **the pipeline drains** — no
in-flight flow instances, new work holds; (2) a design pass compares
the old and new graph structures and emits a **graph-transform
list**, with the simple classes auto-proposed (new tier → walk it;
removed tier → delete its nodes) and the hard classes — renamed,
restructured, or combined tiers — computed by the design agent and
**human-reviewed**, because "renamed" versus "removed plus added" is
a semantic judgment no structural diff can make; (3) the migration
executes the reviewed transforms; (4) the active bundle flips
**only after migration completes**. Never a halfway state with work
in the pipeline. For platform-shipped layers, an update **ships
with its transform list** — authored upstream like §3.4's upgrade
docs — so consuming a new platform-layer version is the same
cutover with act (2) pre-supplied.

**The drain in act (1) is per axis, and the workflow axis relaxes it**
(§7.18's split, resolved at §7.19). On the chain axis it stands as
written: flow instances complete, so an empty pipeline is a condition
that arrives. On the workflow axis it cannot stand — a blocked ticket
is in-flight and stays blocked for as long as its human prerequisite
takes, so requiring an empty pipeline would make workflow evolution
hostage to the slowest block in the organization. Blocked tickets
therefore ride the cutover and re-resolve against the new sequence by
§7.19's rule, anchored on the system statuses, which are the part of
a ticket's history no bundle change can delete. Act (4)'s flip is
**recorded as an event** on both axes; §7.19 depends on it.

**Dropped from v4:** the phase machinery — `phased:` tiers, the
`phase_plan` projection and plan rule, cross-phase delta context, the
plan-change flow, `/run_phase`, in their entirety.
Rationale in §7.9: phases were a batching scheme plus a slicing
methodology; the slicing job is already done by the feature flow's
plan tiers, and the batching job doesn't earn a subsystem. The impl
tier is **unphased** — one impl doc per subcomponent describing the
total end state — with per-ticket deltas scoped by feature plan docs.
The only remnant: the MVP-closure computation (§7.9), a one-time
dependency-closure over `mvp: true` feature pins.

Design-stance note carried over from v4 and reaffirmed: closed
vocabularies everywhere (scope expressions, predicate operators,
options, fragment kinds) — no bundle-provided code, no escape hatches
into Turing-completeness.

---

## 7. The delivery model

Settled. Supersedes the earlier "open seam" framing of this section.
The target lifecycle, per unit of work: (1) the author writes a
feature they want → (2) UI design if applicable → (3) architecture →
(4) code → (5) validate → (6) ship — with each instance of (1) a
ticket, and the machinery below mapping those steps onto both the
siege chain and the orchestration loop.

### 7.1 Linear is stupid; the plane is smart

Orchestration made Linear the state machine out of necessity — GitHub
Actions had no persistence, so the tracker was the only store, and
its rules (state-transition-as-claim, detect-and-revert, pickup
assertions) exist to make a store with no transaction hooks behave
like one. Catapult has Commanded and an event log, so the roles
invert: **the doc graph + event log is the state of record; ticket
state is a coarse projection for human legibility; human actions in
Linear (and comments in Linear and GitHub) are signals — commands the
control plane validates**, accepting them into the event log or
reverting with a comment. Dispatch is driven by `ready_scopes`, never
by tracker state.

This is what makes conflating tiers with ticket states legal.
Orchestration's state-admission test ("each state answers *who has
the ball* differently") was load-bearing because states drove
dispatch; here it relaxes to: machine states may be pipeline phases,
but **every state where the author must act is unmistakable**, and
there are few of them. Orchestration's naming discipline is retained:
no two states (or a state and a label) one hyphen apart in meaning.

**The log records decisions and observations, never wishes** (the
events×external-effects question, settled at the docs review pass).
One answer for every external surface — tracker, host, git,
deploys: **an external effect never shares a transaction with an
event.** Outbound, the plane records the *intent* as an event,
executes the effect through an idempotent outbox worker (§2.6's
pattern applied to ourselves — the event insert plus the job insert
is the one legal transaction), and records *completion* only from
the world's own confirmation (webhook, sweep observation) — "merge
succeeded" enters the log because GitHub said so, never because we
hoped so. Both dual-write failure modes resolve without the log
lying: **intent-without-effect** stands as honest history, visible
in explain-why, owned by retries and escalation;
**effect-without-recorded-completion** is divergence the sweep
re-observes and idempotent ingestion dedupes — the convergence
floor is the healer. The state-driven scheduler's doctrine applied
to writing: the world is observed into the log, never assumed into
it.

### 7.2 The ticket tree is a projection of the doc DAG's fanout

Linear sub-issues nest (a sub-issue is a full issue with a parent
link, multi-level), and blocking relations are native — no subtask
hacks needed. The tree: **feature ticket → component children →
subcomponent grandchildren**, spawned exactly where the doc graph
fans out, each child blocking its parent and carrying its scope's
mutex labels.

**Grain rule: spawn a level down only when the plan document at that
level proves independent parallel work exists.** Default stays coarse
(large tickets — ticket-sizing wisdom assumes human time; a whole
deliverable per ticket suits AI time, and a deliverable-sized
argument is exactly what reconciliation is built to check). Depth is
earned by demonstrated parallelism, never reflexive.

Siege's per-tier plan documents (v4's flow planning tiers, previously
untested) get their concrete job here: the plan at a fanout node
determines what changes at that tier *and which children are
impacted* — **the plan node's output is the child-ticket spawn list
plus its label set.**

Ticket content: the ticket carries the *argument* (human-readable,
for the author); the agent's context bundle — dependency pubapis,
resp/feat slice, related screens, the impl doc — is fetched from the
control plane at claim time. The ticket points; the plane serves.
Context reduction is the point: each thread sees its dependencies'
APIs and its up-graph slice, nothing more.

### 7.3 Entry points

**Entry tier is a property of the ticket, not different machinery.**
The cascade starts at the declared entry tier; gates upstream of
entry are skipped — nothing to review is orchestration's decisionless
pass generalized; everything downstream is standard. The taxonomy:

- **Feature** — enters at the product tier (journeys/screens). The
  default.
- **Capability-only** (responsibilities, no UI) — enters at
  requirements; the first author gate is architecture review.
- **Tech debt / refactor** — enters at architecture (sysarch/comparch
  deltas, no product change). Orchestration's gating-debt rule
  survives (§4.5); the alternating debt milestone it used to route
  through does not — **reversed at ORC-105** (§7.8) — debt tickets
  are this entry with the `tech-debt` label, filed into a milestone's
  `prep` or `cleanup` queue per §4.5's revised routing rather than a
  dedicated milestone.
- **Bug, fixed in-flow** — enters wherever the plan tier localizes
  the defect. "Which artifact was wrong — impl, comparch, screen
  definition?" is itself the first planning question; the cascade
  runs downward from there. In-system is the *default* for bugs;
  out-of-band is the escape valve.
- **Maintenance** (dependency and vulnerability upgrades) —
  plane-filed (§7.10): a watcher auto-files with entry `localized`;
  routine bumps to Triage for batch-accept, advisory-backed security
  bumps directly to the queue with `Urgent`. The plan tier decides
  impl-only vs. architecture-implicating.
- **Bug, fixed out-of-band** — the author's hotfix lands on main
  outside the pipeline (legal, per orchestration §2.5). The base
  check detects the ground moved; because file→scope mapping is
  Boundary-derived, the plane mechanically maps the diff to impacted
  scopes and opens an **absorption ticket** running the upward flow:
  docs absorb reality, walking upward only as far as the change
  argues.
- **Doc edited out-of-band** (docs review pass) — a *body file*
  changed on main outside the pipeline: the author hand-edited
  architecture. The projections are insulated (walks read bodies at
  recorded SHAs, so the graph itself doesn't move), but agents check
  out the repo and humans read files, so an unratified doc state is
  live influence the moment it lands. The base-check sweep detects
  diffs under body paths and files a **doc-reconciliation ticket,
  always `Urgent`** — by rule, not judgment: every ticket that
  starts while the divergence stands can make decisions based on a
  doc claim no code backs. The ticket resolves to one truth: adopt
  the edit through the normal gate flow (it becomes a reviewed
  revision event; downstream staleness follows ordinarily) or revert
  it to match reality. The absorption ticket's mirror image — that
  one makes docs absorb code; this one stops docs from leading it
  unratified.
- **Urgent / stop-the-world** — orchestration's rules port verbatim:
  `Urgent` preempts at pickup, never interrupts in-flight work, never
  steals an in-flight mutex, dispatches regardless of which queue a
  milestone currently sits in (§7.8, revised at ORC-105 from
  "overrides the milestone pause" — there is no longer a distinct
  pause state to override; an Urgent ticket simply ignores queue
  ordering, by construction). A true security patch bypasses the
  pipeline onto main — and its afterlife *is* the absorption path
  above. One mechanism, two doors.

### 7.4 Feedback surfaces

Four surfaces, each at its own altitude; the feedback-hose problem
(one ticket aggregating feedback for dozens of artifacts) is
dissolved by giving every feedback type a home:

1. **Our own UI** (`my-queue`, `board`, `ticket`) — the author's
   inbox and state lever. See tickets waiting on you, action them,
   kick work back to the machine.
2. **GitHub PRs** — diffs and code review feedback, line-anchored,
   because line anchoring is what code review wants. Prose artifacts
   (every tier Phase 4 produces, `systems/delivery.md`'s ORC-33 entry)
   review on the native surface instead, at sentence granularity.
   **Harvesting rule:** on a gate decline (state moved back), the
   plane collects PR review comments made against code since the
   last gate, buckets them by the artifact span they anchor to, and
   threads each bucket into that scope's regeneration as `feedback`
   — a decline on a prose artifact is harvested the same way from
   the native surface instead (`docs/ui-spec.md`,
   `systems/delivery.md`), not from this PR.
   **How machine and human comments are told apart now depends on the
   surface.** On surfaces we own, plane-authored annotations are
   *records with kinds* and no prose is parsed — the marker rule is
   retired there (`docs/ui-spec.md`, `systems/delivery.md`). On
   GitHub PRs, which we do not own, the
   plane's own comments still carry fixed markers, posted issue-level
   rather than line-anchored, which is what the original reason —
   the store is somebody else's, so typed data needs a convention —
   still covers exactly. **Revised (ORC-31): that convention no
   longer decides which *review* comments count as human.** The
   original rule assumed any machine-authored comment could be told
   apart by checking for the marker, but a marker is a convention
   only *our* machine follows; any third-party actor with review
   access — a GitHub App, a bot, a review tool, Claude Code's own
   inline review comments — posts through the identical line-anchored
   review-comment endpoint a human uses, unmarked, and endpoint-of-
   origin alone would harvest those as human feedback. So a review
   comment is treated as human feedback only once it also survives an
   author-identity filter: `performed_via_github_app` excludes
   GitHub-App-authored comments, `user.type == "Bot"` excludes bot
   accounts. **Residual, named rather than hidden:** a bot
   authenticating with a human's personal access token is
   indistinguishable from that human at the API; nothing here closes
   that gap. Mechanism and rationale in full: `systems/delivery.md`.
3. **Preview URLs / storybook exports** — visual review, per branch.
4. **The docs site** — human browsing of settled architecture.

**Comments at the wrong altitude are routed, not honored:** a
parent-ticket comment about a component's internals becomes feedback
on the child (or the artifact), moved by the plane with a note.
Scope rules only protect you if scope stays where it belongs.

**Notifications have exactly two channels, and a third would be a
bug** (notifications pass). If a fact is about *the work*, it is a
ticket — the machinery-filed shapes (enforcement, swap, maintenance,
absorption, doc-reconciliation, Triage notices) — and Linear's inbox
is the delivery mechanism; that stays the overwhelming majority. If
a fact is about *the machine*, it is an observability alert
(Prometheus → the author's pager/email, outside the envelope per
§2.11), mirrored on the dashboard's health surface. The
machine-shaped set, grown as named entries like registry kinds:
**signal silence** (webhook flow stopped — the one failure Linear
cannot announce, because Linear is the silent thing);
**dispatch-budget warn/cutoff** (§7.12.1); **bindings-credential
expiry or auth failure** (invisible until a dispatch fails, so
checked proactively — the *proactive* half; a run **discovering** a
missing prerequisite files `Blocked`/`needs-setup` instead, §7.6,
because once it blocks a ticket the fact is work-shaped);
**deploy-detection anomalies** wider than any
one ticket; **restore/cutover lifecycle states** (§6, §8). The rule
exists because notification surfaces multiply on convenience, and
every additional one is a place attention goes to die.

**The Catapult LiveView UI is the working surface, not only a
debugging one** (§7.17; the screens are `docs/ui-spec.md`). A UI that
only explained the machine would be right if Linear and GitHub already
unified comments, states and diffs. Owning the tracker removes that
premise, and two
things turn out to be *better* here rather than merely available: our
documents diff per sentence rather than per line, and the ticket
graph under a top-level ticket is a view a general tracker cannot
easily draw.

**The debugging half survives untouched and is still the hard part** —
event-log inspection, replay-to-sequence, `ready_scopes` explain-why
("what is blocking this scope" as a first-class query), staleness
provenance, dispatch history, agent-run transcripts. When a pipeline
this deep stalls, "why is nothing happening" must be answerable in
minutes. Budgeted as a real engineering line item, not a leftover
dashboard — and now sharing a surface with the work loop rather than
sitting beside it.


### 7.5 Branches, merges, reconciliation

- **One feature branch with one PR to main; each child ticket gets
  its own PR merging into the feature branch.** Child scoping is
  strict (Boundary-derived file maps), so merges are near-always
  textually safe. **Scope violation is an automatic bounce:** an
  agent touching files outside its ticket's file map gets a
  plane-authored marker comment naming the paths and `Ready for
  rework` — no human involved.
- **Never rebase. Merge main forward.** The plane auto-merges main
  into open feature branches when main moves, and feature branches
  into their children — drift absorbed continuously in small bites.
  A conflict on the auto-merge is a real signal (two features
  semantically adjacent despite disjoint mutexes) and routes to the
  ticket as rework. A failed merge means pull and retry; GitHub
  arbitrates races.
- **The parent's doc diff merges to the feature branch through the
  same PR flow; children branch from the feature branch** and see
  current architecture. Child merges are ordinary merge commits (the
  branch dies anyway); **the feature PR squash-merges to main** —
  main stays one-commit-per-feature, keeping deploy detection, SHA
  ancestry, and retro notes trivially readable.
- **Reconciliation grain mirrors ticket grain.** Child reconcile
  reads the child PR against the child's argument, merges to the
  feature branch. Feature reconcile reads the feature PR — the
  composed diff, which pre-exists as the reconciliation vehicle —
  against the feature's argument, merges to main. The composition
  check orchestration's pre-merge placement "genuinely lost" comes
  back at the feature level. **"Reconcile" here names the `reconcile`
  system status** (`dsl-syntax.md` §15.1, §15.11; §7.19 below,
  ORC-151) — the read is a distinct, required step from the mechanical
  merge that follows it, not a description of `merge` doing both.
- **Deploys are per-feature.** Features merge dark behind their flag
  (§2.10); post-deploy validation runs against the feature's
  affordances/states; the author's flagged-in validation happens on
  prod.
- **Watch item:** in-flight is now feature-scoped, so mutex hold
  windows lengthen. Counterargument accepted for now: a feature
  touching many things is itself more parallelizable, so up to some
  critical mass related to the project's branching factor, parallel
  threads stay saturated regardless of feature count. Measurable
  rather than debatable: mutex-wait time per label is a Prometheus
  metric once the plane runs; "one label serializing unrelated
  features" (orchestration §14, coarser grain) is the panel to watch.

### 7.6 States

**One shared status vocabulary across ticket types**, type carried by
labels (`type:feature` / `type:component` / `type:subcomponent`), the
plane keying routing off state × type (leaving `Reconciling` merges
to the feature branch for a child, to main + deploy-watch for a
feature). The sharing test: **a status may be shared iff its
definition doesn't mention ticket type.** Not every type visits every
state.

- Feature lifecycle: `Todo → Product design → Product review (author)
  → Architecting → Architecture review (author — the sketch review) →
  Implementation → Checks → Reconciling → Merged → Validating →
  Shipped/Done`, `Blocked` anywhere. Two author gates, per
  orchestration's touchpoint budget; entry tier (§7.3) determines which
  early states are skipped. **No `Building` state between architecture
  review and `Implementation`, retired along with the system status it
  named** (`dsl-syntax.md` §15.1, §15.11, ORC-151's third design
  review): the feature's own implementation is real dispatched work,
  `Implementation` (named at ORC-151's fourth design review,
  `dsl-syntax.md` §15.1), immediately after architecture review passes
  — not a wait. What `Building` used to mark, children still in
  flight, is now `Reconciling`'s own entry precondition rather than a
  status of its own: once the feature's own `Implementation` and
  `Checks` complete, the ticket sits at `Checks` for as long as its
  own children take to finish their own subflows, which is the
  identical dwell `Building` used to visualize, needing no separate
  status to do it in.
- Child lifecycle: orchestration's states nearly verbatim — `Ready
  for dev → In progress → Checks → Reconciling → Merged → Done`, plus
  `Ready for rework / Reworking`, design states gone: children are
  born past design (their design is the parent's approved docs),
  entering at `Ready for dev` by construction — which is how
  every-ticket-gets-a-design-pass is satisfied at the parent. **This is
  the generic shape — one undifferentiated generation-shaped visit —
  and it is a second declared type, never the feature type
  depth-filtered, settled at ORC-151's fourth design review**
  (`dsl-syntax.md` §15.11): `design`/`Product design` is feature-only
  vocabulary with no depth-based way to no-op below the root, so a
  component or subcomponent instance cannot legally be running
  `types/feature.yaml`'s own array. **A child spawned by architecture's
  own recursive fan-out (comparch/subcomparch, `dsl-syntax.md` §15.11)
  runs a third, richer type instead of this one** — `In progress` split
  into its own `Architecting`/`Implementation` pair, each with its own
  review, the identical split the feature lifecycle above just took —
  because that child's own artifact needs the same reading before it
  merges that the feature's does. An ordinary child entering directly
  at implementation, with no architecture review of its own to run
  (§7.3's entry-tier taxonomy), still runs this simpler bullet's own
  shape unchanged.
- **`Stubbed`** — machinery-filed swap tickets only (§2.16):
  committed work deliberately waiting on an external timeline. Passes
  the admission test with a distinct who-has-the-ball answer — the
  world's calendar, not the queue and not the author-now (Backlog
  means not committed; Todo means starting when the queue reaches
  it; Stubbed means starting when the world permits). Exempt from
  staleness and escalation checks (nothing is stale about waiting
  deliberately); carries no milestone until scheduled, so it can
  never be the unresolved work that holds a milestone's own queues
  open (§7.8's `blocks:` relation, revised at ORC-105 — "block a
  boundary" in the older phrasing this replaces).
- **Blocked carries flavor labels and its origin** (ported from
  orchestration `372630a`). Three flavors, as labels — never
  states, because a flavor dispatches nothing and a state would be
  Blocked under another name duplicating every attached rule:
  `needs-review` (a judgment is owed), **`needs-setup`** (an
  environment prerequisite — a secret to set, an API to enable, an
  account to create; the filing *must name exactly what has to be
  done*, the `errors/0` remedy mandate applied to aborts — a parked
  ticket nobody can act on is worse than a failed one), and bare
  failure. The column's real question is "is anything broken," and
  waiting-vs-broken must never look identical. **Every Blocked
  entry names its origin state.** In Catapult the event log holds
  this natively — `from` is a projection, not bookkeeping — but the
  plane still stamps it on the Blocked comment, because the author
  reads Linear, not the log, and "Reworking, until someone sets a
  secret" has no obvious exit without its origin. **Blocked has no
  timeout, deliberately** (orchestration `853df67`, rationale
  ported): the only action a timeout could take is moving the
  ticket, the only honest destination is the queue, and that
  discards the claim, the branch, and the reason — to buy a nudge
  that the assignment projection (§7.10) already provides. The
  single-driving-author assumption is that they are prompt.

### 7.7 CI

`on: pull_request` with **no branch filter** (child PRs target
feature branches, so branch-filtered triggers would never fire), with
jobs conditioned on **PR labels the plane applies**: `ci:docs` on
docs-only PRs (review-gate phases — grammar validation + audit, no
compile suite), `ci:code` for the full gate set (§2.13). Selection
logic stays in the plane; the plane consumes check results keyed to
head SHA regardless of base branch.

### 7.8 Containers, queues, and milestones

**Revised wholesale at ORC-105, superseding ORC-103's own unmerged
milestone-only framing of this section.** ORC-103 first tried "give
the milestone its own statuses and the steps that close it" — the
right instinct, a fifth of the actual decision: the milestone is one
declared **container** and the close is one **queue** among five.
Every reason ORC-103 gave for retiring orchestration's boundary
ticket still holds and generalizes rather than being re-argued
(carried forward, not re-derived): the pause needed to be *tracked*
somewhere and the pass needed a *place to live*, both true only
because orchestration has no tracker of its own to hold either
directly; Catapult's ticket state is its own event log (§7.1, §7.17),
so a container can carry its own progress and the record of its own
history without proxying through a ticket. What follows is the
decision set (ORC-105, all four of its passes); the grammar it's
built from is `dsl-syntax.md` §15.1-§15.9. Building the dispatcher,
the sweep, and the scan/setup/retro machinery itself is ORC-104's —
this section settles the shape, not the diff.

**A work-item type names its own gates; a gate names no types.** A
type's effective status sequence is its own declared array, not
something assembled by scanning every gate for a `ticket_types:` entry
naming it — that field is retired from a gate's declaration outright,
so the fact lives in one place. The same move that gave the container form its array applied
to plain ticket types too, and it collapsed `flow:` and `opens:` into
one required field: a queue entry's `flow:` names a member of one
shared registry, and whether that member turns out to be a plain type
(dispatch terminates, an ordinary ticket) or a container (dispatch
mints a nested instance) is visible only in what the *resolved*
declaration itself contains, never in anything the queue entry
declares. This is a real extension of what's declarable, and it
argues with a recorded decision rather than sidestepping it:
`docs/non-goals.md`'s "No per-project restructuring of the automation
protocol" entry is amended alongside this section to record it,
because its own admission rule ("a state may be declared iff no plane
logic branches on it") already covers the addition without needing to
change.

**One declaration shape, not three.** `queues/project.yaml`, a
directory of named containers and a directory of named types were
three file formats for one thing, and most of the differences among
them were artifacts of the split rather than facts about queues or
generations. **The governing rule: a container is any work item whose skeleton has
queues, a ticket is any work item whose skeleton has a generation, and
they are otherwise interchangeable** — a milestone with a `main`
queue, then a human sign-off gate, then a staging deployment, then
`retro` is now an ordinary sentence, where the third pass's grammar
could not have said it (a container's array admitted no gates or
environments at all). One declaration shape holds all three cases —
`ticket`, `container` and the project's own `none` — distinguished by
a `skeleton:` field rather than by which file a declaration lived in
(`dsl-syntax.md` §15.1-§15.2). **Gates and environments widen onto
`container`, joining `ticket`; the project's own `none` does not
join them.** A project's array stays entirely queue-shaped, since
"all review happens at lower levels" (`dsl-syntax.md` §15.1) is a
fact about the outermost scope specifically, not a case the governing
rule above was making a claim about — that rule is ticket versus
container, and never mentions the project. **Critique is a second,
narrower carve-out on top of that**, because its depth selects which
tiers a generation fanned into, and only a `generation` anchor —
which neither a `container`- nor a `none`-skeleton type has — gives
it something to select within (`dsl-syntax.md` §15.5).

**`skeleton:` is optional, and rootness is derived rather than
declared.** `ticket` and `container` are the only two real values, and
a type declaring neither has no anchors at all (`dsl-syntax.md`
§15.1); a `skeleton: none` value would be spent on exactly the fact
its own absence already states. Nothing polices rootness with a load
check either — it falls out of the declaration graph (below). Second,
and
load-bearing rather than cosmetic: excluding the project's array from
gates and environments read "all review happens at lower levels" as a
claim about array *content*, when it was only ever the argument for
why a project needs no *re-resolution anchor* — a different claim, and
the governing rule this section opens with never mentioned the project
either way. **Gates and environments now widen onto every type,
skeleton-less ones included**; a human sign-off between two of a
project's own queues is the milestone example's own logic one level
up, and there was never an argued reason to refuse it. Critique alone
stays the one carve-out, for the reason already given — a `generation`
anchor is what gives its depth something to select within, and no
skeleton-less type has one.

**`after:` is retired: array position says everything it did, and
more precisely.** A gate's own former predecessor field required
one linear order for the whole bundle; with order living on each
citing type's own array instead, two types may run the same two gates
in different relative order, which the old model could not express
without contradiction (`dsl-syntax.md` §15.3). This reaches gates and
environments as they exist today, not merely the container form this
section is about, and the grammar section is where the full argument
lives.

**And it reversed v5 §7.18's own workflow-axis base layer:
`extends:` narrows to the chain axis, and workflow bundles are forked,
not layered.** §7.18's reasoning — that a project's gates and
environments live "in its bundle's `extends:` layer" — assumed the
loader composes a project's workflow bundle from a platform base at
load time. That is not how bundles are actually distributed: §3.1
already chose fork-tailor-merge as the lifecycle for bundles and
policy packs generally, because git has a merge story hex does not,
and a workflow bundle is exactly this shape. `bundles/`'s platform
workflow content becomes a template a project forks from and pulls
later revisions into by git merge, never a base layer the loader
composes underneath a leaf bundle (`dsl-syntax.md` §11 carries the
full argument and the load-time consequence: a workflow bundle
declaring `extends:` at all is now a load error).

**A project is not a container, even though the two now share one
declaration shape.** The reversal at this section's second pass —
against its own first draft, which gave `project` and `milestone` a
shared shape off one `container:` field checked against a two-member
registry — still holds; the fourth pass's unification gives every
type the same *file* shape, whatever `skeleton:` it declares or
omits, without erasing what makes a skeleton-less declaration
different. **A project's queue sequence is fully declared by
the workflow bundle** — any names, any count, any order, chosen
freely because a project needs no re-resolution anchor (all review
happens at lower levels, and a workflow cutover mid-project isn't the
hazard a cutover mid-container is). **A container's `skeleton:` is
one kind, arbitrarily nestable, and every instance carries the
identical required anchor sequence** — `setup` → `prep` → `main` →
`retro` → `cleanup`, platform-fixed, declarable by neither axis, for
the identical re-resolution reason ticket skeletons aren't
(`dsl-syntax.md` §15.1): the anchor a container parked mid-sequence
falls back to when a workflow cutover changes what a queue dispatches
underneath it. This is a required backbone, never an exclusive
membership (a seventh-pass reversal, ORC-148, below): a container's
array may additionally hold a bare generation-shaped entry, a second
population anchor, gates or environments around that backbone. What
varies per declared container is its **name** and what each of its
population-anchor entries' `flow:` *points at* — a registered
ticket-skeleton type (a **work flow**) or another declared container's
name (a **container flow**), the same registry either way
(`dsl-syntax.md` §15.2) — never the anchor names or their required
relative order. Nothing requires a container's queues to bottom out in
tickets at all: with more than one work type, "is this a ticket"
stops being definable, and a queue sequence built entirely from
container-opening queues is legitimate. Declaring `epic` gets
epics-and-milestones for free the moment an `epic` container's own
`main` entry's `flow:` names `milestone` — no new mechanism, because
there is only the one container skeleton and one field; a genuinely
distinct skeleton, if real usage ever wants one, is new
system-status-style vocabulary decided then, on evidence, not guessed
at now.

**Acyclicity is a load-time check over container *declarations*, not
a runtime check over container *instances* — getting this altitude
right took two passes, and getting the graph's own node set right took
a third.** The first pass reached for "no container may be its own
ancestor," checked as instances mint; the corrected version is a
static check of the declaration graph itself — **nodes are every type
with a queue-shaped anchor, edges are `flow:` references between
them** — which must be acyclic, with a type naming itself the
degenerate one-node case of the same rule (`dsl-syntax.md` §13). A
`flow:` edge whose target resolves to a `ticket`-skeleton type takes
no part in this graph — a `ticket`-skeleton type declares no further
`flow:` of its own, so it is always a leaf. **The fourth pass's own
version of this graph admitted only `container`-skeleton types as
nodes, which left a hole a fifth pass found:** excluding skeleton-less
types from the node set excludes every edge *into* one by
construction, and that is exactly the edge a cycle through the project
can run on — `milestone`'s `main` entry naming `flow: project`
alongside `project`'s `build-out` entry naming `flow: milestone` is a
genuine two-node cycle that the narrower graph never built, so it
loaded clean and would have been caught only if some live chain of
instances happened to close the loop. A skeleton-less type's array is
entirely queue-shaped — the same property that makes a
`container`-skeleton type nestable — so the node set now includes both
alike. The instance-level
version is not merely redundant, it is the wrong tool: it leaves unbounded depth
*declarable*, caught only when some live chain of instances happens
to close the loop, which trades a load-time failure for a mid-flight
one — the identical trade this project has already made the other
way (v5 §2.4: failing at config load beats failing mid-flight). The
declaration-graph check is also what actually bars same-name nesting
(a `milestone` declaration cannot open `milestone`) and what bounds
depth without counting it: an acyclic graph has a finite longest path,
so a bundle's maximum nesting depth is knowable from the bundle alone,
even though the number of distinct levels an author declares is
unbounded. No further instance-level check is needed — it falls out
of the declaration graph's acyclicity for free.

**A queue is a query, never stored.** "Work items in this project or
container whose declared flow is this queue's, unresolved" —
addressable whether or not the queue is current, which is the handle
a queue needs while inactive (a future milestone's `prep` is a real,
queryable thing before that milestone opens). A stored per-queue
bucket would be a new in-plane pending set: `ready_scopes` itself
refuses to materialize for the identical reason (v5 §1.2), and
`Catapult.Engine.Scheduler` holds no memory of what it last broadcast
— a stale ordering is worse than none, because it is the kind of
thing that gets acted on (v5 §7.11's staleness projection makes the
same refusal for exactly this reason). Note the noun: **work items**,
not tickets — the distinction only matters the day a non-ticket work
type exists, but the grammar doesn't assume it away.

**One queue may block another, declared, and a block may only name a
sibling.** A queue declaring `blocks:` guards *entry into* the queue it
names: a container or project cannot move into a blocked queue while
the queue that blocks it still holds unresolved work — checked once,
at the transition, corrected to this entry-guard reading at ORC-148's
design review below (an earlier reading of this same paragraph held
the block as a standing condition on the *blocked* queue's own
completion, recomputed for as long as it ran; that reading is
retired). This is what makes "the retro can't finish [be *entered*]
while milestone work is open" an instance of a
general rule (`main` blocking `retro`, below) rather than a special
case, and which also closes the stranding hole ORC-103 solved
narrowly: work in a blocking queue cannot be quietly closed over. A
`blocks:` entry may only name a queue declared in the same type's own
`statuses:` array — a container's other four anchor entries, or
another entry in the project's own array (`dsl-syntax.md` §15.7) —
reaching into a
nested container's own queues would make its internals part of its
interface to whatever blocks it, exactly backwards from
composability. To block on something nested, block on the queue
entry whose `flow:` opens it.

**The project is the outermost scope, and having a lifecycle at all
is less new than it looks — even though being a *container* was the
wrong way to give it one.** `project_id` is already the top-level
scope in the engine store (`systems/engine.md`) — every table carries
it post-ORC-87, `Store.list_project_ids/0` enumerates them, and the
active-bundle-version projection already keys current bundle versions
per project per axis (`systems/engine.md`'s ninth projection). The
project isn't a new concept acquiring a workflow; it's the existing
outermost scope finally having one, declared with no `skeleton:` at
all (`dsl-syntax.md` §15.1) rather than borrowing the container's
fixed anchors. Its queues, in order:
`initialization` → `scaffolding` → `build-out` → `iteration` →
`maintenance` → `deprecating` → `sunsetting` — the default bundle's
own authored choice, not a platform requirement, since a project's
queue list is exactly as declarable as any other project content.
All but `scaffolding` point at the same work flow for now — the
distinctions are ones that *become* meaningful; they needn't be on
the first build. `scaffolding` differs because the seed pass (§7.9)
wants different settings from ordinary ticket work. `initialization`
is autopopulated by business logic, not protocol: the grammar
declares the queue exists; what lands in it on a fresh project is not
the loader's business. `deprecating` and `sunsetting` are real,
ordinary declared queues **from the start** — not dummies promoted
later, since there is no platform-fixed project sequence left for
"later" to mean anything against. **This also settles §6's open
question:** the root has statuses because it is a project like any
other, with its own declared queue list, and closing it means that
list's last entry (`sunsetting`, in the default bundle's own
ordering) resolving with nothing open behind it (`dsl-syntax.md`
§15.6) — not because the root is a container reaching a fixed
terminal kind, which is a mechanism only `container`-skeleton
declarations have.

**Milestone queues, and the end of the debt milestone.** `milestone`
is a declared **`container`-skeleton type** (`dsl-syntax.md` §15.1) —
one instance of the one container skeleton, not a platform-registered
second kind — whose five fixed anchor entries point, in order, at:
`setup` → `prep` →
`main` → `retro` → `cleanup`. `setup` constitutes the instance, once,
at mint; `prep` is work the milestone requires before beginning;
`cleanup` is work that
got missed during it — distinct on purpose, because "debt left over
from the last milestone" and "debt required for the next one" used to
land in one place and are different questions. **This reverses this
section's own earlier framing** (the alternating-debt-milestone
picture inherited from orchestration and restated informally at §1.1)
**, and the reversal is the point.** Debt becomes a queue inside every
milestone instead of a milestone every other slot: nothing has to be
inserted into the project's own queue sequence, no debt milestone has
to be autogenerated, and the alternation stops being prose nothing
enforces. §4.5's `debt`-routing gating test is revised to match: it
now sorts a milestone's own `cleanup` from the next milestone's `prep`
rather than "next debt milestone" from "backlog" — arguably a clearer
question, and every place that gating test is invoked reads it this
way from here.

**Two agents, dispatched as ordinary work items, and what stays
human.** `boundary` is retired as a chain-level agent step
(`dsl-syntax.md` §15.1) and becomes `retro`, a queue-dispatched flow —
it never named anything a tier's `delivery:` actually used, and the
single static pass is exactly what the queue model replaces. A
`setup` flow joins it, dispatched as `milestone`'s own `setup` entry's
declared `flow:` once a milestone instance becomes the *active* one at
whichever of the project's own queues a workflow bundle assigns it to
(`build-out`, `iteration`, ...) — **not once it is minted**
(`dsl-syntax.md` §15.8, this section's own fourth-pass correction).
Minting a milestone instance and activating it are different events:
the instance can exist, and accept groomed work into its own future
queues, well before the project's own queue reaches it — "we set
blockers for and groom the tickets of the next milestone" is exactly
this, done during the current milestone's own `main`. Minting and
constituting were always necessarily two different declarations (the
project's queue entry and the new milestone's own `setup` entry), so
there was never a "before `prep`" position to invent: `setup` **is**
the position, first in the minted instance's own five-entry sequence
rather than a value stashed on `prep`'s own `flow:` (an earlier draft
of this section did exactly that, which runs `setup` once per
*container* rather than once per *mint*). What changes at the fourth
pass is only *when* `setup` fires relative to mint — at activation,
not at mint — which is what makes "runs once" true without leaning on
mint timing, and what lets a milestone be groomed before it opens
without `setup` running twice or early. The split
follows the direction each looks: `retro` —
backward — adjudicates carried findings, scans the diff for debt,
updates the milestone's tickets to reflect what actually landed, and
flips the aggregated flag set (below); `setup` — forward — grooms,
sets blockers, and fills `prep`. **Both are ordinary agent-balled
entries directly in `milestone`'s own array** (ORC-148, superseding
the singleton-ticket shape below): `retro` inside the sub-array it
shares with the sign-off gates around it, `setup` needing no sub-array
of its own (`dsl-syntax.md` §15.2, §15.10). Neither carries `flow:`,
and neither is dispatched as a separately minted child; each runs
once per pass through its own position in `milestone`'s array, the
identical guarantee "runs once, at activation" already gives `main` or
`prep` (§15.8) — a guarantee that needs no declared bound, because
there is exactly one `milestone` instance and exactly one array
position for each to occupy. This is also why `singleton: true`
(`dsl-syntax.md` §15.7) is retired rather than corrected again: it
bounded a *queue*'s lifetime cardinality, the mechanism `setup` and
`retro` needed only while each was a `flow:` naming a separately
minted, ticket-skeleton child (`types/setup.yaml`, `types/retro.yaml`,
both deleted); an inline entry was never a queue, so there is no
cardinality left to bound. Both are still **ordinary work items**:
what's absent is the *pause-proxy* — a ticket standing in for
container state a borrowed tracker had nowhere else to hold
(`dsl-syntax.md` §14's corresponding entry draws this distinction
explicitly, so the next reader doesn't take this shape as a
reversal). What's present is dispatched work, with the same
chain-bundle machinery any other agent-balled entry uses (§7.10's
"opening a ticket IS opening a flow instance" generalizes to "reaching
an agent-balled entry IS dispatching a flow instance," ORC-148) —
`milestone`'s own chain-bundle counterpart carries the tiers whose
`delivery:` blocks give `setup` and `retro` their actual agent
behavior, exactly as a ticket-skeleton type's chain gives its
`generation` entries theirs. **Human, irreducibly:** manual testing
across the milestone (the pipeline protocol's own DESIGN §10 names
this the only place manual testing happens, and nothing here changes
that), reading the `:live` verdict (§2.8), clearing `Blocked` tickets
carrying `needs-review`, accepting or declining `retro`'s Triage-filed
proposals.

**Settled at ORC-148: a container instance is a legal agent dispatch
target, on the identical footing as a ticket instance.** ORC-115 first
named the direction — `setup` and `retro` folding into sub-arrays of
`milestone`'s own array rather than staying separately minted
ticket-skeleton types — and left open whether a container instance
could be a dispatch subject at all, since the shape at the time still
routed both through machinery built only for tickets. The question
does not need a container-specific answer: dispatching from a work
item with a queue and dispatching from one without are the same
operation, attached to different status flows — the container/ticket
split is semantic, never functional (`dsl-syntax.md` §15.2) — and the
queue was never what made a work item a dispatch target. Concretely,
this reaches the executor (it runs against the container instance's
own branch and PR, not a child ticket's), the mutex mapping (a
container instance's own file-map paths, exactly as a ticket's are
today), and `DispatchRun`'s own keying (keyed on the container
instance's id where it was keyed on a ticket id). It also resolves
what `main` blocking `retro` (§15.7) means once `retro` is `milestone`'s
own inline entry rather than a population of unresolved tickets:
`retro` cannot be *entered* while `main`'s own queue still carries
unresolved work — the entry-guard reading `blocks:` takes generally
(below), applied to a guarded entry that is not itself a queue.
`dsl-syntax.md` and `systems/delivery.md` carry
the grammar and the dispatcher's own diff against this; this paragraph
records the decision, not a diff to `bundles/default-flow/**`, which
is dev's to make.

**A design review corrected four things about this section's own
record, and a third review round corrected a fifth, all still
ORC-148's** (`dsl-syntax.md` §13, §15.1, §15.5, §15.7, §15.8, §15.10).
The pass above got the shape of `setup`/`retro` folding into
`milestone`'s own array right and three of its own consequences wrong;
none of the five widen what a bundle may declare — each is a
correction to how the platform-fixed vocabulary or the dispatcher
reads it.

**First, `blocks:` inverts to an entry guard, checked once at the
transition it guards, never a standing hold a projection recomputes.**
The paragraph above already reads this way (corrected in the same
edit): `main blocks: [retro]` means `retro` cannot be *entered* while
`main` still carries unresolved work, checked exactly once, at the
moment something attempts to move into `retro`, not continuously for
as long as `retro` runs. This removes a real defect the standing-hold
reading had: a queue refilling while the guarded entry was already
mid-run pulled the container back out of it, and `retro` is the case
that makes this more than academic — `retro`'s own output lands back
in `main` (adjudicated findings, filed debt), so a completion-hold
form of `blocks:` would have had `retro` interrupting itself the
moment its own run produced the work `main`'s queue was watching for.
A reassignment to a new status must never interrupt an already-
dispatched flow instance; checked once, at entry, this holds by
construction rather than by care taken in the dispatcher. **"Checked
once" describes each attempt, not how many attempts there are or who
makes them**: this system's dispatcher is event-driven, re-attempting
a guarded entry on every engine event that could change the guard's
answer, and it advances the container itself the moment the guard
reads clear — automatically, with no separate human step, the same way
a ticket's own `checks` → `merge` transition already needs none once
its precondition clears. `systems/delivery.md` carries the mechanism
(`ContainerLifecycle`, its dispatcher process manager); this paragraph
states only the semantics the mechanism has to honor.

**Second, reaching `terminal` is guarded by every one of a
container's own queues holding no unresolved work, as a platform rule
— never something a bundle declares via `blocks:` or can opt out of.**
An authored `blocks:` relation is one entry guarding one other,
wherever an author chose to write it; a queue nobody thought to name
in some other entry's `blocks:` list, left unguarded, would otherwise
close over quietly on the way to `terminal` — exactly the stranding
hole this section's "no boundary ticket" decision (above) already
closed once, reopened by omission if `terminal`'s own guard depended
on bundle-authored coverage. This system's dispatcher, not the loader,
enforces it (`systems/delivery.md`), the identical split every other
undeclarable-but-checked fact in this section already takes.

**Third, `generation`'s closed vocabulary grows two named kinds:
`design` and `architecture`.** One `generation` kind could not carry
what a workflow with more than one generation-shaped visit needed to
say — this section's own feature lifecycle (§7.6) has always described
two, *Product design* then *Architecting*, told apart only by array
position and by which review followed each, never by the entry itself.
`design` and `architecture` say it directly, platform-fixed in the same
table `generation` already sits in, not bundle-authored: that is what
keeps a blocked ticket's re-resolution anchor set intact, since the set
it re-resolves against can only be what it is *because* it is not
declarable, and a bundle-invented generation-phase label would be
exactly the undeclarable set acquiring a declarable member. Plain
`generation` is unaffected and stays correct for a single visit —
`setup`, `retro` and the seed pass all keep it. Which of a bundle's own
generation-shaped chain tiers (`sysarch`, `impl`, `ref`, and the rest of
`bundles/default/tiers/**`, today uniformly declaring
`delivery: {phase: generation, agent_step: design}`) picks `generation`,
`design` or `architecture` is bundle content, dev's diff against this
record, not a mapping this pass assigns.

**Fourth, a sub-array is referenced by an entry it contains, never by
a name of its own.** Sub-arrays stay anonymous (`dsl-syntax.md` §15.10
— no `name:`, no `id:`), and `blocks:` (and any future reference into
one) resolves by finding the one entry the reference names and
reaching whatever contains it: `main blocks: [retro]` reaches the
sub-array `retro` sits in exactly the same way it would reach a bare
top-level `retro`. Uniqueness is a property of the reference, not the
declaration — a reference resolving to zero or to two or more matches
is the load error; duplicate entries the reference itself never
reaches are unaffected. This is what makes the two worked examples this
section and `dsl-syntax.md` §15.2/§15.10 carry — `main`'s `blocks:
[retro]` naming a `retro` that carries no `flow:` of its own — load
cleanly: the seventh-pass rule requiring a `blocks:` target to be a
population anchor never fit an inline `retro` in the first place, and
is retired along with the sentence it read from.

**Fifth (a third design review, catching what the second missed, and a
fourth catching that the third over-corrected): a container's position
moves backward on a step's own outcome or an explicit author
transition, never as a side effect of a queue refilling.** The second
review's own account of the first correction above was incomplete:
inverting `blocks:` to a precondition checked once at entry removed
the standing-hold reading's defect from the guard, but `dsl-syntax.md`
§15.8 still stated the identical defect in terms of *position* rather
than of the guard — "a resolved queue un-resolves the moment its
population refills" as one of two ways a container's position moves
backward, un-gated. That sentence is retired: a queue refilling still
un-resolves that queue (§15.7 is unaffected), it no longer implies the
container's own position moved.

The third review's own fix named the surviving cause "an authored
transition," which named *who* moves the position rather than *why*,
and ruled out more than it meant to: a `critique` entry's own decline
is automatic, with no author in it, and §7.19 requires it be
structurally identical to a human decline at a gate — one mechanism,
not two, for regeneration feedback (below). What is left, correctly
stated, is two causes: **a step's own outcome** — a decline, whether a
`critique` entry's own agent run issues it (landing back on the
generation entry it pairs with, §15.5) or a human issues it at a gate
(landing per its `throwback:`, §15.4) — and **an explicit author
transition** — concretely, the return from `retro` to `main`, which
runs `retro`'s own sub-array (its agent step and the human gates
around it) to completion before `main` starts churning the tickets
`retro` just filed, rather than automatically the moment `retro`'s
output lands back in `main` and un-resolves it. A queue's population
changing is still never among them. This is also the reason the second
correction's `terminal` guard is reachable at all: the shipped
`milestone`'s only throwback to `main` is `milestone-signoff`, placed
*before* `retro` (`dsl-syntax.md` §15.10), so without the manual
return `retro` filing work into `main` would leave `cleanup`/`terminal`
blocked with no declared path back. `lib/catapult/engine/projections/
container_queues.ex`'s resolution condition 1 and its own citation to
§15.8 predate this correction and are dev's diff against it, not
design's — named here so a dev pass does not carry the retired reading
forward on the strength of a comment citing a section this pass
changed.

The **`:live` suite** still runs once per milestone (§2.8, settled at
ORC-105 to gate `main`'s completion specifically), and a failing
verdict is exactly the sort of unresolved work `main`'s `blocks:`
relation to `retro` holds open for: `retro` will not begin — and
`:live` re-runs — until it clears. "Shipping" a milestone still
aggregates the flag set from its included features and flips it once
`retro` closes clean, after a green live run and the author's pass —
features merge dark as they complete; the milestone lights up
together.

**Archive is policy, and the retro note dies with it.** Archiving a
container's old work items is a user action, and optionally a status
for operators who want a button rather than immediate archival — it
exists in orchestration because of a borrowed tracker's ticket cap,
which is not a protocol concern here and is never load-checked to
precede anything (`dsl-syntax.md` §14's corresponding entry). What
protocol *does* guarantee: **containers and projects alike keep
references to their work items even once archived**, so either is
always a path to its own history. That kills the retro note
outright — its whole job was duplicate detection over work that
archiving had made invisible, and
nothing here is invisible in the one context that matters. The
archive-precedes-every-step load check ORC-103 drew up goes with it:
it was well-formed only on the premise a scan couldn't otherwise see
archived tickets, and that premise no longer holds — keeping a rule
after its reason is gone is the failure the mix.exs cowlib
advisory-ignore rationale went stale the same way (ORC-91): a
justification that quietly outlives the fact it was true of.

**A sixth pass named the plane's own starting point, which derived
rootness never did.** The fifth pass's declaration-graph fix (above)
answers "is this type a root" — a node nothing else's `flow:`
targets — and a bundle that declares `epic` without ever nesting it
under something else has *two* roots the moment it does, since `epic`
was already one before `milestone` joined it as another. Roots are
not projects, and "the project is a project by convention" — every
earlier pass's own phrasing — named nothing the loader could check.
**`entry:`, a new required key on a workflow bundle's own
`bundle.yaml`, names the type a fresh project actually dispatches
from** (`dsl-syntax.md` §2): a reference, the identical shape
`catapult.yaml` already has pinning one bundle per axis, not a second
copy of a fact the graph produces on its own. The loader checks it in
full — the name resolves, the resolved type carries a population
anchor of its own, and it is a root in the declaration graph — so a
bundle that
loads has a starting point the loader has actually verified rather
than one a reader has to infer from which declaration looks
project-shaped. Worth recording alongside it: acyclicity already
guarantees at least one root exists in any loaded bundle (a finite
DAG always has a node with no incoming edge), so `entry:` is the only
missing piece here, not a general well-formedness rule needing a
companion check of its own.

### 7.9 The scaffold

**No phases.** The initial build-out is: total architecture pass →
**one delivery-only scaffold ticket covering the MVP closure** →
feature-by-feature for the rest of the initial list, re-prioritized
by real usage → the standard flow forever.

The reasoning, recorded because phases were seriously considered and
the arguments shouldn't be re-derived:

- Once the architecture is total and approved, **a phase ticket and a
  delivery-only feature ticket are the same object** — both enter at
  implementation (§7.3), skipping the empty gates. Phases were never
  a third traversal mode; they were a batching scheme plus a slicing
  methodology.
- The slicing methodology (which part of a shared subcomponent does
  this increment build?) is a second delta-scoping mechanism; the
  feature flow's plan tiers (§7.2) already answer that question and
  are needed post-launch regardless. One mechanism, not two.
- **Phases commit build order at plan time; feature-by-feature
  re-decides continuously.** The initial feature list will be
  partially wrong once usage arrives (the premise of stopping the
  scaffold early at all); under phases the invalidated features get
  built, under MVP-then-features they exist only as docs. Docs are
  cheap; code is expensive.
- Per-feature validation is finer than per-phase; the MVP is the
  architectural-error checkpoint (core journeys + foundation validate
  the spine before the long tail builds); deploys were already
  per-feature. Every incrementality argument phases served is served
  as well or better.
- Debt is not the counterargument: per §1's theory, debt is contract
  renegotiation, and contracts are protected structurally, not by
  delivery batching.

Mechanics: MVP selection pins features `mvp: true`; the plane
computes the dependency closure (foundation auto-included). The first
buildable unit is inherently a batch — you can't feature-slice from
zero — hence one scaffold ticket, with component children as usual.

The one cost accepted knowingly: feature-sized delivery of the
initial list maximizes repeat visits and mutex contention on hot
shared components, where a phase would have coalesced each
component's work into one child visit. Mitigation without machinery:
nothing prevents putting several approved features into one delivery
ticket when contention bites — ad-hoc batching is a prioritization
act in the tracker. If that ever feels strained (e.g. a regulated
product that must ship as a coherent whole), phases can return as
*pure batching* without the slicing machinery, which was always their
expensive half. Watch metric: per-label mutex-wait (§7.5).

### 7.10 The delivery DSL

**Framing decision: declare the shape, implement the semantics.** The
plane's Commanded aggregates ARE the semantics (validate-or-revert,
claims, harvesting, auto-merge-forward); there is no YAML-programmable
workflow interpreter — that would be a second Turing tarpit, and the
bundle DSL already drew this line (platform owns edge-type machinery,
bundles own instances). Declarations exist so the plane is generic
over projects and target layers, so the protocol is inspectable
(orchestration's DESIGN.md tables become machine-read artifacts
instead of prose the code hopefully matches), and so the sim ring is
configured from the same declarations production reads.

**The protocol is platform-fixed; projects bind, never restructure.**
Agent prompts, plane logic, and shared vocabulary are written against
the protocol; a project with bespoke states forks all three
(orchestration §1: two copies of a shared vocabulary drift silently).
Projects get **bindings** — tracker team/project ids, the state-name
mapping into Linear's workflow, actor role→user-ids, the `reviewers:`
map, deploy endpoint, preview target, `tunable`-marked thresholds —
nothing structural. **Bindings are plane entities, not a repo file**
(differs from orchestration, which had no store): edited through a
settings/onboarding flow that *queries* Linear and GitHub through the
plane's adapters so the user picks from what exists instead of
pasting ids, with one-click provisioning of the status vocabulary
into a fresh tracker team (orchestration's `setup`, UI-ified). Three
free consequences: binding changes are event-sourced (config history
is a real audit answer), the UI renders exactly the tunable surface
so protocol-fixedness is visually enforced, and the sim/test ring
configures from the same entities. The split that survives: **repo
holds content** (bundle, `catapult.yaml`) — versioned with the
design; **plane holds bindings** — queried, picked, stored. Not
urgent to build (§8); cheap and high-value when it lands.

**The store test, completing the family** (from the
configurable-policy design pass): *does changing it change what would
be generated, validated, or enforced?* → **graph state** — repo
content, versioned, staleness-propagating, because replay determinism
requires every generation input to be answerable from git history.
Policy tunings, component `options:`, the per-project policy overlay
all pass this test: they live in the bundle's `extends:` layer and a
change is a PR, not a settings write. *Does changing it change only
how the plane connects and operates?* → **plane state** — the
bindings entities above. *Does changing it change only the built
app's runtime behavior?* → **app state** — the generated project's
own database, none of Catapult's business. The tempting shortcut —
"it's configuration, put it in the settings UI" — is exactly how
generation inputs leak out of version control; the test is the
tiebreak, applied per attribute, not per feature. The UI consequence
is §5's third prong: the **configuration surface** is a *composer,
not a review surface* — forms generated from registry declarations
(option enums as selects, `tunable` shapes as bounded inputs, `fixed`
policies rendered read-only), where "save" composes a well-formed
diff and files it through the normal entry machinery (the plan tier
classifies impact: a tenancy flip routes through §3.4's upgrade flow;
a threshold tweak is maintenance-grade). Review stays in the PR; the
composer never bypasses a gate.

**The join to the design graph extends the existing syntax rather
than paralleling it.** Forced, not aesthetic: projects can add tiers
via bundle `extends` but cannot edit the protocol, so membership must
be declared at the member, with the protocol defining only the slots:

- **Tiers gain a `delivery:` block** — `phase:` (status shown while
  the tier generates) and the agent step that generates it. **Amended
  at §7.18:** this block names *only* platform-fixed vocabulary. It
  formerly also carried `gate:`, naming the author gate whose PR diff
  approved the tier, with a gate's review set derived from the tiers
  declaring it. Both are gone: a chain cannot name a gate, because
  gates are workflow-bundle declarations and the two axes must
  compose without a shared vocabulary. The review set is still
  derived, keyed on position instead — a gate reviews whatever the
  chain produced at the fixed step it follows. Bundle-load validates
  annotations against the protocol vocabulary: an unknown phase or
  agent step is a load error; one loader spans both worlds.
- **Flows gain a ticket face.** Entry types (§7.3) and v4's flow
  catalog are one list — opening a ticket IS opening a flow instance.
  A flow's `flow.yaml` adds `ticket: { entry: <tier>, labels: [...] }`
  alongside its schema delta and walk primitive; its planning tiers
  carry `delivery:` annotations like any tier. Flow completion maps
  onto phase transitions ("phase complete" = no ready or in-flight
  scopes with this phase within this flow instance). Scaffolding
  keeps its v4 status as "a flow with an empty delta" — the base
  schema wearing a ticket face.
- **Spawn is a plane rule, not a declaration.** Spawning is
  partitioned by the fanout structure of the impacted scope set
  (plan/staleness data), one child per impacted component, nesting to
  subcomponents only where the plan proves independent parallel work;
  ticket type follows nesting depth.
  **Amended: children are created when the plan node names them, not
  at the Building transition** (`docs/ui-spec.md` §3.1). The reason
  is review, not display: reviewing a design that names its children
  is better with those children in existence, so the artifacts and
  comments attach where they belong from the start. Spawning at
  Building means the fan-out first appears after every gate it should
  have informed.
  **The load-bearing reason is structural, and it is §7.19's own.** A
  review status carries a fan-out depth, and a child's effective
  sequence is the declared sequence filtered to its depth — so **any
  depth-scoped gate sitting before Building is unclaimable unless the
  children exist by then.** Spawning at Building confines every
  depth-1 and depth-2 gate to the post-Building half of the sequence,
  which forbids the case most worth having: a component-level
  architecture review while the design is still under review. Early
  spawn is therefore a precondition for half of §7.19's depth
  mechanism rather than an ergonomic preference, and it lets gates at
  a fan-out layer be claimed from the moment that layer exists —
  which is the shape the initial build-out wants, where every
  component is new at once.
  **Clutter was the original objection and it is answered elsewhere:**
  the board collapses fan-outs by default (`docs/ui-spec.md` §3.1),
  so early children cost nothing in legibility. Noted because the
  amendment was first reached *from* that screen work; it does not
  depend on it, and the reasoning above is what it rests on.
  **Creation is not dispatchability.** A child created at plan time
  enters a pre-queue state and becomes queue-eligible only when its
  parent's design gates have passed; otherwise agents would start
  work against an unreviewed design, which is the failure this
  ordering exists to prevent. Two things need care and are called out
  rather than assumed: the blocking relation (§7.2's child-blocks-
  parent, which is about completion) must not be read as dispatch
  gating, and a queue's own `blocks:` check (§7.8's generalization of
  orchestration's `openBlockerFor`) must not treat early children as
  blockers that prevent the parent's own dispatch.
  Product-tier fanouts never spawn because product tiers generate
  under gate phases, not Building. The grain rule is a platform
  constant.

**What remains standalone** is exactly the files with no design-graph
counterpart:

- `states.yaml` — the status vocabulary with owners and the **writer
  matrix** (`moved_by: author | machine | ci | deploy | nobody` per
  transition — one field, and it makes the state-admission test
  executable by the sim ring), plus which states are gates, plus
  **display metadata: a per-state color, with board order = the
  file's declaration order** (previously unstipulated; caught at
  the states pass). Provisioning writes both, so every
  Catapult-provisioned tracker board reads identically. The palette
  originates in orchestration and is **restated here in full**
  (whoever builds states.yaml reads this document, not orchestration
  source). Rule one: **per-state, never per-category** — most
  pipeline states share Linear's `started` category, and a
  category-keyed palette paints the whole board one color. The
  families answer "what is happening, and is any of it mine?" at a
  glance:

  | Family | Hex | Meaning | Catapult states |
  |---|---|---|---|
  | grey | `#bec2c8` | not scheduled | Backlog; Stubbed (deliberate wait — its own column is its visibility; the color needn't shout) |
  | light grey | `#e2e2e2` | queued | Todo, Ready for dev, Ready for rework |
  | violet | `#9b8fd4` | a generation agent is working | Product design, Architecting, Implementation |
  | green | `#4cb782` | building | In progress, Reworking |
  | yellow | `#f2c94c` | machinery verifying/shipping | Checks, Merged (awaiting deploy), Validating |
  | cyan | `#26b5ce` | reconcile agent | Reconciling |
  | orange | `#f2994a` | the author's sign-off | Product review, Architecture review |
  | red | `#eb5757` | stuck; the author unsticks | Blocked |
  | dark grey | `#95a2b3` | terminal, out of mind | Done/Shipped, Canceled |

  Rule two, carried with its reason: **Done is deliberately grey,
  not green** — finished work is out of mind, and green is spent on
  work in flight. Nothing reads colors back; they exist so the
  author sees the queue without reading it. **`Building` drops from
  the green row, retired along with the status it named**
  (`dsl-syntax.md` §15.1, ORC-151's third design review): a feature
  runs its own `Implementation` (violet, above — real dispatched work,
  ORC-151's fourth design review), then sits at `Checks` while its own
  children build, and `Checks` already carries the yellow row above —
  no separate wait-status, no separate color for it.
- `types.yaml` — ticket types, per-type lifecycles, PR topology
  (feature: base main, squash; child: base parent branch, merge).
- `escalation.yaml` — thresholds routing to `Blocked`, with `tunable`
  markers as the only project-override surface.

CI suite selection is *derived*, not declared: gate phases are
docs-phases → `ci:docs`; a ticket's own `implementation` phase
(`dsl-syntax.md` §15.1, ORC-151's fourth design review — `Building`
no longer names this transition, and it is real dispatched work
rather than the bare `checks` an earlier pass stood in for it) →
`ci:code`. A `ci.yaml`
exists only if a real exception ever forces it.

**Agents are three layers, changing at three rates.** The writer
matrix carries *roles* only — authority, invariant across
implementations. The protocol names *agent kinds* (design, dev,
reconcile, validation, and — dispatched through a milestone's
declared queues rather than a tier's `delivery:` block, §7.8, revised
at ORC-105 from the single static `boundary` kind — retro and setup)
as vocabulary. Tier declarations may
carry an *executor profile* (model, effort, harness requirements —
v4's per-tier `thinking_effort` is the precedent). The project
bindings file maps kind → runtime (orchestration's `agents:` config,
generalized). Supporting a second agent implementation is a new
bindings entry and zero protocol or bundle change.

**Maintenance is in-system and plane-filed.** In-system entry is the
default for bugs and dependency/vulnerability work; out-of-band (§7.3)
is the author's escape valve, not a recommended route. A plane-side
watcher (Oban job over hex advisories, `mix hex.outdated`, GitHub
security advisories) auto-files maintenance tickets with entry
`localized` — the plan tier decides impl-only (the overwhelming case:
delivery-only ticket, empty gates) vs. architecture-implicating (a
major version changing APIs walks the doc graph like any change).
Filing discipline bends "issues only on the author's ask" the same
way a milestone's `scan`-sourced proposals do (§7.8): routine bumps
file to Triage for batch-accept; advisory-backed security bumps file
directly to the queue with `Urgent` plus a notification — the
alternative is the author doing it by hand out-of-band, which is
strictly worse. The auto-queue threshold is a `tunable`. Bumps touch
`mix.exs`/`mix.lock` (accepted shared-file territory) and serialize
textually at their natural cadence. `Urgent` itself is a **modifier
on any type**, never a type: pure precedence (preempts at pickup,
dispatches regardless of which queue a milestone currently sits in —
revised at ORC-105 from "overrides the milestone pause," which named
a mechanism §7.8 no longer has — never steals an in-flight mutex),
preserving orchestration's treatment.

**Restricted scopes carry a third touchpoint, and the budget
principle bends knowingly.** A scope marked `codegen: restricted`
(§6, §2.15 — review-pending crypto compositions being the founding
case) auto-bounces any diff in its file map unless the ticket carries
an explicit override label, and its child reconcile inserts a
per-scope human review. Rationale: the two-gate budget was calibrated
for ordinary code; unattended merge of unreviewed cryptographic
composition is indefensible, and the external-node path can't cover
it (these are project-owned constructions with no vetted upstream).
The marker is rare, shrinks as constructions clear external review
(clearing it is itself a reviewed doc change), and restates the
budget principle as: **touchpoints are budgeted per ticket class, not
globally denied.** With stub grade (§2.16), restricted in-repo code
exists only while its review window is actually open — the stub runs
ungated, and the gate rides the swap ticket — so the third touchpoint
gets rarer still.

**Stubbed scopes project into the working surface as swap tickets.**
When a stub declaration is approved, the plane files the swap ticket
(machinery-filed, like a milestone's `scan`-sourced proposals — §7.8,
revised at ORC-105 from "the boundary ticket" — and maintenance) in
the **`Stubbed`** status (§7.6), carrying the scope's mutex labels,
the deferral argument, the exit plan, and the gate it will run when
scheduled. **No milestone** — the point is an open timeline, and a
milestone-bound Stubbed ticket would hold that milestone's queues
open forever (§7.8's `blocks:` relation). Scheduling is the author's
act: assign a milestone, move it into the
flow, ordinary (gated) ticket from there. The audit keeps tickets and
inventory in lockstep (§2.14). Rationale: the stub inventory is the
mechanical truth; the Stubbed column is that truth standing
permanently in the author's field of view — a live, visible list of
what is deliberately half-built.

**Assignment is derived, never authority.** The plane writes tracker
assignees as a projection of who-has-the-ball: author-owned states
and `Blocked` assign to the step's **default reviewer** (project
bindings: a `reviewers:` map, step → user, everything defaulting to
the author); machine-owned states assign to the step's
**pseudo-user** (tracker app/agent users), so the ball-holder is
readable from the assignee column. The plane never *reads* assignees
— states answer who-has-the-ball; assignees render it. A human
reassignment within an author-owned state is delegation and is
respected until the next state entry re-derives. At one human this
degenerates correctly: "My Issues" is exactly the cross-project list
of tickets needing the author — the inbox property, with no
filtering. (Deliberately rejected: assigning everything to the
author — if every ticket is yours, the attention signal dies; the
full inventory already exists as project views.) Catapult-plane
feature only: for Catapult's own build the author runs a simple
external assign-when-needed rule; nothing is ported into the Go
pipeline.

### 7.11 Validation and the repair loop

Validation is per-ticket and bottom-up over the ticket tree, and its
repair loop is deliberately *simultaneous* — the rationale is §1's
debt theory applied to repair: **when several validation failures
share an ancestor, fixing them one at a time renegotiates the shared
contract serially** — three sequential patches to one comparch is
interface drift happening inside the machinery built to prevent it.
Simultaneous rework lets the upward walk reach the shared parent
carrying every failing child's context and make one coherent
revision.

The mechanics, all built from existing machinery:

- **Bottom-up order is a readiness rule.** "A component cannot
  validate until all its subcomponents validate" is the standard
  cardinality-many gate; validation slots into the scheduler as
  per-scope passes gated by child passes — leaves first, the feature
  last. No new scheduler machinery.
- **The repair is `up_then_down`, seeded by the failure set.** The
  walk coalesces naturally at lowest common ancestors — which is
  where interaction-catching happens. **The walk may terminate at
  height zero**: its first planning step decides how far up to go,
  and "no doc change, fix the implementation" is the degenerate case
  — so every failure gets shared-cause detection without forcing doc
  churn on ordinary implementation bugs.
- **A new join point, flowing the reverse direction:** the flow's
  planning tiers may read `ticket.findings` — the validation findings
  and ticket thread for scopes the walk visits. Delivery data as doc
  generation context; every prior join point flowed the other way.
- **The down-walk catches the passed-but-now-stale.** A revision
  landing at comparch stales passing siblings that depend on the
  revised contract through ordinary staleness; their tickets reopen
  to rework alongside the failures. Re-validate the affected subtree;
  passes over untouched scopes stand.
- **No new states.** A validation failure files a findings comment
  (fixed marker) and routes the child through `Ready for rework` —
  newest-comment-is-scope works unchanged, and the marker is what
  tells the plane to open the up-walk. The feature holds in
  `Validating` while its subtree churns. State set stays small;
  meaning rides the marker, per the label-vs-state discipline.
- **Convergence guard:** the progress criterion is that the failure
  set strictly shrinks each full cycle. A failure surviving two
  cycles escalates individually to `Blocked`; two full cycles with no
  shrinkage escalates the feature. Same pattern as CI-red-twice and
  bounce-twice — the author is the fixed point of every
  non-converging loop.

**Staleness is a projection, never stored state** (from the
staleness design pass — explicit because whoever builds this won't
have read v4 and must not reinvent its mechanism). v4 held staleness
as a persistent per-node flag with comments parked on the node: the
node was the mailbox, and "whatever run procs next" was the delivery
mechanism, because v4 had nowhere else to hold pending work. v5
does — pending work is always a ticket, and feedback lives in
`ticket.findings` and harvested PR comments, scoped to a flow
instance. So there is no stale flag table and no node-attached
pending work, ever; "stale" is a pure computation off the event
log — *this node's committed content predates the inputs its context
walk reads* — queryable (the dashboard's staleness provenance view)
but never work-holding. It has exactly two consumers, split
mechanically by whether a live flow's walk reaches the node:

- **Inside a flow → scope of the current ticket.** The spawn rule
  already partitions children by the impacted scope set, and the
  down-walk already reopens passed-but-now-stale siblings; the
  cascade set of the walk *is* the stale set, including
  previously-shipped nodes when they're downstream-reachable from a
  revision. No sequencing question can arise — there is no separate
  staleness pass to order against the current ticket, because
  staleness resolution *is* the walk, and bottom-up readiness defines
  the order.
- **Outside any flow → a plane-filed backlog ticket**, and every
  out-of-band staling source already has a named ticket shape:
  upgrade-flow tickets (§3.4), enforcement tickets (§4.5), swap
  tickets (§2.16), ref regeneration chosen from a hint (§4.5). There
  is deliberately no generic "staleness ticket" kind — the named
  shapes carry more meaning, and a generic kind would be the flag
  table sneaking back in as a ticket. Input documents are
  deliberately absent from this list: they are frozen at intake
  (§1.1) — an input-doc edit is not a staling source at all; it
  stales nothing and is answered loudly with a Triage notice.

The case that spans both — feature A revising a shared contract
while feature B is in-flight downstream — needs no cross-ticket
blocking edge: the mutex prevents simultaneous holds, and the
handoff is the existing merge-main-forward rule. When A lands and
the plane merges main into B's branch, B's own readiness computation
sees the moved inputs and B's walk regenerates the affected nodes —
the in-flow mechanism, executing inside B's flow instance.

Open within this: the *content* of a validation pass (affordance and
state checks against the deployed feature, impl-doc `<tests>` as
normative, composed-journey checks) is specced in pieces across
§2.8/§4.3 and needs consolidation into a single check inventory.

### 7.12 Still open within the delivery model

#### 7.12.1 Agent-run substrate

Actions vs owned runners, and how many concurrent sessions the
plane dispatches — now covering *all* generation, not just
children (§1.2). Direction decided, shape open: start on Actions
with **prebaked container images** (the browser/toolchain stack
pulls, never builds, per firing); the scale-out is an autoscaling
worker pool pulling from our queue —
**committed as a late-delivery feature, not speculative**: the
validation loop's endgame needs agents that interactively drive
rendered apps (chromium-grade tooling), which screenshots can't
replace for client-locus apps. Interim validation capability:
Pages previews + containerized screenshot/trace jobs whose
artifacts agents read (orchestration's preview machinery
extended). Likely pool shape: actions-runner-controller on the
already-blessed DOKS cluster, images cached on nodes.
Refinements from the hosted-option pass (§8): **the execution
substrate is an adapter behind the dispatch port** — Actions and
the worker pool are two adapters over one runner-harness contract
(fetch rendered context, run agent, commit, report); the contract
is the invariant, the substrate is swappable, and the executor
must not grow Actions-specific assumptions outside its adapter.
Actions stays the default (self-hosters will use it out of
convenience); the pool is the latency upgrade. And **the pool
rides BYO like everything else**: its canonical home is the
customer's cluster (ARC on their DOKS — the same blessed pattern),
with plane-adjacent managed runners as the opt-in for zero-infra
customers, not the default. **The dispatch-concurrency cap is a
per-instance, plane-enforced `tunable` in the bindings** — this
open item's "how many concurrent sessions" question now has two
consumers (scheduler backpressure and hosted tiering), so the cap
is plane state from the start, never a config constant.
**Runner↔plane authentication (docs review pass, settled — this
was the review's top gap):** the Actions adapter authenticates
runs with **GitHub Actions OIDC** — the runner requests GitHub's
signed ID token and presents it as a bearer to the plane's
context-fetch and result-report endpoints; the plane validates
offline against GitHub's published JWKS and matches audience,
`repository`, and `run_id` against its own dispatch record. The
credential is therefore scoped to a single run the plane itself
started, expires in minutes, is minted by GitHub rather than
stored by anyone, and **no secret rides the dispatch inputs**
(which are visible-log territory — the reason a naive shared
token is wrong). This is the industry-standard mechanism (the
same tokens authenticate Actions to AWS/GCP/Vault); JWT + JWKS
verification is stock Elixir machinery (joken/joken_jwks-grade),
not custom crypto. The pool adapter mints per-dispatch capability
tokens delivered over the dispatch channel instead — pool
dispatch is plane-initiated and not publicly logged, so
plane-minted is safe there; cluster OIDC is the upgrade if ever
wanted. Corollary under both adapters: **rendered context never
contains bindings or credentials** — context is design content
only.
**Model credentials are a pair, and the runner harness carries
the failover** (credential pass): the harness's run-agent step
accepts `ANTHROPIC_API_KEY` and/or `CLAUDE_CODE_OAUTH_TOKEN` —
both customer-side secrets per the BYO rule; the plane never
sees either. This is budget-path economics, not a convenience:
solo devs will mostly run Max subscriptions, and the
subscription token is what makes their marginal generation cost
near zero. **The order is a per-project bindings `tunable`**
(an ops preference — plane state by the store test), delivered
to the runner as an ordinary dispatch input, since a preference
is not a secret. Failover fires on **limit-class failures only**
(usage/rate limits, exhausted credits); every other failure
fails the run unchanged — failover is for capacity, never for
bugs, or a real failure gets paid for twice. The run report
names which credential served, so dispatch history answers
"when did we start spilling onto the meter" as a query, not
archaeology.
**A daily dispatch budget rides beside the concurrency cap**
(notifications pass): the cap bounds parallelism, not volume, and
an unattended system spending customer money needs both. Two
`tunable` thresholds per instance: **warn** (notification +
dashboard banner) and **cutoff** (dispatch halts; in-flight runs
finish; urgent notification). Alerting rides the observability
dogfood (Prometheus, §2.11) — a machine-shaped fact, not a
ticket, per §7.4's two-channel rule.

#### 7.12.2 Linear API and webhook limits

Under many child tickets — verify plan limits before the plane
assumes them (orchestration §14's warning, inherited).

#### 7.12.3 The validation check inventory

Routing settled, content scattered (§7.11).

#### 7.12.4 Pseudo-user assignability and seat economics

On Linear's plan (§7.10's assignment projection) — verify before
relying on per-step pseudo-users; the reviewer-map half works
regardless.

### 7.13 Load-bearing constants

Recorded so nothing relitigates them: mutex labels derive from
doc-graph scopes (§2.1, §5.4); the sketch is a diff against
architecture bodies; the audit is the shared enforcement organ
between design and delivery; orchestration's Go pipeline delivers
Catapult itself while the Elixir plane re-expresses the protocol for
generated projects; the Go core's snapshot→actions purity is the
porting model (near-1:1 to a Commanded process manager); descriptions
immutable and newest-comment-is-scope survive at the child grain;
detect-and-revert survives as validate-or-revert with the event log
as authority; the protocol has one home in the platform layer —
projects bind ids and tune marked thresholds, never restructure
states.

### 7.14 Bug intake and the log cursor

An event-sourced plane can answer a question a conventional one
cannot: **what was true when this went wrong.** Bug intake is built
around that answer rather than around a description of symptoms.

- **A bug report carries a sequence, not just a timestamp.** On
  intake the plane stamps the report with the log sequence at the
  moment of ingest, as a marker comment (§7.1's programmatic-comment
  rule). Wall-clock is what a reporter has; a sequence is what the
  log can seek to. The stamp is an **upper bound on cause** —
  everything causal happened at or before it — and that alone turns
  "reproduce it" into "replay to N and look," which is the return on
  being event-sourced in the first place.
- **Where the stamp comes from, in preference order.** Best is the
  *observation* point: a report raised from the dashboard or from a
  running app's error surface carries the sequence the reporter was
  looking at, and the bound is tight. Next is ingest: a ticket typed
  into Linear is stamped when the plane first sees it, and the bound
  is loose by however long the human took to file. **That gap is
  stated on the ticket, never hidden** — a bound presented as a
  pointer is worse than no bound, because it sends the agent
  searching the wrong window with confidence.
- **Vicinity is causal, not temporal.** A ±k window around N is the
  v0 approximation and a poor one: the log interleaves every stream,
  so a temporal window is mostly noise from unrelated scopes. The
  target is the events the failing read's projections actually
  consumed, and the machinery already exists — readiness and
  staleness are computed from context walks (§7.11), which is
  precisely a statement of which inputs a node's state depends on.
  Ship the window, name it as an approximation, replace it with the
  walk.
- **The unit is the ticket, not a window.** A report or harness
  finding attached to a ticket imports *that ticket's* events — its
  dispatches, claims, transitions, and the domain events its scope
  produced. For a harness issue that is the entire causal set by
  construction, since the pipeline's own events are ticket-scoped.
  For a domain bug it is the seed, and the causal walk above extends
  it.
- **Seeded statically, expanded on demand.** The claim renders the
  ticket's event set — a guaranteed floor, present even when every
  other surface is down, bounded, and marked as **evidence rather
  than instruction** (§7.4's rule applies to payloads verbatim, since
  a payload is data somebody else wrote). Past that floor the run may
  query, because the cases worth solving are cross-ticket: a defect
  visible on one ticket whose cause sits in another scope still in
  flight. Rendering every candidate ticket's events into one prompt
  trades a context problem for a worse one.
- **The query surface is typed and plane-mediated, never open.**
  Reads are named questions — the events for a ticket, the projection
  as of a sequence, explain-why for a scope — not a query language,
  and **summarizing by default: the map before the territory.** A
  tool that answers with five hundred payloads has spent the context
  it was invented to save; it answers with counts, kinds and streams,
  and yields payloads on request. Causal filtering happens plane-side
  where the context walks live, not agent-side after the fact.
- **A credential the plane mints, scoped to the run.** Not a standing
  token the run happens to hold: dispatch mints it, scoped to that
  ticket's readable set, expiring with the run. This is what the 403
  actually taught — not "never fetch," but *never depend on a
  credential nobody guaranteed you.* A rework run on this project's
  own pipeline reached for CI logs with a token that could not read
  them and worked the ticket blind, at the cost of a full run.
- **Queries are recorded, and that is what replaces determinism
  here.** Every read lands in the run's transcript as an observation
  (§7.1: the log records decisions and observations). A diagnostic
  run cannot be predicted in advance the way a generation run can,
  but it must be reconstructible afterwards — *why it concluded what
  it concluded* has to be answerable from the record. That is the
  boundary of §8's MCP exclusion, restated there.
- **Payloads are classified before they are rendered.** In a hosted
  instance event payloads hold customer data, so rendering one into a
  model call is a data-flow decision rather than a convenience:
  events carry a classification the way `externals/0` entries do
  (§2.2), and the renderer redacts by class. A formality for the
  community tier, the legal surface for the hosted one — and far
  cheaper carried from the first event than retrofitted across a
  format zoo (§2.4).
- **Archived sequences stay reachable.** Cold-storage archiving (§8)
  may not move a sequence out of reach while an open bug references
  it: either open references pin their range, or retrieval is
  transparent and slow. Decide it with the archiving work; do not let
  a bug ticket become a pointer to nothing.

**Why this earns its place beyond Catapult.** Generated projects
adopt the same ES family (§2.4), so a bug-report-with-cursor is a
platform capability rather than a plane feature: every application
Catapult builds can hand its author a reproducible bug the same way.
That is the argument for building intake properly instead of as an
internal debugging aid — it is a product surface that happens to
serve us first, and client-filed bugs and requests arrive through the
tracker we already run on.

Open: whether a bug is a distinct ticket type or a feature ticket
wearing a label — it is born needing diagnosis rather than design, so
it enters past the design gates the way children do (§7.10), but the
label admission test is what settles the shape. Also open: whether
client requests share intake with bugs (one surface, two types) or
arrive on their own.

### 7.15 Pausing and resuming a pass

The first architecture pass over a real seed is expected to outrun a
subscription window. That is the normal shape of intake, not an
incident, and the machinery treats it that way: a pass pauses, says
so, and resumes itself.

**Two failure modes, never merged.** *Overran an internal budget* and
*overran an external limit* look alike from a distance and behave
differently in every way that matters, so they get separate handling
and separate names.

| | internal budget | external limit |
|---|---|---|
| whose | ours (§7.12.1's `cutoff`) | the provider's |
| when known | predictable — we choose the stopping point | discovered on the failure |
| boundary | **clean**: in-flight runs finish | **dirty**: the run dies mid-scope |
| resume | scheduled, at the window we set | polled hourly until it lifts |
| manual restart | available, **and requires raising the limit** | available |

The manual restart on the internal side carries the raise because it
must: a restart that leaves the budget where it was trips the same
cutoff on the next dispatch, and a button whose only effect is to
re-announce the thing you just dismissed teaches you to stop pressing
it. The external side has no such lever — the limit is not ours to
raise — so its button is a "try now" against the hourly poll.

**Both tiers get the same strategy.** Spilling to the metered
credential does not make hosted immune: a hosted instance runs on
credentials that have their own ceiling, so it meets the external
mode too. Only the notification default differs — self-hosted
notifications are **opt-in**, since a solo instance paging its owner
by default is a pager they will mute (§7.4's two-channel rule and
its warning about surfaces where attention goes to die). Every
threshold, the resume schedule, the poll interval and the
notification choice are `tunable`: the point is that it behaves the
way its operator wants, not the way we guessed.

**Where the resumable state lives: not in the run.** This is the
question that looks hard and is already answered by two recorded
decisions. Readiness is a query against current projections (§7.11's
state-driven scheduler), and staleness is a projection rather than
stored state (§7.11) — so *what still needs doing* is derived, on
demand, from the log. A pass therefore has no cursor to checkpoint
and no queue to restore. **Resume is re-asking the readiness
question.**

**"Scope" here is a doc-graph node, not a ticket — the two fan out at
different times and this is the place that confusion lands.** The
graph is materialized at intake, so scopes exist from the first pass
and `ready_scopes` ranges over them; generation dispatches per scope
and the log carries per-scope events from the beginning. The *ticket*
tree is a separate, deliberately coarser projection of the same
fanout (§7.2), and its children spawn when the plan document proves
independent parallel work exists — depth earned, never reflexive,
never at a status transition (§7.10's own amendment, corrected here to
match: an earlier draft of this paragraph had children spawning "at
`Building`," which §7.10 had already retired in favor of spawning at
plan-node-naming time by the point this section was itself written,
and the correction was never carried over).

**For the architecture tree specifically, scope and ticket are the
same grain, settled at ORC-151.** A `critique` decline needs to land
on the one tier that produced what it declined, never on a sibling or
a parent (`dsl-syntax.md` §15.5, §15.11) — which a ticket sitting in
one status covering several fanned-out scopes at once cannot give it,
since a ticket has one status at a time (§7.19). So sysarch, each
comparch and each subcomparch dispatches through its own ticket
instance, spawned the identical way any other component or
subcomponent child already is, one level at a time as the plan proves
each layer's own independent parallel work — not a second grain this
paragraph's own distinction argues against, since the distinction
above is about *when* graph nodes and ticket nodes each come to exist,
not about how finely either fans out. A tier whose own critique never
needs an independent bounce — this section's own subject, an internal
architecture pass pausing and resuming mid-run — still dispatches per
scope beneath whichever ticket its own fan-out level sits at; nothing
about resumption below changes for it.

The consequence is about what the author sees: a paused pass surfaces
on the ticket currently dispatching and on the dashboard's
unbuilt-scope count. That count is not a convenience during intake —
it is the progress surface for whatever is not itself already a
ticket the author can watch directly.

What that requires of the executor, stated so it is built that way
rather than discovered later:

- **One dispatched run per ready scope**, never one run per pass. The
  scope is the unit of work *and* the unit of resumption.
- **One atomic commit per scope, at the end.** A scope that dies
  partway leaves no commit, so the readiness query still lists it and
  it is dispatched again from the top. A half-written artifact is
  never committed — partial output is the one thing that would turn a
  derived answer back into a checkpoint.
- **No memory across dispatches.** A re-dispatched scope re-renders
  its context walk and starts clean. Re-running a scope must be
  indistinguishable from running it the first time, because after an
  external limit that is exactly what happens.

The asymmetry above is why this matters more than it looks: an
internal cutoff never needs the idempotent path, because it stops on
a commit boundary by choice. An external limit always needs it.
Building only for the tidy case leaves the untidy one to be
discovered by a customer.

**The failure this must detect rather than loop on: a scope too large
to finish inside one full window.** It will fail at the limit,
resume when the window lifts, fail again, and consume every window
forever while reporting progress it is not making. Repeated
limit-class failure on the *same* scope is therefore `Blocked` with a
named reason (§7.6's `needs-setup` shape: say exactly what must
change — split the scope, raise the plan, or move that tier to the
metered credential), never another retry. A retry loop that always
fails at the same place is indistinguishable from work, which is what
makes it dangerous.

**Progress is a query, not a report.** Unbuilt ready scopes, with the
paused-until time when paused: one number the dashboard shows beside
explain-why (§7.4), and the same number a resumed pass starts from. A
paused pass that looks identical to a dead one is the "signal
silence" failure §7.4 already names — so pausing announces, and the
announcement carries when it intends to wake.

### 7.16 Concurrent writers

**Small teams are supported.** This reconciles a contradiction the
record carried rather than reversing a decision: §1's target class
has read "single-author / **small teams** shipping enterprise-scale
systems" from the start, and §2.9's identity component already ships
orgs, membership, invitations and roles-as-data. The old
`No multi-writer projects` non-goal was the outlier, inherited from
v4 rather than decided here.

**The two things that entry welded together, separated — one stays
out:**

- **Concurrent authoring of artifact bodies** is still out. Bodies
  live in git; PRs already carry merge semantics, and the plane does
  not grow a second set. This is what v4 actually carved out and the
  carve-out holds.
- **Concurrent action on the delivery protocol** is in, and is the
  subject of this section. It is optimistic concurrency, not merge
  semantics — a solved problem rather than a different system.

**Sign-off is role-scoped, and any holder of the role satisfies it.**
Product/design sign-off and architecture sign-off are distinct
permissions; one or more people hold each; any one of them can give
their role's. This lands exactly on §2.9's split — **permissions are
code, roles are data**: the delivery system defines the sign-off
atoms, identity stores who holds them and evaluates the grant. More
sign-off classes, and whatever states they imply, are a later
increment (§7.6's admission test still governs); nothing here may
assume today's two.

**Every transition carries the state it believed it was leaving.**
First writer wins. A second writer's command whose `from` no longer
matches the ticket's actual state is **rejected, not applied**, and
the rejection names who moved it and to what — so the loser retries
against the new state or goes and talks to the winner. Commanded's
`expected_version` is the mechanism and the aggregate is the arbiter;
this is the same primitive the mutex uses against agents, so
human-vs-agent and human-vs-human races resolve through one path
rather than two.

**The synchronous rejection is not achievable through Linear, and
that is a property of the tracker, not of this design.** Two humans
both moving a ticket in Linear both succeed there — Linear applies
last-write-wins and tells nobody — and the plane sees the result
afterwards, by webhook or sweep. The loser is therefore reverted
after the fact with a comment (§7.1's validate-or-revert, already the
designed behavior) rather than stopped at the point of action. "Pop
an error and make them try again" requires a surface the plane
controls. Recorded here because it is a standing force on §7.17's
tracker question, and because the degradation must be understood as
chosen rather than discovered.

**Approval is a status, and review states are declared** (shape
settled; the mechanism is a later increment, and a sizeable one).
There is no separate approval object: a human approves by moving the
ticket, and the state it lands in *is* the record. This is why the
one-approves-one-rejects case needs no resolution rule — the ticket
is in exactly one place at all times, the first mover wins under the
rule above, and the second is told who moved it and where, then moves
it again from the new state. The disagreement becomes a conversation
instead of a data structure. Attribution is not lost to the coarse
projection: the tracker shows only a status, but the plane records
the command with its actor, so *who approved* stays answerable from
the log.

**The shape, stated as the rule it implies: we fix the shape of the
automation, not the shape of the organization.** The agent and queue
states are platform-fixed. **Review states are declared**, vary by
ticket type, and the default set is a UX review and an engineering
review, either of which may throw back to design.

The admission rule is narrow, and stated as one: **a state may be
declared iff no plane logic branches on it.** What "platform-fixed"
protects is that prompts, plane logic and shared vocabulary are all
written against the states, and that holds for states the automation
reads. It does not hold for a state whose only job is routing a
human: nothing dispatches from it and no prompt is written against
it. `docs/non-goals.md` records the rule in that form.

Mechanically the plane never learns a new state. A gate sits on an
*edge* of the fixed graph: the plane parks there and resumes on a
resolution drawn from a fixed vocabulary (proceed, or throw back to
the gate's declared target). Gate identity is data; gate resolution
is the fixed thing the plane branches on. This is §6's doctrine
applied to the delivery protocol — declarations configure fixed
semantics, and a gate declaration is not a program.

**A gate declares three things, each closing a failure:** the role it
routes to (§2.9 holds the grants; a gate whose role has no holders is
a deadlock that must fail at configuration time, not look like a slow
reviewer); its exits, forward and throwback; and its escalation
policy, since §7.6 already shows states carrying distinct escalation
semantics and a human gate is author-owned.

**Two failure classes grow with a declared set and must be closed at
configuration time.** A declared gate with no corresponding tracker
state is the unmapped-state halt (§7.17's evidence list) — the plane
provisions its own states and validates the mapping at boot and in
the audit, turning a silent runtime halt into a loud misconfiguration.
And §7.6's naming discipline — no two states, or a state and a label,
one hyphen apart in meaning — was cheap to hold against a fixed list
and is not against a declared one, so it becomes an audit check.

**Still open within this section:**

- **The compare token: version, not status.** Status alone cannot
  tell two writers apart who both moved `A → B`, and it readmits the
  ABA case — a ticket that returns to `A` accepts a stale command
  aimed at the first `A`. The compare should be the aggregate's
  version while the *message* speaks in states, because the version
  is what is correct and the state is what the human needs to hear.
  Author's call: the rule as stated compares on status.
- **Staleness clocks under more writers.** `staleClaimGrace` measures
  from `max(Run.EndedAt, StateSince)`, so every state move resets it.
  More writers means more resets, and the constant (§7.13) was chosen
  against a single-writer rate.

**What a passed gate pins — resolved (ORC-115).** A chain-axis review
tier is not the object in question: `reviews: <tier>` is 1:1 with the
tier it reviews and its staleness already falls out of §7.11, but this
item names the declared *workflow* gate this section itself defines
above
("Approval is a status, and review states are declared"). §7.19
draws exactly this line: a throwback reopening "the two approvals
before it" names workflow gates, and separately exempts a review
*tier* by name — "It therefore has no throwback semantics: there is
no passed gate downstream of it to reopen" — and a review tier
declares no committed artifact, so there is nothing for the
derivation to anchor on regardless. What the ORC-6 pass actually
found, correctly, is not the answer to this item but a reason it
never engages with a different object: a review tier needs no
staleness treatment at all. `systems/engine.md` records that
finding. This item is open again, unchanged:

A gate approves a version of an artifact; the ticket
then moves past it. When the artifact regenerates underneath, the
ticket is already downstream and the judgment it carries is stale
while nothing says so. §7.11's staleness-is-derived machinery is
the natural home — a passed gate goes stale when what it approved
does, and reopens — but the gate has to record what it approved for
that to be derivable at all. A direction, not a decision: the plane
already logs the transition command with its actor (this section,
above), so an approval event carries a sequence and the node it
approved has a latest-commit sequence — "did what this gate
approved change" may be answerable as a log join rather than a
stored field. Whether that holds is a workflow-gate design
question, for whenever gates are declared (`systems/delivery.md`'s
Phase 7), not this ticket's to settle.

**Resolved (ORC-115).** `dsl-syntax.md` §15.10's sub-array grouping
gives a gate the structural referent this item was missing: a gate's
citing sub-array holds exactly one non-critique agent-balled entry,
by its own load-time check, so what the gate approves is that
entry's own committed content, read at the gate's declared `depth:`
— the same node set `critique`'s own depth already selects among
when a critique entry shares the group. The direction left open
above — a log join rather than a stored field — is confirmed rather
than merely plausible: the join is against a structurally derived
node, never a value the loader or the plane has to remember on the
gate's own behalf, so "did what this gate approved change" reduces
to §7.11's ordinary staleness-is-derived question, asked of the
pinned node instead of an implied one. Building the join itself —
reading the pinned node's latest-commit sequence against the gate's
own approval-event sequence — is still `systems/delivery.md`'s Phase
7, alongside the rest of declared workflow gates; this pass gives
that future build an object to pin against, where the ORC-6 pass
correctly found there wasn't one.

### 7.17 The tracker is ours; the host is an adapter

**Reversed, deliberately, and it is the largest change to the record
since §1.2's inversion.** An earlier draft of this section had the
tracker as a port with Linear the only adapter and a native tracker
deferred. That is inverted: **every user gets Catapult's own ticket
UI, and external trackers become an add-on.** The reason is the one
§7.16 exposed — a protocol this specific fights a general-purpose
tracker at every step. Declared review states must be provisioned
into someone else's product and mapped, an unmapped one halts the
sweep, the tracker applies last-write-wins where the protocol needs
compare-and-swap, it cannot say who wrote a change, and the
rejection §7.16 specifies cannot be delivered at the point of action.
Each is survivable; together they are a permanent tax on the
protocol's own semantics.

**What the add-on is: an outbound projection, and one grain only.**
Events duplicate out to the customer's tracker of choice (Jira,
Linear, Notion) for teams inside a larger org that must report
somewhere central. **Only top-level tickets mirror** — the fan-out
(§7.2's ticket tree) stays native, which is the descoping this buys
and is most of why the add-on is cheap. Mirroring a projection
outward is safe by construction: it is a read model leaving the
building, and §7.1 already says the log is the authority.

**Inbound is the dangerous direction and is not committed.** Accepting
events *from* a mirrored tracker reintroduces every problem above —
unmapped states, last-write-wins, unattributable writes — inside a
system that just escaped them. If it happens it is a narrow, explicit
command surface (comments, at most a bounded set of transitions),
never a general write path, and every inbound event is a §7.1 signal
validated like any other rather than a state change to be adopted.

**Two things follow that were not obvious before the reversal.** The
review surface partly comes home: our docs diff better per sentence
than per line, and a graph view of the tickets under a top-level
ticket is something a general tracker cannot easily replicate — both
are reasons the native UI is not merely a substitute but the better
surface for this content. And the UI stops being a debugging
dashboard and becomes a working surface, which reverses a second
non-goal; how far it extends is what the UI spec has to settle, not
this section.

**The host stays a port with swappable adapters**, GitHub the only
one built, for the reasons the rest of this section gives. The
asymmetry is the point: ticket state is a projection the plane
already computes, so owning it removes machinery; code hosting and CI
are services the plane is architecturally forbidden to be
(`docs/non-goals.md`: never executes target-project code), so a forge
is always somebody else's, and the port is how that stays cheap.

**Three disciplines, without which the port is nominal:**

1. **Ports are shaped by what the protocol needs, never by what the
   vendor offers.** A `Host` that grows a method because GitHub has
   the feature is a GitHub-shaped port with an adapter-shaped hole in
   it. This is the easy thing to get wrong while exactly one adapter
   exists — and it applies to the mirror add-on too, whose port is
   "publish a top-level ticket's state somewhere", not Jira's issue
   model.
2. **The fake is the second implementation.** `systems/delivery.md`
   already ships a fake with every port; the reason is not only the
   offline test ring — it is the forcing function that keeps the port
   vendor-neutral, and it only works if the fake is written against
   the protocol rather than mirroring the adapter.
3. **No capability negotiation until a second adapter demands it.**
   Degradation frameworks for backends that do not exist are the
   speculative machinery `docs/non-goals.md` rejects elsewhere.

**The forge is two seams, decided separately.** The `Host` port (PRs,
merges, file writes, ancestry) and the execution substrate (§7.12.1's
dispatch port, already committed as an adapter) are different
questions, and a forge swap needs both. Keeping them distinct means
the CI-substrate work, which is planned, does not entangle with a
forge swap, which is not. The one genuinely hard piece is
runner↔plane authentication: §7.12.1 settled it on GitHub-minted
Actions OIDC, which is a good design and a GitHub-specific one.

**The evidence the reversal rests on**, recorded so the decision
reads as accumulation rather than as a bad afternoon: the pipeline
already needs an external state store because the tracker cannot say
*who* wrote a change; protocol state already rides in tracker
comments behind markers; an unmapped tracker state has halted a sweep
for hours; tracker comment ordering has silently contradicted its own
API contract; and §7.16's declared review states would have to be
provisioned and mapped into a product that does not know what they
mean. No single one of these decides it. The shape of the list does —
every entry is the same shape, a general tracker refusing a specific
protocol, and that is a tax that grows with the protocol rather than
one that gets paid off.

**There is no cutover, and no tracker adapter is ever written.** The
reversal landed before any tracker integration existed, so the plane
never acquires one and nothing has to be migrated off. Worth stating
plainly because the opposite reading is the natural one: **Catapult
the platform does not talk to Linear at all.** Orchestration builds
Catapult and orchestration uses Linear — a different system running a
different loop, unaffected by any of this and not a dependency of it.

**What this costs, recorded honestly.** A working tracker is a real
product surface: search, notifications, permissions, and mobile —
and mobile matters more than its line here suggests, because the
author works from a phone and the incumbent's app is good. And the
cost lands *earlier* than a staged reading suggests: with no borrowed
surface to lean on, **UI v1 is the authoring loop's floor rather than
a later stage** (`docs/ui-spec.md` §5). Nothing renders the loop
until it exists. That is the honest shape of the bill — the reversal
does not defer the UI, it makes it a prerequisite.

### 7.18 Configurable deployments, and where configurability lives

**Deployment environments are declared, on the same rule as §7.16's
review states.** The default set is `dev` and `staging`; per-PR
environments are a later addition and, when they land, are `deploy`
at fan-out depth `0` (§7.19) rather than a special case — the fan-out
would otherwise mint an environment per child, which is the cost that
makes per-PR previews expensive everywhere they are expensive.
Promotion between environments is automation and stays
platform-fixed; *which* environments exist, and what a promotion into
one requires, is the organization's shape, not the automation's.

**There is no second bundle system, and adding one would contradict
§9.** The instinct to give delivery configuration its own bundle
mechanism parallel to the prompt bundles is the thing §9 already
refused: one DSL, core plus extensions. The existing split does the
whole job, and the two halves are already named in `dsl-syntax.md`:

- **Vocabulary is an extension** (`dsl-syntax.md` §12) —
  platform-shipped modules registering annotation namespaces,
  declaration kinds, and enforcement profiles. A gate kind and an
  environment kind are new declaration kinds registered exactly this
  way. Extensions compose the *language*.
- **Instances are content** (`dsl-syntax.md` §11) — a project's
  actual gates and environments are versioned in the repo, changed by
  PR — **not via an `extends:` layer.** The chain axis's
  `platform-elixir` base has no workflow-axis counterpart; §7.8 and
  `dsl-syntax.md` §11 record why the analogy does not survive contact
  with how bundles actually distribute
  (fork-tailor-merge, §3.1) and the consequence: a workflow bundle now
  carries no `extends:` field at all. The content is still repo
  content, versioned, changed by PR — only the mechanism that gets it
  there changed, from a load-time layer to a forked bundle.

**The store test (§7.10) splits each feature in the same place, and
the split is not where intuition puts it.** *Topology is content;
attachment is a binding.* Which gates exist, which roles they route
to, their exits, which environments exist and what promotion into one
requires — all change what is generated, validated or enforced, so
they are graph state: repo, versioned, staleness-propagating, PR to
change. Who currently holds a reviewer role, and an environment's
endpoint URL and credentials — these change only how the plane
connects and operates, so they are plane state in the bindings, and
they must never become repo content. The tempting error runs in both
directions: an endpoint in the bundle breaks the hosted BYO rule
(§8's constraint 1), and a gate in the bindings puts a generation
input outside version control, which §7.10's test exists to prevent.

**The decomposition and the workflow are separately importable, and
this is load-bearing rather than a convenience.** A project imports
two bundles: a **chain bundle** (the doc graph — tiers, edges, flows,
prompts, schemas: what the agents do) and a **workflow bundle** (the
human cycle — gates, review states, environments). The driving case
is an organization whose two projects need different decompositions
under one shared workflow, and it gets more common with each language
binding: decomposition tracks the target stack, while review and
deployment track the organization. Welding them into one artifact
forces a fork of the workflow per stack, which is the failure this
split exists to prevent.

**One language, two documents.** This is not a second bundle system
(§9 again): same loader, same validation pass. **`extends:` semantics
diverge by axis as of ORC-105's fourth pass** — the chain axis keeps
them unchanged; the workflow axis has no `extends:` at all, forked
instead (below). `catapult.yaml` names one of each instead of one
bundle, and a bundle manifest declares its `kind`. The declaration
kinds a workflow bundle contains are registered exactly like any other
(`dsl-syntax.md` §12).

**The invariant that makes the split real: neither axis references
the other. Both reference only the platform's fixed vocabulary —
statuses, queues, and agent steps.** A chain says which agent step
generates a tier and which status shows while it does. A workflow
says how its own steps relate to those same fixed positions: this
gate sits after that agent step, this environment is promoted into at
that status. Neither names anything the other declares.

The consequence is the strong form of what the split was reaching
for: **any workflow bundle composes with any chain bundle**, with no
shared gate or environment vocabulary and no compatibility contract
between them. An earlier draft of this section had tiers naming their
gate, which made the workflow's gate names a published interface and
the pairing a thing to check. That was a weaker design for a worse
reason — it kept a coupling that buys nothing, since a gate does not
need to know which tier it is reviewing to review it.

**The review set is derived from position, not from naming.** A gate
placed after a fixed step reviews whatever the chain produced at that
step — one tier or six, and the gate is unchanged either way. This
replaces §7.10's earlier derivation ("a gate's review set is the
tiers declaring it") with the same principle keyed differently, and
it is what lets a decomposition grow a tier without any workflow
noticing.

**The cost, stated plainly: review granularity is bounded by the
fixed vocabulary.** If two tiers generate at the same step, no
workflow can gate them separately — the knob is the platform's phase
set, not the project's. That is the intended trade and it is the same
sentence as §7.16's rule: we fix the shape of the automation, not the
shape of the organization. Finer granularity is a *platform* change,
reviewed as one, which is exactly where the design wants that
decision to sit. It also means the fixed vocabulary has to be rich
enough to carry the gates people actually want — §7.6's lifecycle
already separates product-tier from architecture-tier generation,
which is what makes the two default gates expressible without any
project-specific reference.

**A near miss worth recording, because it looks like a leak and is
not:** comparch's `enforcement:` block names profiles like
`codegen: restricted`, which bind delivery gates. Those profiles are
platform-shipped (`dsl-syntax.md` §12), so the chain is naming fixed
vocabulary there too, not a workflow bundle's declaration. The rule
holds; the resemblance is what makes it worth a sentence.

**`extends:` layers within an axis and never across it** — a chain
extending a workflow, or the reverse, is a load error. Shipping the
delivery DSL from the `platform-elixir` layer would tie the workflow
vocabulary to one language binding, which is the weld this section
breaks. Narrowed further below: the workflow axis has no `extends:` at
all. Delivery shipped
from a platform *workflow* layer, which was also where the default
gates (a UX review and an engineering review) and the default
environments (`dev`, `staging`) lived.

**There is no platform *workflow* layer, and the workflow axis has
no `extends:` at all** (§7.8). A base layer here would rest purely on
analogy with the chain axis's `platform-elixir` layer, and the analogy
does not hold: v5 §3.1 already chose fork-tailor-merge as how bundles
and policy packs are distributed, because git has a merge story hex
does not, and a workflow bundle is exactly this shape — never
composed from two files by a loader at runtime. `bundles/`'s default
gates and environments are a **template** a project's workflow bundle
forks from and tailors, pulling later platform revisions in by
ordinary git merge. What survives unchanged: delivery still shares no
vocabulary with any one language binding, and the default gates and
environments are still where a fresh project's workflow bundle starts
from — only the mechanism that gets them there changed, from a
runtime layer to a fork (`dsl-syntax.md` §11 carries the load-time
consequence).

**A consequence worth keeping straight: the `runtime` dialect loads
no workflow bundle at all.** §12 defines it as having no review
lifecycle and no git bodies, so a workflow bundle there is not merely
unused but incoherent, and the loader should say so rather than
accept it.

**Two recorded absences have to narrow to admit this**, the same
narrowing `docs/non-goals.md` took at §7.16 and for the same reason:
`dsl-syntax.md` §11's "the protocol's own files never override" and
§14's "per-project protocol restructuring, deliberately absent". Both
were written when every state was platform-fixed. What they protect —
that no project rewires the automation graph — is untouched: a
declared gate or environment adds a node the plane parks at, and the
plane still branches only on a fixed resolution vocabulary. What
narrows is the claim that *nothing* in the protocol is declarable.
Load-time validation (§13) is where this is enforced, and it grows
the checks §7.16 named: a gate whose role has no holders, a declared
state with no counterpart in the mirror mapping, and §7.6's
one-hyphen-apart naming rule over the declared set.

### 7.19 System statuses, review sequences, and fan-out depth

**The fixed vocabulary is the set of *system statuses*** — `pending`
(renamed from `queue` at ORC-105's fourth pass, once a container's own
queue positions joined the same vocabulary — `dsl-syntax.md` §15.1),
generation, checks, merge, deploy. These are the platform's, they are
what both bundle axes reference (§7.18), and they are the anchors
everything else positions against. The earlier framing of "between
generation steps" was too narrow: a security review before merge and
an approval before a staging deploy are both obviously wanted and
neither sits between generations.

**A workflow bundle declares an arbitrary sequence of review statuses
on any edge between system statuses.** The default workflow ships a
product review between the product and architecture generations; an
organization is free to insert a UX review and a security review
beside it, or before merge, without the chain knowing. §7.6's
existing feature lifecycle is the degenerate case of this model with
every sequence length pinned at one, which is a good sign the shape
is right rather than novel.

**Queue statuses are required before every generation and every
deployment**, and that is a load-time check rather than a convention.

**Sequential only, deliberately.** A ticket has one status and one
assignee at a time, which is how essentially every tracker in common
use behaves — and comprehensibility is the reason, not a limitation
we are accepting. Users of this system already face a large amount of
novel UI; swim lanes with single assignees are a UX win even when
they cost review latency. Parallel review is a real want and is
**deferred, not refused**: the intended shape is a togglable
*parallelize sequential review* setting that takes review steps which
would run serially on one edge and runs them together. Worth noting
why the order of these two matters — a sequential model can be
relaxed into a parallel one later, while a parallel spec cannot be
serialized without losing information. Sequential-first is what keeps
the option open.

**Throwback reopens everything downstream of the regeneration.** The
happy path is a straight line and the sad paths are simple loops. A
throwback from the third review on an edge re-runs the generation,
and the two approvals before it approved a version that no longer
exists, so they reopen. The all-reopen rule is only affordable
because staleness is derived rather than eagerly reset (§7.11): a
passed review goes stale when what it approved changes, so a
regeneration that touched nothing it saw costs nothing to re-pass.
This is what turns §7.16's open item — *what a passed gate pins* —
from a loose end into a dependency: without the pin there is no
derivation, and all-reopen degrades into re-reviewing everything by
hand every time.

**Structural as of ORC-115, not merely affordable.** The paragraph
above was written as a description of intended behavior with no
mechanism enforcing it: "downstream of the regeneration" named a
region of the array by prose, not by anything a loader or a dispatcher
computed. `dsl-syntax.md` §15.10's sub-array grouping gives it one —
a throwback's default fallback is its citing sub-array's own earliest
entry, its own leading `pending` for a generation-shaped group (§13's
tightened check, a fourth-pass correction from resolving straight to
the agent step), so "everything downstream of the regeneration" *is*
"everything in this sub-array," derived from the same structure that
already answers §7.16's open item above.
The derivation supplies the sub-array's own default landing point, and
`throwback:` (below) survives beside it as a single, explicit override
for the gate that wants a different one — never a second, narrower
*legality* rule (§4.5's escape-hatch discipline): the "earlier in the
effective sequence" test below is the only bound on what a decline may
target, declared or not.

**Blocked stays a single system status** (§7.6's decision, revisited
under declarable statuses and upheld), with flavor labels for the
reason dimension. It is itself a system status, not a review status:
the automation kicks tickets into it, so it belongs to the fixed
vocabulary.

**The origin status is tracked beside it, and needs no new
mechanism.** §7.6 already requires every Blocked entry to name its
origin, and already observes that in Catapult the event log holds
this natively — `from` is a projection, not bookkeeping. What
changes with the native UI (§7.17) is that the projection is *read*
rather than stamped onto a comment: §7.6 stamped it because "the
author reads Linear, not the log", and owning the surface retires
that workaround. Swim lanes group blocked tickets under the status
that kicked them over.

**Returning from Blocked is one rule: the origin status, or any
earlier status in this ticket's effective sequence. Never forward.**
Forward would skip steps that later stages depend on — a required
review before deployment, a `pending` before generation — so it is
refused rather than discouraged. Landing on a status that has a
`pending` before it puts the ticket there, not directly into
generation.

**"Earlier" is well-defined only because review is sequential
(§7.19's own decision).** A ticket's effective sequence at its
fan-out level is a total order, so "earlier" is a prefix — computable
and directly renderable. Under parallel branches it would be a
partial order and this rule would be ambiguous exactly when someone
needed it.

**No routing rules are declared, because the default carries the
load.** The return defaults to the origin status — one action,
covering nearly every unblock — with the earlier-prefix offered as a
picker behind it. Per-pair routing hints (blocked label × source
status) were the reason multiple blocked statuses looked attractive;
with origin tracked and the prefix computable, the matrix has nothing
left to say and is not introduced.

**Backward movement is one rule with two entry points.** A throwback
from a review and an unblock to an earlier status are the same
movement; both reopen everything downstream, and §7.11's derived
staleness makes the re-pass free where nothing a review saw actually
changed. Specifying them separately would let an unblock leave a
stale approval standing downstream.

**Corrected on a second design review: the equivalence is about target
legality too, not reopen scope alone.** The paragraph above still
states what it always stated — both reopen everything downstream —
but the claim that a declared gate `throwback:` stays a *bounded
allow-list, distinct from* this section's rule rested on a
shipped-enforcement claim that does not hold: `Catapult.Engine
.Aggregate`'s `DeclineGate` clause enforces no such membership check
against a gate's declared list — that validation is the command
edge's, and the command edge does not exist yet (`dsl-syntax.md`
§15.10 records the correction in full). A gate's decline and a
Blocked-return are the same movement on both counts now: reopen scope,
from this section, and target legality — any earlier status in the
ticket's effective sequence, never narrower — from the same "earlier"
prefix this section already defines two paragraphs above.
**Third design review: `throwback:` survives the correction above, and
narrows.** A declared list has no remaining role once legality is
unbounded — naming several targets said "any of these is legal," which
is exactly the bound just retired. But a landing point is a different
fact from a legal-target set, and it survives: `throwback:`
(`dsl-syntax.md` §15.4) narrows to a single, optional status, the
explicit override a gate declares when its citing sub-array's own
earliest entry — the derived default, above — is not the one-click
landing point it wants. Blocked-return has no equivalent override; its
one-click action is always the tracked origin, because nothing groups
it into a sub-array the way a gate's decline is grouped.

**The escape valve for a genuinely unwanted step stays heavy on
purpose.** Deciding a parked ticket does not need its security review
means changing the workflow bundle, which is graph state, which is a
PR. Skipping a required review is not a one-click operation, and if
an override is ever warranted it is an explicit labeled exception
recorded as an event (the shape `codegen: restricted`'s override
label already uses), never a softening of the routing rule.

**A workflow bundle can change while a ticket sits blocked, and §6's
drain does not cover it.** §6 requires a destructive bundle change to
be a cutover whose first act is that *the pipeline drains — no
in-flight flow instances*. That rule was written when there was one
bundle. It is satisfiable on the chain axis, where flow instances
complete; it is **not reliably satisfiable on the workflow axis**,
because a blocked ticket is in-flight and blocked tickets are
long-lived by definition — a `needs-setup` block waits on a human
creating an account, for as long as that takes. Requiring a fully
empty pipeline before any workflow change would make workflow
evolution hostage to the slowest human in the organization.

**So blocked tickets survive the cutover, and the system statuses are
what they survive on.** When a ticket's recorded status no longer
exists in the new bundle, it resolves to (a) the most recent status
it held that still exists, failing that (b) **the status after the
most recent system status it reached**. (b) always terminates: system
statuses are platform-fixed, so they are exactly the part of a
ticket's history that no bundle change can delete. The fixed
vocabulary earns a second job here — it is the anchor set that makes
re-derivation total rather than best-effort, and it is only able to
be that because it is not declarable.

Two properties worth stating, because they are what make this safe:
(b) can never place a ticket past a system status it has not reached,
so §7.19's no-skipping-forward invariant survives the migration
intact; and a ticket landing on a newly declared review status it
never saw is correct rather than a defect — the new workflow says
that review is required, and the ticket has not had it.

**This requires the active-bundle flip to be an event, on both axes.**
§7.10 already records binding changes as event-sourced; the bundle
flip is stated in §6 as act (4) of the cutover but not explicitly as
a recorded event, and it now has to be, because rule (a) above is a
join between a ticket's status history and the bundle-version
timeline. Neither half is answerable without the other in the log.
This is §7.1's doctrine applied to our own configuration: the world
is observed into the log, and a graph the engine switched to is an
observation like any other.

**Every generation status must have at least one blocked exit** — a
load-time check, since a generation that can fail with nowhere to
land is the parked-ticket-nobody-can-act-on failure §7.6 names.

**Scope is expressed as fan-out depth, which is how a status narrows
without naming a tier.** A status carries an optional depth: omitted
or `0` means the top level only; `1` adds components; `2` adds
subcomponents. The simplifying assumption is that **validation wanted
at a nested level is also wanted at every level above it**, which is
what lets depth be one number instead of a set of levels. If that
ever fails, depth generalizes to a level set compatibly.

Worked example — `checks` (2) → `code review` (1) → `merge` (2)
→ `deploy` (0): subcomponents get checks and then merge to their
component branch; components get checks and code review before merge;
the top level gets checks and code review before merge, with
deployment after. **The effective sequence at any level is the
declared sequence filtered by depth, order preserved**, which is what
makes one declaration describe every level at once.

**Depth is a maximum, never a requirement — and this is what keeps
portability intact.** Bundles choose how far they fan out;
component/subcomponent is the sweet spot and the default chain's
shape, but nothing hard-codes it. So a workflow declaring depth `2`
against a chain that fans out once applies at the two levels that
exist, silently. It must *not* be a load error: erroring would make
the workflow's depth a claim about the chain's decomposition, which
is precisely the cross-axis coupling §7.18 removed. Depth is a number
rather than a name, which is the whole reason it can scope without
coupling.

**One special case disappears into this.** §7.18 said per-PR
environments would attach to top-level tickets only. That is not a
special case; it is `deploy` at depth `0`, and it stops needing its
own rule.

**The chain's own auto-review had nowhere to run — `critique`.** v4's
siege bundle paired every LLM tier's generation prompt with a review
prompt (`review_comparch.md` and its siblings), and the whole reason
the per-tier triad invariant is worded as "generation and review
receive identical context plus `draft`" is that both runs read the
same graph. `delivery:` gives a tier exactly one `phase:` and one
`agent_step:`, so a tier that both generates and is reviewed needs
somewhere for the second run's own schedule position to live. The v5
workflow design missed the use case outright — the review sequence
was designed for *human* gates declared on the workflow axis, and an
agent critiquing a draft is neither a human gate nor a generation.

**`validating`/`validate` is not its home**, though the names invite
it. That status is post-deploy verification with the ball on the
plane, and that step is §7.11's repair loop; both sit after `deploy`.
A tier's auto-review reads a freshly produced design artifact. Same
word, opposite end of the lifecycle, different subject — folding them
together would conflate "did the shipped thing work" with "is this
draft any good."

**Resolution, revised: a review is a tier, not a nested block on the
tier it reviews.** `critique` is an ordinary system status — the
agent step a review tier's own `delivery:` names, exactly as
`generation` is the status a generation tier's `delivery:` names.
There is no `review:` sub-block anywhere and nothing materializes
positionally: a review tier is declared, scheduled and dispatched the
same way as any other tier, because it is one.

This supersedes an earlier version of this entry, which kept the
nested `review: {prompt, grammar, required:}` block and had the
platform wrap every generation step as `queue → generation →
⟨critique⟩`, materializing the critique slot only when a tier declared
one. That wrapper existed solely to compensate for review not being a
tier — a generation tier declares its prompt, grammar, **context** and
a status; the nested block declared a prompt and grammar with **no
context of its own and no status**. Making review a tier deletes the
asymmetry along with the machinery built to paper over it, and buys a
second thing along the way: **the triad invariant becomes checkable.**
"Generation and review receive identical context plus `draft`" was a
runtime discipline living in a shared assembly path; a review tier now
declares its own `context:`, so the loader can verify it against the
reviewed tier's walk at load time instead of trusting the assembly
code to keep them in step forever.

Two things this does *not* rest on, because they were already true
and are not the reason for the change: per-tier review prompts
(`prompts/review/comparch.md.liquid` was already declared per tier)
and chain-side ownership of the review declaration. Both survive the
tier-ification unchanged.

**This does not leak across the axis.** A chain may declare a review
tier that the active workflow never runs — a workflow disabling the
critique slot after a given generation status is how a workflow turns
review off, and that is the right direction of decoupling. But the
match is on **platform-fixed vocabulary only**: "no `critique` after
`generation`" is a legal workflow declaration, and naming a review
tier — `comparch_review` — from the workflow side is the cross-axis
leak §7.18 exists to prevent, precisely as a chain may never name a
workflow's gate. It is symmetric with `pending`, which is likewise a
platform-fixed position nobody's content declares by name.

**It is a second dispatched run, and it reads committed state.** Not
a phase inside the generation run: a critique whose output lived only
in an agent transcript would be invisible to the plane, so nothing
could show it, act on it, or count it. It runs against the current
state of the ticket's PR. The cost is honest — a tier that pairs with
a review tier doubles its dispatches, which is a real draw on
§7.12.1's per-instance concurrency cap.

**Its output is comments, not a committed artifact — a deliberate
break from v4, and this is the thing tier-ification puts most at
risk.** Every other tier has a `draft:` and commits a body; the v4
bundles commit `review.md` beside `body.md` and give tier declarations
a `review_path:` next to `body_path:`. v5 does not port that, and
making review an ordinary tier does not reopen it: a review tier
declares prompt, grammar, context and scope **without** a `draft:` and
without a committed artifact. Do not infer one because every sibling
tier has one. A critique decline should be structurally identical to a
human decline, so that regeneration feedback has **one** mechanism
rather than two: §7.4's decline harvesting already buckets review
comments by artifact span and threads them as regen feedback, and the
critique agent's findings are the same shape arriving from a different
author. Two paths into regeneration would drift. **`review_path:`
stays retired** — a fourth v4→v5 delta beyond the three
`seed-docs/README.md` enumerates, and one a faithful port would
otherwise reproduce correctly and wrongly.

**The review grammar survives the move unchanged; only the storage
changes, and nothing about tier-ification trims it.** The run's output
is still validated against the platform-wide review grammar at the
commit path — it is projected into comments rather than written to a
file. Two of its fields stay load-bearing rather than decorative:
`<score>` (0-100, v4's buckets: 0-30 fundamental rework, 31-60
structural, 61-85 minor, 86-100 ready) is what a threshold predicate
reads, and each `<finding id="...">` is what becomes one anchored
comment. The score lands in the log with the run's result event, which
is where a threshold or a cycle count is answerable from.

**Position and loop.** A review tier is dispatched immediately after
the generation tier it reviews and before every workflow gate
downstream of that generation status, so the default shape is one
generation → critique → generation cycle before a human sees anything.
It therefore has **no throwback semantics**: there is no passed gate
downstream of it to reopen, and this section's all-reopen rule never
engages. A review tier currently carries no gating flag of its own —
its verdict is recorded and available to a downstream predicate, but
nothing yet stops the chain from proceeding on a low score; that is
the threshold-passing item below, not something this entry's removal
of `required:` quietly drops.

**Wanted later, not now: threshold passing.** A draft leaves
`critique` on a score bar or after a bounded number of cycles rather
than after exactly one pass. The grammar already carries the field
this needs, so it is a scheduler decision rather than a content one.

Scheduling — where `critique` sits in the dispatch machinery and how a
cycle terminates — lands with the workflow-bundle work, not with the
chain port. The port only has to carry the review tiers themselves
(prompt, grammar, context, `delivery: {phase: critique, agent_step:
critique}`) and the platform-wide review grammar, both of which it
already does.

**Revised (ORC-92): depth generalizes to a pair, and gains a
declaration form for a system status.** Two gaps stood before this
ticket. `depth:` accepted only a bare integer — one ceiling, no way
to say "the project's first pass through this status wants more
scrutiny than every later one." And `depth:` itself existed on a
gate and an environment (§15.4), both declarable, while
`critique` is a system status (§15.1), declarable by neither axis —
so "disable the critique slot" was asserted twice in this repo's own
prose (this section, and `dsl-syntax.md` §3.3) and declarable
nowhere. Both close together, and one leans on the other: a
declaration form for `critique`'s own participation is only worth
building because the depth it carries can now say more than one
number.

**Depth may now be a pair, `[first, rest]`.** Scaffolding a project
from its seed has no reviewed prior graph to trust, so that pass
wants its fan-out reviewed in full; every later pass runs against a
graph a human, or the auto-reviewer, has already read once and
returns to the top level. "First" names **the project's first
traversal of the status a depth is attached to** — not the first
time a given ticket visits it, and not the pass right after a
throwback sends the status back for a repeat visit; both of those are
ordinary later traversals of a status the project has already been
through once. A bare integer still means both positions at once, so
no declaration that predates this pair form changes meaning. The
selector is positional — first/rest by position in the pair, never a
name — because naming one would put a chain-side concept (which flow,
which cascade) into a workflow-side declaration, exactly the
cross-axis coupling §7.18 exists to prevent; depth already scopes
without naming a tier for the identical reason, and a named position
would undo that for the one case that needs it least.

**`critique` is an entry in a type's own array, not a file**
(`dsl-syntax.md` §15.5): a `critique` entry, immediately following a
`generation` entry in a `ticket`-skeleton type's own `statuses:`
array, carrying the same `depth:` grammar the file used to. What moved
is only the file: the same fixed-vocabulary kind (`critique`, §15.1)
is still configured rather than declared, and the reasoning below
survives unchanged because it was never about the file, only about
what presence means.

**Settled: critique is opt-in, not on-by-default — a conclusion the
retirement above doesn't touch.** Both readings were defensible from
this section's own words — "a workflow disabling the critique slot"
reads as present-by-default — but the mechanism decides it once
stated plainly. As first argued here, that mechanism was `extends:`
composing by union and same-path replacement, with nothing that
expresses "the layer below declared this; unmake it." The workflow
axis no longer has `extends:` at all (§7.8, §7.18), but the same shape
of argument holds one level down: a type's own `statuses:` array has
no "the type below named this; unmake it" primitive either, only
presence or absence of a `critique` entry next to a given `generation`
entry. A default-on critique could only be turned off by a declaration
whose entire content is a negative, a shape this DSL has nowhere else,
whichever layer or level the declaration lives at. Default-off costs
nothing equivalent: turning critique on is an ordinary addition,
exactly the shape a gate or an environment already takes, and it never
needs to un-declare anything. Consequence, stated because it is not
free: `bundles/default-flow` declares no `critique` entries today, so
the day this form ships, the default chain's eight review tiers stop
being merely unscheduled (true since the tier-ification decision
above) and start being a workflow that has been asked, plainly,
whether it wants them, and has not yet answered. Answering that is
bundle content, not this decision; `systems/platform_content.md`
carries the recommendation for the implementing pass.

**A gate's depth 0 is the rule, not merely its default.** A gate is a
human sign-off, and a human reads the top level; reasoning about how
far a chain fans out to set a gate's depth is arguing the
auto-reviewer's case inside the human reviewer's own declaration.
`bundles/default-flow/gates/engineering-review.yaml` currently
declares `depth: 2`, justified in its own comment by the chain's
fan-out — exactly that misplaced argument, and wrong for it;
`systems/platform_content.md` carries the fix as a decision for the
implementing pass. Fan-out reasoning belongs to `critique.yaml`'s own
depth instead, which is the whole reason it exists as a separate
declaration rather than a new field bolted onto a gate.

**Sequencing, stated so nobody lands half of it.**
`Catapult.Dsl.Gate.parse_depth/2` (and `Catapult.Dsl.Environment`'s
own copy) accept a scalar today and reject a list — the grammar
change, the loader change and the shipped bundle content that uses
the pair form move in one change, because updating content ahead of
the parser fails every bundle load, including the reference
deployment's. `depth:` is not read by anything today, on a gate, an
environment or a `critique` entry, so — as before this ticket — there
is no scheduling consumer to migrate; the window stays free until one
exists. (`ticket_types:` and `after:`, both a gate's own fields at the
time this paragraph was written, are retired outright at ORC-105 —
§7.8 above and `dsl-syntax.md` §15.3 respectively — so neither applies
to it at all anymore, rather than merely applying to an unread one.)

**A second review status category, `reconcile`, joins `critique` as
review-shaped — ORC-151, design pass.** `dsl-syntax.md` §15.1's fixed
table has always had a fact missing: what an entry *does to the
artifact*, as opposed to who holds the ball while at it. Every kind is
either
**generation-shaped** (`generation`, `design`, `architecture`) —
originates an artifact — or **review-shaped** (`critique`,
`reconcile`) — judges one that already exists. `reconcile` names what
§7.5 above has always described as reading a produced PR against its
own argument before merge, and what `Catapult.Dsl.SystemStatus
.agent_steps/0` has always carried as `:reconcile` with no matching
`phase:` to declare — until now, both the judgment and the mechanical
join it precedes shared one kind, `merge`. `dsl-syntax.md` §15.1,
§15.11 carries the grammar; the decision recorded here is the split
itself and why it is a table growth rather than a bundle-declarable
addition, the identical shape §7.8 above already used for
`design`/`architecture`: `docs/non-goals.md`'s "No per-project
restructuring of the automation protocol" entry covers it without
amendment, because the admission rule it states ("a state may be
declared iff no plane logic branches on it") is about what a bundle
may declare, and nothing here grows that — the platform-fixed table
itself is growing, the same way it grew for `design`/`architecture`.

**`merge`'s own `ball` changes from `agent` to `plane`.** Once
`reconcile` carries the judgment, the join into the parent branch is
mechanical — the plane performs it the moment `reconcile` approves,
barring a conflict, which routes to `Blocked` the ordinary way any
agent-balled entry's failure already does. This is what removes the
one named exception `Catapult.Delivery.ContainerLifecycle
.inline_dispatch_point?/1` has carried since ORC-148's dev pass — a
`status != "merge"` check inside a module whose own moduledoc asserts
it branches on no status name at all. The predicate needed the name
check only because `merge` was agent-balled without being a fresh
dispatch point; once it is not agent-balled, "agent-balled and not
review-shaped" already excludes it, and the exception disappears
rather than needing documentation.

**`reconcile` is required wherever `merge` appears, stated
positionally — a design-review correction to this decision's own
first pass, which had stated it as a `ticket`-skeleton rule.**
`dsl-syntax.md` §15.11: a `merge` entry must be preceded, earlier in
the same array, by a `reconcile` entry, a fact about that array's own
contents rather than one keyed to which skeleton, if any, the citing
type declares — reaching `container`-skeleton arrays too, which closed
a gap the skeleton-keyed version left open: `dsl-syntax.md` §15.2's
`milestone.yaml` worked example once ran `setup` and `retro` each
through a bare `checks → merge → deploy`, merging unread, twice, before
gaining a `reconcile` of its own for each. **The rule still reaches
`container`-skeleton arrays; `milestone.yaml` itself no longer
exercises it** (ORC-155) — neither `setup` nor `retro` produces code
any more, so neither merges, and the current declaration holds no
`merge` at all. A
generation-shaped entry with no adjacent `critique` simply runs no
auto-review — a workflow's prerogative; nothing merges, of any
skeleton, without having been read against its own argument first.
`reconcile` may also recur, the way a generation-shaped entry and
`merge` already could — `dsl-syntax.md` §15.11's own worked example
carries two, one per phase closed, rather than one pinned between
`checks` and a single `merge`.

**Gate scope — an open question with no definition in this grammar
before now — is derived from position relative to the nearest
`reconcile` entry before it, not declared.** `reconcile` may recur
(above), so this is not a single before/after split: a gate earlier
than every `reconcile` in a type's own effective sequence approves
that tier's own artifact alone; one sitting after a `reconcile`
approves what the nearer one has already read and accepted, superseded
again by whichever `reconcile` follows it later in the array — and,
settled at this same review's third pass (below), approves content
already merged onto the citing instance's own branch, not merely read
by the reconcile agent. This settles nothing about what a passed gate
*pins* — `dsl-syntax.md` §15.10's own answer to that (the sub-array's
one generation-shaped entry) is unaffected for a gate inside a
sub-array — it gives the *other* case, a gate positioned relative to a
join rather than to a single draft, a structural answer for the first
time. No new field: a `scope:` field restating what array position
already determines was considered and rejected on the identical
reasoning `throwback:`'s own narrowing already used (`dsl-syntax.md`
§15.10) — a fact computable from position does not need a bundle
author to restate it.

**`fanout` retires from the fixed table, at this same review's third
pass.** It named a status the feature ticket sat in "while children in
flight, progress rolls up," and nothing ever dispatched from it — the
shipped default bundle had already dropped the anchor by ORC-104. Its
only remaining job, marking the wait before a ticket's own
implementation-phase `reconcile` can run, is now a load-bearing
*precondition on entering that `reconcile`* (below), not a status to
sit in meanwhile — a real status kind needs a dispatch of its own to
justify existing, and this one had none left. `dsl-syntax.md` §15.1,
§15.11 carries the grammar; the edge type of the identical name
(`Catapult.Dsl.Edge`'s `@types`, node-id minting "at fanout time") is
untouched — this is a status-kind retirement, not a rename that
reaches the minting mechanism architecture's own generation tier
still uses.

**Architecture's own fan-out dispatches through the ticket tree, one
instance per tree level, rather than through one ticket spanning every
level — settled at this same review's third pass, correcting the
decision's own second pass.** That pass's own worked example ran a
single `architecture, depth: 2` visit inside one ticket, dispatching
comparch and subcomparch as scope-runs beneath it. That cannot give a
subcomparch `critique` its own bounce: a ticket has one status at a
time (above), so a decline on any one scope regenerates everything the
single ticket's single visit fanned out, sysarch through subcomparch
alike — no `depth:` value narrows a throwback to one branch, because
depth was never able to say "only this branch." Sysarch, each comparch
and each subcomparch instead dispatches through its own ticket
instance of the identical declared type, spawned the way a feature's
own component and subcomponent children already spawn — "when the
plan node names them" (§7.10 above), recursively, one level at a time,
wherever the plan proves independent parallel work exists — not a
second spawn mechanism, and not a change to the grain rule (§7.2)
that already governs how far any fan-out earns a child. §7.15's own
account of ticket spawning is corrected to match: an earlier draft had
children spawning "at `Building`," which this section had already
retired in `Building`'s own favor before that correction was carried
through everywhere it needed to be.

**Merge becomes implicit for every instance but the root — the third
pass's own largest structural change, and not a rule about subflows or
grouping.** Two rules, read as the completion rule above applied
twice: a ticket cannot enter its own `reconcile` until every child
blocking its completion has finished that child's own subflow
(§7.2's child-blocks-parent, as a precondition on entry rather than
only on completion); and the moment a ticket enters `reconcile`, the
plane mechanically merges every child now ready, before the reconcile
agent run reads what they produced. `merge`'s own depth is 0 by rule,
the identical posture a gate's own depth 0 already has — a mechanical
join belongs to the root because "the root" is what merging into main
means — which is what keeps `merge` out of every non-root instance's
own effective sequence: excluded by the same ceiling mechanism as any
entry too deep for it, nothing added. Every `ticket`-skeleton type
still declares exactly one `merge`, reconcile-preceded, load-checked
exactly as before; what changes is that only the root instance ever
reaches it by its own dispatch, and every other instance's copy of the
identical declaration means "merge, once your parent says so." **This
withdraws a claim the second pass made, rather than merely correcting
one it hadn't:** implying `merge` from tree shape is not plane logic
branching on grouping, and it was never in tension with
`docs/non-goals.md`'s automation-protocol entry — that entry's own
admission rule is about *states*, extended by `dsl-syntax.md` §15.10
to *groupings* of already-legal entries because a sub-array is an
authored choice; the trigger this decision actually uses is the
doc-graph tree's own shape, a runtime fact the plane observes the
identical way spawning itself already does, never vocabulary a bundle
declares or arranges.

**`reconcile` does not gain a `depth:`, reversing this decision's own
second pass.** That pass gave the first occurrence `depth: 1` and let
the second inherit depth 0 from its own omission; both readings assume
one ticket dispatching a join at several depths, which the correction
above retires. Once architecture dispatches per instance, whether a
given instance runs its own `reconcile` is a fact about that
instance's own children — has it any work beneath it needing a join —
never a declared ceiling: a ceiling would only restate what the tree
already settles. `depth:` stays exactly where it narrows something the
tree's own shape does not answer by itself, on a gate and on
`critique`, both of which review a level regardless of whether that
level has children at all. This also retires the widened
never-validated-against-the-chain posture the second pass gave
`reconcile`, along with the gap it named there: there is no ceiling
left to set too shallow, so there is nothing left to silently drop.

**A chain bundle may attach a synthesis tier to a `reconcile`
position, and does not have to.** The `synthesis` edge type
(`dsl-syntax.md` §4, `Catapult.Dsl.Edge`'s `@types`) already exists
for exactly this: a generation tier with edges to child nodes and/or
their critiques, plus the tier it synthesizes into, declaring `phase:
reconcile`. `reconcile` the status needs no such tier to mean
something — the mechanical merge and the reconcile agent's own read
(§7.5 above) happen regardless, so a bundle declaring none still gets
a real, structurally present fan-in for gate-scope and staleness
derivation; declaring one only decides whether a human reading the
post-join gate sees an authored document or the composed diff alone.

**`implementation` joins the fixed table as a third named generation
kind, at this same review's fourth pass.** The third pass's own worked
example dispatched a tier's code through a second, bare `checks` entry
— but `checks` is world-balled CI against produced work; nothing in
that shape ever wrote the code `checks` then ran against.
`implementation` names the generation run that actually produces it,
generation-shaped on the identical footing `design` and `architecture`
already stand on (`dsl-syntax.md` §15.1). It is deliberately gateless
in the default bundle: the touchpoint budget (§7.10 above) calibrates
a feature to two author gates, product and architecture, and a third
keyed to implementation is the "restricted scopes carry a third
touchpoint" exception rather than the ordinary case — architecture and
policy are what constrain intention narrowly enough that no ordinary
scope needs a human reading the code it produces.

**Two type declarations, not one array depth-filtered — settled at
this review's fourth pass, answering a question the third pass's own
worked example left open.** That pass instantiated "one declared
type… once per node the plan names," the feature ticket included, at
depth 0 of its own array. That cannot be the feature's own type:
`design` and its product review are feature-only, and neither `design`
nor a bare `status:` entry carries a `depth:` field to make it no-op
below the root the way a gate or `critique` already can. The feature
type (design → architecture → implementation → merge, one instance,
ever) and the type architecture's own fan-out spawns (architecture →
implementation, recurring per tree level) are therefore two separate
declarations sharing the vocabulary, never one array read two ways.
This is v5 §7.6's own "Child" lifecycle, read correctly for the first
time: a child spawned by architecture's own recursive fan-out runs
this second, richer type — its own `In progress` split into
`Architecting`/`Implementation`, mirroring the feature's own split —
while an ordinary child entering directly at implementation, with no
architecture review of its own to run, still runs §7.6's simpler
generic shape unchanged. It is also the exercised case behind this
ticket's own "two types declaring different ceilings" precedent
(`dsl-syntax.md` §13's never-validated-against-the-chain posture for
`depth:`): the fan-out type's own gates reach one level deeper than
the feature type's ever need to, because the two types fan to
different depths by declaration, not by anything the chain claims.

**`pending` recurs, once per generation-shaped entry's own sub-array —
a fourth-pass tightening of the original "somewhere earlier in the
array" reading.** A single leading `pending` used to license every
later generation-shaped entry in the same array, which satisfied the
load-time check while leaving a second or third such entry nowhere to
wait for dispatch capacity — invisible while `fanout` still gave a
ticket somewhere else to sit meanwhile, load-bearing now that `fanout`
retires (above) and `pending` is the only plane-balled wait position
left. `dsl-syntax.md` §13 states the check in full; the consequence
that matters here is throwback's own derived default (§15.10), which
now falls back to a generation-shaped sub-array's own leading `pending`
rather than straight to the generation-shaped entry itself — matching
this section's own repair-loop mapping, `Ready for rework`(pending) /
`Reworking`(generation), rather than skipping the queued wait every
other entry into that status goes through.

**The same declared gate may be cited twice within one type's own
array — but only when the two citations land in distinguishable
namespaces, a narrowing at ORC-155's design review to what this same
pass first settled without that condition.** This is the gate-and-
environment analogue of `critique`'s own established precedent —
citing a system status more than once to give two generation phases
different depths — for the identical reason: depth and scope are
facts about a citation's *position*, not about the declaration, so two
citations of the same gate can compute two different answers from the
identical declared `role:`/`escalation:`/`throwback:` only when
something actually distinguishes the two positions. Once a status
entry can carry a bundle-authored name of its own (`dsl-syntax.md`
§15.12), a position's identity is namespaced by the sub-array it sits
in, one level deep — and two citations sharing one sub-array are not
distinguished by that scheme merely because one sits before a
`reconcile` and the other after it: a citation told apart from its
sibling only by which side of a `reconcile` it falls on needs a second
level of qualification namespacing refuses to add. `architecture-review`
was this pass's own exercised case for the rule as first stated — cited
once before a `reconcile`, scoped to the tier's own artifact, and once
after, scoped to what that `reconcile` has joined, both inside the
identical sub-array. ORC-155 renames the second citation instead: two
distinct declared gates, `architecture-review` and
`architecture-synthesis-review`, each reviewing what its own name says
rather than being told apart by a join neither name mentions.

**`checks` sits between a generation-shaped entry and the `critique`
that reviews it, wherever a sub-array declares both — a fifth-pass
correction, not a new field.** Every worked example `dsl-syntax.md`
§15.2 and §15.11 carried had `checks` running after `critique` instead,
in two cases after the human gate as well, so a reviewer could sign off
on a draft CI had not yet run against. Machine validation runs first:
neither an agent's `critique` nor a human gate should spend a read on
a draft that fails CI. `dsl-syntax.md` §13 and §15.5 carry the grammar
— `critique`'s own adjacency rule now reads "immediately after a
generation-shaped entry, or immediately after that entry's own
`checks`, never before it" — and `dsl-syntax.md` §15.1's own mapping
onto this section's lifecycles is corrected to match, one `Checks` per
generation-shaped visit, positioned before its review.

**Not in this ticket's scope**, named because a reader following
`reconcile`'s own thread might look for them here: the critique
threshold and its conditional throwback (ORC-150) — a threshold
becomes easier to state once review-shaped is a named category, but
declaring one is not this decision; and ORC-150's container-dispatcher
corrections, unaffected by anything above.

---

## 8. Parked / open items

- **Hosted option** (direction favored, not committed; **the
  discipline is live now**). Shape if it happens: instance-per-org —
  separate plane + Postgres per customer, no multitenancy machinery
  (`topology: single` stands); BYO keys and cloud — the model
  credentials (API key and/or subscription OAuth token, §7.12.1)
  live in the customer's Actions secrets and never transit the
  plane, agent compute rides their runners, deploy targets and
  preview hosting live in the customer's own accounts. What makes
  hosting cheap is the recorded architecture itself (§1.2; "never
  executes target-project code"): the plane is coordination-only and
  IO-bound, so per-org cost is one small instance and its database —
  and nothing may erode that property. Three constraints are active
  today so the hosted product stays a fork-free extension rather
  than a rewrite:
  1. **Per-project credentials and connectivity are bindings
     entities (§7.10) — never env vars, never repo files.** Env is
     instance-level config only. Hosted onboarding is the bindings
     UI plus app-grade auth flows (GitHub App, tracker OAuth)
     replacing the solo-operator tokens; that swap only stays cheap
     if nothing meanwhile grows roots in env.
  2. **Registry artifact identity includes origin registry, from
     the first artifact (§3.1).** The hosted shape is per-org
     instance registries — orgs bless and self-host artifacts —
     federated with a central community registry. With origin in
     identity, federation is a namespace; without it, a migration.
  3. **The central registry decides contribution terms before it
     accepts any outside artifact.** Community content compiles
     into customer applications, so inbound grants must permit that
     — under any license posture Catapult itself ends up with.
  4. **The execution substrate stays an adapter behind the dispatch
     port (§7.12.1).** Actions is the community default; the worker
     pool — BYO on the customer's cluster canonically, managed
     runners as opt-in — is the hosted latency upgrade. The
     runner-harness contract is the invariant; nothing outside the
     Actions adapter may assume Actions.
  5. **The dispatch-concurrency cap is a per-instance, plane-enforced
     `tunable` in the bindings (§7.12.1)** — scheduler backpressure
     and hosted tiering are the same knob; it is plane state from
     the start, never a config constant.
  Everything else (fleet provisioning, upgrade train, the auth
  flows, billing) is deferred entirely. **License posture is
  decided** and recorded in `LICENSING.md` at the repo root:
  AGPL-3.0-only plane, Apache-2.0 for everything that ships into
  generated projects (the hard requirement), CLA-before-open (which
  preserves the commercial-license option without offering it).
  Hosted is the monetization path; self-hosting is the budget path;
  hosted tiers are business-targeted.
- **Restore-from-backup semantics** (docs review pass; **settled at
  the evidence model**; cold-storage rider open). The authority
  question resolved as a distinction, not a demotion: **the event
  log is the source of truth in operation; git and Linear are
  evidence in recovery** — recoverability is a property of the
  system, not a transfer of the crown. Two cases, both supported:
  (1) *database corrupt, world fine* — restore the known-good copy,
  then **re-ingest the gap window from git and Linear as evidence**:
  body commits and ticket transitions re-derive as observed facts;
  only plane-native events (bindings edits, dispatch history) are
  lost for the window, and those are operational rather than
  authoritative — bindings are rare and re-enterable, dispatch
  history is observational. (2) *the world went wrong* — operate
  from the backup moment. Binding in both cases: after any restore
  the plane re-synchronizes from tracker and host as *signals*
  before resuming authority — validate-or-revert never "corrects"
  the world back to a rewound log. **Cold-storage rider (punted as
  machinery, shaping the backup strategy now):** at scale,
  projections will need snapshotting and old events will archive to
  cold storage — the database will not stay tidy. Constraints
  pinned ahead of that build: archived segments are **part of the
  backup/restore surface** (a restore includes them; archived
  events remain immutable and replay-reachable), and snapshots stay
  **disposable projections — never backup artifacts, never
  authority**. Ops floor today: PITR on the plane's Postgres
  (SETUP.md).
- **MCP surface** (parked — customer-era, not near-term; scope
  shaped now so it doesn't get designed badly later). Three prongs,
  one exclusion:
  1. **A plane MCP server** for the author's assistant: the queries
     only the plane can answer (explain-why, staleness provenance,
     dispatch history, findings, stub inventory, enforcement gaps,
     bindings health) plus plane-native actions with no
     tracker/host expression. Auth via the identity component's API
     tokens (§2.9). Phase 7-adjacent.
  2. **Never reimplement GitHub's or Linear's MCP servers** —
     first-party servers exist, and legality is already structural:
     every tracker/host write from *any* client is a signal under
     validate-or-revert, and the writer matrix doesn't care who
     typed it. An assistant misusing Linear's MCP gets the same
     revert-with-comment a human does. A pre-validating pass-through
     is therefore **UX polish, not a safety requirement** — adopt it
     only if revert-after proves noisy in practice.
  3. **`api_surface/0` emits an MCP server** the way it emits
     OpenAPI and the typed channel client (§4.4): generated apps get
     an MCP surface from declarations — thin-wrapper legality by
     construction, `audience` levels apply, breaking-change
     detection rides the same handle-diff machinery. The
     customer-facing win, and it's mostly existing machinery.
  Exclusion, recorded before someone helpfully adds it: **agent runs
  never get an open plane-query MCP.** Context walks are the
  contract; a mid-run query surface would erode context reduction
  and break replay determinism — generation inputs must be
  answerable from recorded context, and an ad-hoc query is an
  unrecorded input.
  **Bounded by run class (§7.14, and the boundary was found by
  pushing on it).** That reasoning is about *generation* runs, where
  it holds absolutely: an artifact's inputs must be answerable from
  its recorded context walk, or staleness and regeneration mean
  nothing. A **diagnostic** run — a bug or harness finding attached
  to a ticket — has no context walk to protect and produces no
  artifact whose provenance must replay, so the premises simply do
  not reach it. It gets a typed, plane-mediated read port, a
  credential minted per dispatch and scoped to its ticket, and every
  query recorded as an observation. The load-bearing word in the
  exclusion is **open**: no query language, no unrecorded reads, and
  never on the generation path.
- Tenancy default-on vs opt-in (§2.9).
- Dialyzer in the gate set (§2.13) — **settled: the native
  set-theoretic type checker instead**, in-compiler, so
  warnings-as-errors makes it a gate for free; Dialyzer's cost
  bought only overlap.
- Registry notifications / push-on-release (§3.1) — seam designed,
  build later. The registry is now multi-kind: packages, extracted
  handles, handle diffs, whole-app operator releases, harness
  baselines, **external policies with their enforcement** (§4.5) —
  name new kinds as entries, not debates.
- Release distribution to third-party operators (Haven pass) —
  "validated on the reference instance" vs "released to operators"
  as a versioned whole-app artifact through the registry; flags
  default-off in releases, operator flips are ops acts. Shaped, not
  designed; Phase-2-of-Haven timing.
- SAML (§2.9) — deferred behind OIDC.
- CLI surface composer (§4.4) — spec'd, build later.
- React convention pass (§5.5) — shape blessed (Phoenix-hosted),
  contents still need the pass; folds in the client corpus (§5.6)
  and the kit-with-drift-test stance.
- Multi-target frontend vs second project — decided at a project's
  V2 (React Native); leaning recorded in §1.4.
- Storage (S3-compatible) shared component (§2.12) — likely, not
  designed; §2.12's adapter convention covers projects today.
- Machine-audience journeys for partner API flows (§4.4) — optional
  modeling, revisit with real use.
- `siege_engine_multi_seed.md` (SiegeEngine seed-docs) — not yet
  reviewed against §1.1's multi-document intake; reconcile before the
  input-role design freezes (the intake role list has since grown:
  behavior docs, invariants, capability inventories, forward
  strategies, `non_goals`).
- Agent-run substrate for child tickets (§7.12.1).
- Linear plan/API limits under many sub-issues (§7.12.2).
- Validation check inventory (§7.12.3) — routing settled in §7.11,
  checks scattered across §2.8/§4.3, needs consolidation.
- Phases-as-pure-batching fallback (§7.9) — only if ad-hoc batching
  ever strains; not designed.
- Debugging surface scope (§7.4) — budgeted as real engineering;
  undesigned.
- Mutex hold-window saturation (§7.5 watch item) — measure via
  per-label mutex-wait metrics; act only if a label serializes
  unrelated features.
- Generation-runtime DSL-profile boundary (§10) — which core
  primitives are in, which defaults differ; shaped, still mulling.
- Prompt-harness app-facing mode (§10) — ships with the runtime's v1
  or follows it.
- Shared-component build order — identity, observability, LLM
  adapters, generation runtime, `platform-client-ts`, storage: the
  roster is set, the sequencing isn't.
- Bindings settings/onboarding UI (§7.10) — query-and-pick over
  Linear/GitHub, one-click tracker provisioning. Designed, not
  urgent; big team QoL for cheap.

---


- **A bundle-authoring surface** (direction favored, not committed;
  **out of the current spec, and deliberately not a non-goal**).
  An earlier draft had it — v2 §A.11.6: "because the bundle is a typed
  graph, it visualizes directly: tiers as boxes, edges as labeled
  arrows with crow's-foot cardinality, predicates as badges opening an
  expression builder", with bundle diffs rendering as diagram diffs,
  "which makes bundle governance workable without reading YAML."
  v5 dropped it without recording why, which is the actual gap: it is
  absent from `docs/ui-spec.md` §6's deliberately-absent list, so
  nothing says whether it was rejected or forgotten. It was forgotten.

  **The rationale is the DSL's own premise.** Customization is why the
  DSL exists rather than hard-coded chain logic. If customizing
  requires learning YAML, that premise is half-delivered — the
  capability ships and the audience for it doesn't. People will
  hand-edit prompts to build their own differentiation whether or not
  it is advisable, and that demand *is* the demand the DSL was built
  to serve; refusing it a surface does not remove it, it just routes
  it through a text editor with no guardrails.

  **Two surfaces, not one, and they should not be conflated.**
  *Structural* editing — tiers, edges, gates, environments — is a form
  over a declaration, a solved shape. Half of it is already specified
  rather than designed: `systems/dashboard.md`'s configuration prong
  is "forms generated from declarations, save files a change through
  the normal entry machinery, review stays in the PR", and
  `ui-spec.md`'s `workflow` screen is read-only precisely because it
  "routes editing to `configuration`". So the workflow axis is a
  build. The chain axis — tiers, edges, and above all prompts — has no
  screen and no mechanism.

  *Prose* editing is the hard half and wants a different surface.
  **Navigating to a prompt from the UI is worth having early and is
  not the same as editing one**; reading is cheap and the reachability
  is what makes the bundle feel like part of the product rather than a
  file tree. But **the prompt revision surface plugs into the harness
  (§10.2), not into a configuration form.** The evidence is this
  repo's own: two passes over the default bundle destroyed 76% of the
  prompt corpus by word count while believing they were improving it,
  and the only thing that caught it was counting against a vendored
  original. That safeguard is not expressible as a save button. A
  prompt edit wants a scored campaign against a pinned baseline, which
  is what the harness already is.

  **AI-assisted editing of the YAML is out of scope and explicitly not
  ruled out** — recorded so nobody files it as a non-goal later. Once
  the visualization exists it is a small lift, and the graph is the
  part that has to be right first.

  Revisit condition: **the first customer.** Nice-to-have while the
  only bundle authors are engineers who wrote the DSL; mandatory the
  moment non-engineers are expected to participate in workflow
  construction, which is the point at which "learn the configuration
  DSL" stops being an acceptable answer.
## 9. One DSL: core and extensions

**The commitment: a single DSL with a frozen core and codified
extensions — no dialect forks.** Every new use case will need new
vocabulary tied into the DSL; if extension isn't codified from the
start, each need becomes a fork and the dialects drift apart
(orchestration §1's two-copies argument, at the language level).

- **The core**, frozen and small: tiers, scopes, edges, fragments,
  handles, context walks, grammars, readiness, generators, the
  predicate language, bundle layout + `extends:` layering.
- **An extension** is *platform-shipped* code that registers with the
  loader: new annotation namespaces on existing declaration kinds
  (the `delivery:` block, the `enforcement:` block), new declaration
  kinds and files (the flow ticket face; `states.yaml`), new
  generator types (`external`, `template`), new context-source kinds
  (`ticket.findings`), and new audit/enforcement profiles. Each
  extension carries its own validation schema; the loader validates
  the union; type-level checks run over the union. **Never
  bundle-side code** — bundles declare instances against whatever
  vocabulary the installed extensions provide, so the
  closed-vocabulary doctrine survives per-installation.
- **A dialect is core + extension set + defaults.** Two registered
  dialects so far: **design** (core + delivery + review lifecycle +
  git bodies — Catapult proper) and **runtime** (core + execution
  semantics, no review lifecycle, no git bodies — the embedded
  generation runtime, §10). Same vocabulary, different profiles.
- **Extensions compose the language; `extends:` composes content.**
  Two orthogonal mechanisms, both codified. The elixir-target layer
  is content layering; the delivery DSL is a language extension; they
  are not the same kind of thing and the spec keeps them apart.

Retroactive tidiness note: the delivery DSL (§7.10), the enforcement
block, and the runtime profile were each invented as one-off moves;
this section names the mechanism they were all instances of.

---

## 10. Generation runtime and prompt harness

### 10.1 The generation runtime

**The insight (integration pass over both gap reports): the
LLM-Oban-Commanded component apps need is Catapult's own engine,
extracted.** The plane's doc generation (Oban worker → Liquid render
over projections → provider call → grammar validation → event →
reducer → scheduler finds next ready scope) and Polyphony's beat loop
(Oban job → context from filtered projections → provider call →
schema validation → command → aggregate → projectors →
enqueue-on-completion) are the same machine. Every abstraction in
"tie jobs to prompts to events, with chaining and prompt
configuration" already exists in the DSL: a generation node is a
tier; its inputs are a context walk over read models; its output
contract is a grammar; its chaining is readiness; its effect is the
event the reducer applies.

The stack, three layers, each a shared component:

1. **LLM adapters** — provider behaviour with real/deterministic-fake
   implementations (the precondition for no-network CI in any LLM
   app), model-tier routing, metering/cost ledger with caps and
   circuit breaker, the three-way failure taxonomy (refusal →
   editable; transport → retryable; schema-invalid → cancel),
   generation-failures-as-domain-read-models (never crash reporting).
   Absorbs the serial-pipeline pattern: enqueue-on-completion chains
   with log-derived progress (pausable, resumable, identical inline
   in tests). **Boundary: the adapter contract is synchronous
   completions only** — API call or CLI subprocess, both
   request/response — because the fake, the metering, and the
   taxonomy depend on that purity. Agent-in-environment runs are
   *stateful* (delegate to an environment, complete out-of-band) and
   belong to the dispatch machinery (host port, run correlation),
   never to an adapter. **Catapult's own chain never uses this
   layer** (§1.2: agents end-to-end) — the adapter component's
   customer is the generation runtime, i.e. target apps, so it is
   **built with the runtime (Phase 8), not before**. Its design is
   settled here so the runtime dialect's contract is stable; its
   construction waits for its consumer.
2. **Generation runtime** — the embedded engine loading the DSL's
   **runtime dialect** (§9): declared generation nodes, scopes,
   context queries, grammars, readiness; on-success commands/events
   via the ES store family (§2.4). Building an LLM app becomes "build
   the programmatic side, write configuration." **Not mandatory; not
   hand-rolled** — a declared dependency, like auth. Caution recorded:
   the profiles have different envelopes (doc generation is
   long-form, low-frequency, review-gated; app generation is
   latency-sensitive, high-frequency, cost-capped) — the runtime is a
   subset with different defaults, not the platform engine linked
   wholesale.
3. **Prompt harness** — see §10.2.

**Dogfooding note, corrected for §1.2** (stale text caught at the
docs review pass — the original claimed the plane's doc tiers ran on
layers 1–2): the plane's chain is agents end-to-end and never
touches the adapter. The adapter and runtime get their exercise from
the harness's runtime-dialect campaigns (§10.2) and from the
runtime's first real consumer — Polyphony's beat loop, Phase 8 —
which is why both are built with that consumer, not before.

### 10.2 The prompt harness

Catapult needs a prompt-iteration harness for its own default-bundle
prompts; and because the harness is a **function of the
generation-runtime abstractions** (anything with declared nodes,
scopes, grammars, and reviewers can be harnessed), building the
runtime makes the harness portable to every app on it — the nearby
win, confirmed.

**Not greenfield: SiegeEngine already built it.** The cohort
machinery — stratified sampling with the upstream-only-axes rule,
fresh-vs-review iteration modes, score histograms and per-round
deltas, worst-N views, full-corpus sweeps, batch tagging — is a
working prompt harness that re-platforms onto the v5 engine. Shape:
sample scopes into a cohort; regenerate under a prompt variant; score
via the declared review grammar plus structural metrics (grammar
parse rate, cardinality violations); compare against a baseline
pinned in the registry (a registry artifact kind).

**Campaigns never touch the pipeline** (harness isolation pass).
Candidates and scores live in a **campaign workspace** —
harness-owned storage seeded from a snapshot of the target graph —
never the production graph, never git, never Linear. No tickets, no
gates, no review lifecycle: gates exist to protect shipped truth,
and harness output is deliberately disposable at a throughput
(hundreds of regenerations of one tier's prompt) that would abuse
any human-attention surface. The author drives campaigns from the
harness surface directly. The dummy repo + test tracker project
remain the **protocol** test surface (sim ring, live suite) —
protocol correctness and content quality are different axes, tested
by different instruments, and the harness deliberately opting out of
Linear is what lets it iterate single prompts at volume instead of
staging full runs.

**Candidates run under the tier's production executor** — the
fidelity rule: a design-dialect tier's candidates generate as
dispatched agent runs (same render path, same executor profile,
committing into the campaign workspace instead of git); a
runtime-dialect tier iterates through the adapter, which *is* its
production executor. A prompt scored under a different executor
than production is a measurement of the wrong thing — an agent that
can research behaves differently from a bare completion on the same
prompt. Offline mode uses the matching fake (agent-port or
adapter). Budgets are campaign-scoped by construction:
dispatch-count caps for agent campaigns (§7.12.1's budget
machinery), adapter metering for completion campaigns — a run
without a cap is a config error, not a choice.

**Campaigns key off files and bundle commit shas, not only tier
names.** The cohort machinery samples *scopes* by tier, which answers
"how does this tier's prompt score" and not the two questions a prompt
revision surface (§8) has to ask: score the variants of *this file*,
and what changed between *these two bundle states*. A bundle sha is
the addressable unit for the second — a prompt's score is only
meaningful against the bundle it ran under, and "the prompt at the
time" is otherwise unrecoverable once the file moves on. Cheap to
build in, expensive to retrofit onto a corpus of campaign results
already keyed the other way.

**Whole-flow campaigns are wanted, beyond single-prompt ones.** A
flow's quality is not the sum of its tiers' scores — the failure this
chain actually produces is a handoff that degrades across tiers, each
of which scores acceptably alone. Not scoped here; recorded so the
campaign model is not designed in a way that forecloses it.

Open (also in §8): the exact runtime-dialect boundary, and whether
the app-facing harness mode ships with runtime v1 or follows.

---

## Provenance

Sections marked "gap passes" derive from three inputs: the Haven
fitness report and the Polyphony fitness report (each run blind to
the other, against this document as rubric), and the integration
pass that unified their findings (the realtime section, the ES
store family, the enforcement-profile mechanism, the client-corpus
slot model, the identity option portfolio, the negative-space
doctrine, and §§9–10). Where a convention was independently invented
by a subject app before the platform named it — the adapter pattern,
state-names-as-storybook-variations, audit-as-tests, journey-scoped
state — that convergence is the strongest evidence this corpus
codifies practice rather than theory.

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
audit, alternating debt milestones), and the residual risk of
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

v4 §A.0.2 required SiegeEngine to produce byte-identical artifacts to
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
per milestone at the boundary — after the boundary ticket is created,
before the author's pass — results posted on the boundary ticket,
failures filed as milestone blockers, and the flag flip (§7.8)
strictly downstream of a green run. Rationale: per-ticket determinism
is what the escalation rules depend on, but a live check that never
runs is how "merged and green" quietly diverges from "works against
the world"; both properties hold, each at its own cadence.
(Orchestration-side: one added boundary step, absorbed by its
existing step-comment resume machinery.)

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
- `@tag :skip` requires a ticket key; CI rejects bare skips — keeps the
  boundary agent's debt-scan input trustworthy.
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
  behind the feature's flag; the milestone boundary (the author's
  manual pass — already the only manual-testing point) is the natural
  flip point; flag *removal* is gating debt — the boundary agent's
  debt scan gets a bounded input "flags fully-on for > N milestones"
  and files cleanup proposals.
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
  its features' flag set at the boundary.
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

**Self-hosted, hex-compatible** (the `mini_repo` pattern): generated
projects consume shared components with ordinary `mix deps` machinery;
packages publish from Catapult's monorepo, not hex.pm. Notifications /
push-on-release: not needed yet; the seam is designed so the registry
can grow into serving handle diffs and release notifications later.

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

- The dev agent never edits shared-component code — structurally
  guaranteed (hex dep, outside the repo tree, outside file maps).
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
is re-approval + staleness, and staleness *hints, never cascades*
(v4 §A.6.5 kept): a ref edit surfaces its consumers in the staleness
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
- **`debt`** — accumulates to the next debt milestone through the
  existing debt-composition machinery, gating test and all. Code
  style and non-load-bearing conventions.

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
  the convention corpus. The delivery DSL section (§7) also ships from
  this layer.
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
  slots); spawn is a plane rule at the Building transition; only
  `states.yaml` / `types.yaml` / `escalation.yaml` remain standalone
  — the files with no design-graph counterpart.

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

**Dropped from v4:** the phase machinery — `phased:` tiers, the
`phase_plan` projection and plan rule, cross-phase delta context, the
plan-change flow, `/run_phase` (v4 §A.7 and §B.5 in their entirety).
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
  deltas, no product change). Orchestration's alternating debt
  milestones and gating-debt rules survive unchanged; debt tickets
  are this entry with the `tech-debt` label.
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
  steals an in-flight mutex, overrides the milestone pause. A true
  security patch bypasses the pipeline onto main — and its afterlife
  *is* the absorption path above. One mechanism, two doors.

### 7.4 Feedback surfaces

Four surfaces, each at its own altitude; the feedback-hose problem
(one ticket aggregating feedback for dozens of artifacts) is
dissolved by giving every feedback type a home:

1. **Linear** — the author's inbox and state lever. See tickets
   waiting on you, action them, kick work back to the machine.
2. **GitHub PRs** — diffs and artifact feedback. At the review gates
   the artifact set *is* a doc diff on the feature PR, so artifact
   feedback is line-anchored PR review comments. **Harvesting rule:**
   on a gate decline (state moved back), the plane collects review
   comments since the last gate, buckets them by the artifact file
   span they anchor to, and threads each bucket into that scope's
   regeneration as `feedback`. Machine comments carry fixed markers
   (orchestration's programmatic-comment rule); anything unmarked in
   the diff span is human feedback.
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

**The Catapult LiveView UI is a debugging surface, not a working
surface.** Lesson from siege: the DAG is for machine comprehension
(humans got a tree view because the graph was unnavigable), and
Linear+GitHub already unify comments, states, and diffs. The
debugging surface is load-bearing and genuinely hard — event-log
inspection, replay-to-sequence, ready_scopes explain-why ("what is
blocking this scope" as a first-class query), staleness provenance,
dispatch history, agent-run transcripts. When a pipeline this deep
stalls, "why is nothing happening" must be answerable in minutes.
Budgeted as a real engineering line item, not a leftover dashboard.

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
  back at the feature level.
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
  Building (children in flight; progress = sub-issue roll-up) →
  Reconciling → Merged → Validating → Shipped/Done`, `Blocked`
  anywhere. Two author gates, per orchestration's touchpoint budget;
  entry tier (§7.3) determines which early states are skipped.
- Child lifecycle: orchestration's states nearly verbatim — `Ready
  for dev → In progress → Checks → Reconciling → Merged → Done`, plus
  `Ready for rework / Reworking`, design states gone: children are
  born past design (their design is the parent's approved docs),
  entering at `Ready for dev` by construction — which is how
  every-ticket-gets-a-design-pass is satisfied at the parent.
- **`Stubbed`** — machinery-filed swap tickets only (§2.16):
  committed work deliberately waiting on an external timeline. Passes
  the admission test with a distinct who-has-the-ball answer — the
  world's calendar, not the queue and not the author-now (Backlog
  means not committed; Todo means starting when the queue reaches
  it; Stubbed means starting when the world permits). Exempt from
  staleness and escalation checks (nothing is stale about waiting
  deliberately); carries no milestone until scheduled, so it can
  never block a boundary.
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

### 7.8 Milestones

Unchanged from orchestration: a milestone is a collection of
features; the boundary ticket, author's pass, archive/debt-scan/
grooming machinery all port as-is. One added machine step: on
boundary-ticket creation, the **`:live` suite runs** (§2.8) and
posts results before the author's pass, so the pass happens with the
true end-to-end check in hand; failures block the boundary through
the existing blocking rule. "Shipping" a milestone aggregates the
flag set from its included features and flips it at the boundary
after the author's pass and a green live run — features merge dark
as they complete; the milestone lights up together.

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
  the tier generates) and `gate:` (which author gate's PR diff
  approves it). A gate's review set is *derived* — the tiers
  declaring it. Bundle-load validates annotations against the
  protocol vocabulary: unknown phase or gate is a load error; one
  loader spans both worlds.
- **Flows gain a ticket face.** Entry types (§7.3) and v4's flow
  catalog are one list — opening a ticket IS opening a flow instance.
  A flow's `flow.yaml` adds `ticket: { entry: <tier>, labels: [...] }`
  alongside its schema delta and walk primitive; its planning tiers
  carry `delivery:` annotations like any tier. Flow completion maps
  onto phase transitions ("phase complete" = no ready or in-flight
  scopes with this phase within this flow instance). Scaffolding
  keeps its v4 status as "a flow with an empty delta" — the base
  schema wearing a ticket face.
- **Spawn is a plane rule, not a declaration.** Spawning attaches to
  the *Building transition*, not to fanout edges: at entry to
  Building, spawn children partitioned by the fanout structure of the
  impacted scope set (plan/staleness data), one child per impacted
  component, nesting to subcomponents only where the plan proves
  independent parallel work; ticket type follows nesting depth.
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
  | violet | `#9b8fd4` | a generation agent is working | Product design, Architecting |
  | green | `#4cb782` | building | Building, In progress, Reworking |
  | yellow | `#f2c94c` | machinery verifying/shipping | Checks, Merged (awaiting deploy), Validating |
  | cyan | `#26b5ce` | reconcile agent | Reconciling |
  | orange | `#f2994a` | the author's sign-off | Product review, Architecture review |
  | red | `#eb5757` | stuck; the author unsticks | Blocked |
  | dark grey | `#95a2b3` | terminal, out of mind | Done/Shipped, Canceled |

  Rule two, carried with its reason: **Done is deliberately grey,
  not green** — finished work is out of mind, and green is spent on
  work in flight. Nothing reads colors back; they exist so the
  author sees the queue without reading it.
- `types.yaml` — ticket types, per-type lifecycles, PR topology
  (feature: base main, squash; child: base parent branch, merge).
- `escalation.yaml` — thresholds routing to `Blocked`, with `tunable`
  markers as the only project-override surface.

CI suite selection is *derived*, not declared: gate phases are
docs-phases → `ci:docs`; Building → `ci:code`. A `ci.yaml` exists
only if a real exception ever forces it.

**Agents are three layers, changing at three rates.** The writer
matrix carries *roles* only — authority, invariant across
implementations. The protocol names *agent kinds* (design, dev,
reconcile, boundary, validation) as vocabulary. Tier declarations may
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
way the boundary ticket does: routine bumps file to Triage for
batch-accept; advisory-backed security bumps file directly to the
queue with `Urgent` plus a notification — the alternative is the
author doing it by hand out-of-band, which is strictly worse. The
auto-queue threshold is a `tunable`. Bumps touch `mix.exs`/`mix.lock`
(accepted shared-file territory) and serialize textually at their
natural cadence. `Urgent` itself is a **modifier on any type**, never
a type: pure precedence (preempts at pickup, overrides the milestone
pause, never steals an in-flight mutex), preserving orchestration's
treatment.

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
(machinery-filed, like the boundary ticket and maintenance) in the
**`Stubbed`** status (§7.6), carrying the scope's mutex labels, the
deferral argument, the exit plan, and the gate it will run when
scheduled. **No milestone** — the point is an open timeline, and a
milestone-bound Stubbed ticket would block that boundary forever.
Scheduling is the author's act: assign a milestone, move it into the
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

1. Agent-run substrate (Actions vs owned runners) and how many
   concurrent sessions the plane dispatches — now covering *all*
   generation, not just children (§1.2). Direction decided, shape
   open: start on Actions with **prebaked container images** (the
   browser/toolchain stack pulls, never builds, per firing); the
   scale-out is an autoscaling worker pool pulling from our queue —
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
2. Linear API/webhook limits under many child tickets — verify plan
   limits before the plane assumes them (orchestration §14's warning,
   inherited).
3. The validation check inventory (§7.11) — routing settled, content
   scattered.
4. Pseudo-user assignability and seat economics on Linear's plan
   (§7.10's assignment projection) — verify before relying on
   per-step pseudo-users; the reviewer-map half works regardless.

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
fanout (§7.2), and its children spawn at `Building`, where the plan
document has proved independent parallel work exists — depth earned,
never reflexive. So during an architecture pass there is **one**
feature ticket sitting in `Architecting` while N scopes generate
beneath it. Per-scope pause and resume needs no early ticket fanout
and must not be read as an argument for one.

The consequence is about what the author sees: with no per-scope
tickets during design, a paused pass surfaces on the parent ticket
and on the dashboard's unbuilt-scope count, and nowhere else. That
count is not a convenience during intake — it is the only progress
surface there is.

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
v4 §A.0.1 commitment 4 rather than decided here.

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

This argues against `docs/non-goals.md`'s
`No per-project protocol restructuring`, which says states and gates
are platform-fixed — and it satisfies that entry's stated reason,
which is that prompts, plane logic and shared vocabulary are written
against the states. That holds for states the automation reads. It
does not hold for a state whose only job is routing a human: nothing
dispatches from it and no prompt is written against it. So the
admission rule narrows rather than dissolving — **a state may be
declared iff no plane logic branches on it.**

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
- **What a passed gate pins** — the one piece status-as-approval does
  not answer, and the sharper problem now that the approval *is* the
  transition. A gate approves a version of an artifact; the ticket
  then moves past it. When the artifact regenerates underneath, the
  ticket is already downstream and the judgment it carries is stale
  while nothing says so. §7.11's staleness-is-derived machinery is
  the natural home — a passed gate goes stale when what it approved
  does, and reopens — but the gate has to record what it approved for
  that to be derivable at all.
- **Staleness clocks under more writers.** `staleClaimGrace` measures
  from `max(Run.EndedAt, StateSince)`, so every state move resets it.
  More writers means more resets, and the constant (§7.13) was chosen
  against a single-writer rate.

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

**What this costs, recorded honestly.** A working tracker is a real
product surface: search, notifications, permissions, and mobile —
and mobile matters more than its line here suggests, because the
author works from a phone and the incumbent's app is good. The
staging is what makes it survivable: delivery to Linear stands until
the native UI exists, and the UI spec (§7.18's sibling work) is what
turns "we build our own" from a direction into a scope.

### 7.18 Configurable deployments, and where configurability lives

**Deployment environments are declared, on the same rule as §7.16's
review states.** The default set is `dev` and `staging`;
per-PR environments are a later addition and, when they land, are
expected to attach to top-level tickets only — the fan-out would
otherwise mint an environment per child, which is the cost that makes
per-PR previews expensive everywhere they are expensive. Promotion
between environments is automation and stays platform-fixed; *which*
environments exist, and what a promotion into one requires, is the
organization's shape, not the automation's.

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
  actual gates and environments live in its bundle's `extends:`
  layer, versioned in the repo, changed by PR. `extends:` composes
  *content* and never adds vocabulary.

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
- ~~Dialyzer in the gate set (§2.13)~~ **Settled: the native
  set-theoretic type checker instead** — in-compiler, so
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

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

**Two execution substrates**, and the distinction is load-bearing:

- Document-tier generation is a deterministic Liquid render → LLM API
  call → grammar-validated commit. Runs as plain Anthropic API calls
  from Oban workers. No agent session needed.
- Ticket delivery needs a real agent session with a repo checkout,
  toolchain, and CI. Stays "dispatch a Claude Code run" (Actions or a
  runner we own).

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

- **Backends: Elixir only**, with an escape hatch for non-Elixir
  components (shape TBD — likely a component whose delivery skips the
  Elixir conventions and whose contract is an API surface).
- **Frontends: Phoenix LiveView + daisyUI, or React. Exactly one per
  project** — the product tier (§4) doesn't know which frontend exists;
  the fork appears only at the frontend-architecture tiers (§5) and in
  delivery conventions.
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

### 2.2 Component behaviour and registries

Every component adopts a platform behaviour (`use Catapult.Component`,
name TBD) with callbacks that register claims on shared root
resources, aggregated by a compile-time root composer that fails the
build on collision:

- `config/0` — Vapor provider; per-component `.env`, prefixed env vars.
- `pubsub_topics/0` — topics as functions (`Comp.Topics.user_updated(id)`),
  never raw strings.
- `oban_queues/0` — queue and worker names.
- `telemetry_events/0` — see §2.11.
- `feature_flags/0` — see §2.10.
- `permissions/0` — see §2.9.
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
- Known tax, accepted: projects run this machinery at n=1–2 nodes for
  a while. Retrofitting placement discipline into a live system is the
  week-to-month rewrite this exists to preempt; dev-mode ergonomics
  (single-node topology, identical behavior) get deliberate attention
  in the skeleton.
- Consequence for deploys: DO App Platform can't cluster BEAM nodes
  (no inter-instance networking for distribution). The blessed deploy
  target must support it (DOKS / droplets / Fly-shaped). Decision to
  pin one target is **open**; the health-endpoint contract (§2.13)
  keeps delivery's deploy detection provider-independent either way.

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
the pipeline exists to keep them out of. Hence: no network in tests
(fakes per §2.12), Ecto sandbox async-by-default, injected clock,
seeded randomness.

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

### 2.10 Feature flags

Rationale first: main is production, merges are unattended, there is
no staging — so any feature spanning multiple tickets has partial
state on prod mid-milestone. Orchestration never addresses this;
Catapult minting whole phases of tickets makes it untenable. Flags are
the platform primitive that makes the deploy model safe:

- FunWithFlags (Ecto-backed, actor/group targeting, admin UI slots
  into the admin-surface convention).
- Flags registered via `feature_flags/0`, spine-named, collision-
  checked; a new flag is a §2.8 named decision.
- **Lifecycle from existing machinery:** features pin to phases (the
  phase plan); a phase's tickets land behind the feature's flag; the
  milestone boundary (the author's manual pass — already the only
  manual-testing point) is the natural flip point; flag *removal* is
  gating debt — the boundary agent's debt scan gets a bounded input
  "flags fully-on for > N milestones" and files cleanup proposals.
- **Flags partially substitute for staging:** the author's pass
  exercises flagged-off features on production via actor targeting.
  Not a full substitute (schema changes and deploy-time behavior still
  hit prod raw) but covers review-before-users-see-it, which is most
  of what staging was for.
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
verification honest across projects. Dialyzer: **open** (value vs.
CI-loop latency).

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

---

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
convention set is less developed and needs its own pass.

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
  (§2.8); journey and screen grammars per §4.2/§4.3.
- **Nav edges:** cyclic-legal, never readiness-bearing (§4.3).
- **A delivery section** — states, owners, transitions, invariants,
  escalations (roughly orchestration's protocol tables + config as a
  declaration), sharing the node vocabulary with the design graph.
  Join points declared: which tier's approval mints tickets, which doc
  diffs constitute a sketch, which scopes derive mutex labels.
  **Shape deliberately unspecified pending §7.**

Design-stance note carried over from v4 and reaffirmed: closed
vocabularies everywhere (scope expressions, predicate operators,
options, fragment kinds) — no bundle-provided code, no escape hatches
into Turing-completeness.

---

## 7. THE OPEN SEAM: delivery and the ticket model

Deliberately unresolved. The next conversation; likely to reshape
parts of §6's delivery section and possibly the impl tiers' grain.
What follows records the direction and its tensions, not decisions.

### 7.1 The target lifecycle

The end goal, per feature: (1) author writes a feature they want →
(2) UI design for the feature, if applicable → (3) architecture for
the feature → (4) code → (5) validate → (6) ship. **The instinct: each
instance of (1) is a ticket**, and those six steps map onto both the
orchestration flow (design pass → dev → reconcile → deploy) and the
siege flow (feature expansion → propagation through tiers). The open
question is how much of the siege document machinery gets *baked into
Linear state* versus remaining Catapult-side with tickets as the
delivery projection.

### 7.2 Ticket grain — direction under discussion

- **Scaffold (initial implementation): roughly a ticket per
  subcomponent**, ordered by the dependency graph. Possibly feature-
  tickets with subcomponent subtasks for better parallelization.
- **Thereafter: a ticket per feature request** — the feature flows
  through docs (staleness cascade) and lands as one delivery unit.
- **Bias toward larger tickets.** Common wisdom on ticket sizing
  assumes human time; AI does in hours what humans do in days-to-
  weeks, so a ticket can be a whole deliverable. (Note the alignment:
  orchestration's reconciliation verifies a diff against an
  *argument* — a coherent deliverable-sized argument is exactly what
  it's built to check. Many tiny tickets dilute the argument;
  one-feature-one-argument concentrates it.)
- **Parallelism:** original SiegeEngine assumed one propagation pass
  at a time. The mutex machinery may permit much more: the doc graph
  gives delivery *better* collision data than orchestration's native
  config — mutex labels derived from component scopes, plus declared
  edges (`renders`, `calls`, `uses_shapes`, consistency annotations)
  giving the re-evaluation machinery real adjacency instead of
  hand-reconstructed guesses.

### 7.3 Questions the next conversation must answer

1. How much siege machinery moves into Linear state? (Options range
   from "tickets are a projection of doc-graph state, Linear is dumb"
   to "Linear states carry the doc lifecycle and Catapult reacts to
   tracker transitions, orchestration-style." Orchestration's hard-won
   rules — states answer *who has the ball*, descriptions immutable,
   newest-comment-is-scope, detect-and-revert enforcement — should
   survive whatever the split is.)
2. Ticket grain at scaffold: per-subcomponent tickets vs. per-feature
   tickets with subtasks; how phase plan and dependency order
   translate into milestone/queue structure.
3. Do feature tickets carry their doc-regeneration (steps 2–3) as
   ticket-internal stages, or do docs regenerate Catapult-side first
   with the ticket minted only for step 4+? (This is the crux of
   "ticket per instance of (1)": if the ticket IS the feature, design
   and architecture become ticket states, which merges siege's
   document state machine into the tracker far more deeply than
   orchestration's single design-pass state.)
4. Where the initial-scaffold ticket enters orchestration's state
   machine (pre-designed tickets arguably enter at `Ready for dev`
   with sketch attached — bending the every-ticket-gets-a-design-pass
   rule).
5. How many dev agents / how much parallel in-flight work the mutex +
   adjacency data actually supports, and what the single-dispatcher
   control plane needs to guarantee it.
6. Whether validation (step 5) is reconciliation as-is, or grows
   (post-deploy checks against affordances/states, `mix catapult.audit`
   as the reconcile harness, flag-gated author validation at the
   milestone boundary).

### 7.4 What seems stable regardless

Recorded so the next conversation doesn't relitigate: mutex labels
derive from doc-graph scopes (§2.1, §5.4); the sketch is a diff
against architecture bodies; the audit is the shared enforcement organ
between design and delivery; orchestration's Go pipeline delivers
Catapult itself while Catapult's Elixir control plane re-expresses the
protocol for generated projects; the Go core's snapshot→actions purity
is the porting model (near-1:1 to a Commanded process manager).

---

## 8. Parked / open items

- Blessed deploy target supporting BEAM clustering (§2.5) — pick one.
- Tenancy default-on vs opt-in (§2.9).
- Dialyzer in the gate set (§2.13).
- Registry notifications / push-on-release (§3.1) — seam designed,
  build later.
- SAML (§2.9) — deferred behind OIDC.
- CLI surface composer (§4.4) — spec'd, build later.
- Non-Elixir component escape hatch (§1.4) — shape undefined.
- React convention set (§5.5) — needs its own pass.
- Storage (S3-compatible) shared component (§2.12) — likely, not
  designed.
- Machine-audience journeys for partner API flows (§4.4) — optional
  modeling, revisit with real use.
- `siege_engine_multi_seed.md` (SiegeEngine seed-docs) — not yet
  reviewed against §1.1's multi-document intake; reconcile before the
  input-role design freezes.

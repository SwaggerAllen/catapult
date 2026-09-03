---
paths:
  - bundles/**
---

# platform_content

The bundle *content* the DSL loads, across **both bundle axes** (v5
§7.18):

- **chain axis** — `bundles/default/` (the software-design chain:
  tier declarations, edges, the prompts ported from SiegeEngine, and
  — since `platform-elixir` folded in, ORC-153 — the platform-wide
  review grammar and the elixir-target convention content that used
  to ship on its own layer).
- **workflow axis** — the platform workflow content, carrying the
  default review sequence (a UX review and an engineering review) and
  the default `dev`/`staging` environments.

**Delivery declarations moved off the elixir-target content** (v5 §6,
corrected at §7.18): shipping them from the language corpus welded
the workflow vocabulary to one target stack, which is exactly what the
two-axis split exists to prevent. They ship from the workflow bundle
instead, and neither bundle composes the other — both axes are
forked, never layered (v5 §6, `dsl-syntax.md` §11).

A separate system from core_dsl **for the mutex**: prompt iteration
and loader development are unrelated work streams, and one label
covering both would serialize them (v5 §7.5's watch-item logic,
applied preemptively). Prompt tickets carry `system:platform_content`;
loader tickets carry `system:core_dsl`.

## Standing decisions

- **Prompts are content, reviewed as diffs, never inline in code**
  (conventions §11). The harness iterates them; the git history is
  their changelog.
- **The siege port preserves semantics first**: mechanical
  f-string→Liquid conversion, then iteration via the harness —
  never both in one change, or a quality regression is
  unattributable.
- **The meaning-engine discipline governs edits** (SiegeEngine's
  hard-won rule): each tier's prompt names its
  downstream reader and pushes against category-speak; if a tier's
  output is vague, fix that tier's prompt, don't pass more context
  downstream.
- **The layer carries the default license policy, written literally
  into the generated project** (ORC-16). `mix catapult.audit`'s license
  check is held to a list of SPDX identifiers the project states in its
  own `mix.exs` (`systems/substrate.md`), and the check itself carries
  none: an allowlist compiled into a module that ships everywhere is
  Catapult's legal position imposed on codebases nobody here has read.
  Somebody still has to supply the sane starting value, and that is
  this layer's job rather than the check's — the elixir-target layer is
  what a generated project's `mix.exs` comes from, and it is already
  where the enforcement profiles live.

  **Literally, and this is the whole of the decision.** The five
  identifiers are emitted as data in the project's own file, readable
  and editable in place; never as a call into a shipped module that
  resolves them, which would put the constant back inside the check
  with an extra hop and leave a project unable to read what it is being
  held to. A project that edits the list is not evading a gate, it is
  stating a policy — the distinction `systems/substrate.md` records
  against the per-dependency waiver, which stays refused.

  Nothing here exists yet: `bundles/` arrives in Phase 3 and the check
  lands before it, so this is recorded now for the ticket that builds
  the layer rather than built now. Until then the only project on the
  path is `components/substrate`, which states its own list by hand
  because it is not a generated project.
- **A generated project's `mix.exs` declares `boundary: [default:
  [type: :strict]]`, not an apps list** (ORC-50), and this is recorded
  now for the same reason the entry above is: the layer does not exist
  yet, and the obvious move when it does is to copy the plane's own
  block, which would be copying a workaround along with it. Catapult
  runs `check: [apps: [...]]` because `components/substrate` is a
  **path** dep and Boundary drops a path dep's boundaries from its
  cached view (`systems/foundation.md`, measured twice). A generated
  project fetches substrate from hex like any other package, so the
  defect has no purchase there and strict is simply available —
  and strict is the better artifact: it needs no list, so it cannot
  have an incomplete one, and `Catapult.Audit.BoundaryApps` is inert
  against it and says so on every green run rather than auditing a
  declaration the project was never asked to maintain. The plane's list
  is the exception that a defect bought, and exceptions are not what a
  generator emits.
- **Stubbing is the instructed pattern for externally-gated scopes**
  (v5 §2.16): the arch and impl prompt material tells the generator —
  design the contract fully, type it opaquely, stub the
  implementation, declare `implementation: stubbed` with its exit
  plan. An agent improvising a stub without the declaration is a
  prompt bug, not an agent judgment call: undeclared stubs are
  exactly the silent half-implementation the doctrine forbids.

- **The architecture chain is the full backend family, mint-then-
  articulate at every fan-out** (ORC-84). Order: `feature_expansion`
  → `requirements` → `resp` (projection) → `sysarch` → `comp`
  (projection) → `comparch` → `subcomp` (projection) → `subcomparch`
  → `impl`, plus the pools `policy`, `vocab`, `ref`. `sysarch` is its
  own tier — a decomposition is a distinct cognitive act from
  requirements' rotation, with its own prompt and failure mode;
  folding it into resp asks one prompt to do two jobs (a previous
  ORC-7 pass made exactly this mistake and it is not repeated here).
  `comp`/`subcomp` are projection tiers (no draft, no prompt,
  `generator: synthesis`), minted by the `decomposition` edge's
  sysarch→comp and comparch→subcomp instances (one edge name, several
  sites sharing the mechanism — dsl-syntax.md §4.1's `instances:` form;
  `edges/decomposition.yaml`) from their parent decomposition's row.
  `resp` gets the same treatment: v5 restores it as a real tier
  (`seed-docs/README.md`'s first known delta) by minting one node per
  atom `requirements` emits (`decomposition`'s requirements→resp
  instance), rather than leaving each atom a field inside
  `requirements`' own body the way v4 did — what
  restoring it as a tier buys is a stable target for `fulfills` and
  for a policy scoped "through responsibilities" (v5 §4.5) to survive
  a sysarch re-decomposition.
  **No `kind: domain | presentational`, no `domain_parent` edge, no
  `fanin` tier, and no replacement edge minted in its place.**
  `seed-docs/README.md`'s second known delta replaces that whole
  mechanism with v5 §4.1's product/backend/frontend split, which is a
  tier-level split (product tier, frontend architecture tiers) rather
  than a `kind:` attribute on a backend component — this chain, being
  backend-only, never needs it; every component `sysarch` mints is
  simply a component. `domain_parent`'s only job in v4 was letting a
  presentational comp read its domain parents' fan-in synthesis —
  with no presentational kind and no fan-in tier, that job has no
  successor to
  wire, so none is invented speculatively; a frontend/product-side
  parent-link edge (if one turns out to be needed) is Phase 5's
  decision when the frontend tiers it would serve actually land, not
  this ticket's to guess at.

  **Siege's two sysarch techniques go with it, and are not reinvented
  one level down.** The `<kind>` decision test ("would deleting this
  component lose state or business logic, or a way to expose them to
  outsiders?") and the ownership-vocabulary self-check (watching for
  `persist`, `atomically`, `commit`, `transaction`, `event log`
  leaking into a presentational component's contract) both need two
  components in one graph with two vocabularies — one owning state,
  one fronting it. This chain has only the first, so the decision test
  has nothing to sort between and the leak check has no other contract
  to have leaked from. Comparch's subcomponents are not that split
  either: they divide on data/operation seams (writer, reader, cache)
  that are all equally domain, so a subcomponent claiming "commits
  atomically" is not borrowing someone else's ownership vocabulary —
  there is no non-owning role for it to borrow from. A same-shaped
  check built there would be a guess wearing a port's clothes, and the
  worry underneath it — contract text making a claim it does not back
  — already has stronger mechanisms in `comparch.md.liquid`: "Names
  create semantic obligations" and the "Rationale, not inventory"
  final scan. What *did* generalize is ported rather than dropped: the
  named anti-pattern list and the wrong/right worked examples live in
  `sysarch.md.liquid`'s naming and purpose rules, since a generic
  shell name and a purpose that parrots a larger scope are failures
  any component can commit, backend or not.
  **The `<owns>` block's un-fanned-out escape does not carry
  forward.** v4 let a comp with no natural subcomponent split skip
  fanning out to subcomponents entirely (impl attaching directly to
  the comp); expressing that as a scope needs a union this ticket's
  closed scope-expression set (`singleton | per(X) | child_of(X)`,
  dsl-syntax.md §3.1) has no form for (`per(subcomp) OR per(comp where
  count(subcomponents)==0)`). Dropped as a content simplification, not
  carried forward silently: `decomposition`'s comparch→subcomp
  instance declares `source: {min: 1}`, making every comp fan out into
  at least one subcomponent.
- **A second intake root, `non_goals`, mints distilled non-goal policy
  nodes ahead of the architecture chain proper** (v5 §1.1, §4.5, the
  negative-space doctrine). `feature_expansion` stops being this
  chain's only tier reading raw input prose: `non_goals` sits beside
  it as a second `scope: singleton`, `generator: llm` root, context
  `input.*` (the whole raft — the prompt is written to depend on it
  being present) plus `input.non_goals` (the tagged-document role,
  strong signal when the raft carries one). Neither form can block
  readiness, and the two are alike in that rather than contrasting:
  since ORC-107, `input.<role>` and `input.*` both resolve to
  `{:ok, []}` when nothing is pinned under that role, fold vacuously
  satisfied through `walk_ready?`, and never block a tier's readiness
  (`dsl-syntax.md` §7, `systems/engine.md`'s standing decision). The
  two roots name no `context:` entry on each other — a raft's negative
  space is read from the same frozen input prose either root reads,
  never from the other root's own drafted output, so nothing sequences
  one behind the other and both are ready the moment intake pins the
  raft. Its own `non_goals_review` counterpart puts the whole extracted
  set in front of the author through the ordinary draft→review→approve
  gate loop — no new review mechanism. Declining is declining the
  batch: the same all-or-nothing shape every other fanout-minting
  tier's authored block already has (`sysarch`'s `<policies>`,
  `comparch`'s `<subcomponents>`), and a decline naming one candidate
  to drop is answered the way every other tier's decline is — a
  comment naming the candidate, reaching the regenerating pass as
  ordinary `feedback` prose (`dsl-syntax.md` §9), never a
  per-candidate accept/reject affordance, which this pool has never
  had and this ticket does not add. Separately, the worry this answers
  ("dropping it silently means the next intake of the same raft
  proposes it again") does not arise: intake is one function
  called at most once per project (`systems/delivery.md`'s ORC-107
  entry), so there is no second intake of the same raft to re-propose
  from.

  `non_goals` mints straight into the `policy` pool through a third
  `decomposition` instance — the identical mechanism the flat-pools
  entry below already documents for `sysarch`'s and `comparch`'s own
  `<policies>` blocks, not a new edge and not a new node kind (this
  ticket's own governing constraint, echoing v5 §4.5: "a separate
  non-goal tier would be the policy tier with the sign flipped"). The
  flat-pools entry below carries what's new in the minted shape itself
  — the grain restriction, the revisit-condition field, and what
  reading the result back still cannot do.

  **One root, not two, and no second grain at intake.** The raft may
  well argue for a responsibility- or component-scoped refusal, not
  only a project-global one, but grains two and three
  (`policy_application`'s policy→resp and policy→comp instances) need
  a `resp` or `comp` id to scope through, and intake mints neither —
  nothing has been decomposed yet when `non_goals` runs, by
  construction (it is a chain root). A scoped refusal is real and
  expected; it enters the way v5 §1.1 already settles for every
  post-intake non-goal — as an ordinary policy node via a ticket, once
  the `resp` or `comp` it scopes through exists to reference. The same
  reasoning excludes the stub-grade attachment §4.5 gives an
  "implementation-shaped" deferral (§2.16): that grade attaches to a
  per-scope `<implementation>` block on a `comp`/`subcomp` that, at
  intake, does not exist either. Nothing distilled at intake can be
  implementation-shaped for the identical reason nothing distilled at
  intake can be resp- or comp-scoped.
- **This chain is one of four families sharing the same mint-then-
  articulate shape** (v5 §5.1): UI (`ui_coll → ui_collarch → ui_subcomp
  → ui_subcomparch → impl_ui`), screen (`screen_coll → … →
  impl_screen`) and client (`client_comp → … → impl_client`) each
  fan out the same way this backend chain does, behind their own tier
  files. Backend's own terminal tier stays bare `impl` until it has
  siblings to be qualified against — it takes the family-qualified
  name `impl_backend` once the other three exist. UI and screen land
  in Phase 5 with `frontend_sysarch`; client lands in Phase 7 with its
  consumer, `platform-client-ts` (`systems/client_ts.md`).
- **Fragment ownership is 5 kinds at `comp`, 3 at `subcomp`** (ORC-84,
  confirming the previous pass's own correct call — kept rather than
  re-litigated). `comp` owns `techspec`, `pubapi`, `privapi`,
  `policies`, `failure_surface`, all written by `comparch`. `subcomp`
  owns only `techspec`, `pubapi`, `privapi`, written by `subcomparch`:
  siege's own `subcomparch` grammar has no `<policies>` or
  `<failure-surface>` section — policy reachability is transitive
  from the owning comp's policies, and failure modes route
  through pubapi's typed return shapes instead. The fragment
  vocabulary in `bundle.yaml` stays 5 kinds either way (dsl-syntax.md
  §2's per-bundle closed set is over kinds, not over which tier owns
  which); what's tier-specific is which kinds a given tier's
  `handle.fragments:` and `produces:` actually name.
- **`ref`/`vocab`/`policy` are flat pools, not singleton nodes**
  (v5 §4.5, ORC-84). `vocab` is `child_of(feature_expansion)`, minted
  by `decomposition`'s feature_expansion→vocab instance from the
  `<vocabulary>` block's flagged candidate terms (name + scope, not a
  full definition — see the content-delta entry below); `policy` is
  `child_of(sysarch)` with three `decomposition` mints (sysarch→policy
  from sysarch's project-level `<policies>`, comparch→policy from
  comparch's component-local `<policies>`, and non_goals→policy from
  the distilled intake set's own candidates, above; three fanout
  instances into one flat pool is legal under the loader, since
  `Catapult.Dsl.Tier`'s scope check only requires `child_of(X)` to
  name a *declared* tier, not the sole edge targeting it); `ref` is
  `scope: singleton`, read the same loose way ("the pool", not "the
  one node") since `identity: id` over a literal singleton would be
  meaningless and refs are things that accrete via a write tool, never
  minted by a fanout edge at all. **`ref` may attach anywhere, any
  parent, any child** — v4's "comparch and below" restriction loosened
  to a general rule: no per-use kinds, no special-case lifecycles. The
  attachment sites (`edges/reference.yaml`'s three instances —
  comparch, subcomparch, impl, one edge name per dsl-syntax.md §4.1)
  are wired only where content is actually consumed, matching v4's
  own choice of sites — the looser rule is about the `ref` tier's own
  shape carrying no restriction, not a mandate to pre-wire every tier
  against a need nothing has yet. `reference` is its own edge name
  rather than an instance of `fulfills`, `dependency`,
  `domain_parent`, `decomposition` or `policy_application`: ref
  attachment is not a mint, not the comp↔resp binding, and not a
  policy scope grain, and folding it into one of those would misname
  the mechanism rather than honor "same mechanism, one name".
  **Policy scoping is v5 §4.5's three grains, never `child_of(resp)`**:
  project-global (no scope edge — a `<policy>` with neither `<required>`
  nor `<structural/>`, read via `all.policy` when a tier genuinely
  needs the unscoped grain — dsl-syntax.md §7.2), through-
  responsibilities (`policy_application`'s policy→resp instance — the
  load-bearing grain, since a policy bound to a resp survives a
  sysarch re-decomposition instead of being re-typed by hand), and
  direct component links for genuinely structural policies
  (`policy_application`'s policy→comp instance — grammar siege lacks:
  its own `<policy>` element only ever names a resp id via
  `<required>`; the `<structural/>` marker in `schemas/sysarch.xsd`
  and `schemas/comparch.xsd` is what a policy declares instead,
  mutually exclusive with `<required>` by the grammar's own
  `xs:choice`, never both). Both are instances of one
  `policy_application` edge (dsl-syntax.md §4.1).
  **The through-responsibility read is wired.** A one-hop context
  grammar that cannot reach a grain is a missing construct to propose
  in `dsl-syntax.md`, not a reason to leave the load-bearing grain
  unread; §7.1's hop chains and reversed hops (`.<edge>~`) are that
  construct: `comparch.yaml` reads `self.parent.policy_application~ ->
  policy.handle` (direct grain, one reversed hop) and
  `self.parent.fulfills.policy_application~ -> policy.handle`
  (through-responsibility grain, forward then reversed), and both land
  in one `policy` collection (dsl-syntax.md §9). No new edge is needed
  — `policy_application`'s two instances already carry both grains in
  their declared direction; reversal reads them backward at walk time.

  **A distilled non-goal mints project-global, grain one, only — and
  the schema says so rather than the prompt.** The `non_goals` tier's
  own policy-analog element carries no `<required>`/`<structural/>`
  choice at all, unlike `sysarch`'s and `comparch`'s `<policy>`: at
  intake there is no `resp` or `comp` id either grain could reference,
  so the grammar that would let a model invent one is simply absent,
  the same "enforced by the grammar, not a boolean flag" posture the
  `xs:choice` above already takes for the other two grains.

  **The revisit condition is one optional, free-text element on every
  `Policy` shape.** `bundles/default/tiers/policy.yaml`'s `fields:`,
  both `<Policy>` complex types (`schemas/sysarch.xsd`,
  `schemas/comparch.xsd`) and the distillation schema carry it — the
  first two for the general case v5 §4.5 states: any policy can be an
  argued deferral, not only a distilled one. "Never, argued" and "not
  until X" are values of that one field, per §4.5, never two shapes:
  an ordinary policy simply omits it, and a deferral's prompt guidance
  is to always fill it, whichever value applies. No closed vocabulary
  gates the value — "never" carries no schema-level meaning beyond
  being the text an author or model writes to argue permanence,
  consistent with the free-form posture this whole doctrine already
  takes (v5 §1.1: no closed non-goals registry, no required file).

  **No policy in this chain declares a grade, distilled or authored.**
  §4.5's promote-from-prose ladder and its enforcement-ticket machinery
  are unbuilt entirely, so a distilled non-goal carries none either —
  it is exactly as ungraded as every other policy this chain ships.
  `prose` is what an absent grade means operationally; the enforcement
  ladder above `prose` arrives with its consumers, unrelated to
  distillation.

  **`all.policy` reads every scope indiscriminately, so the
  project-global grain is not added to any scoped tier's context.**
  `comparch.yaml`'s own comment records why: `all.policy` is
  unfiltered by construction (dsl-syntax.md §7.2) and would return
  every resp- and comp-scoped policy too, indiscriminate noise next to
  the grains a tier already reads explicitly. A scope-filtered "only
  the unscoped grain" read has no expression in this DSL, and supplying
  one is a `core_dsl` question, not bundle content. A consumer that
  wants `all.policy`'s indiscriminate reading on its own merits
  (reconciliation, whose job is project-wide by nature, is the
  plausible first taker) wires it itself.
- **`mint.<name>` is the field source for every join-target tier**
  (`comp`, `subcomp`, `resp`, `policy`, and the mint-time identity
  fields on `vocab`) — `docs/dsl-syntax.md` §3 gains the convention in
  this ticket's diff, closing the gap `seed-docs/README.md` flagged:
  a tier with no `draft:` still needs a field source, and `mint.<name>`
  names the minting fanout edge's `declared_in:` row (or, for a value
  inherited from a grandparent one hop further than a single walk
  reaches — `comp`'s `project_techspec`/`project_policies_summary`
  copied from `sysarch` at the same mint moment — a plain copy made at
  mint time). Both are engine-side resolution, unvalidated at load
  time exactly as `draft.<name>` already is.

- **Five flows ship, not six** (ORC-84): `feature_request`, `refactor`,
  `bug_fix`, `downward_propagation`, `upward_propagation`. `plan_change`
  is the one flow v5 voids outright — it exists solely to recompute
  phase assignment and cascade phased-tier regeneration, and v5 §6
  drops the phase machinery it operates on wholesale ("dropped from
  v4: ...the plan-change flow"). The other five carry no phase
  dependency in v4 either and are ported: four walk
  `downward_cascade`, `upward_propagation` walks `up_then_down` (the
  one place this bundle uses the second walk primitive).
  `upward_propagation` is further simplified from v4's two-stage
  `assessment_plan` + `propagation_plan` to one combined planning
  tier, since sequencing two flow-scoped tiers needs instance-level
  flow-state ("has the upstream stage closed yet") that only
  projection-time instance checks could supply. Flow instance state
  becoming a real, checkable loader or engine concept is what would
  reopen the two-stage split, on its own merits rather than under a
  content port.

  **Each flow's planning tier mints one `cascade_visit`-scoped node
  per node the flow's cascade actually visits, not one `singleton`
  node per open instance.** v5's closed scope set had no kind standing
  for "whichever tier this cascade is currently visiting" the way v4's
  informal `scaffold_tier` did, and a missing scope kind is a
  `dsl-syntax.md` proposal — the same move `mint.<name>` made — not a
  reason to ship without the capability. `cascade_visit` (dsl-syntax.md
  §3.1) is that kind (`systems/core_dsl.md` records the grammar side);
  every `<flow>_plan` tier uses it, and `edges/plan_target.yaml`
  supplies the live pointer from a plan instance to the specific
  scaffold node it is planning for. Completion follows the same shape:
  `all(<flow>_plan -> resolved)` (`predicates.yaml`) reads "every
  visited node's plan has resolved," the universal quantifier over the
  tier's own name as path root (dsl-syntax.md §8's addendum) — not
  v4's `count(open_visit) == 0`, which is unparseable under
  `lib/catapult/dsl/predicate.ex`'s grammar (no `open_visit` edge, no
  `decomposed_by(...)` call), and not a single-node `resolved == true`.

  One gap remains open and is *not* a grammar question: no planning
  tier reads `ticket.findings` (dsl-syntax.md §7's "ticket thread for
  the scope", v5's replacement for v4's dropped `seed:` block) —
  `lib/catapult/dsl/dialect.ex` registers no context-source extension
  in either dialect, so declaring it fails load — measured, not
  assumed. What is missing is a registration rather than a grammar:
  `ticket.findings` already parses and is already spec'd, and what it
  needs is a platform module implementing
  `Catapult.Dsl.Extension`'s `context_sources/0` and registering
  `"findings"`. That is `core_dsl`'s delivery-system milestone —
  plane extension code, not bundle content. Every planning tier reads
  `input.project_doc` instead, which is the frozen original intake,
  not the flow's own new prose.

  `feature_request`'s planning-tier prompt is
  `seed-docs/siege-prompts/propose_feature.md`, ported close to
  verbatim (real source, real content). The other four have no siege
  source — only prose describes them, with no shipped prompt — so
  their planning-tier prompts are authored fresh and kept
  proportionately small rather than padded to match
  `feature_request`'s length.
- **The `modify_*` prompts fold into each tier's own generation
  prompt as a `{% if feedback %}` section, not into the flow
  layer.** `seed-docs/siege-prompts/modify_sysarch.md`,
  `modify_comparch.md`, `modify_subcomparch.md` are not referenced by
  any ported flow or tier declaration (confirmed: zero hits for
  `modify_` in either vendored v4 document outside the file
  listing) — they are
  siege's own generic "surgical diff against targeted feedback"
  variant, orthogonal to which flow (if any) produced the feedback.
  `dsl-syntax.md` §3's tier grammar has exactly one `prompt:` slot per
  tier, and §9 confirms a tier's single template receives `feedback`
  as a variable on every regen, review or not — there is no second
  "modify" template slot in the grammar, and inventing one would be
  new DSL surface a content-porting ticket has no mandate to add. The
  shared discipline (surgical modification, sticky sections) lives
  once in `prompts/partials/_architecture_framing.md.liquid`'s own
  `{% if feedback %}` block; each of `sysarch`/`comparch`/
  `subcomparch`'s own prompts carries the tier-specific "preserve
  this, when the feedback says X do Y" content from its matching
  `modify_*.md` source in its own `{% if feedback %}` section.
  `impl`, `feature_expansion`, `requirements`, `vocab`, `ref` have no
  `modify_*` source and rely on the shared partial's generic framing
  alone.
- **`catapult.yaml` is created** (ORC-84), naming `chain: default` /
  `workflow: default-flow` — `core_dsl`'s file map already claims the
  path (ORC-5); this ticket supplies the content the map was left
  pointing at nothing for. `bundles/default/bundle.yaml` declares
  `extends: platform-elixir`, so a minimal `platform-elixir` stub
  (empty tier/edge/flow lists, `kind: chain`) ships alongside it —
  otherwise the `extends:` reference is a load error. This is the
  smallest stub that makes the reference resolve; the elixir-target
  layer's real content (convention grammars, template tiers,
  enforcement profiles) is a separate ticket's job. The platform-wide
  review grammar (`schemas/review.xsd`) lives on this stub layer per
  this ticket's own instruction — worth noting for a future reader
  that nothing in the Phase 3 loader (`lib/catapult/dsl/chain.ex`)
  actually checks a `draft.grammar` or `review.grammar` path resolves
  to a file at all yet ("prompt rendering, XSD body validation at
  commit" is this ticket's own stated out-of-scope), so this
  placement is not load-bearing today — it is the ticket-instructed
  shape, validated only as "does not break the loader," not as "is
  read by anything yet."
- **A review is a tier, not a nested `review:` block** (ORC-84;
  `docs/v5-design-decisions.md` §7.19). The eight LLM tiers —
  `sysarch`, `comparch`, `subcomparch`, `requirements`,
  `feature_expansion`, `impl`, `ref`, `vocab` — carry no nested
  `review: {prompt, grammar}` block; each has a sibling tier file
  (`tiers/<name>_review.yaml`) declaring `reviews: <name>` instead.
  `dsl-syntax.md` §3.3 documents the mechanism: a review tier's scope
  and cardinality are the reviewed tier's by construction (never
  restated), it carries no `draft:`/`produces:` (comments, not a
  commit), and its `context:` is restated verbatim and checked at load
  time against the reviewed tier's own `context:` — the per-tier triad
  invariant made a load-time property instead of a shared-assembly-code
  discipline. A review tier's delivery is `delivery: {phase: critique,
  agent_step: critique}`, not the reviewed tier's `delivery: {phase:
  generation, agent_step: design}` with the review read as an implicit
  wrapper; `tiers: [tiers/*.yaml]` in `bundle.yaml` globs the review
  files in, so the manifest names none of them.
  `bundles/platform-elixir/schemas/review.xsd` carries `<score>`
  (integer, 0-100) and `id` on `<finding>` — both load-bearing per
  `docs/v5-design-decisions.md` §7.19, and nothing in the review
  grammar gets trimmed. `dsl-syntax.md` §15.1's system-status table
  carries `critique`, and the loader's own closed set mirrors it —
  `Catapult.Dsl.SystemStatus.kinds/0` has `:critique` between
  `:generation` and `:fanout`, `agent_steps/0` has `:critique` between
  `:dev` and `:reconcile`.

- **A gate reads `depth: 0`; the architecture chain's `critique`
  entries read `depth: [2, 0]`** (ORC-92; `docs/v5-design-decisions.md`
  §7.19 carries the argument, `docs/dsl-syntax.md` §15.5 the form). A
  gate is a human sign-off and reads the top level however far the
  chain fans out beneath it, so fan-out reasoning never belongs on a
  gate — it belongs on the citing type's own `critique` entry. `[2, 0]`
  is the pair that follows: `2` for a project's first traversal,
  because the architecture chain's own deepest fan-out is two edges
  (`comp`, then `subcomp`), and `0` for every later traversal, which
  returns to the top level.

  **What this closes is silence, not a wrong number.** `critique` is
  opt-in and an absent entry is not a load error, so a chain declaring
  none ships its review tiers **inert** the moment the loader gains the
  form — nothing red anywhere, and no signal that eight review tiers
  stopped running.

- **Every `<flow>_plan` tier declares `fields: argument: draft.argument`,
  closing the gap `docs/dsl-syntax.md` §3's new reserved name leaves
  open by default** (ORC-114, design pass). A flow's planning tier —
  `feature_request_plan`, `refactor_plan`, `bug_fix_plan`,
  `downward_propagation_plan`, `upward_propagation_plan` — is already,
  by this doc's own "Five flows ship" entry above, the tier every one
  of these flows opens at (`FlowOpened.entry_node_id`), so it is the
  one tier per flow the work surface's `ticket` screen actually reads
  `fields["argument"]` off. It is also, already, the tier whose job is
  closest to stating one: `feature_request_plan`'s own prompt is the
  near-verbatim port of `seed-docs/siege-prompts/propose_feature.md` —
  a proposal is an argument by another name — and the other four are
  authored fresh in this same voice (above). Each of the five grammars
  gains a short `<argument>` element (one or two sentences, "why this
  work exists," not a restatement of the plan's own structured content)
  and each tier's `fields:` gains the one-line mapping; no tier outside
  this set declares it, so a fan-out child (`comp`, `subcomparch`, …)
  never carries its own argument distinct from its top-level ticket's —
  correct, since `docs/ui-spec.md` §3.1 only ever shows one, for the
  ticket the surface is currently open to.

- **A prompt guard on a possibly-omitted collection tests `.size > 0`,
  never bare truthiness** (ORC-134). Liquid counts an empty list as
  truthy — only `nil` and `false` are falsy — so `{% if feedback %}`
  opens its section on every render the moment a caller passes `[]`
  instead of omitting the key. The shared `partials/_architecture_framing`
  carries the guard once; `sysarch`, `comparch` and `subcomparch` each
  carry their own second copy, guarding the tier-specific "preserve X,
  when the feedback says Y do Z" content the partial doesn't have
  (below) — the rule is about the spelling, not about which copies
  fire, so it reaches all four. It generalizes further still: it is
  the bundle-authoring rule for any future prompt gating on a
  collection.

  **It is a rule spanning two trees, which is why it is recorded here
  and not only in the code.** `Catapult.Generation.ContextAssembly`
  omits `feedback` on `[]` rather than emptying it, and a guard correct
  *only* because of that promise is one plane-side refactor from
  silently opening — a second renderer or a hand-built fixture would do
  it too. The plane keeps the omission and the bundle guards
  independently, on purpose, and neither half is redundant with the
  other. Each carries its own reason where it would be edited: the
  templates' own `{% comment %}` blocks, and `ContextAssembly`'s
  moduledoc. The Solid mechanics behind the spelling live there too,
  including why a filter pipe is not available inside a conditional
  under `Solid.parse/1`. `test/catapult/generation/context_assembly
  _test.exs` holds the four copies above against all three shapes —
  these are the suite's claims to keep current, not the next reader's
  to re-derive by reading `deps/solid`.

  **Every `{% render "partials/_architecture_framing" %}` passes
  `feedback` explicitly, because `{% render %}` isolates the partial's
  scope from its caller's.** Solid's `RenderTag` (`deps/solid`) lets a
  caller's variables into a partial only through the call's own
  arguments — a `with`/`for` binding, or a plain comma-separated
  `key: value` list. A bare `{% render "partials/<name>" %}` leaves
  `feedback` outside the partial's scope, so its `{% if feedback.size
  > 0 %}` block never fires, on any tier or flow — which is how the
  partial's copy of this guard sat inert across all thirteen call
  sites in `bundles/default/{prompts,flows}/**` while masking two live
  defects (ORC-193). Each of the thirteen therefore reads `{% render
  "partials/_architecture_framing", feedback: feedback %}`. `draft` is
  not passed: it is generation-prompt-off-limits by `dsl-syntax.md`
  §9's own design
  (`Catapult.Generation.ContextAssembly.build_variables/5` sets it
  only for a review tier's own dispatch), and every one of the
  thirteen call sites is a generation tier, so the partial carries no
  `{{ draft }}` and no "Current draft is below" framing; its section
  is worded around what a generation-tier regeneration actually has:
  the feedback text, and the same upstream `context:` the tier's
  fresh-generation half already reads.

  The first defect the dead guard masked: a top-level guard that fires
  and then emits only static prose ("preserve everything the feedback
  doesn't ask you to change") never shows the model what the feedback
  said. A prompt's own guard reads `feedback` directly from
  `ContextAssembly`'s context rather than through the isolated
  partial, so it does fire — and a firing guard with nothing behind it
  is not the working half of anything; it is a second inert copy that
  merely fails silently instead of failing loud. That was the shape of
  all five shipped prompts' own guards (`vocab`, `ref`, `subcomparch`,
  `sysarch`, `comparch`): none interpolated `{{ feedback }}` at all.

  The second: a bare `{{ feedback }}` does not render the comment text
  either. `feedback` is a list of maps
  (`body`/`locator`/`author_id`/`posted_at`); Solid's list-stringify
  path flattens and `Enum.join`s, which calls `to_string` per element,
  and a bare Elixir map has no `String.Chars` implementation — verified
  directly against `deps/solid`: `{{ feedback }}` on a non-empty list
  raises `Protocol.UndefinedError`, not a wrong rendering. So passing
  the variable through and leaving the partial's interpolation as
  written would have turned "the model never sees feedback" into
  "generation crashes the first time any node carries feedback" — a
  regression the partial's dead guard was accidentally shielding
  against. **A `feedback`-shaped collection is rendered via
  `{% for entry in feedback %}`, printing the fields the model needs
  (`entry.body`, `entry.author_id`, `entry.posted_at`), never
  interpolated bare** — the same "spelling, not which copies fire"
  generalization the `.size > 0` rule above makes, extended to cover
  what a collection guard's own body does once it opens.

  That rule is the suite's to hold, not the next reader's to re-verify
  against `deps/solid`. `context_assembly_test.exs`'s direct-render
  harness (`Solid.parse/1` + `Solid.render/3` against the real
  `bundles/default/prompts` tree, cited above) parses and renders the
  partial file itself against the same populated shape it drives
  through the guarded templates — `%{"feedback" => [%{"body" =>
  "..."}]}`, string-keyed because that is what Solid resolves against
  — asserting the `{% for entry in feedback %}` loop renders each
  entry's fields. That is the coverage a bare `{{ feedback }}` would
  fail, which is what makes the spelling above a checked rule rather
  than a remembered one.

  Three shipped prompts carry a guard of their own: `sysarch`,
  `comparch` and `subcomparch`. Theirs sits at a different location in
  the file from the partial's render call at the top, so the partial
  firing there doesn't reach it, and it is trimmed to only the
  tier-specific "preserve X, when the feedback says Y do Z" bullets
  ported from their `modify_*.md` sources — the generic preamble is
  the partial's single copy. `vocab` and `ref` carry none: theirs
  duplicated the partial's generic framing without showing the
  feedback either, and the partial reaches them.

  **What this does not close.** Even with the feedback text visible,
  "preserve every alias, dep edge and policy the feedback doesn't
  touch, verbatim" — the tier-specific content `sysarch`, `comparch`
  and `subcomparch` keep — asks the model to round-trip a body it is
  never shown: `draft` stays off-limits to a generation tier's own
  prompt, so nothing gives the model a baseline to preserve *against*.
  Closing it means either admitting `draft` to a generation tier's
  prompt specifically when it is regenerating over feedback —
  narrowing, not repealing, §9's "review-tier alone" rule — or
  replacing the verbatim-preservation instruction with something
  achievable without it. It is a standing-invariant question spanning
  `dsl-syntax.md` §9/§3.3, `systems/generation.md`'s own restatement
  of the same rule, and this doc, not a call-convention fix, and it is
  named here rather than carried forward silently as unenforceable
  prompt text.

- **`partials/_review_framing` has the same scope-isolation defect
  ORC-193 fixed on the generation side, and every review tier carries
  it** (ORC-201; `docs/dsl-syntax.md` §9). The partial opens "You are
  reviewing the draft below," and all eight `review/<tier>.md.liquid`
  prompts render it as a bare `{% render "partials/_review_framing" %}`.
  Bare `{% render %}` isolates scope, so `draft` never entered the
  partial and the draft was never below anything: every review
  dispatch in the chain asked a model to judge an artifact it was not
  shown. `Catapult.Generation.ContextAssembly.build_variables/5` does
  supply `draft`, and only to a review tier's own dispatch — the
  variable was present at the call site and dropped at the boundary,
  which is why nothing failed loudly.

  The fix is ORC-193's, applied to the other partial: all eight call
  sites pass `draft: draft` explicitly, and the partial prints it
  under a "Draft under review:" heading. `draft` is a plain string
  (`draft_variable/2` returns the body or `""`), so it interpolates
  directly rather than needing the `{% for %}` form
  `_architecture_framing` gives `feedback` — the distinction the
  ORC-193 entry above draws between a scalar and a collection, applied
  rather than restated.

  **`prior_review` is the same gap and closes with it.** It is
  supplied to the same dispatch, rendered by nothing, and it is a map
  (`score`/`findings`/`kind`/`body_sha`) — so the eight call sites pass
  it too, and the partial renders the score and iterates the findings.

  Two spellings in that block are decided by measurement rather than by
  symmetry with `feedback`, because both differ from it. The guard is
  bare `{% if prior_review %}`, not `.size > 0`: `prior_review_variable/3`
  omits the key entirely when there is no prior review, and a map is
  not a list, so nothing here can be the empty-list-is-truthy trap
  ORC-134 records. And the findings are iterated rather than
  interpolated: `{{ prior_review.findings }}` on a list of maps raises
  `Protocol.UndefinedError` — reproduced directly by breaking the loop
  and watching the suite fail on it, which is the same failure the
  ORC-193 entry above predicts for `feedback` and the first time this
  repo has held that prediction to a test.

  **The keys are string-keyed, measured rather than inferred.** The
  write path builds findings atom-keyed
  (`Catapult.Generation.CommitPath`'s own `review_findings/1`) and
  `feedback_variable/3` converts by hand for exactly that reason, two
  functions above `prior_review_variable/3`, which does not. It does
  not need to: the column is `{:array, :map}`, so the value crosses
  jsonb, and `%{id: "f1"}` reads back `%{"id" => "f1"}` — the atom key
  is unreachable and `entry.id` resolves. The store round trip performs
  the conversion the sibling function performs explicitly, which is why
  the asymmetry between them is not the bug it looks like.

- **Every `agent_step: design` tier's `delivery.phase` across
  `bundles/default/tiers/**` stays uniformly `generation` (never
  `design` or `architecture`), because that phase is a tier-level echo
  of a distinction the work-item *type* declaration owns, not one a
  tier draws for itself.** This is narrower than "every tier" — the
  other agent-step family, `critique`, pairs uniformly with
  `phase: critique` instead, an unrelated axis untouched by this entry.
  `dsl-syntax.md` §15.1 and v5 §7.6 name `design`, `architecture` and
  `implementation` as kinds a type's own lifecycle draws —
  `feature.yaml`'s generation sub-array splitting into a
  `design`-then-`architecture` pair, and the recursive architecture
  fan-out's own child type (`dsl-syntax.md` §15.11) reading the same
  kinds — not a distinction a tier makes independently of the type it
  fans out from. `delivery.phase` has exactly one reader in the tree,
  `Catapult.Dsl.Chain`'s load-time check that its value names a real
  system-status kind (`lib/catapult/dsl/chain.ex`), so nothing
  dispatches on which kind a tier picks. Tier values move together
  with that type-level split, never per-tier ahead of it: picking
  `design`/`architecture` for a subset of the `agent_step: design`
  tiers reading `phase: generation` (`grep -l 'agent_step: design'
  bundles/default/tiers/*.yaml` finds them all — the set grows as new
  families land, so this is the check rather than a count of it) would
  leave their siblings inconsistent against a split the type
  declaration has not drawn (ORC-179).

- **`bundles/platform-elixir/` folds into `bundles/default/`, and
  `extends:` retires from the DSL** (ORC-153;
  `docs/v5-design-decisions.md` §5.5, §6, §7.18; `docs/dsl-syntax.md`
  §11). The layer's only content, `schemas/review.xsd` — a
  platform-wide review grammar belonging to no language — lives in
  the chain bundle's own `schemas/`; nothing else was ever loaded onto
  the stub (the convention grammars, template tiers and enforcement
  profiles the ORC-84 entry above names for an elixir-target layer
  never shipped there). The workflow axis carries no base layer either
  (ORC-105), so `extends:` has no user on either axis: a chain bundle
  is a single directory of authored content, the same shape a
  workflow bundle has, and `extends:` is an unknown key on any
  bundle's manifest. **The bundle-relative content-path traversal
  guard is not part of what retires**: a `prompt:` or `grammar:` path
  is still checked against escaping its own bundle under
  single-directory path resolution, because that guard is about
  bundle-authored content being untrusted input, not about there
  being a second layer underneath to escape into.

- **`journeys`/`journey` and `screens`/`screen` land as two more
  spine-plus-projection pairs, the identical shape `requirements`/
  `resp` already has** (ORC-109; `docs/v5-design-decisions.md`
  §4.1-§4.3). Chain placement: `feature_expansion → journeys → screens
  → requirements → sysarch → …` — both new tiers sit `scope:
  per(feature_expansion)`, `context: [self.parent.handle]` (plus the
  additions below), one `generator: llm` draft authoring every
  instance in a single pass exactly the way `requirements` authors
  every `<responsibility>` in one draft rather than one LLM call per
  responsibility. `journey` and `screen` are each a bare
  `child_of(journeys)` / `child_of(screens)` projection — `mint.<name>`
  fields only, `generator: synthesis`, no draft, no prompt, no review
  — minted by two `decomposition` instances (`journeys.draft
  .journey[]`, `screens.draft.screen[]`), the same join-target shape
  `resp` already has relative to `requirements` and `comp` has
  relative to `sysarch`. **Not `vocab`'s shape**: `vocab` splits mint
  (a name+scope stub flagged by its parent) from articulation (vocab's
  own per-instance LLM call) because `feature_expansion`'s job is
  deliberately extraction-only (the comment on `feature_expansion.yaml`
  records why). Neither `journeys` nor `screens` has that reason to
  split — each is already the tier whose job is to fully author its
  rows — so the `requirements`/`resp` shape is the one that fits, not
  `vocab`'s, and `feature_expansion.xsd` carries no stub block for
  either. `journey`'s handle carries everything its mint row does
  (name/slug, argument, `feats`, the ordered screen-walk, the state
  block) rather than `resp`'s minimal `id, name, feats` — comp's own
  richer handle over resp's sparser one is the precedent for a
  join-target handle carrying more than identity when a downstream
  reader needs the body, and `screens` (below) is exactly that reader.
  `screen`'s handle is equally rich: slug, purpose, the named state
  list, the affordance list, displayed data, its own navigation edges,
  screen group.

  **`screens` also reads every already-minted `journey`**: `context:
  [self.parent.handle, all.journey.handle]`. `all.journey.handle` —
  the individual children, not `all.journeys.handle` — is the walk
  that actually reaches each journey's ordered screen-walk and state
  block; `journeys`' own handle, like `requirements`' own handle
  (`fields: [id, intro]`), carries no per-row content.

  `feature_expansion` and `screens` both carry `input.mocks` in their
  own `context:` — §4.1 names both; the entry below this block names
  the shape.

  This is also why `screens` cannot be `child_of(journey)`: a screen
  legitimately named by more than one journey's walk (`v5 §4.2`'s
  "screen belongs to 0..n journeys") would mint as two different nodes
  under a per-journey fanout, one per referencing journey. `screens`
  being `per(feature_expansion)` and authoring every screen
  (journey-driven and standalone alike) in the one pass that already
  sees every journey is what keeps the pool deduplicated without
  inventing any mint-time merge the loader doesn't have.

  **The ordered screen-walk stays informal, the same way `<feats>`
  already is** — a per-journey list of screen slugs inside `journey`'s
  own mint row, read but not loader-validated, matching every other
  feature-ish cross-reference in this bundle (features aren't a tier
  either, and nothing here promotes them to one). What *is* a formal,
  loader-checked graph fact is screen membership and IA navigation,
  because both sides are real tiers:
  - **`reference` gains three instances**: `source: journey, target:
    screen, declared_in: screens.draft.screen[].journeys.journey[].@ref`
    (screen belongs to 0..n journeys — declared on the `screens` side,
    the same way `dependency`'s comp→comp instance is declared inside
    `sysarch`'s own draft rather than either comp's; by the time
    `screens` runs, every `journey` node already exists, so this is an
    ordinary reference to already-minted nodes, never a forward
    reference to ones that don't exist yet — cardinality `source:
    {min: 1}` \[a journey walks through ≥1 screen\], `target: {min: 0}`
    \[standalone screens are legal\]), and `source: resp, target:
    journey` / `source: resp, target: screen` (requirements'
    integration point, below — both permissive, `{min: 0}` each side,
    since a backend-only responsibility grounds in no product surface
    at all) — three more sites under the one mechanism this edge
    already names, not a new edge.
  - **A new `navigation` edge**: `type: reference`, `navigation: true`,
    `source: screen, target: screen`, `declared_in: screens.draft
    .screen[].navigation.edge[].@to`, no `graph_constraint` — this is
    the edge `docs/dsl-syntax.md`'s v5 rule ("navigation edges \[…\]
    are cyclic-legal reference edges" and "must never appear in a
    readiness-bearing context walk") anticipates, and `screens` is
    where it is declared. Declared inside `screens`' own draft (same
    document as every screen it connects), so no forward reference
    here either.

  **Two more decisions follow from that shape:**
  - **`journeys` and `screens` each have a review tier**:
    `journeys_review` (`reviews: journeys`) and `screens_review`
    (`reviews: screens`) — the per-tier triad invariant applies to the
    two authored spines the same way it applies to `requirements`;
    `journey` and `screen`, like `resp` and `comp`, are projections and
    get no review tier of their own, because there is nothing there
    for a review to read that `journeys`'/`screens`' own review doesn't
    already cover.
  - **`requirements` stays `per(feature_expansion)`, and gains
    `all.journey.handle` and `all.screen.handle`.** Re-scoping to one
    requirements node per screen would fragment the rotation
    requirements exists to do — its whole job (seen already in
    `prompts/requirements.md.liquid`'s own framing, "features onto
    system-side axes: auth produces several…") is consolidating many
    surfaces into few cross-cutting responsibilities, which needs one
    pass seeing every surface at once, not one pass per surface.
    `<responsibility>` gains journey and screen reference blocks
    alongside its existing `<feats>` (kept — a responsibility can be
    grounded in a feature with no product surface yet, and `<feats>`
    is still the primary grounding); the requirements prompt is
    instructed to prefer citing a journey over a screen when a
    responsibility's feature is journey-backed, falling back to a
    direct screen reference for standalone screens (v5 §4.2's own
    "responsibilities prefer journey references" and "the bridge falls
    back to screen refs"), and the `reference` edge's resp→journey /
    resp→screen instances above are what those citations resolve
    against.

  **Screen groups vs. IA regions is settled in
  `docs/v5-design-decisions.md` §4.3 itself**, which records `screen
  group`'s semantics: a free-form signal into `frontend_sysarch`'s
  later IA-region grouping (§5.3), not the region itself and not a
  gate on it — §5.3's own "journeys are a signal, not a gate" rule
  extended to this field. `screen group` is a plain string in
  `screens`' grammar, validated against no vocabulary, so the
  settlement is semantics-only with no schema consequence for this
  tier.

  **Not the same "screen" as this repo's own.** `journey`/`screen` are
  chain tiers a *generated project's* product tier mints; Catapult's
  own `screens/*.md` is orchestration's native screen machinery and is
  unrelated (`docs/build-plan.md`'s own standing decision for the
  build, not a Phase 5 one: "Catapult's product tier … doesn't apply
  to Catapult itself"). No entry under `screens/` or `storybook/`
  exists for them for that reason — there is no UI screen here to
  define, only chain content, and chain content is dev's to write
  into `bundles/**`.

- **`feature_expansion` and `screens` gain `input.mocks`, closing the
  wiring the entry above deferred** (ORC-110, design pass;
  `docs/v5-design-decisions.md` §4.1). `feature_expansion`'s
  `context:` gains a second entry: `[input.project_doc, input.mocks]`.
  `screens`' gains a third: `[self.parent.handle, all.journey.handle,
  input.mocks]`. Both render as a plain `{{ mocks }}` string
  (`systems/generation.md`'s `ContextAssembly` entry — keyed by role
  name, omitted from the variables map entirely when the raft carries
  no `mocks`-tagged document), so both prompts need no explicit
  presence guard: a bare `{{ mocks }}` renders empty when the variable
  is omitted, the same unset-is-empty behavior `feature_expansion`'s
  own bare `{{ project_doc }}` already relies on
  (`bundles/default/prompts/feature_expansion.md.liquid`). This makes
  the hybrid case native rather than special, as v5 §4.1 requires: a
  raft with prose and no mocks omits
  the variable and reads exactly as it does today; a raft with mocks
  and no prose has `project_doc` omitted instead and `feature_expansion`
  still runs, extracting from mock evidence alone.

  **Mocks are read as source, not rendered.** The extraction tiers
  read whatever text or markup the raft pins under the `mocks` role,
  the same as any other input role. No tier depends on rendering a
  prototype, because no generation run can promise one: the chain's
  generation runs dispatch into the target project via
  `catapult-dispatch.yml`, whose harness-invocation step is an
  unpinned placeholder that exits 1 (`test/catapult/generation/
  fixtures/toy_seed/catapult-dispatch.yml`, "harness invocation not
  yet pinned — ORC-10") — it installs nothing because nothing is
  pinned yet, not because some fixed toolchain excludes a renderer. A
  mock set needing `npm install && npm run dev` to be legible is read
  as whatever static source it contains, the same as one that's
  already static markup. This settles the ticket's first open
  question: no runnable-target convention exists for a generation run
  to use, so every mock set is read as source.

  **No schema change for either tier**, because both extraction
  disciplines already carry the mechanism negative-space completion
  needs. `feature_expansion`'s `<implicit/>` marker
  (`schemas/feature_expansion.xsd`) already covers "the project
  obviously needs it but the user didn't name it explicitly" — mock
  evidence is one more source feeding that inference, not a new
  marker. `screens`' own prompt already instructs naming "narrower
  [state] names … whenever the screen's behavior at that state is
  genuinely different" (`prompts/screens.md.liquid`), and its review
  checklist already flags a `<displayed-data>` detail "visible in the
  mock" with no matching `<affordance>` (`prompts/review/screens.md
  .liquid`) — written by ORC-109 ahead of this wiring landing. Both
  prompts are instructed to weigh mock evidence against these existing
  rules: a mock set showing only a happy path doesn't excuse `screens`
  from naming `empty`/`error`/`loading`/`denied` when the feature
  narrative implies them, and doesn't excuse `feature_expansion` from
  flagging an `<implicit/>` feature that a mock's error or admin
  screen implies but its prose never states. Extraction completing the
  negative space is the chain improving the mocks, not transcribing
  them (v5 §4.1) — the instruction reaches both tiers, not just
  `screens`.

  **Review stays the tiers' own — no bespoke negative-space
  question.** An invented state or an `<implicit/>` feature is
  ordinary content in `screens_review`/`feature_expansion`'s own
  review the same as any other row; being chain-proposed rather than
  mock-evidenced changes nothing about what a reviewer checks, and
  `screens`' review checklist already reads the whole state list for
  exactly this (above). This settles the ticket's third open question
  against a new review gate: a second, dedicated pass over content the
  ordinary review already reads would be checking a thing already
  checked, not adding coverage.

- **`frontend_sysarch` mints both collection families in one pass, and
  the UI and screen families are each two authored tiers plus `impl`,
  the identical mint-then-articulate shape the backend chain already
  has** (ORC-111; `docs/v5-design-decisions.md` §5.1-§5.4;
  `docs/build-plan.md`'s Phase 5 entry). No entry under
  `screens/`/`storybook/` exists for these tiers, for the same reason
  `journeys`/`screens` have none: there is no UI screen here to define
  either, only chain content, and chain content is dev's to write into
  `bundles/**`.

  **Chain placement and per-family tiers.** `frontend_sysarch` is
  `scope: singleton` (the closed scope set — dsl-syntax.md §3.1 — has
  a real kind for exactly this: no `per(X)` parent it would otherwise
  need a context walk to reach), one `generator: llm` draft per
  project, reading `context: [all.journey.handle, all.screen.handle,
  all.sysarch.handle]` — three `all.<tier>` walks (dsl-syntax.md
  §7.2), no edge needed for any of them, the same no-owning-parent
  case `vocab`/`ref`/project-global `policy` already use.
  `all.sysarch.handle` is what makes reading the backend sysarch
  handle expressible at all: `sysarch` is `scope: per(requirements)`,
  a sibling of `frontend_sysarch` under no common fanout edge, so
  there is no `self.parent` walk between them — `all.<tier>` is
  exactly the mechanism this loader ships for a needed read with no
  walkable relationship, not a workaround.

  Each family is `<coll> → <collarch> → <subcomp> → <subcomparch> →
  impl_<family>`, the backend shape renamed per family: UI
  (`ui_coll`/`ui_collarch`/`ui_subcomp`/`ui_subcomparch`/`impl_ui`) and
  screen (`screen_coll`/`screen_collarch`/`screen_subcomp`/
  `screen_subcomparch`/`impl_screen`). `ui_coll` and `screen_coll` are
  `scope: child_of(frontend_sysarch)`, `generator: synthesis` join
  targets — no draft, no prompt, `mint.<name>` fields, excluded from
  dispatch by `ReadyScopes.generation_tier?/1` — the same shape `comp`
  already has relative to `sysarch`. `ui_collarch`/`screen_collarch`
  are `scope: per(ui_coll)`/`per(screen_coll)`, `generator: llm`, one
  articulation pass per collection, mirroring `comparch`. `ui_subcomp`/
  `screen_subcomp` are `child_of` their own `collarch`, synthesis join
  targets exactly like `subcomp`; `ui_subcomparch`/`screen_subcomparch`
  are `per(...)` their own subcomp, `generator: llm`, mirroring
  `subcomparch`; `impl_ui`/`impl_screen` are `per(...)` their own
  subcomp, `generator: llm`, mirroring `impl`. Fragment ownership
  follows the same 5-then-3 split the backend pair has (the ORC-84
  entry above: `techspec`/`pubapi`/`privapi`/`policies`/
  `failure_surface` at `*_coll`, written by `*_collarch`; `techspec`/
  `pubapi`/`privapi` at `*_subcomp`, written by `*_subcomparch`) — the
  fragment vocabulary is a bundle-wide closed set of 5 kinds, not a
  per-family one, so this is that rule applied, not a per-family
  choice. Every `generator: llm` tier in both families has a sibling
  `_review` tier (`frontend_sysarch_review`, `ui_collarch_review`,
  `ui_subcomparch_review`, `impl_ui_review`, `screen_collarch_review`,
  `screen_subcomparch_review`, `impl_screen_review`) the same way the
  eight backend tiers already do — the per-tier triad invariant applies
  identically, and there is nothing about a UI or screen collection
  that exempts it. Every `agent_step: design` tier among the above
  declares `delivery: {phase: generation, agent_step: design}`,
  uniformly, per the standing rule that `delivery.phase` stays
  uniformly `generation` for every `agent_step: design` tier until the
  work-item type declaration itself draws a `design`/`architecture`
  split (above) — none of these are that type-level declaration.

  **Backend's terminal tier carries its family-qualified name.**
  `bundles/default/tiers/impl.yaml` is `impl_backend.yaml` (`tier:
  impl_backend`), and `impl_review.yaml` follows it
  (`impl_backend_review.yaml`, `reviews: impl_backend`) — the name
  qualifies once another family's `impl` tier exists alongside it
  (ORC-106), and `impl_ui`/`impl_screen` do. No other backend tier,
  edge or prompt changes shape for this — the rename is a name, not a
  restructuring.

  **Minting two target tiers from one source is the loader's existing
  shape, not a new one.** `edges/decomposition.yaml`'s `sysarch`
  source already fans into two different targets, `comp` and `policy`,
  as two `instances:` entries under one edge name — "the same source
  fanning out to several different target tiers," in dsl-syntax.md
  §4.1's own words, describing exactly this shape and already
  load-bearing. `frontend_sysarch` carries two more `decomposition`
  instances the identical way: `source: frontend_sysarch, target:
  ui_coll, declared_in: frontend_sysarch.draft.ui_collections
  .collection[]` (`cardinality: source: {min: 0}` — a project may
  recurrence-seed no shared widgets — `target: {min: 1, max: 1}`) and
  `source: frontend_sysarch, target: screen_coll, declared_in:
  frontend_sysarch.draft.screen_collections.collection[]` (`source:
  {min: 1}` — every project's screens need at least one hosting
  collection, mirroring `screens`' own `{min: 1}` — `target: {min: 1,
  max: 1}`). `ui_collarch → ui_subcomp` and `screen_collarch →
  screen_subcomp` are two further `decomposition` instances, the same
  shape `comparch → subcomp` already has. `decomposition`
  (`bundles/default/edges/decomposition.yaml`) names `sysarch→comp`,
  `comparch→subcomp`, `feature_expansion→vocab`, `requirements→resp`,
  `sysarch→policy`, `comparch→policy`, `non_goals→policy`,
  `journeys→journey`, `screens→screen` and the four above — not a new
  mechanism at any of them.

  **The layering rule is enforced as load-time type-level acyclicity,
  not merely unviolated by omission.** A UI-collection-to-screen-
  collection edge is inexpressible, not just never declared.
  `systems/core_dsl.md`'s own standing decision records type-level
  acyclicity as a load-time check (libgraph, over the full
  edge-instance graph — dsl-syntax.md §13's "type-level acyclicity
  over the edge-instance graph," §4.1's "every instance still
  contributes its own `{source, target}` pair to the type-level
  acyclicity check … the graph is over sites, not over edge names").
  Two guarantees stack, not one: first, no edge instance anywhere in
  the bundle names a UI-family tier as `source` and a screen-family
  tier as `target` — the bundle simply carries no such site, so
  nothing downstream can walk that direction — and second, were a
  future bundle edit to add one anyway (mistakenly or not), the
  full-graph acyclicity check would refuse the *load* over it, because
  `screen_coll → ui_coll` (`renders`, below) already exists in the
  same graph and the two together are a cycle at the tier level. `v5`
  §5.1's "inexpressible" claim holds on both counts: absent by
  construction, and rejected by the loader if that ever stops being
  true.

  **Shapes vs. calls, wired as distinct edge names, not distinct
  instances of one name.** `dependency` already carries same-family
  sites (`comp↔comp`, `subcomp↔subcomp`); the UI and screen families
  carry the identical shape for their own same-tier deps — `ui_coll ↔
  ui_coll` (declared in `frontend_sysarch`'s own draft, project-wide,
  mirroring `comp↔comp`) and `ui_subcomp ↔ ui_subcomp` (declared in
  `ui_collarch`'s own draft, sibling-scoped, mirroring
  `subcomp↔subcomp`), and the same pair for `screen_coll`/
  `screen_subcomp`. The three **cross-family** edges v5 §5.4 names each
  take their own edge name instead of a further `dependency` instance,
  because the audit-relevant fact is *which family may declare which
  edge at all*, and a distinct name makes that a load-time
  cross-reference check rather than a convention someone has to
  remember to grep for:
  - `renders` (`type: dependency`), `source: screen_coll, target:
    ui_coll`, declared in `screen_collarch`'s own draft — a screen
    collection's own composition decision, made when that collection is
    fully articulated, the same moment backend's local `subcomp↔subcomp`
    deps are decided.
  - `uses_shapes` (`type: dependency`), `source: ui_coll, target: comp`
    (the backend join-target tier, the same target `comp↔comp`
    dependency already reads), declared in `ui_collarch`'s own draft.
    Only `ui_collarch`'s tier file ever declares this edge — no
    screen-family tier does, and no instance targets anything but
    backend `comp` — which is what makes "a UI collection reads backend
    shapes, never calls" a fact about which edges the *loaded bundle*
    contains, not only about what a generated file happens to do.
  - `calls` (`type: dependency`), `source: screen_coll, target: comp`,
    declared in `screen_collarch`'s own draft — symmetric to
    `uses_shapes`, and, again, the edge simply has no `ui_coll`- sourced
    instance anywhere, so a UI collection has no declared path to a
    backend call at all; the audit check for a backend function
    invocation inside a UI collection's file map — a layering violation
    — still catches a generated file that ignores its own graph, but
    the graph itself already refuses the shape.

  `screen_coll → screen` ("hosts") reuses `fulfills` rather than
  minting a fourth new edge name: a screen collection is the
  implementation locus for the screens it groups, the identical
  relationship `fulfills`' existing `comp → resp` instance already
  states for the backend ("this architecture node is the one that
  implements this responsibility"), and the cardinality matches exactly
  (`source: {min: 1}` — a collection must group ≥1 screen to justify
  existing, `target: {min: 1, max: 1}` — a screen is hosted by exactly
  one collection). `fulfills` is in `instances:` form to carry both.
  Declared inside `frontend_sysarch`'s own `screen_collections
  .collection[].screens.screen[].@ref` rows — the same pass that groups
  screens into collections is the one naming which screens land in
  which collection, so this is an ordinary reference to already-minted
  `screen` nodes (`screens` runs upstream in the chain), never a
  forward one.

  `screen_coll → journey` ("consumes journey state") is a `reference`
  instance, `declared_in: screen_collarch.draft.journeys
  .journey[].@ref`, both sides `{min: 0}` — a collection may consume no
  journey's live state, and a journey may back no screen collection
  directly (it already reaches its screens through the product-tier
  `journey → screen` reference `reference.yaml` already carries).
  Declared at articulation time, not mint time: which journeys a
  collection actually needs state from is a design decision for that
  collection's own pass, not a grouping fact `frontend_sysarch` can
  read off IA region alone. `ui_collarch`, `ui_subcomparch`, `impl_ui`,
  `screen_collarch`, `screen_subcomparch` and `impl_screen` each carry
  the same `reference → ref` attachment site backend's `comparch`,
  `subcomparch` and `impl` already have, and each carries `all.vocab
  .handle` in its own `context:` — both are the existing per-tier
  convention applied to six more tiers, not a new one.

  `ui_coll → design_system` ("primitives") is a further `dependency`
  instance, declared in `ui_collarch`'s own draft: `source: ui_coll,
  target: design_system`. `design_system` is its own tier, minting at
  most one node project-wide (ORC-110; `systems/core_dsl.md`'s
  "Deferred to the ticket that lands `frontend_sysarch`/`ui_coll`"
  entry), so the edge has a real target, and a project supplying none
  simply has no instance of this edge to declare — absence, not a
  zero-cardinality edge naming a node that doesn't exist.

  **No `policy_application` instances for either family.** A UI or
  screen collection fulfills no `resp`, so the through-responsibility
  grain has nothing to scope through — a direct collection-to-policy
  link would be speculative surface with no cited need behind it, and
  component-collection policy scoping is added only against a cited
  need.

  **No frontend/product-side parent-link edge replaces
  `domain_parent`** (the open item the ORC-84 entry above leaves to
  Phase 5). `fulfills`' `screen_coll → screen` instance and
  `reference`'s `screen_coll → journey` instance already give the
  screen family everything `domain_parent` was for — a link from an
  architecture node to the product-side surface it implements — and
  the UI family, having no product-tier counterpart of its own to link
  to, needs no such edge at all.

  **Screen groups vs. IA regions is settled at the ORC-109 entry
  above**, not here: `docs/v5-design-decisions.md` §4.3 records
  `screen group` as a free-form signal into `frontend_sysarch`'s own
  IA-region grouping, not the region itself and not a gate on it.

  **Not the same `system:` label this repo's own mutex uses, either.**
  v5 §5.4's `system:ui-avatar` / `system:scr-account` slugs name
  mutex labels a *generated project's* own per-collection systems docs
  will carry, once a real `frontend_sysarch` run groups real
  collections on a real project — the collection-level analogue of the
  "not the same screen as this repo's own" note above, and unrelated to
  how this repo's own `systems/*.md` file maps resolve `system:`
  labels (the pipeline protocol's own mutex resolution: a `system:`
  label derives from the mapped doc's filename, `systems/<name>.md` →
  `system:<name>`, not a stored mapping —
  `.pipeline/internal/filemap/filemap.go`). No entry in
  `pipeline.config.json` names or needs to name this convention: the
  file has no label-mapping section for either axis, mutex labels here
  resolve straight off `systems/*.md`/`screens/*.md` file maps, and
  nothing about a *generated project's* own future label scheme
  touches that file at all.

## Initial vs target

Initial (Phase 3): default bundle's upstream tiers + ported prompts,
platform-elixir grammar skeletons. Target: full tier set including
product tier, `frontend_sysarch`, and the UI and screen families
(Phase 5), delivery declarations and the client family (Phase 7),
runtime-dialect example content (Phase 8).

## Depends on

core_dsl defines what these files may say; generation renders them.

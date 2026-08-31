---
paths:
  - bundles/**
---

# platform_content

The bundle *content* the DSL loads, across **both bundle axes** (v5
§7.18):

- **chain axis** — `bundles/platform-elixir/` (the elixir-target
  layer: convention grammars, template tiers, enforcement profiles)
  and `bundles/default/` (the software-design chain: tier
  declarations, edges, and the prompts ported from SiegeEngine).
- **workflow axis** — the platform workflow layer, carrying the
  default review sequence (a UX review and an engineering review) and
  the default `dev`/`staging` environments.

**Delivery declarations moved off the elixir layer** (v5 §6, corrected
at §7.18): shipping them from the language layer welded the workflow
vocabulary to one target stack, which is exactly what the two-axis
split exists to prevent. They ship from the workflow layer instead,
and the two layers are never `extends:`-related.

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
  `child_of(sysarch)` with two `decomposition` mints (sysarch→policy
  from sysarch's project-level `<policies>`, comparch→policy from
  comparch's component-local `<policies>` — two fanout instances into
  one flat pool is legal under the loader as implemented today, since
  `Catapult.Dsl.Tier`'s scope check only requires `child_of(X)` to
  name a *declared* tier, not the sole edge targeting it); `ref` is
  `scope: singleton`, read the same loose way ("the pool", not "the
  one node") since `identity: id` over a literal singleton would be
  meaningless and refs are things that accrete via a write tool, never
  minted by a fanout edge at all. **`ref` may attach anywhere, any
  parent, any child** — an author decision loosening v4's "comparch
  and below" restriction to a general rule: no per-use kinds, no
  special-case lifecycles. This pass wires the attachment sites
  (`edges/reference.yaml`'s three instances — comparch, subcomparch,
  impl, one edge name per dsl-syntax.md §4.1) only where content is
  actually consumed today, matching v4's own choice of sites — the
  looser rule is about the `ref` tier's own shape carrying no
  restriction, not a mandate to pre-wire every tier against a need
  nothing has yet. `reference` is not among this ticket's own named
  five edges (`fulfills`, `dependency`, `domain_parent`,
  `decomposition`, `policy_application`), and folding ref attachment
  into one of those five to hit the literal count would misname the
  mechanism rather than honor "same mechanism, one name": ref
  attachment is not a mint, not the comp↔resp binding, and not a
  policy scope grain.
  **Policy scoping is v5 §4.5's three grains, never `child_of(resp)`**:
  project-global (no scope edge — a `<policy>` with neither `<required>`
  nor `<structural/>`, read via `all.policy` when a tier genuinely
  needs the unscoped grain — dsl-syntax.md §7.2), through-
  responsibilities (`policy_application`'s policy→resp instance — the
  load-bearing grain, since a policy bound to a resp survives a
  sysarch re-decomposition instead of being re-typed by hand), and
  direct component links for genuinely structural policies
  (`policy_application`'s policy→comp instance, new grammar — siege's
  own `<policy>` element only ever names a resp id via `<required>`;
  the `<structural/>` marker this pass adds to `schemas/sysarch.xsd`
  and `schemas/comparch.xsd` is what a policy declares instead,
  mutually exclusive with `<required>` by the grammar's own
  `xs:choice`, never both). Both are instances of one
  `policy_application` edge (dsl-syntax.md §4.1).
  **The through-responsibility read is wired, not a recorded gap.**
  An earlier pass here read `comparch`'s one-hop context grammar as
  unable to reach it and left both grains unread rather than
  under-deliver the load-bearing one; design review called that the
  wrong response to a missing construct. `dsl-syntax.md` §7.1's hop chains and reversed hops
  (`.<edge>~`) are what changed: `comparch.yaml` now reads
  `self.parent.policy_application~ -> policy.handle` (direct grain,
  one reversed hop) and `self.parent.fulfills.policy_application~ ->
  policy.handle` (through-responsibility grain, forward then
  reversed), and both land in one `policy` collection (dsl-syntax.md
  §9). No new edge was needed — `policy_application`'s two existing
  instances already carry both grains in their declared direction;
  reversal reads them backward at walk time.
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
  flow-state ("has the upstream stage closed yet") that
  "projection-time instance checks" (this ticket's own stated
  out-of-scope) would have to supply. Flow instance state becoming a
  real, checkable loader or engine concept is what would reopen the
  two-stage split, on its own merits rather than under a content
  port.

  **Each flow's planning tier mints one `cascade_visit`-scoped node
  per node the flow's cascade actually visits, not one `singleton`
  node per open instance** (design review). The first pass here read v5's closed scope
  set as having no tier standing for "whichever tier this cascade is
  currently visiting" the way v4's informal `scaffold_tier` did, and
  concluded a real per-visited-node plan fan-out was inexpressible
  without a `core_dsl` ticket's mandate. Design review rejected that
  conclusion: a missing scope kind is a `dsl-syntax.md` proposal, the
  same move already used for `mint.<name>`, not a reason to ship
  without the capability. `cascade_visit` (dsl-syntax.md §3.1) is that
  proposal, landed (`systems/core_dsl.md` records the grammar side);
  every `<flow>_plan` tier uses it, and `edges/plan_target.yaml`
  supplies the live pointer from a plan instance to the specific
  scaffold node it is planning for — the "schema delta is where
  plan→target lives, and it is empty" gap design review named,
  closed. Completion follows the same shift: `all(<flow>_plan ->
  resolved)` (`predicates.yaml`) reads "every visited node's plan has
  resolved," the universal quantifier over the tier's own name as path
  root (dsl-syntax.md §8's addendum) — not v4's `count(open_visit) ==
  0` (still unparseable under `lib/catapult/dsl/predicate.ex`'s actual
  grammar: no `open_visit` edge, no `decomposed_by(...)` call), and no
  longer the single-node `resolved == true` this entry previously
  described.

  One gap remains open and is *not* a grammar question: no planning
  tier reads `ticket.findings` (dsl-syntax.md §7's "ticket thread for
  the scope", v5's replacement for v4's dropped `seed:` block) —
  `lib/catapult/dsl/dialect.ex` registers no context-source extension
  in either dialect yet, so declaring it fails load — measured, not
  assumed. What is missing is a registration rather than a grammar:
  `ticket.findings` already parses and is already spec'd, and what it
  needs is a platform module implementing
  `Catapult.Dsl.Extension`'s `context_sources/0` and registering
  `"findings"`. That is `core_dsl`'s delivery-system milestone —
  plane extension code, not bundle content. Every planning tier reads
  `input.project_doc` instead today, which is the frozen original
  intake, not the flow's own new prose.

  `feature_request`'s planning-tier prompt is
  `seed-docs/siege-prompts/propose_feature.md`, ported close to
  verbatim (real source, real content). The other four have no siege
  source — only prose describes them, with no shipped prompt — so
  their planning-tier prompts are
  authored fresh and kept proportionately small rather than padded to
  match `feature_request`'s length.
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
- **A review is a tier, not a nested `review:` block** (ORC-84,
  revising the previous pass's `critique`-as-positional-wrapper
  reading of `docs/v5-design-decisions.md` §7.19). The eight LLM tiers
  that carried a nested `review: {prompt, grammar}` block —
  `sysarch`, `comparch`, `subcomparch`, `requirements`,
  `feature_expansion`, `impl`, `ref`, `vocab` — lose it; each gains a
  sibling tier file (`tiers/<name>_review.yaml`) declaring `reviews:
  <name>` instead. `dsl-syntax.md` §3.3 documents the mechanism: a
  review tier's scope and cardinality are the reviewed tier's by
  construction (never restated), it carries no `draft:`/`produces:`
  (comments, not a commit), and its `context:` is restated verbatim
  and checked at load time against the reviewed tier's own `context:`
  — the per-tier triad invariant made a load-time property instead of
  a shared-assembly-code discipline. `delivery: {phase: critique,
  agent_step: critique}` replaces the old `delivery: {phase:
  generation, agent_step: design}` + implicit-wrapper reading; `tiers:
  [tiers/*.yaml]` in `bundle.yaml` already globs the eight new files
  in, so no manifest edit was needed. `bundles/platform-elixir/schemas
  /review.xsd` gained `<score>` (integer, 0-100) and `id` on
  `<finding>` in the same pass — both were already named load-bearing
  by `docs/v5-design-decisions.md` §7.19's original text and by design
  review's explicit "nothing in the review grammar gets trimmed," but
  neither actually existed in the shipped grammar until this pass
  found the gap while rewiring the eight tiers around it.
  `dsl-syntax.md` §15.1's system-status table now carries `critique`
  (added by a later pass on this same ticket, once the eight
  `*_review.yaml` tiers below made `delivery: {phase: critique,
  agent_step: critique}` real bundle content rather than a design
  proposal) and this dev pass mirrors it into the loader's own closed
  set — `Catapult.Dsl.SystemStatus.kinds/0` gains `:critique` between
  `:generation` and `:fanout`, `agent_steps/0` gains `:critique`
  between `:dev` and `:reconcile` — the same accepted-gap shape
  `cascade_visit` and the reversed context-walk hop had before their
  own loader support landed, now closed the same way.

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
  instead of omitting the key. Five shipped prompts gate a revision
  section this way (`vocab`, `ref`, `subcomparch`, `sysarch`,
  `comparch`), and the shared `partials/_architecture_framing` carries
  the identical guard though its own copy cannot fire (below) — the
  rule is about the spelling, not about which copies fire, so it
  reaches all six. It generalizes further still: it is the
  bundle-authoring rule for any future prompt gating on a collection.

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
  _test.exs` holds all five templates with a working top-level guard
  against all three shapes, so these are the suite's claims rather than
  the next reader's to re-derive by reading `deps/solid`.

  **The shared partial's own copy of this guard cannot fire today, and
  that is a hook, not cruft to prune (ORC-184).** `{% render
  "partials/<name>" %}` isolates the partial's scope from its caller's
  unless the call passes `with`/`for` (`deps/solid`'s `RenderTag`); none
  of `partials/_architecture_framing`'s call sites across
  `bundles/default/{prompts,flows}/**` do, so `feedback` and `draft`
  never enter its scope and its `{% if feedback.size > 0 %}` block is
  inert. What actually gates a revision section today is each of the
  five shipped prompts' own top-level copy of the same guard —
  `vocab`, `ref`, `subcomparch`, `sysarch` and `comparch` — reading
  the `feedback` (and, on a review tier's own prompt, `draft`)
  `ContextAssembly` puts directly in *that* prompt's context —
  `dsl-syntax.md` §9's "generation and review templates for a tier
  receive identical context plus `draft`". The partial's copy stands
  ready for the day a caller starts rendering it `with feedback:
  feedback, draft: draft` instead of bare; deleting it now would mean
  re-deriving the exact `.size > 0` reasoning above a second time when
  that caller arrives. Until then it renders nothing and gates nothing,
  which is expected, not a defect.

## Initial vs target

Initial (Phase 3): default bundle's upstream tiers + ported prompts,
platform-elixir grammar skeletons. Target: full tier set including
product tier (Phase 5), delivery declarations (Phase 7), runtime-
dialect example content (Phase 8).

## Depends on

core_dsl defines what these files may say; generation renders them.

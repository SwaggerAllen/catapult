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
forked, never layered (v5 §6, `bundle.md` #7).

A separate system from core_dsl **for the mutex**: prompt iteration
and loader development are unrelated work streams, and one label
covering both would serialize them (v5 §7.5's watch-item logic,
applied preemptively). Prompt tickets carry `system:platform_content`;
loader tickets carry `system:core_dsl`.

## #1 Standing decisions

- **#2 Prompts are content, reviewed as diffs, never inline in code**
  (conventions §11). The harness iterates them; the git history is
  their changelog.
- **#3 The siege port preserves semantics first**: mechanical
  f-string→Liquid conversion, then iteration via the harness —
  never both in one change, or a quality regression is
  unattributable.
- **#4 The meaning-engine discipline governs edits** (SiegeEngine's
  hard-won rule): each tier's prompt names its
  downstream reader and pushes against category-speak; if a tier's
  output is vague, fix that tier's prompt, don't pass more context
  downstream.
- **#5 The layer carries the default license policy, written literally
  into the generated project** (ORC-16). `mix catapult.audit`'s license
  check is held to a list of SPDX identifiers the project states in its own
  `mix.exs` (`systems/substrate.md`), and the check itself carries none: an
  allowlist compiled into a module that ships everywhere is Catapult's legal
  position imposed on codebases nobody here has read.
- **#6 Literally, and this is the whole of the decision.** The five
  identifiers are emitted as data in the project's own file, readable and
  editable in place; never as a call into a shipped module that resolves
  them, which would put the constant back inside the check with an extra hop
  and leave a project unable to read what it is being held to. A project
  that edits the list is not evading a gate, it is stating a policy — the
  distinction `systems/substrate.md` records against the per-dependency
  waiver, which stays refused.
- **#7 A generated project's `mix.exs` declares `boundary: [default:
  [type: :strict]]`, not an apps list** (ORC-50), and this is recorded now
  for the same reason the entry above is: the layer does not exist yet, and
  the obvious move when it does is to copy the plane's own block, which
  would be copying a workaround along with it.
- **#8 Stubbing is the instructed pattern for externally-gated scopes**
  (v5 §2.16): the arch and impl prompt material tells the generator —
  design the contract fully, type it opaquely, stub the
  implementation, declare `implementation: stubbed` with its exit
  plan. An agent improvising a stub without the declaration is a
  prompt bug, not an agent judgment call: undeclared stubs are
  exactly the silent half-implementation the doctrine forbids.

- **#9 The architecture chain is the full backend family, mint-then-
  articulate at every fan-out** (ORC-84). Order: `feature_expansion` →
  `requirements` → `resp` (projection) → `sysarch` → `comp` (projection) →
  `comparch` → `subcomp` (projection) → `subcomparch` → `impl`, plus the
  pools `policy`, `vocab`, `ref`. `sysarch` is its own tier — a
  decomposition is a distinct cognitive act from requirements' rotation,
  with its own prompt and failure mode; folding it into resp asks one prompt
  to do two jobs (a previous ORC-7 pass made exactly this mistake and it is
  not repeated here). `comp`/`subcomp` are projection tiers (no draft, no
  prompt, `generator: synthesis`), minted by the `decomposition` edge's
  sysarch→comp and comparch→subcomp instances (one edge name, several sites
  sharing the mechanism — `chain.md` #27's `instances:` form;
  `edges/decomposition.yaml`) from their parent decomposition's row. `resp`
  gets the same treatment: v5 restores it as a real tier
  (`seed-docs/README.md`'s first known delta) by minting one node per atom
  `requirements` emits (`decomposition`'s requirements→resp instance),
  rather than leaving each atom a field inside `requirements`' own body the
  way v4 did — what restoring it as a tier buys is a stable target for
  `fulfills` and for a policy scoped "through responsibilities" (v5 §4.5) to
  survive a sysarch re-decomposition. **No `kind: domain | presentational`,
  no `domain_parent` edge, no `fanin` tier, and no replacement edge minted
  in its place.**
- **#10 Siege's two sysarch techniques go with it, and are not reinvented
  one level down.**
- **#11 A second intake root, `non_goals`, mints distilled non-goal policy
  nodes ahead of the architecture chain proper** (v5 §1.1, §4.5, the
  negative-space doctrine). `feature_expansion` stops being this chain's
  only tier reading raw input prose: `non_goals` sits beside it as a second
  `scope: singleton`, `generator: llm` root, context `input.*` (the whole
  raft — the prompt is written to depend on it being present) plus
  `input.non_goals` (the tagged-document role, strong signal when the raft
  carries one). Neither form can block readiness, and the two are alike in
  that rather than contrasting: since ORC-107, `input.<role>` and `input.*`
  both resolve to `{:ok, []}` when nothing is pinned under that role, fold
  vacuously satisfied through `walk_ready?`, and never block a tier's
  readiness (`chain.md` #22, `systems/engine.md`'s standing decision). The
  two roots name no `context:` entry on each other — a raft's negative space
  is read from the same frozen input prose either root reads, never from the
  other root's own drafted output, so nothing sequences one behind the other
  and both are ready the moment intake pins the raft. Its own
  `non_goals_review` counterpart puts the whole extracted set in front of
  the author through the ordinary draft→review→approve gate loop — no new
  review mechanism. Declining is declining the batch: the same
  all-or-nothing shape every other fanout-minting tier's authored block
  already has (`sysarch`'s `<policies>`, `comparch`'s `<subcomponents>`),
  and a decline naming one candidate to drop is answered the way every other
  tier's decline is — a comment naming the candidate, reaching the
  regenerating pass as ordinary `feedback` prose (`chain.md` #35), never a
  per-candidate accept/reject affordance, which this pool has never had and
  this ticket does not add.

  `non_goals` mints straight into the `policy` pool through a third
  `decomposition` instance — the identical mechanism the flat-pools
  entry below already documents for `sysarch`'s and `comparch`'s own
  `<policies>` blocks, not a new edge and not a new node kind (this
  ticket's own governing constraint, echoing v5 §4.5: "a separate
  non-goal tier would be the policy tier with the sign flipped"). The
  flat-pools entry below carries what's new in the minted shape itself
  — the grain restriction, the revisit-condition field, and what
  reading the result back still cannot do.
- **#12 One root, not two, and no second grain at intake.**
- **#13 This chain is one of four families sharing the same mint-then-
  articulate shape** (v5 §5.1): UI (`ui_coll → ui_collarch → ui_subcomp
  → ui_subcomparch → impl_ui`), screen (`screen_coll → … →
  impl_screen`) and client (`client_comp → … → impl_client`) each
  fan out the same way this backend chain does, behind their own tier
  files. Backend's own terminal tier stays bare `impl` until it has
  siblings to be qualified against — it takes the family-qualified
  name `impl_backend` once the other three exist. UI and screen land
  in Phase 5 with `frontend_sysarch`; client lands in Phase 7 with its
  consumer, `platform-client-ts` (`systems/client_ts.md`).
- **#14 Fragment ownership is 5 kinds at `comp`, 3 at `subcomp`** (ORC-84,
  confirming the previous pass's own correct call — kept rather than
  re-litigated). `comp` owns `techspec`, `pubapi`, `privapi`,
  `policies`, `failure_surface`, all written by `comparch`. `subcomp`
  owns only `techspec`, `pubapi`, `privapi`, written by `subcomparch`:
  siege's own `subcomparch` grammar has no `<policies>` or
  `<failure-surface>` section — policy reachability is transitive
  from the owning comp's policies, and failure modes route
  through pubapi's typed return shapes instead. The fragment
  vocabulary in `bundle.yaml` stays 5 kinds either way (`chain.md`
  #13's fragment vocabulary is over kinds, not over which tier owns
  which); what's tier-specific is which kinds a given tier's
  `handle.fragments:` and `produces:` actually name.
- **#15 `ref`/`vocab`/`policy` are flat pools, not singleton nodes**
  (v5 §4.5, ORC-84). `vocab` is `child_of(feature_expansion)`, minted
  by `decomposition`'s feature_expansion→vocab instance from the
  `<vocabulary>` block's flagged candidate terms (name + scope, not a
  full definition — see the content-delta entry below); `policy` is
  `child_of(sysarch)` with three `decomposition` mints (sysarch→policy
  from sysarch's project-level `<policies>`, comparch→policy from
  comparch's component-local `<policies>`, and non_goals→policy from
  the distilled intake set's own candidates, above; three fanout
  instances into one flat pool is legal, since `Catapult.Dsl.Tier`'s
  scope check only requires `child_of(X)` to name a *declared* tier,
  not the sole edge targeting it); `ref` is `scope: reference`
  (`docs/dsl-syntax.md` §3.1, ORC-236): `id` identity over a literal
  singleton would be meaningless, and `scope: reference` names exactly
  what `ref` is — a flat pool that accretes via a write tool, never
  minted by a fanout edge at all.
  **`ref` may attach anywhere, any parent, any child** — a general
  rule rather than v4's "comparch and below" restriction: no per-use
  kinds, no special-case lifecycles. The attachment sites
  (`edges/reference.yaml`'s three instances — comparch, subcomparch,
  impl, one edge name per `chain.md` #27) are wired only where content
  is actually consumed, matching v4's own choice of sites — the general
  rule is about the `ref` tier's own shape carrying no restriction, not
  a mandate to pre-wire every tier against a need nothing has yet.
  `reference` is its own edge name, not an instance of one of the five
  edges ORC-84 names (`fulfills`, `dependency`, `domain_parent`,
  `decomposition`, `policy_application`): ref attachment is not a mint,
  not the comp↔resp binding, and not a policy scope grain, so any of
  those names would misname the mechanism rather than honor "same
  mechanism, one name". **Policy scoping is v5 §4.5's three grains,
  never `child_of(resp)`**: project-global (no scope edge — a `<policy>`
  with neither `<required>` nor `<structural/>`, read via `all.policy`
  when a tier genuinely needs the unscoped grain — `chain.md` #19),
  through- responsibilities (`policy_application`'s policy→resp instance
  — the load-bearing grain, since a policy bound to a resp survives a
  sysarch re-decomposition instead of being re-typed by hand), and
  direct component links for genuinely structural policies
  (`policy_application`'s policy→comp instance, grammar siege has no
  counterpart for — its own `<policy>` element only ever names a resp id
  via `<required>`; the `<structural/>` marker in `schemas/sysarch.xsd`
  and `schemas/comparch.xsd` is what a policy declares instead, mutually
  exclusive with `<required>` by the grammar's own `xs:choice`, never
  both). Both are instances of one `policy_application` edge (`chain.md`
  #27). **The through-responsibility read is wired.** `comparch`'s
  one-hop context reads cannot reach the grain on their own; `chain.md`
  #19's hop chains and reversed hops (`.<edge>~`) are the construct
  that does: `comparch.yaml` reads `self.parent.policy_application~
  -> policy.handle` (direct grain, one reversed hop) and
  `self.parent.fulfills.policy_application~ -> policy.handle`
  (through-responsibility grain, forward then reversed), and both
  land in one `policy` collection (dsl-syntax.md §9). No further
  edge is needed — `policy_application`'s two instances already
  carry both grains in their declared direction; reversal reads them
  backward at walk time.
- **#16 A distilled non-goal mints project-global, grain one, only — and
  the schema says so rather than the prompt.** The `non_goals` tier's own
  policy-analog element carries no `<required>`/`<structural/>` choice at
  all, unlike `sysarch`'s and `comparch`'s `<policy>`: at intake there is no
  `resp` or `comp` id either grain could reference, so the grammar that
  would let a model invent one is simply absent, the same "enforced by the
  grammar, not a boolean flag" posture the `xs:choice` above already takes
  for the other two grains.
- **#17 The revisit-condition field is one optional, free-text element on
  all three `Policy` shapes.** `bundles/default/tiers/policy.yaml`'s
  `fields:`, both `<Policy>` complex types (`schemas/sysarch.xsd`,
  `schemas/comparch.xsd`) and the distillation schema carry it — the first
  two for the general case v5 §4.5 states: any policy can be an argued
  deferral, not only a distilled one. "never, argued" and "not until X" are
  values of that one field, per §4.5, never two shapes: an ordinary policy
  simply omits it, and a deferral's prompt guidance is to always fill it,
  whichever value applies. No closed vocabulary gates the value — "never"
  carries no schema-level meaning beyond being the text an author or model
  writes to argue permanence, consistent with the free-form posture this
  whole doctrine already takes (v5 §1.1: no closed non-goals registry, no
  required file).
- **#18 No policy in this chain declares a grade, distilled or authored.**
  §4.5's promote-from-prose ladder and its enforcement-ticket machinery are
  unbuilt entirely, so a distilled non-goal carries none either — it is
  exactly as ungraded as every other policy this chain ships.
- **#19 `all.policy` reads every scope indiscriminately, so the
  project-global grain is not added to any scoped tier's context.**
- **#20 `mint.<name>` and `mint.parent.<name>` together are the field
  source for every join-target tier** — every `generator: synthesis`
  tier, the predicate that finds them, plus the mint-time identity
  fields on `vocab`, which is not a join target and carries a draft of
  its own. A given field on a given tier uses one or the other, never
  both, per the split below. `chain.md` #12 states the convention (the
  gap `seed-docs/README.md` flagged: a tier with no `draft:` still
  needs a field source), and `mint.<name>` names the minting fanout
  edge's `declared_in:` row — the row-local form. The row-local form
  is unvalidated at load time — nothing cross-checks a bare
  `mint.<name>`'s `<name>` against the minting instance element's own
  attributes. The inherited case — a value copied from the committing
  tier's own already-computed `fields:`/`produces:` entries rather
  than read off the minting instance element, one hop further than a
  single walk reaches (`comp`'s
  `project_techspec`/`project_policies_summary`, copied from `sysarch`
  at the same mint moment) — has its own name, `mint.parent.<name>`,
  and is cross-checked at load time against the committing tier's own
  `fields:`/`produces:` entries, the same cross-validation a
  `draft.<path>` source gets against its schema (ORC-236, `chain.md`
  #12, #32).
- **#21 Five flows ship, not six** (ORC-84): `feature_request`,
  `refactor`, `bug_fix`, `downward_propagation`, `upward_propagation`.
  `plan_change` is the one flow v5 voids outright — it exists solely to
  recompute phase assignment and cascade phased-tier regeneration, and v5 §6
  drops the phase machinery it operates on wholesale ("dropped from v4:
  ...the plan-change flow"). The other five carry no phase dependency in v4
  either and are ported: four walk `downward_cascade`, `upward_propagation`
  walks `up_then_down` (the one place this bundle uses the second walk
  primitive). `upward_propagation` is further simplified from v4's two-stage
  `assessment_plan` + `propagation_plan` to one combined planning tier,
  since sequencing two flow-scoped tiers needs instance-level flow-state
  ("has the upstream stage closed yet") that projection-time instance checks
  would have to supply.

  One gap remains open and is *not* a grammar question: no planning
  tier reads `ticket.findings` (an extension context-source kind,
  `chain.md` #39 — the ticket thread for the scope, v5's replacement
  for v4's dropped `seed:` block) — `lib/catapult/dsl/dialect.ex`
  registers no context-source extension in either dialect, so
  declaring it fails load. What is missing is a registration rather
  than a grammar: `ticket.findings` already parses and is already
  spec'd, and what it needs is a platform module implementing
  `Catapult.Dsl.Extension`'s `context_sources/0` and registering
  `"findings"`. That is `core_dsl`'s delivery-system milestone — plane
  extension code, not bundle content. Every planning tier reads
  `input.project_doc` instead, which is the frozen original intake,
  not the flow's own new prose.
- **#22 Each flow's planning tier mints one `cascade_visit`-scoped node
  per node the flow's cascade actually visits, not one `singleton` node per
  open instance.** v5's closed scope set had no tier standing for "whichever
  tier this cascade is currently visiting" the way v4's informal
  `scaffold_tier` did, and a missing scope kind is a `chain.md` proposal,
  the same move already used for `mint.<name>`, not a reason to ship without
  the capability. `cascade_visit` (`chain.md` #6) is that proposal, landed
  (`systems/core_dsl.md` records the grammar side); every `<flow>_plan` tier
  uses it, and `edges/plan_target.yaml` supplies the live pointer from a
  plan instance to the specific scaffold node it is planning for — the
  schema delta is where plan→target lives. Completion follows the same
  shape: `all(<flow>_plan -> resolved)` (`predicates.yaml`) reads "every
  visited node's plan has resolved," the universal quantifier over the
  tier's own name as path root (`chain.md` #37) — not v4's
  `count(open_visit) == 0` (unparseable under
  `lib/catapult/dsl/predicate.ex`'s actual grammar: no `open_visit` edge, no
  `decomposed_by(...)` call), and not a single-node `resolved == true`.
- **#23 The `modify_*` prompts fold into each tier's own generation
  prompt as a `{% if feedback %}` section, not into the flow
  layer.** `seed-docs/siege-prompts/modify_sysarch.md`,
  `modify_comparch.md`, `modify_subcomparch.md` are not referenced by
  any ported flow or tier declaration (confirmed: zero hits for
  `modify_` in either vendored v4 document outside the file
  listing) — they are
  siege's own generic "surgical diff against targeted feedback"
  variant, orthogonal to which flow (if any) produced the feedback.
  `chain.md` #5's tier grammar has exactly one `prompt:` slot per
  tier, and #35 confirms a tier's single template receives `feedback`
  as a variable on every regen, review or not — there is no second
  "modify" template slot in the grammar, and inventing one would be
  new DSL surface a content-porting ticket has no mandate to add. The
  shared discipline (surgical modification, sticky sections) lives
  once in `prompts/partials/_architecture_framing.md.liquid`'s own `{%
  if feedback %}` block; each of `sysarch`/`comparch`/ `subcomparch`'s
  own prompts carries the tier-specific "preserve this, when the
  feedback says X do Y" content from its matching `modify_*.md` source
  in its own `{% if feedback %}` section. `impl`, `feature_expansion`,
  `requirements`, `vocab`, `ref` have no `modify_*` source and rely on
  the shared partial's generic framing alone.
- **#24 `catapult.yaml` is created** (ORC-84), naming `chain: default` /
  `workflow: default-flow` — `core_dsl`'s file map already claims the path
  (ORC-5); this ticket supplies the content the map was left pointing at
  nothing for. `bundles/default/bundle.yaml` declares `extends:
  platform-elixir`, so a minimal `platform-elixir` stub (empty
  tier/edge/flow lists, `kind: chain`) ships alongside it — otherwise the
  `extends:` reference is a load error.
- **#25 A review is a tier, not a nested `review:` block** (ORC-84;
  `docs/v5-design-decisions.md` §7.19, read as a review tier rather
  than as a `critique` positional wrapper). The eight LLM tiers
  `sysarch`, `comparch`, `subcomparch`, `requirements`,
  `feature_expansion`, `impl`, `ref`, `vocab` carry no nested
  `review: {prompt, grammar}` block; each has a sibling tier file
  (`tiers/<name>_review.yaml`) declaring `reviews: <name>` instead.
  `dsl-syntax.md` §3.3 documents the mechanism: a review tier's scope
  and cardinality are the reviewed tier's by construction (never
  restated), it carries no `draft:`/`produces:` (comments, not a
  commit), and its `context:` is restated verbatim and checked at load
  time against the reviewed tier's own `context:` — the per-tier triad
  invariant made a load-time property instead of a shared-assembly-code
  discipline. A review tier declares `delivery: {phase: critique,
  agent_step: critique}`, not `delivery: {phase: generation,
  agent_step: design}` behind an implicit wrapper; `tiers:
  [tiers/*.yaml]` in `bundle.yaml` globs the eight review files in, so
  no manifest entry names them. `bundles/platform-elixir/schemas
  /review.xsd` carries `<score>` (integer, 0-100) and `id` on
  `<finding>` — both load-bearing per `docs/v5-design-decisions.md`
  §7.19, and nothing in the review grammar is trimmed. `workflow.md`
  #10's kind table carries `critique`, and the loader's own closed set
  mirrors it — `Catapult.Dsl.SystemStatus.kinds/0` carries `:critique`
  between `:generation` and `:fanout`, `agent_steps/0` carries
  `:critique` between `:dev` and `:reconcile`.

- **#26 A gate reads `depth: 0`; the architecture chain's `critique`
  entries read `depth: [2, 0]`** (ORC-92; `docs/v5-design-decisions.md`
  §7.19 carries the argument, `workflow.md` #33 the form). A gate is a
  human sign-off and reads the top level however far the chain fans out
  beneath it, so fan-out reasoning never belongs on a gate — it belongs
  on the citing type's own `critique` entry. `[2, 0]` is the pair that
  follows: `2` for a project's first traversal, because the
  architecture chain's own deepest fan-out is two edges (`comp`, then
  `subcomp`), and `0` for every later traversal, which returns to the
  top level.

- **#27 Every `<flow>_plan` tier declares `fields: argument: draft.argument`,
  closing the gap the reserved `argument` field name leaves open by
  default** (ORC-114, design pass). A flow's planning tier —
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

- **#28 A prompt guard on a possibly-omitted collection tests `.size > 0`,
  never bare truthiness** (ORC-134). Liquid counts an empty list as
  truthy — only `nil` and `false` are falsy — so `{% if feedback %}`
  opens its section on every render the moment a caller passes `[]`
  instead of omitting the key. The shared `partials/_architecture_framing`
  carries the guard once; `sysarch`, `comparch` and `subcomparch` each
  carry their own second copy, guarding the tier-specific "preserve X,
  when the feedback says Y do Z" content the partial doesn't have
  (ORC-193) — the rule is about the spelling, not about which copies
  fire, so it reaches all four. It generalizes further still: it is
  the bundle-authoring rule for any future prompt gating on a
  collection.

  All thirteen call sites pass `feedback` explicitly in that form, so
  the partial's guard and its `{% for %}` loop reach every tier and
  flow. The partial carries no `{{ draft }}` and no "Current draft is
  below" framing — nothing will ever populate `draft` there — and its
  section is worded around what a generation-tier regeneration
  actually has: the feedback text, and the same upstream `context:`
  the tier's fresh-generation half already reads. `vocab` and `ref`
  carry no top-level guard of their own: theirs duplicated the
  partial's generic framing without ever showing the feedback either,
  and the partial reaches them. `sysarch`, `comparch` and `subcomparch`
  keep their own guards — a different location in the file from the
  partial's render call at the top, so the partial firing there
  doesn't reach it — trimmed to only the tier-specific "preserve X,
  when the feedback says Y do Z" bullets ported from their
  `modify_*.md` sources; the generic preamble lives in the partial's
  single copy. Three shipped prompts carry their own guard.
- **#29 The shared partial receives `feedback` explicitly at every call
  site, because `{% render %}` isolates the partial's scope from its
  caller's** (ORC-193). `{% render "partials/<name>" %}` passes nothing
  through unless the call passes arguments (`deps/solid`'s `RenderTag` — a
  `with`/`for` binding, or a plain comma-separated `key: value` list).
- **#30 A `feedback`-shaped collection is rendered via `{% for entry in
  feedback %}`, printing the fields the model needs (`entry.body`,
  `entry.author_id`, `entry.posted_at`), never interpolated bare** — the
  same "spelling, not which copies fire" generalization the `.size > 0` rule
  above makes, extended to cover what a collection guard's own body does
  once it opens.

- **#31 `partials/_review_framing` has the same scope-isolation defect
  ORC-193 fixed on the generation side, and every review tier carries it**
  (ORC-201; `chain.md` #35).

  The fix is ORC-193's, applied to the other partial: all eight call
  sites pass `draft: draft` explicitly, and the partial prints it
  under a "Draft under review:" heading. `draft` is a plain string
  (`draft_variable/2` returns the body or `""`), so it interpolates
  directly rather than needing the `{% for %}` form
  `_architecture_framing` gives `feedback` — the distinction the
  ORC-193 entry above draws between a scalar and a collection, applied
  rather than restated.

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
- **#32 `prior_review` is the same gap and closes with it.** It is
  supplied to the same dispatch, rendered by nothing, and it is a map
  (`score`/`findings`/`kind`/`body_sha`) — so the eight call sites pass it
  too, and the partial renders the score and iterates the findings.
- **#33 The keys are string-keyed, measured rather than inferred.**

- **#34 Every `agent_step: design` tier's `delivery.phase` across
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

- **#35 `bundles/platform-elixir/` folds into `bundles/default/`, and
  `extends:` retires from the DSL** (ORC-153;
  `docs/v5-design-decisions.md` §5.5, §6, §7.18; `bundle.md` #5, #7).
  The layer's only content, `schemas/review.xsd` — a platform-wide
  review grammar belonging to no language — lives in the chain
  bundle's own `schemas/`; nothing else was ever loaded onto the stub
  (the convention grammars, template tiers and enforcement profiles
  the ORC-84 entry above scoped to "a separate ticket's job" never
  shipped there). With the workflow axis carrying no base layer of its
  own either (ORC-105), `extends:` has no user on either axis, so a
  chain bundle is a single directory of authored content, the same
  shape a workflow bundle has, and `extends:` is an unknown key on any
  bundle's manifest. **The bundle-relative content-path traversal
  guard is not part of what retires**: a `prompt:` or `grammar:` path
  is still checked against escaping its own bundle wherever
  single-directory path resolution lands, because that guard is about
  bundle-authored content being untrusted input, not about there being
  a second layer underneath to escape into.

- **#36 `journeys`/`journey` and `screens`/`screen` land as two more
  spine-plus-projection pairs, the identical shape `requirements`/
  `resp` already has** (ORC-109; `docs/v5-design-decisions.md`
  §4.1-§4.3). Chain placement: `feature_expansion → journeys → screens
  → requirements → sysarch → …` — both tiers sit `scope:
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

  `feature_expansion` and `screens` both carry `input.mocks` in their
  own `context:` — §4.1 names both; the entry below this block names
  the shape.

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
    the edge `chain.md` #23's rule ("carries no context and no
    readiness in either direction") already anticipated; this bundle is
    what declares it. Declared inside `screens`' own draft (same
    document as every screen it connects), so no forward reference here
    either.

  **Review and `requirements`' scope follow from the shape:**
  - `journeys_review` (`reviews: journeys`) and `screens_review`
    (`reviews: screens`) exist — the per-tier triad invariant applies
    to the two authored spines the same way it applies to
    `requirements`; `journey` and `screen`, like `resp` and `comp`, are
    projections and get no review tier of their own, because there is
    nothing there for a review to read that `journeys`'/`screens`' own
    review doesn't already cover.
  - `requirements` **stays `per(feature_expansion)`, gains
    `all.journey.handle` and `all.screen.handle`.** Re-scoping to one
    requirements node per screen would fragment the rotation
    requirements exists to do — its whole job (seen already in
    `prompts/requirements.md.liquid`'s own framing, "features onto
    system-side axes: auth produces several…") is consolidating many
    surfaces into few cross-cutting responsibilities, which needs one
    pass seeing every surface at once, not one pass per surface.
    `<responsibility>` carries journey and screen reference blocks
    alongside its `<feats>` (kept — a responsibility can be grounded in
    a feature with no product surface yet, and `<feats>` is still the
    primary grounding); the
    requirements prompt is instructed to prefer citing a journey over
    a screen when a responsibility's feature is journey-backed, falling
    back to a direct screen reference for standalone screens (v5
    §4.2's own "responsibilities prefer journey references" and "the
    bridge falls back to screen refs"), and the `reference` edge's
    resp→journey / resp→screen instances above are what those
    citations resolve against.
- **#37 `screens` also reads every already-minted `journey`**: `context:
  [self.parent.handle, all.journey.handle]`. `all.journey.handle` — the
  individual children, not `all.journeys.handle` — is the walk that actually
  reaches each journey's ordered screen-walk and state block; `journeys`'
  own handle, like `requirements`' own handle (`fields: [id, intro]`),
  carries no per-row content.
- **#38 Screen groups vs. IA regions is settled in
  `docs/v5-design-decisions.md` §4.3 itself**, which records `screen
  group`'s semantics: a free-form signal into `frontend_sysarch`'s later
  IA-region grouping (§5.3), not the region itself and not a gate on it —
  §5.3's own "journeys are a signal, not a gate" rule extended to this
  field. `screen group` is a plain string in `screens`' grammar, validated
  against no vocabulary, so this is a semantics-only settlement with no
  schema consequence for this tier.
- **#39 Not the same "screen" as this repo's own.** `journey`/`screen` are
  chain tiers a *generated project's* product tier mints; Catapult's own
  `screens/*.md` is orchestration's native screen machinery and is unrelated
  (`docs/build-plan.md`'s own standing decision for the build, not a Phase 5
  one: "Catapult's product tier … doesn't apply to Catapult itself"). No
  entry under `screens/` or `storybook/` exists for them for that reason —
  there is no UI screen here to define, only chain content, and chain
  content is dev's to write into `bundles/**`.

- **#40 `feature_expansion` and `screens` gain `input.mocks`, closing the
  wiring the entry above deferred** (ORC-110; `docs/v5-design-decisions.md`
  §4.1). `feature_expansion`'s `context:` is `[input.project_doc,
  input.mocks]`; `screens`' is `[self.parent.handle, all.journey.handle,
  input.mocks]`. Both render as a plain `{{ mocks }}` string
  (`systems/generation.md`'s `ContextAssembly` entry — keyed by role name,
  omitted from the variables map entirely when the raft carries no
  `mocks`-tagged document), so both prompts need no explicit presence guard:
  a bare `{{ mocks }}` renders empty when the variable is omitted, the same
  unset-is-empty behavior `feature_expansion`'s own bare `{{ project_doc }}`
  already relies on (`bundles/default/prompts/feature_expansion.md.liquid`).
- **#41 Mocks are read as source, not rendered.** The extraction tiers
  read whatever text or markup the raft pins under the `mocks` role, the
  same as any other input role.
- **#42 No schema change for either tier**, because both extraction
  disciplines already carry the mechanism negative-space completion needs.
  `feature_expansion`'s `<implicit/>` marker
  (`schemas/feature_expansion.xsd`) already covers "the project obviously
  needs it but the user didn't name it explicitly" — mock evidence is one
  more source feeding that inference, not a new marker. `screens`' own
  prompt already instructs naming "narrower [state] names … whenever the
  screen's behavior at that state is genuinely different"
  (`prompts/screens.md.liquid`), and its review checklist already flags a
  `<displayed-data>` detail "visible in the mock" with no matching
  `<affordance>` (`prompts/review/screens.md .liquid`). Both prompts are
  instructed to weigh mock evidence against these existing rules: a mock set
  showing only a happy path doesn't excuse `screens` from naming
  `empty`/`error`/`loading`/ `denied` when the feature narrative implies
  them, and doesn't excuse `feature_expansion` from flagging an
  `<implicit/>` feature that a mock's error or admin screen implies but its
  prose never states. Extraction completing the negative space is the chain
  improving the mocks, not transcribing them (v5 §4.1) — the instruction
  reaches both tiers, not just `screens`.
- **#43 Review stays the tiers' own — no bespoke negative-space
  question.**

- **#44 `frontend_sysarch` mints both collection families in one pass, and
  the UI and screen families are each two authored tiers plus `impl`,
  the identical mint-then-articulate shape the backend chain already
  has** (ORC-111; `docs/v5-design-decisions.md` §5.1-§5.4;
  `docs/build-plan.md`'s Phase 5 entry). No entry under
  `screens/`/`storybook/` exists for it, for the same reason `screens`
  has none: there is no UI screen here to define either, only chain
  content, and chain content is dev's to write into `bundles/**`.

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
  follows the same 5-then-3 split ORC-84 already settled for the
  backend pair (`techspec`/`pubapi`/`privapi`/`policies`/
  `failure_surface` at `*_coll`, written by `*_collarch`; `techspec`/
  `pubapi`/`privapi` at `*_subcomp`, written by `*_subcomparch`) — the
  fragment vocabulary is a bundle-wide closed set of 5 kinds, not a
  per-family one, so this is that existing rule applied, not a fresh
  choice. Every `generator: llm` tier in both families has a sibling
  `_review` tier (`frontend_sysarch_review`, `ui_collarch_review`,
  `ui_subcomparch_review`, `impl_ui_review`, `screen_collarch_review`,
  `screen_subcomparch_review`, `impl_screen_review`) the same way the
  eight backend tiers do — the per-tier triad invariant applies
  identically, and there is nothing about a UI or screen collection
  that exempts it. Every `agent_step: design` tier among the above
  declares `delivery: {phase: generation, agent_step: design}`,
  uniformly, per the standing rule that `delivery.phase` stays
  uniformly `generation` for every `agent_step: design` tier until the
  work-item type declaration itself draws a `design`/`architecture`
  split (above) — none of these are that type-level declaration.

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
    ui_coll`, declared in `frontend_sysarch`'s own draft, not
    `screen_collarch`'s (ORC-235): the pass that mints both collections
    is already deciding their relationship, and the backend analogue is
    that `subcomp↔subcomp` is decided by `comparch`, one tier *above*
    `subcomparch`, not by the reading tier itself — a tier reading an
    edge only its own draft declares is a walk that can never resolve
    on the pass that would declare it. `screen_collarch`'s own
    `self.parent.renders -> ui_coll.handle...` context entry reads
    which `ui_coll`s its own `screen_coll` renders.
  - `uses_shapes` (`type: dependency`), `source: ui_coll, target: comp`
    (the backend join-target tier, the same target `comp↔comp`
    dependency already reads), declared in `frontend_sysarch`'s own
    draft, not `ui_collarch`'s (ORC-235). Only
    `frontend_sysarch`'s own `ui-collections.collection[]` rows may
    carry this edge's `declared_in` path — no `screen-collections` row
    does, and no instance targets anything but backend `comp` — which
    is what makes "a UI collection reads backend shapes, never calls" a
    fact about which edges the *loaded bundle* contains, not only about
    what a generated file happens to do; the guarantee is "which of
    `frontend_sysarch`'s own two top-level sub-trees," the identical
    `declared_in`-leading-segment check `systems/core_dsl.md`'s ORC-232
    entry establishes for a join target's relationships living in its
    minting tier's draft.
  - `calls` (`type: dependency`), `source: screen_coll, target: comp`,
    declared in `frontend_sysarch`'s own draft, not `screen_collarch`'s
    (ORC-235) — symmetric to `uses_shapes`, checked against
    `screen-collections` rows instead of `ui-collections` ones, and,
    again, the edge simply has no `ui_coll`-sourced instance anywhere,
    so a UI collection has no declared path to a backend call at all;
    the "backend function invocation inside a UI collection's file
    map is a layering violation" audit check still catches a generated
    file that ignores its own graph, but the graph itself already
    refuses the shape.

  `screen_coll → screen` ("hosts") reuses `fulfills` rather than
  minting a fourth new edge name: a screen collection is the
  implementation locus for the screens it groups, the identical
  relationship `fulfills`' existing `comp → resp` instance already
  states for the backend ("this architecture node is the one that
  implements this responsibility"), and the cardinality matches exactly
  (`source: {min: 1}` — a collection must group ≥1 screen to justify
  existing, `target: {min: 1, max: 1}` — a screen is hosted by exactly
  one collection). `fulfills` is in `instances:` form to carry both.
  Declared inside `frontend_sysarch`'s own `screen-collections
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
  read off IA region alone — so the declaration site is
  `screen_collarch`'s own draft, unlike `renders`/`uses_shapes`/`calls`
  (ORC-235). What `screen_collarch`'s own **context** entry reads is
  the pool, not that edge: `self.parent.reference -> journey.handle`
  would name the collection's own not-yet-declared edge, which can
  never resolve to anything on the pass that would declare it — the
  identical chicken-and-egg shape the three edges above avoid by
  declaring in the minting tier, which here would contradict the
  sentence before. So `screen_collarch`'s `context:` reads
  `all.journey.handle` — every already-minted journey, the full pool
  to choose from and cite by id — exactly the pattern `requirements`,
  `screens` and `frontend_sysarch` itself use for "cite an
  already-minted node by id, chosen from the full pool" (the ORC-109
  entry above). The `reference` instance itself is declared inside
  `screen_collarch.draft.journeys.journey[].@ref`, screen_coll's own
  decision, made from real journey content rather than from an edge
  that cannot yet exist. `ui_collarch`, `ui_subcomparch`, `impl_ui`,
  `screen_collarch`, `screen_subcomparch` and `impl_screen` each carry
  the same `reference → ref` attachment site backend's `comparch`,
  `subcomparch` and `impl` have, and each reads `all.vocab
  .handle` in its own `context:` — both are the existing per-tier
  convention applied to six more tiers, not a new one.

  `ui_coll → design_system` ("primitives") is a further `dependency`
  instance, declared in `ui_collarch`'s own draft: `source: ui_coll,
  target: design_system`. `design_system` is ORC-110's tier, and this
  edge is the one `systems/core_dsl.md`'s `design_system` entry names.
  `design_system` mints
  at most one node project-wide (ORC-110), so a project supplying none
  simply has no instance of this edge to declare — absence, not a
  zero-cardinality edge naming a node that doesn't exist.
- **#45 Chain placement and per-family tiers.** `frontend_sysarch` is
  `scope: singleton` (the closed scope set — `chain.md` #6 — has a real kind
  for exactly this: no `per(X)` parent it would otherwise need a context
  walk to reach), one `generator: llm` draft per project, reading `context:
  [all.journey .handle, all.screen.handle, all.sysarch.handle,
  all.comp.handle]` — four `all.<tier>` walks (`chain.md` #19), no edge
  needed for any of them, the same no-owning-parent case
  `vocab`/`ref`/project-global `policy` already use.
- **#46 `all.comp.handle` is read because `uses_shapes`/`calls` are
  declared in this draft** (below; ORC-235): naming which backend `comp` a
  UI or screen collection depends on means having backend components to
  name, and `all.sysarch.handle`'s own handle (`[id, intro, techspec]`)
  names no component at all. The bare handle, not
  `.handle.fragments[pubapi]`: `comp`'s handle fields (`name`, `purpose`,
  `is_foundation` — `tiers/comp.yaml`) are `mint.<name>`, set directly from
  `sysarch`'s own decomposition at mint time, and already enough to decide
  *which* component a dependency should name; the pubapi text itself is a
  `comparch`-written fragment `comp`'s bare handle carries no promise about
  (`systems/generation.md`'s ORC-235 entry is why that distinction matters —
  a fragment read is a different, and currently moot, question from a handle
  read).
- **#47 Backend's terminal tier carries its family-qualified name.**
  `bundles/default/tiers/impl.yaml` is `impl_backend.yaml` (`tier:
  impl_backend`), and `impl_review.yaml` follows it
  (`impl_backend_review.yaml`, `reviews: impl_backend`) — ORC-106's rule
  that the qualification lands once the other three families' `impl` tiers
  exist alongside it, and `impl_ui`/`impl_screen` are the first two. No
  other backend tier, edge or prompt differs in shape for it — the
  qualification is a name, not a restructuring.
- **#48 Minting two target tiers from one source is the loader's existing
  shape.** `edges/decomposition.yaml`'s `sysarch` source already fans into
  two different targets, `comp` and `policy`, as two `instances:` entries
  under one edge name — the same source fanning out to several different
  target tiers, which is one instance sharing a source with another instance
  of the same edge (`chain.md` #27), and already load-bearing.
  `frontend_sysarch` carries two `decomposition` instances the identical
  way: `source: frontend_sysarch, target: ui_coll, declared_in:
  frontend_sysarch.draft.ui-collections.collection[]` (`cardinality: source:
  {min: 0}` — a project may recurrence-seed no shared widgets — `target:
  {min: 1, max: 1}`) and `source: frontend_sysarch, target: screen_coll,
  declared_in: frontend_sysarch .draft.screen-collections.collection[]`
  (`source: {min: 1}` — every project's screens need at least one hosting
  collection, mirroring `screens`' own `{min: 1}` — `target: {min: 1, max:
  1}`). `ui_collarch → ui_subcomp` and `screen_collarch → screen_subcomp`
  are two further `decomposition` instances, the same shape `comparch →
  subcomp` already has. `decomposition` (`bundles/default/edges
  /decomposition.yaml`) names `sysarch→comp`, `comparch→subcomp`,
  `feature_expansion→vocab`, `requirements→resp`, `sysarch→policy`,
  `comparch→policy`, `non_goals→policy`, `journeys→journey`,
  `screens→screen`, `frontend_sysarch→ui_coll`,
  `frontend_sysarch→screen_coll`, `ui_collarch→ui_subcomp` and
  `screen_collarch→screen_subcomp` — one mechanism at every one of them.
- **#49 The layering rule is enforced as load-time type-level acyclicity,
  not merely unviolated by omission.** A UI-collection-to-screen- collection
  edge is *inexpressible*, not merely never declared:
  `systems/core_dsl.md`'s own standing decision records type-level
  acyclicity as a load-time check (libgraph, over the full edge-instance
  graph — every instance contributes its own `{source, target}` pair to
  that check, so the graph is over sites, not over edge names).
- **#50 `ui_coll → design_system` is declared in `ui_collarch`'s own
  draft, unlike `renders`/`uses_shapes`/`calls`** (ORC-235).
- **#51 No `policy_application` instances for either family.**
- **#52 No frontend/product-side parent-link edge replaces
  `domain_parent`** (the ORC-84 entry above's open item).
- **#53 Screen groups are a signal into IA regions, not the regions
  themselves** (ORC-109): `docs/v5-design-decisions.md` §4.3 records `screen
  group` as a free-form signal into `frontend_sysarch`'s own IA-region
  grouping, not the region itself and not a gate on it (the ORC-109 entry
  above, in full).
- **#54 Not the same `system:` label this repo's own mutex uses, either.**
  v5 §5.4's `system:ui-avatar` / `system:scr-account` slugs name mutex
  labels a *generated project's* own per-collection systems docs will carry,
  once a real `frontend_sysarch` run groups real collections on a real
  project — the collection-level analogue of the "not the same screen as
  this repo's own" note above, and unrelated to how this repo's own
  `systems/*.md` file maps resolve `system:` labels (the pipeline protocol's
  own mutex resolution: a `system:` label derives from the mapped doc's
  filename, `systems/<name>.md` → `system:<name>`, not a stored mapping —
  `.pipeline/internal/filemap/filemap.go`).
- **#55 A `declared_in` path spells an element or attribute segment the
  way the schema that owns it spells it — the schema is the
  authority, not the edge file** (ORC-232). Every multi-word element
  name in every schema under `bundles/default/schemas/**` is
  hyphenated and none is underscored; `frontend_sysarch.xsd`'s own
  documentation prose refers to `<ui-collections>` and
  `<screen-collections>` throughout; the checked-in stub
  (`test/catapult/generation/fixtures/toy_seed/frontend_sysarch.xml`)
  carries the hyphenated form. Six distinct segments named below match
  no element the schema declares under that spelling, across nine
  `declared_in` instances across three edge files —
  `Extraction.descend/2` (`lib/catapult/generation/extraction.ex`)
  resolves a segment by exact string equality, with no hyphen/
  underscore normalization, so every one of the nine matched nothing
  in a committed body and the edge instance it named minted or
  resolved nothing, for every project on this bundle. A tenth instance,
  in a fourth file, carries the same consequence from a different
  defect shape — a spelled-right segment that names no element at all
  rather than one the schema spells differently — found only once the
  load-time check below actually ran against the whole bundle rather
  than by inspection:

  - `edges/decomposition.yaml`'s `frontend_sysarch → ui_coll` and
    `frontend_sysarch → screen_coll` instances — `ui_collections` and
    `screen_collections`, where the schema spells `ui-collections` and
    `screen-collections`.
  - `edges/fulfills.yaml`'s `screen_coll → screen` instance —
    `screen_collections`, where the schema spells `screen-collections`
    (the `screens.screen[].@ref` tail matches the schema).
  - `edges/dependency.yaml`'s `subcomp → subcomp`, `ui_subcomp →
    ui_subcomp` and `screen_subcomp → screen_subcomp` sibling-scope
    reads — `sub_dependencies` at three sites (`comparch`'s,
    `ui_collarch`'s and `screen_collarch`'s own drafts), where the
    schema spells `sub-dependencies`. (The sibling `comp → comp`
    instance, declared in `sysarch`'s own draft as single-word
    `dependencies`, matches the schema.) The `comparch`-sited
    `subcomp → subcomp` instance is the live, backend-only one:
    `subcomparch`'s own `context:` (`self.parent.dependency ->
    subcomp.handle.fragments[pubapi]`) has been reading nothing back
    since the tier landed, generating every `subcomparch` document
    without the dependency context it was written to carry.
  - `edges/dependency.yaml`'s `ui_coll → ui_coll` and
    `screen_coll → screen_coll` project-wide reads — `ui_dependencies`
    and `screen_dependencies` (both declared in `frontend_sysarch`'s
    own draft), where the schema spells `ui-dependencies` and
    `screen-dependencies`.
  - `edges/dependency.yaml`'s `ui_coll → design_system` instance —
    `design_system`, where the schema declares the `<design-system>`
    element inside the `Primitives` complexType. The path's own second
    segment, `primitives`, is a single word and matches the schema;
    it names `ui_collarch.xsd`'s `<xs:element name="primitives"
    type="Primitives">`, not the `Primitives` complexType itself, which
    a reader only reaches by following that element's `type=`
    reference. That makes this the one instance of the nine whose wrong
    segment sits behind a named-type reference rather than as a direct
    child of its tier's root element — load-bearing for the load-time
    check's own coverage (`systems/core_dsl.md`'s ORC-232 entry). The
    same line's `target: design_system` names the tier, not the
    element, and keeps its underscore — the identical tier-name/
    root_tag split the entry below states for the five renamed tiers,
    here landing on one line instead of three sites, which is exactly
    why it reads as a typo rather than a distinction without this
    sentence.
  - `edges/reference.yaml`'s `impl_backend → ref`, `impl_ui → ref` and
    `impl_screen → ref` instances — the tenth, differently-shaped
    instance. Each `declared_in` repeated `implementation` as its own
    second segment
    (`impl_backend.draft.implementation.references.reference[].@target`),
    but `schemas/impl.xsd`'s root element (root_tag `implementation`)
    puts `<references>` directly under its own root — there is no
    nested `<implementation>` wrapper for a second `implementation`
    segment to descend into. The sibling `comparch`, `subcomparch`,
    `ui_collarch`, `screen_collarch` and `screen_subcomparch` instances
    in the same file go straight from their own tier to `references`,
    with no such extra hop; the three `impl_*` instances were the only
    ones that ever had it, present since `impl.xsd`'s first port
    (ORC-84) and carried unchanged through every `impl` →
    `impl_backend`/`impl_ui`/`impl_screen` rename since. The path is
    `impl_backend.draft.references
    .reference[].@target` and its two siblings, with no stray segment.
- **#56 A `declared_in` path's leading segment names a tier, and the
  schema to check the rest of the path against is that tier's own
  `draft.grammar` — not necessarily the citing instance's `source`.**

- **#57 Five `root_tag`s hyphenate, as a public-API spelling correction
  independent of the `declared_in` fix above** (ORC-232, author
  decision). `frontend_sysarch`, `screen_collarch`,
  `screen_subcomparch`, `ui_collarch` and `ui_subcomparch` were the
  bundle's only underscored `root_tag`s — every other multi-word
  `root_tag` already hyphenates (`bug-fix-plan`, `feature-expansion`,
  `feature-request-plan`, `non-goals`, `propagation-plan`,
  `refactor-plan`, `upward-propagation-plan`, `vocab-entry`) — and a
  generated document's root element is public surface, spelled
  consistently whether or not anything is functionally broken by the
  inconsistency. They are `frontend-sysarch`, `screen-collarch`,
  `screen-subcomparch`, `ui-collarch` and `ui-subcomparch`.
- **#58 The tier name is not the `root_tag`, and only the second one
  moves.** `frontend_sysarch` (the tier, the YAML basename, the XSD
  filename, and every `context:`/`declared_in` reference to the tier) stays
  underscored — bundle identifiers are underscored by convention here,
  unrelated to this correction — while the same tier file's own root-tag
  line is `draft.root_tag: frontend-sysarch`, not `draft.root_tag:
  frontend_sysarch`, and the schema's own root is `<xs:element
  name="frontend-sysarch">`, not `<xs:element name="frontend_sysarch">`, to
  match (`Dsl.validate_draft` rejects a body whose root element doesn't
  match the declared `root_tag` — `root_tag_mismatch`, one of ORC-223's four
  422 reasons). The same split applies to the other four. All five are in
  the set `systems/generation.md`'s `@root_tag_fixtures` entry documents: a
  checked-in fixture filename that tracks the bundle's own tier name rather
  than the hyphenated `root_tag` it maps to.

- **#59 `ref.yaml` sheds everything a generated tier needs and keeps
  nothing a generated tier doesn't** (ORC-236;
  `docs/v5-design-decisions.md` §4.5, `docs/dsl-syntax.md` §3.1, §3.2).
  It is `scope: reference`, not `scope: singleton`, and `generator:
  reference`, not `generator: llm`, so it carries no `prompt:` and no
  `delivery:` block — there is no dispatch to phase, since nothing
  dispatches it — and no `draft:` (no `root_tag`, no `grammar`): a
  write-path-created node has no draft to validate against a grammar.
  `fields:` carries `title`/`body`, sourced to `reference.title` and
  `reference.body` — the fourth field-source form
  (`docs/dsl-syntax.md` §3), legal only on a `scope: reference` tier,
  naming a key the write path's own payload supplies directly rather
  than a `draft.title`/`draft.body` this tier has no draft to hold.
  The payload shape itself is the write tool's to define when it is
  built, not this tier declaration's — only the key names are fixed
  here. There is no `ref_review.yaml`: nothing commits a draft for it
  to review. There is no `prompts/ref.md.liquid` and no
  `schemas/ref.xsd` either, since no field names them, and
  `systems/generation.md`'s `@root_tag_fixtures` entry counts neither
  a `reference` root_tag nor a `ref` review tier.
- **#60 Every third-party-declared edge instance gains `source_ref:`/
  `target_ref:` where their `source`/`target` isn't the committing tier
  itself** (ORC-236; `chain.md` #27, `systems/core_dsl.md`'s ORC-236
  entry). Seven `reference`/`fulfills` instances and ten
  `dependency`-typed instances share this shape, each enumerated below
  with its locator kind — the two edge files' own instance count
  includes `navigation.yaml`'s `screen → screen` (declared in
  `screens`'s draft, which never commits under the name `screen`) and
  `calls`/`renders`/`uses_shapes` (three separate `type: dependency`
  edges, not instances of the `dependency` edge itself, each declared in
  `frontend_sysarch`'s own draft rather than `screen_coll`'s or
  `ui_coll`'s). All seven `reference`-typed instances resolve
  structurally with no explicit locator: `fulfills`'s `comp → resp` and
  `screen_coll → screen`, `reference`'s `resp → journey`, `resp →
  screen`, and `navigation`'s `screen → screen` (its *source* side) all
  take `source_ref: fanout(decomposition)` implicitly the moment the
  loader finds `decomposition`'s own matching instance's `declared_in`
  is a prefix of theirs; `reference`'s `journey → screen` is the mirror
  shape on its target side, `target_ref: fanout(decomposition)`;
  `reference`'s `screen_coll → journey` takes `source_ref: self.parent`,
  also automatic (`screen_collarch` is `per(screen_coll)`). Every side
  not resolved structurally on its own instance defaults to the trailing
  `.@attr` segment of `declared_in` (`docs/dsl-syntax.md` §4.2's widened
  default) — which is what closes `navigation`'s own target side (its
  `declared_in`'s trailing `.@to`, not a second `fanout(decomposition)`
  locator: both sides resolving through the same fanout element would
  make source and target the identical `<screen>` node on every
  instance) and the *other* side of each of the remaining six with no
  explicit locator either.

  Of the ten `dependency`-typed instances, four resolve the identical
  implicit way: `calls`, `renders` and `uses_shapes` each take
  `source_ref: fanout(decomposition)` (their `declared_in` shares
  `frontend_sysarch`'s own `screen-collections.collection[]` or
  `ui-collections.collection[]` prefix with `decomposition`'s own
  `screen_coll`/`ui_coll` fanout instance) with their `target` (`comp`
  for `calls`/`uses_shapes`, `ui_coll` for `renders`) defaulting off the
  trailing attribute; `dependency.yaml`'s own `ui_coll → design_system`
  takes `source_ref: self.parent` (`ui_collarch` is `per(ui_coll)`) and
  needs no `target_ref:` at all, because `design_system` is
  `scope: singleton` (`docs/dsl-syntax.md` §4.2's fourth locator kind) —
  there is exactly one node to mean, so nothing needs pointing at.

  The remaining six — `comp ↔ comp`, `subcomp ↔ subcomp`, `ui_coll ↔
  ui_coll`, `ui_subcomp ↔ ui_subcomp`, `screen_coll ↔ screen_coll`,
  `screen_subcomp ↔ screen_subcomp`, all in `dependency.yaml` — are the
  residual case and carry an explicit pair, since neither end is `self`,
  `self.parent`, a fanout element, nor a `scope: singleton` tier:
  `source_ref: "@from"`/`target_ref: "@to"`, naming whichever attribute
  pair `bundles/default/schemas/*.xsd` actually gives each `<dep>`
  element — checked against the schema at load time the same way any
  other `declared_in` segment is (ORC-232's entry above). Across those
  seven edge files, only these six instances carry an explicit
  `source_ref:`/`target_ref:`; every instance's
  `source`/`target`/`declared_in`/`cardinality` values stand as
  declared.
- **#61 `comp`, `subcomp`, `ui_subcomp` and `screen_subcomp` gain
  `mint.parent.<name>` values in place of `mint.<name>` on exactly the
  fields that were never row-local** (ORC-236;
  `chain.md` #12). `comp.yaml`'s `project_techspec` field's value is
  `mint.parent.techspec`, naming `sysarch`'s own `techspec` field
  (`sysarch.yaml`'s `fields: techspec: draft.techspec`); its
  `project_policies_summary` field's value is
  `mint.parent.policies_summary`, naming `sysarch.yaml`'s
  `policies_summary` field (`fields: policies_summary:
  draft.policies-summary`, hyphenated to match the schema element below
  — `Extraction.text/2` matches a path segment against a schema element
  by exact string equality with no `_`↔`-` normalization, the same rule
  `systems/core_dsl.md`'s ORC-232 entry states for `declared_in`, also
  checked for `fields:`/`produces:` at load time per that same system's
  ORC-236 entry). `sysarch` carries that field because `comp`'s own
  field has nothing else to name, and three more sites carry the
  element with it, since a field naming nothing to read is inert:
  `bundles/default/schemas/sysarch.xsd`'s `<sysarch>` sequence has a
  `policies-summary` element alongside
  `introduction`/`techspec`/`components`/`policies`/`dependencies`;
  `bundles/default/prompts/sysarch.md.liquid` carries the instruction
  to produce it; and `test/catapult/generation/fixtures/toy_seed
  /sysarch.xml` carries the element so the toy chain's own fixture is
  valid against the schema. `subcomp.yaml`, `ui_subcomp.yaml` and
  `screen_subcomp.yaml`'s five `parent_*` fields' values are each
  `mint.parent.<fragment kind>` (`parent_techspec:
  mint.parent.techspec`, and so on for the other four), each naming the
  fragment kind `comparch.yaml`/`ui_collarch.yaml`/
  `screen_collarch.yaml`'s own `produces:` is *declared* to write under
  that same name. The six tiers' `authored:` paths must spell their
  schema elements exactly (`systems/core_dsl.md`'s ORC-236 entry on the
  widened declared_in/schema check): four of those five fragments' own
  `authored:` sources were misspelled against their schema,
  independently of this bullet's own mechanism, and
  `mint.parent.techspec`/`pubapi`/`privapi`/`failure_surface` each
  named an empty fragment until the paths were corrected — the
  mechanism this bullet specifies has nothing to copy while the values
  underneath it are silently empty. Every other `mint.<name>` field on
  these four tiers, and every `mint.<name>` field on
  `resp`/`policy`/`screen`/`screen_coll`/`ui_coll`/`journey`/`vocab`,
  is row-local and stays `mint.<name>` — `mint.parent.<name>` is only
  for the fields that could never have been row-local in the first
  place.
- **#64 The default pair is rewritten as one file per axis, and the
  binding reverses with it.** `bundles/default/chain.yaml` and
  `bundles/default-flow/workflow.yaml` replace the per-tier,
  per-edge, per-type and per-gate trees the entries above describe,
  together with each bundle's manifest and the standalone status,
  type and escalation files. What stays beside them is what the
  declaration names: `schemas/<tier>.xsd`, the prompt families, and a
  flow's own prompts (`bundle.md` #3, #4). Four consequences for this
  bundle's own content, each naming what it supersedes:
  1. **No tier names a position.** A generation position lists the
     tiers that run at it, and a ticket type names the chain flows it
     serves (`workflow.md` #22, #40), so every `delivery:` block in
     the entries above goes with `phase:` and `agent_step:`.
  2. **The two ticket types are `scaffold` and `delta`**, named for
     the shape of change they serve. `feature` was the wrong name for
     a type that receives bug fixes and refactors, and it collided
     with the chain flow the scaffold pass runs.
  3. **The seventeen review tiers and the reconcile tiers collapse
     into `review:` and `reconcile:` blocks** on the tiers they belong
     to (`chain.md` #14, #15), so `tiers/<name>_review.yaml` and the
     `reviews: <name>` key go.
  4. **Each tier's context is derived from the edges it and its scope
     parent declare** (`chain.md` #20), with `context:` adding to the
     derivation rather than restating it; node identity, a node's own
     fields and plain cardinality move into the schemas (`bundle.md`
     #10).

  The rewritten pair is measured against the acceptance bound
  (`bundle.md` #14): at most 800 lines for the chain file with
  comments at most a fifth of that, at most 240 for the workflow file.

## #62 Initial vs target

Initial (Phase 3): default bundle's upstream tiers + ported prompts.
Target: full tier set including product tier, `frontend_sysarch`, and
the UI and screen families (Phase 5), the client family (Phase 7),
runtime-dialect example content (Phase 8).

This bundle is where every reserved construct is declared for the
first time, so it carries the shape each consumer will read. The flow
engine's (engine#69): the five plan tiers, their `synthesis` edges,
the `flows:` block and its walks and completion predicates. Delivery
Phase 7's (delivery#123): `enforcement:` on `comparch`, the
`environment:` entries and the gates' `escalation`. The registry's
(registry#7): `version` on either declaration. Generation's
(generation#50): the `executor:` profile the chain sets as a default.

## #63 Depends on

core_dsl defines what these files may say; generation renders them.

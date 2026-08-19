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
applied preemptively). Prompt tickets carry `system:platform-content`;
loader tickets carry `system:core-dsl`.

## Standing decisions

- **Prompts are content, reviewed as diffs, never inline in code**
  (conventions §11). The harness iterates them; the git history is
  their changelog.
- **The siege port is a re-expression, not a byte conversion** —
  revised (ORC-7). The source is vendored at `seed-docs/`: siege's own
  prompt chain under `siege-prompts/`, and the mapping this repo kept
  citing as "v5 §B.2", which is really **Appendix B of
  `seed-docs/catapult-spec-v4.md`** — §B never existed in
  `v5-design-decisions.md`, and every citation of it here before the
  corpus was vendored was wrong. The earlier rule (mechanical
  f-string→Liquid conversion first, harness iteration second, never
  both in one change) is retired because **v5 moved the structure the
  prompts are written against** — `resp` restored as a tier, `fanin`
  and the domain/presentational split replaced by §4.1's three-way
  product/backend/frontend split, the product tier inserted into the
  chain head (`seed-docs/README.md`'s three known deltas) — so there
  is no tier-for-tier correspondence left to convert along. Sequencing
  a mechanical step before an iterative one only buys attributable
  quality regressions when the mechanical step is a real
  transformation of matching parts; here it would be a rewrite wearing
  a conversion's name.
  **The license is not a second reason.** `bundles/**` is Apache-2.0
  and SiegeEngine is AGPL-3.0, but siege has a single copyright
  holder, no third-party contributors and no users, so carrying its
  text into the Apache zone is authorized outright, including verbatim
  (`seed-docs/README.md`). Rewriting is a quality judgment, not a
  permission boundary.
  What the vendored corpus is *for*, then: the v4 documents
  (`catapult-default-bundle-v4.md` especially) pin scope, identity,
  handle, body grammar and generator per tier — structural fact that
  survives the rewrite — and the prompts (`siege-prompts/`) show what
  siege learned about how to ask. Both are read and adapted, quoted
  close to verbatim where quoting is the right call (noted in the
  authoring commit where it happens) — the constraint is editorial
  judgment, not provenance. Content deltas from siege's semantics are
  argued below and in `docs/non-goals.md`, not discovered later.
- **The meaning-engine discipline governs edits** (v4 §B.2.5,
  SiegeEngine's hard-won rule): each tier's prompt names its
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
  stating a policy — the distinction `docs/non-goals.md` records
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
  articulate at every fan-out** (ORC-7, second pass — corrects the
  first pass's collapse, which `docs/non-goals.md` records rather than
  restates). Order: `feature_expansion` → `requirements` → `resp`
  (projection) → `sysarch` → `comp` (projection) → `comparch` →
  `subcomp` (projection) → `subcomparch` → `impl`. `sysarch` is its
  own tier — a decomposition is a distinct cognitive act from
  requirements' rotation, with its own prompt and failure mode; folding
  it into resp asks one prompt to do two jobs. `comp`/`subcomp` are
  projection tiers (no draft, no prompt, `generator: synthesis`),
  minted by `component_fanout`/`subcomponent_fanout` from their parent
  decomposition's row — the mechanism that lets a *different* bundle
  attach edges to a node its own drafting tier doesn't own, which is
  the reason fan-out nodes exist at all. `resp` gets the same
  treatment: v5 restores it as a real tier (`seed-docs/README.md`'s
  first known delta) by minting one node per atom `requirements`
  emits, rather than leaving each atom a field inside `requirements`'
  own body the way v4 did.
  **No `kind: domain | presentational`, no `domain_parent` edge, no
  `fanin` tier.** `seed-docs/README.md`'s second known delta replaces
  that whole mechanism with v5 §4.1's product/backend/frontend split —
  a mechanism this ticket's chain, being backend-only, never needs;
  every component `sysarch` mints is simply a component.
  **No minted `feat` tier.** `seed-docs/README.md` names exactly three
  v4→v5 deltas and a feature tier isn't one of them; features stay
  `feature_expansion` body content, referenced downstream by name, as
  in v4.
  **No "un-fanned-out" escape** on `comparch` (v4's zero-subcomponent
  case, with `impl` attaching directly to the comp instead): the DSL's
  closed scope vocabulary (`singleton | per(X) | child_of(X)`, one X)
  has no union form for "`per(subcomp)` or `per(comp) where
  count(subcomponents)=0`", and inventing one would repeat the
  mistake the mint/draft collapse already made once — a syntax gap
  papered over by collapsing structure instead of naming the gap.
  Every component decomposes into at least one subcomponent in this
  bundle. Revisit condition: a real DSL union-scope form, or a small-
  component case from the toy-seed pass strained enough by mandatory
  decomposition to argue the point concretely.
- **Every join-target tier's `fields:` source from `mint.<name>`**
  (ORC-7; the addendum to `docs/dsl-syntax.md` §3 this decision
  proposes). `docs/dsl-syntax.md`'s own `fields:` examples were all
  `draft.*`, and a join-target tier has no draft — the gap the first
  pass hit and, wrongly, resolved by removing the tiers instead of
  naming the source. `mint.<name>` is the value the minting fanout's
  row carried (comp's `purpose` from sysarch's `<component>` row) or,
  for content one hop further than a single context walk reaches
  (comp's `project_techspec`, copied from its grandparent sysarch at
  the same mint moment, since `comparch` — `per(comp)` — has no
  self.parent route to sysarch that wouldn't cycle against
  `component_fanout`), a plain copy made at mint time from the minting
  instance's own handle. Neither is validated at load time — no more
  than a `draft.*` path already is — naming the convention is so two
  authors, or one bundle read twice, agree what it means.
- **`ref` stays a flat pool with no fanout at all**; `vocab` is
  `child_of(feature_expansion)`; `policy` is `child_of(sysarch)` with
  a second fanout (`policy_fanout_comp`, source `comparch`) minting
  into the same pool. None of the three is `child_of(resp)` — v5 §4.5's
  three policy-scoping grains and the redirect on this ticket are both
  explicit that scoping through a responsibility is not the same as
  being *parented* by one, and `ref`/`vocab` never had a resp
  relationship to begin with. `identity: id` over many nodes, not one
  — v5 §4.5's "singleton pool" phrasing reads as "one flat,
  project-wide collection", the same loose reading the first pass used
  and got right.
  `ref` — v4 §1.13's "any parents, any children" escape hatch stays
  general: created via a write tool or the dashboard, never minted by
  a fanout, attached to `comparch`/`subcomparch`/`impl` via three
  `reference` edges (`comparch_ref`, `subcomparch_ref`, `impl_ref` —
  one per consuming tier, since an edge names one fixed source).
  `vocab` — v4 §1.12 mints it from `feature_expansion`'s own
  `<vocabulary>` block either way (project-level or feature-local);
  the feature-local case carries a `feature_name` field rather than an
  edge to a minted feature node, because there is no minted feature
  node (see above). **Content delta from v4/siege**: this tier's own
  prompt writes the definition/disambiguation/see-also content;
  `feature_expansion`'s prompt only flags the candidate (name + scope).
  Siege's `feature_expansion.md` emits the full entry inline in one
  pass; splitting mint from articulation matches the pattern every
  other fan-out in this bundle already uses, so `feature_expansion`
  does one job and `vocab` does the other.
  `policy` — v5 §4.5's three grains, never resp parentage: project-
  global (a policy declaring neither scope edge), through-
  responsibilities (`policy_scope_resp`, load-bearing per the redirect
  — a policy scoped to what the system does survives a `sysarch`
  re-decomposition), and direct component links for genuinely
  structural policies (`policy_scope_comp` — new grammar, a
  self-closing `<structural/>` marker this ticket adds since siege's
  `<policy>` only ever names a resp id). Two fanout edges
  (`policy_fanout` from `sysarch`, `policy_fanout_comp` from
  `comparch`) mint into the one pool; `lib/catapult/dsl/tier.ex`'s
  `scope_problems` check only requires a `child_of(X)` tier's `X` to
  be a *declared* tier, not the sole edge targeting it, so this is
  legal under the loader as implemented, not an invented allowance.
- **`subcomparch` produces three fragments onto its subcomp, not
  five.** `comparch` writes all five (techspec, pubapi, privapi,
  policies, failure_surface) onto its comp — the redirect's own
  reading of v4 §1.5/§3.2/examples over §3.1's contradicting bullet.
  `subcomparch` writes only techspec, pubapi, and privapi:
  `seed-docs/siege-prompts/subcomparch.md`'s actual grammar has no
  `<policies>` or `<failure-surface>` section at all — the source
  explicitly rejects a `<policies>` element ("subcomponents don't have
  policies") and routes failure modes through `<public-surface>`'s
  typed returns instead. Policy reachability is transitive from
  comp-level policies (v4 §5.2), so nothing is lost by a subcomp
  minting none of its own. The bundle's fragment vocabulary
  (`bundle.yaml`) stays one closed set of five kinds; not every kind
  is owned at every scope that carries fragments.
- **The default workflow bundle is named `default-flow`** (matching
  dsl-syntax.md §1's own `catapult.yaml` example literally) and *is*
  the platform workflow layer — it carries no `extends:` because
  nothing sits above it yet; a project wanting a third review or a
  per-ticket-type variant overlays it with its own bundle naming
  `extends: default-flow`. Its two gates are named `ux-review` and
  `engineering-review`, matching this ticket's own wording, layered
  onto dsl-syntax.md §15.1's bolded default-lifecycle labels
  (`Product review`, `Architecture review`) rather than reusing those
  labels verbatim — the mapping table names them as *this vocabulary's*
  defaults, not as fixed system statuses, "which is what makes them
  replaceable" in that same section's own words.
  **`ux-review` names `after: generation`**, a §15.1 system-status
  *kind* — never a display label like "Product design" or
  "Architecting". The first pass's draft used the labels from §15.1's
  worked lifecycle mapping directly; `lib/catapult/dsl/workflow.ex`'s
  `gate_after_problems/1` and `gate_throwback_problems/1` (landed with
  ORC-5, after that draft was written) resolve `after:`/`throwback:`
  only against the eleven fixed kinds or another declared gate's name,
  so those labels fail to load. Fixed on this pass, together with
  `docs/dsl-syntax.md` §3's own tier `delivery:` example, which had the
  identical bug (`phase: Architecting`) and was corrected the same way
  ahead of this ticket. `engineering-review`'s `depth: 2` is a ceiling
  covering both levels this chain fans out at (`sysarch`'s
  `component_fanout`, then `comparch`'s `subcomponent_fanout`) — never
  validated against the chain's actual depth (§13), so raising it
  costs nothing if a future chain fans out less.

## Initial vs target

Initial (Phase 3, this ticket): the default bundle's full backend
architecture chain — `feature_expansion`, `requirements`, `resp`,
`sysarch`, `comp`, `comparch`, `subcomp`, `subcomparch`, `impl` — plus
the supporting `ref`, `vocab`, `policy` tiers, their edges, fragments,
prompts and grammars, and the platform workflow layer (`default-flow`:
`ux-review`, `engineering-review`, `dev`, `staging`). `platform-elixir`
ships only the platform-wide review grammar (`schemas/review.xsd`) at
this phase — genuinely a skeleton, not the fuller convention corpus
(permission taxonomy content, template-generator tiers for read-model/
infra-kind components, audit grammar) that `comparch`'s own
`<permissions>`/`<enforcement>` blocks above already anticipate but
don't yet need a populated platform layer behind them.
Target: full tier set including the product tier (Phase 5 — `journeys`
and `screens` insert between `feature_expansion` and `requirements`;
`docs/v5-design-decisions.md` §4.1), delivery declarations (Phase 7),
runtime-dialect example content (Phase 8).

## Depends on

core_dsl defines what these files may say; generation renders them.

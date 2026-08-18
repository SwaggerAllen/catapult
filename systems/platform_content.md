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
- **The siege port preserves semantics first** (v5 §B.2's mapping):
  mechanical f-string→Liquid conversion, then iteration via the
  harness — never both in one change, or a quality regression is
  unattributable.
- **The meaning-engine discipline governs edits** (v5 §B.2.5,
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
- **The siege port has no siege to diff against** (ORC-7). The actual
  source — SiegeEngine's prompt chain and the v4 spec's own Appendix
  B mapping (`catapult-spec-v4.md`, `seed-docs/` in the SiegeEngine
  repo) — lives in a repository this pass has no checkout of and no
  way to fetch; every reference to "v5 §B.2" elsewhere in this repo's
  docs points at that appendix, not at anything in
  `v5-design-decisions.md`. So this is not, mechanically, a port: it
  is a from-scratch authoring of the default bundle's chain content
  against `docs/v5-design-decisions.md` and `docs/dsl-syntax.md` as
  the executable spec, which is what those documents already claim to
  be ("the platform's own record," "v5 §B.2's mapping" cited but never
  quoted). Recorded here rather than silently passed over, per this
  ticket's own instruction that every content delta from the siege
  originals be named: every sentence of prompt prose, every XSD
  element, and the edge/tier structure connecting them in this commit
  is new text, not a migrated one. The mechanical-conversion-first
  rule two bullets up (f-string→Liquid, then iterate) could not be
  followed literally for the same reason; what happened instead is the
  nearest honest equivalent — structure fixed from the closed DSL
  grammar first, prose filled in afterward, in this one pass, because
  there was no separate mechanical step available to do first.
- **The architecture chain collapses the mint/draft split** — no
  separate `comp`/`subcomp` tiers, no separate `sysarch` tier — for
  reasons recorded in `docs/non-goals.md` rather than restated here;
  both are ORC-7 entries and both name a revisit condition.
- **`ref`, `vocab` and `policy` are flat pools, minted `child_of(resp)`**
  via their own fanout edges (`ref_fanout`, `vocab_fanout`,
  `policy_fanout`), seeded as slugs in resp's own draft and grown
  independently thereafter through each pool's own generation pass.
  v5 §4.5's "singleton pool" phrasing is read as "one flat,
  project-wide collection" rather than "one node" — `identity: id`
  on all three only makes sense if many independent nodes exist, and
  refs and policies are explicitly things that "grow by tickets" over
  the project's life, which a single ever-revised document does not
  model as cleanly as a pool that gains members. `policy`'s two
  `policy_application` edges (`policy_scope_resp`, `policy_scope_comp`)
  are separate from `policy_fanout`: the fanout edge only mints the
  node, the scope edges (declared in the policy's own draft) are what
  place it at one of v5 §4.5's three grains — project-global is the
  case where a policy node declares neither.
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
  **`ux-review` names `after: Product design`** even though no tier in
  today's default chain declares that phase (the product tier is
  Phase 5) — legal because gates attach to system statuses and
  platform-fixed phase labels, never to a specific chain's tiers
  (dsl-syntax.md §11, §13), and there is deliberately no chain/workflow
  compatibility check to violate. The alternative (`after: generation`,
  the bare system status, or renaming the phase this bundle's chain
  actually starts with) was rejected because it would make the default
  workflow layer describe *today's* chain rather than the platform's
  fixed review sequence, and workflow content is supposed to outlive
  any one chain's shape (v5 §7.18).

## Initial vs target

Initial (Phase 3, this ticket): default bundle's architecture chain —
`resp`, `comparch`, `subcomparch`, `impl`, plus the supporting `ref`,
`vocab`, `policy` tiers, their edges, fragments, prompts and grammars
— and the platform workflow layer (`default-flow`: `ux-review`,
`engineering-review`, `dev`, `staging`). `platform-elixir` ships only
the platform-wide review grammar (`schemas/review.xsd`) at this phase
— genuinely a skeleton, not the fuller convention corpus (permission
taxonomy content, template-generator tiers for read-model/infra-kind
components, audit grammar) that `enforcement:`/`scope_filter:
is_domain` above already anticipate but don't yet need populated.
Target: full tier set including product tier (Phase 5), delivery
declarations (Phase 7), runtime-dialect example content (Phase 8).

## Depends on

core_dsl defines what these files may say; generation renders them.

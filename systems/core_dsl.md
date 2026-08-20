---
paths:
  - lib/catapult/dsl/**
  - test/catapult/dsl/**
  - catapult.yaml
---

# core_dsl

The DSL: the frozen core vocabulary (tiers, scopes, edges, fragments,
handles, context walks, grammars, readiness, generators, the
predicate language), the bundle loader (`bundle.yaml` + registered
files → validated union), `extends:` content layering, and the
**extension registry** (v5 §9) through which platform extensions add
annotation namespaces, declaration kinds, generator types,
context-source kinds, and audit profiles.

## Standing decisions

- **The core is frozen; growth happens in extensions** (v5 §9).
  A change to core vocabulary is a platform-versioned event with a
  migration story; an extension is an entry. When in doubt, it's an
  extension.
- **No bundle-side code, ever.** Bundles declare instances against
  installed-extension vocabulary; the predicate language stays
  non-Turing-complete (v5 §6). This is a correctness property the
  scheduler and audit lean on, not a style choice.
- **All validation at load time where possible**: type-level
  acyclicity (libgraph), cross-references, cardinality shapes,
  extension schemas. A bundle that loads is a bundle the engine can
  run; instance-level checks (dependency cycles) run at projection
  time.
- **Destructive bundle change over a populated graph is a cutover,
  never a hot edit** (v5 §6): additive loads freely; removals,
  renames, and restructures go through the cutover ticket — drain,
  reviewed graph-transform list, migrate, then flip the active
  bundle. The loader may load the new bundle for validation, but
  the engine switches graphs only at a completed cutover. **The
  drain is per axis** (v5 §7.19): it stands on the chain axis, where
  flow instances complete, and relaxes on the workflow axis, where a
  blocked ticket is in-flight for as long as its human prerequisite
  takes. Blocked tickets ride a workflow cutover and re-resolve
  against the new sequence, anchored on the system statuses — the
  part of a ticket's history no bundle change can delete. The flip
  is recorded as an event on both axes; the re-resolution joins a
  ticket's status history against the bundle-version timeline and
  needs both in the log.
- **Grammar machinery lives here** (validators derived from bundle
  declarations); engine and generation call it. One validator source
  because commit-time rejection (engine) and pre-flight validation
  (generation, CLI later) must agree byte-for-byte.
- **`catapult.yaml` is the loader's, not the bundle's** (dsl-syntax.md
  §1-2). It names one bundle per axis and nothing else — it is what
  the loader reads to find `bundles/` in the first place, not content
  the loader validates against a bundle schema. That makes it this
  system's file, same as any other loader input, and distinct from
  `bundles/**`'s content, which `platform_content` owns. Previously
  unowned (repo-root, no system's map claimed it, not on
  `systems/README.md`'s unowned list either) — the gap this ticket's
  sketch closes.
- **Four core-grammar growth events landed directly, not through the
  extension registry** (ORC-84, design review): a fourth scope kind,
  `cascade_visit` (§3.1 — one node per node a flow's own cascade walk
  visits, for a planning tier, engine-minted rather than fanout-minted);
  a context walk's hop chain lengthened from exactly one to any number,
  plus a `~` suffix reversing a hop (§7.1 — walker matches the edge's
  `target` instead of its `source`); a new context-walk source,
  `all.<tier>.<projection>` (§7.2 — every declared instance of a tier,
  no edge); and edges gaining an `instances:` list, several
  source/target sites sharing one name and mechanism (§4.1). None of
  these are extension points in the §9/§12 sense — annotation
  namespaces, declaration kinds, generator types, context-source
  *kinds*, enforcement profiles are all vocabulary the grammar
  references, installed or not; these four are the grammar's own
  productions (how many hops a walk may chain, what scope kinds exist
  at all), which the extension registry has no callback for and was
  never meant to carry. "The core is frozen; growth happens in
  extensions" therefore doesn't route these anywhere — there is no
  extension shaped to hold a scope kind. What actually governs a core
  grammar change is the sentence right after: "a platform-versioned
  event with a migration story." This entry is that story. All four
  landed inside a content-porting ticket rather than a dedicated
  `core_dsl` ticket because that ticket's own design review directed
  it, in these words, after the first pass tried the alternative
  (recording each gap as a non-goal) and was told that was the wrong
  move: "a missing DSL construct is a `docs/dsl-syntax.md` proposal,
  not a reason to ship the bundle without the capability" — the same
  instruction this ticket had already given, and this pass had already
  followed, for `mint.<name>` (§3's join-target field-source
  addendum, landed the same way one pass earlier). Design review's
  sign-off is the reviewed change; a dedicated ticket would be
  re-litigating a decision already made in daylight, not making a new
  one. Every addition is additive to the closed sets it extends (no
  existing bundle content stops parsing) and ships with loader tests
  (`test/catapult/dsl/context_walk_test.exs`,
  `test/catapult/dsl/loader_test.exs`) exercising the new productions
  directly, not only through `bundles/default/`'s own use of them.
  Revisit condition: none for the mechanism split itself (extensions
  still own vocabulary, core still owns grammar); a *fifth* grammar
  growth event still wants the same daylight this one got, whether or
  not another ticket happens to be carrying it.
- **A fifth core-grammar growth event, same daylight, same ticket**
  (ORC-84, author decision revising `docs/v5-design-decisions.md`
  §7.19): a tier declaration gains `reviews: <tier>` (dsl-syntax.md
  §3.3), marking it a review tier for the named tier rather than a
  generation tier of its own. Unlike the four above, this isn't a new
  scope kind, edge form, or context-walk source — it's a new relation
  *between two tier declarations*: `reviews:` fixes the declaring
  tier's scope and cardinality to the named tier's, 1:1, without
  restating `scope:`, and it obligates a load-time check with no
  precedent in the closed sets §13 already validates — that the
  review tier's own `context:` names the same set of walks as the
  reviewed tier's `context:`. Landed here rather than in a dedicated
  ticket for the identical reason the first four did: the author's
  decision superseded this ticket's own prior (and design-review-
  corrected) handling of the chain's review mechanism, mid-flight, and
  said so explicitly — "It lands mid-flight... the difference is that
  it reaches the branch as ticket direction the pass reads before it
  starts... the doc edit is this pass's to make." No loader tests
  accompanied the design pass that added this paragraph (the six
  plane-code files this ticket's design role may touch were already
  stripped once by a prior review comment and stayed stripped —
  `lib/catapult/dsl/**` and `test/catapult/dsl/**` were left for this
  ticket's own dev pass, same as the four above). **Landed by that dev
  pass**, alongside the four-item entry above (same commit): `reviews:`
  is implemented in `Catapult.Dsl.Tier`/`Catapult.Dsl.Chain`, with
  loader tests exercising it directly (`test/catapult/dsl/loader_test
  .exs`); `bundles/default/` now loads clean end to end (25 tiers — 17
  generation/projection plus 8 review — 6 edges, 5 flows, 2 workflow
  gates). Revisit condition: none — this *is* the daylight the entry
  above asked for.
- **`Chain.t()` carries its resolved `predicates.yaml` map forward**
  (ORC-8, named here because the reactive scheduler is the first
  runtime consumer). `Chain.build/3` already resolves and validates
  every named predicate a bundle's four slots (`scope_filter`,
  `cardinality.when`, an edge `constraint`, a flow `completion`,
  dsl-syntax.md §8) reference — then discards the map once load-time
  validation passes. Nothing downstream can evaluate a `scope_filter`
  reference against live graph state without it; re-parsing
  `predicates.yaml` independently would double-implement this system's
  own load path and risk drifting from what the loader actually
  validated. The fix is a field, not a second reader: `Chain.t()` gains
  `predicates: %{String.t() => Predicate.t()}`, populated from the
  value `build/3` already computes. `systems/engine.md` records the
  runtime-evaluator decision this field exists to serve.

## Initial vs target

Initial (Phase 3): core vocabulary, loader, design-dialect extension
set (delivery annotations arrive with delivery). Target: full
extension registry with delivery + runtime dialects registered;
bundle-diff support for the registry's handle machinery.

## Depends on

substrate. Content it loads lives in platform_content.

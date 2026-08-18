---
paths:
  - lib/catapult/dsl/**
  - test/catapult/dsl/**
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

## Initial vs target

Initial (Phase 3): core vocabulary, loader, design-dialect extension
set (delivery annotations arrive with delivery). Target: full
extension registry with delivery + runtime dialects registered;
bundle-diff support for the registry's handle machinery.

## Depends on

substrate. Content it loads lives in platform_content.

---
paths:
  - catapult.yaml
  - bundles/**
  - lib/catapult/dsl/loader.ex
---

# The bundle

A project runs on two bundles on two independent axes (v5 §7.18): a
**chain** bundle, the document graph the agents build, and a
**workflow** bundle, the human cycle of positions, gates and
environments around it. This document is the contract for what a
bundle is on disk and how the two axes meet; `chain.md` and
`workflow.md` are the contracts for each axis's own file. Every rule
carries an id and its reason lives in the `.reasons.md` sibling
(conventions §12). A construct is marked **live** when the engine
reads it today, or **reserved** with the consumer that will, and a
reserved construct is grammar the loader accepts and checks now so a
bundle written against it does not change shape when the consumer
lands.

## #1 Two files, one per axis

- **#2 `catapult.yaml` at the repo root names exactly one bundle per
  axis and nothing else.** It is the loader's input, not bundle
  content: `chain: <name>` and `workflow: <name>`, each resolving to
  `bundles/<name>/`. A project has one document graph even when its
  components span languages, so there is no list form; per-stack
  variation lives inside the one chain's own tiers and prompts.
- **#3 A chain bundle is one declaration file plus the content it
  names.** `bundles/<name>/chain.yaml` carries every tier, edge, flow
  and predicate; `schemas/<tier>.xsd` carries each draft's grammar and
  the intra-node facts (#7); `prompts/<tier>.md.liquid`,
  `prompts/review/<tier>.md.liquid`, `prompts/reconcile/<tier>.md
  .liquid` and `prompts/partials/*.md.liquid` carry the prose;
  `flows/<flow>/*.md.liquid` carry a flow's own prompts. A path in the
  declaration is relative to the bundle and may not escape it: a
  `prompt:` of `../..` reads as not found, never as a file.
- **#4 A workflow bundle is one declaration file.**
  `bundles/<name>/workflow.yaml` carries every type, gate and
  environment, and the chain tier and flow names each type binds to
  (#11). It names no file outside itself.
- **#5 The manifest fields are `name`, `version` (reserved: the
  registry, for bundle pinning) and `kind: chain | workflow`**; a
  bundle of the wrong kind on an axis, an unknown top-level key, and
  a bundle that names `extends:` are each a load error.

## #6 Fork, tailor, merge upstream

- **#7 No bundle has a base layer.** The platform's `bundles/default`
  and `bundles/default-flow` are templates a project forks and
  tailors; nothing composes them back in underneath at load time, and
  a forked file's divergence shows in `git log` where a layered
  override would show nowhere. Later platform revisions arrive by
  ordinary git merge, with a conflict where both sides touched the
  same lines (v5 §3.1).
- **#8 Forking composes content and never adds vocabulary.** New
  generator types, context-source kinds, enforcement profiles and
  annotation namespaces are the extension registry's (reserved: the
  registry system, v5 §9); a bundle declares instances against
  installed vocabulary and carries no code of its own, which is what
  keeps the predicate language (`chain.md` #37) short of Turing
  completeness and lets the loader validate everything it accepts.

## #9 Where a fact lives

- **#10 A fact about one document lives in that document's schema; a
  fact relating two nodes lives in the chain file.** Identity, the
  fields a handle exposes, and how many of an element a body may
  carry are annotations and occurrence bounds in the XSD (`chain.md`
  #32); which element mints which tier's children, what a tier
  produces onto its parent, and every walk are in `chain.yaml`. The
  commit path validates a draft against its schema before the event
  lands, so the schema is the enforcer of what it states.
- **#11 The workflow references the chain, checked at load; the
  chain never references the workflow.** A generation position names
  the tiers that run at it (`workflow.md` #22) and a ticket type names
  the chain flows it serves (`workflow.md` #40). A tier, an edge and a
  flow name no position, gate or type anywhere, so a chain bundle is
  valid on its own, and it is the pair that fails at load: a position
  naming a tier the chain does not declare, and a served flow's tier
  that no position lists, are each an error rather than a fallback.
- **#12 Between the two files, the loader warns and never errors on
  shape mismatches that only degrade.** A generation position none of
  whose tiers are active in a given flow, and a gate depth deeper than
  the chain fans out, each produce a load warning and then apply at
  the levels and positions that exist (`workflow.md` #24, #28). A
  mismatch that would leave work unrun or unplaced is #11's error
  instead.

## #13 The acceptance test

- **#14 The default pair is readable in one sitting by someone who
  has not read the engine.** `bundles/default/chain.yaml` is at most
  800 lines including comments with comments at most a fifth of that,
  `bundles/default-flow/workflow.yaml` at most 240, and both read in
  thirty minutes. A change that breaks the bound is a design change,
  reviewed as one.

---
paths:
  - docs/dsl/**
---

# The retired DSL spec, section by section

`docs/dsl-syntax.md` was the normative DSL grammar until `bundle.md`,
`chain.md` and `workflow.md` replaced it. It is gone from the tree, and
its citation shorthand resolves to nothing on purpose, so that no pass
supplies an invented path for it.

This index is what a reader follows instead. Each row names what a
section of the retired spec stated and the rules that state it now. It
exists because the citations outlive the document: `bundles/**` still
cites it until its tree is replaced, and git history cites it forever.
Cite the rule, never the row — a rule id survives a rewording and a
section number does not.

Where a row says **no successor**, the section stated something the
redesign removed. Those are the rows to read before concluding that a
rule went missing.

## Chain sections

| Retired | What it stated | Now |
|---|---|---|
| §1 | Two bundles on two independent axes, and the files each carries | `bundle.md` #1, #2, #3, #4 |
| §2 | The manifest fields, and `entry:` naming the root type | `bundle.md` #5; `workflow.md` #2 |
| §3 | Tier declarations and every key on one | `chain.md` #4 through #17 |
| §3 (`fields:`) | `mint.<name>`, `mint.parent.<name>` and `reference.<name>` as field sources | `chain.md` #12, narrowed to cross-node copies; a node's own fields are schema annotations (`bundle.md` #10, `chain.md` #32) |
| §3.1 | The closed scope set | `chain.md` #6 |
| §3.2 | The closed generator set | `chain.md` #8 for `llm` and `supplied`, #17 for a supplied tier's `source:`, #39 for the four reserved |
| §3.3 | `reviews: <tier>`, a review as a tier of its own | `chain.md` #14, where a review is a `review:` block on the tier it reviews |
| §4 | Edge declarations, the closed type set, navigation edges | `chain.md` #24, #25, #26, #23 |
| §4.1 | `instances:` and the multi-instance form | `chain.md` #27 |
| §4.2 | `source_ref:` and `target_ref:` | `chain.md` #27 |
| §6 | Flows, their walks and their ticket face | `chain.md` #38, #40, #41 |
| §7 | Context walks | `chain.md` #18 through #23 |
| §7.1 | Hop chains and reversal | `chain.md` #19 |
| §7.2 | `all.<tier>` | `chain.md` #19 for the form, #22 for what it costs in readiness |
| §8 | The predicate language | `chain.md` #37 |
| §9 | Prompts, their variables, `input.<role>` | `chain.md` #34, #35; `input.<role>` is #19 |
| §10 | Body grammars | `chain.md` #31, #32, #33 |
| §11 | Fork, tailor, merge upstream; no `extends:` | `bundle.md` #6, #7; the manifest refusal is #5 |
| §12 | Extension registration | `bundle.md` #8 |
| §14 | Deliberately absent | **No successor.** The section was dropped: its contents read as an argument to whoever was present for it, and each of its refusals that still binds is stated where the rule it qualifies lives, or in `docs/non-goals.md` |

## Workflow sections

| Retired | What it stated | Now |
|---|---|---|
| §15 | Workflow declarations as a whole | `workflow.md` |
| §15.1 | The fixed kind table, the skeletons, `pending`, the lifecycle mapping | `workflow.md` #4 for skeletons, #10 for kinds, which are now the shapes the engine branches on; `design`, `architecture` and `implementation` return as `name:` values, and `pending` becomes an engine flag (#25) |
| §15.2 | One work-item declaration per file | `workflow.md` #4, #5; every type is an entry of the one `types:` block (`bundle.md` #4) |
| §15.3 | The array is the only ordering mechanism, and there is no `after:` | `workflow.md` #12 and #16 state the relative orders the array carries. **No rule restates the absence of `after:`**, because no key was ever added to refuse |
| §15.4 | Gate and environment declarations | `workflow.md` #31 through #36 for gates, #37 through #39 for environments; `depth:` on a citation is #33 |
| §15.5 | `critique` paired with a peer generation entry | `workflow.md` #26 |
| §15.6 | Nesting, and the declaration graph that bounds it | `workflow.md` #9 for `flow:`, #28 for depth filtering. **The declaration-graph acyclicity check has no rule here**; it is the loader's, `systems/core_dsl.md` #15 |
| §15.7 | Queues, dispatch, blocking | `workflow.md` #16 through #19 for the container backbone, #29 and #30 for queue-shaped types, #9 for `flow:` |
| §15.8 | Mint versus activation | `workflow.md` #19 |
| §15.9 | The declarable-protocol narrowing | `workflow.md` #10, #30 |
| §15.10 | Sub-arrays and throwback | `workflow.md` #6 for the group, #8 for how a reference reaches into one, #34 and #35 for throwback |
| §15.11 | `reconcile` before `merge`, and gate scope from position | `workflow.md` #13, #27, #36; the fan-out tier's own `reconcile:` block is `chain.md` #15 |
| §15.12 | A status entry's `name:`, and positions namespaced by it | `workflow.md` #7, #8 |

## §13, load-time validation

§13 was a single checklist of every load-time check, which is why it
was cited more often than any section but §15.10 and §15.1. It has no
single successor, and that is the point: each check now sits on the
rule it enforces, so a rule and its check are amended together rather
than drifting apart in two places.

To repoint a §13 citation, read what the sentence is checking and cite
that rule. The checks cited most often, and where they live:

- unknown keys, at any level, refused: `chain.md` #2, `workflow.md`
  #2, `bundle.md` #5
- every context hop checked against the declared edges: `chain.md` #19
- a walk that resolves to a later position: `workflow.md` #23
- a tier no position lists, and a position naming an undeclared tier:
  `bundle.md` #11, `workflow.md` #22
- a name that recurs in one type: `workflow.md` #7
- a reference resolving to none or to several: `workflow.md` #8
- a `critique` that is not adjacent to the position it reviews:
  `workflow.md` #26
- `merge` not preceded by `reconcile`: `workflow.md` #13
- a handle narrowed to a name outside the node's own set: `chain.md`
  #11
- a `produces` or `declared_in` path resolving to no element:
  `chain.md` #32
- a draft validated against its schema before its event lands:
  `chain.md` #33

## The sites that still cite it, and why

Twenty-seven sentences in `systems/*.md` still name the retired spec.
Each was left on purpose: the sentence states a rule the redesign
reversed, so repointing it would make the doc assert something the
cited rule contradicts. Each needs its sentence decided, not its
citation fixed. They fall into five reversals.

- **Positions namespaced by their sub-array.** Not a reversal after
  all, and the sites are repointed rather than left: `<anchor>.<name>`
  inside a sub-array and a bare name at the top level both survive
  (`workflow.md` #7, #8), which is what `seam-decisions.md` §2.B.4
  decided. An earlier draft of those two rules flattened the namespace
  to one per type; the rules now say what was decided.
- **`pending` as a declared entry.** It is an engine flag every
  agent-balled position carries (`workflow.md` #25), so the
  opens-with-pending, pending-precedes and sub-array-head rules have
  nothing to attach to. Sites: `delivery.md` 310; `delivery.reasons.md`
  499.
- **`design`, `architecture` and `implementation` as status kinds.**
  They are `name:` values on generation entries (`workflow.md` #10).
  Sites: `delivery.md` 625, 1157; `delivery.reasons.md` 193.
- **A fan-out child running a second declared type.** Settled, and the
  sites are fixed. One type serves every depth, a position's depth
  comes from the tiers it lists, and a ticket stands at a position
  when its own depth is at most the deepest tier there (`workflow.md`
  #28). A child exists only where a fan-out spawns one, which no
  product-tier fan-out does (#41, `chain.md` #42).
- **`scope: reference`, `generator: reference`, and `reviews:`.** A
  ref is a supplied tier with no scope (`chain.md` #5, #17), and a
  review is a block on the tier it reviews (`chain.md` #14). Sites:
  `core_dsl.md` 70, 689, 729; `engine.md` 246, 251, 462;
  `engine.reasons.md` 182; `generation.md` 127; `platform_content.md`
  170, 208, 340, 1000, 1008, 1040, 1058;
  `platform_content.reasons.md` 342.

Two more sit outside those five: `core_dsl.md` 116 and 376 are entries
already marked superseded by the entry below them, and `core_dsl.md`
225 and `delivery.md` 318 state that a gate with no earlier entry must
declare `throwback:`, where `workflow.md` #35 now lets it have none.

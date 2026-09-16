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

## Who still cites it

No document in `docs/`, `systems/`, `screens/` or `seed-docs/` cites a
section of the retired spec any more. Every one of those citations was
read and repointed at the rule that replaced it, or dropped where the
sentence already stated its rule.

`bundles/**` still cites it, in the header comments of the per-tier,
per-edge and per-type files. Those files are replaced wholesale when
the default pair is rewritten as `chain.yaml` and `workflow.yaml`
(`platform_content.md` #64), so scrubbing a comment in a file being
deleted buys nothing; the citations go with the files.

Git history cites it forever, which is what this index is for.

Three reversals were settled rather than repointed, because the
sentence carrying them stated a rule the redesign reverses. Each is
now recorded in the superseding entry of the document that carried it
— `core_dsl.md` #45, `delivery.md` #125, `platform_content.md` #64 —
rather than restated at every site:

- **`pending` is an engine flag, not a declared entry** (`workflow.md`
  #25), so the opens-with-pending, pending-precedes and
  sub-array-head rules have nothing to attach to.
- **`design`, `architecture` and `implementation` are `name:` values
  on generation entries, not kinds** (`workflow.md` #10).
- **`scope: reference`, `generator: reference` and `reviews:` leave
  the vocabulary.** A ref is a supplied tier with no scope
  (`chain.md` #5, #17) and a review is a block on the tier it
  reviews (`chain.md` #14).

Two rules the retired spec stated and the redesign had dropped were
found by this pass and carried into the contract rather than lost:
`chain.md` #22's refusal of an `all.<tier>` read of a never-draining
write-sourced pool (and of a non-zero cardinality `min` on an edge
naming one), and `workflow.md` #35's reversal of the forced
`throwback:` on an ungrouped gate, which #45's and #125's own entries
record as a change rather than a move.

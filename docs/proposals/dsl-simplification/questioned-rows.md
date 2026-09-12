# The questioned rows, resolved against v4 and the author

`classification-matrix.md` §3 listed eleven constructs with no engine
reader and no intent the v5 record names. The author answered each
and asked for a cross-reference against the vendored v4 corpus
(`seed-docs/catapult-spec-v4.md`, `catapult-default-bundle-v4.md`,
`-examples.md`), which is where most of the original reasons live.
This file records what v4 said, what the author decided, and what
each resolution changes in the plan. Where the author's memory and
v4 disagree, v4 is quoted and the disagreement is named.

| Construct | v4 says | Author | Resolution |
|---|---|---|---|
| `scope_filter` | needed for three mechanisms v5 removed | inclined to drop; suspected the logic moved to templates and handles | **retire** |
| `cardinality.when` | the default bundle's "foundation at every level" invariant | validation of agent-produced structure | **reserved**: projection-time content invariants |
| `cardinality.per_source` | named once in the spec, never used | same | **retire** |
| edge `constraint` | domain/presentational endpoint condition, removed with that split | sibling-dependency scoping; acyclicity moved | **retire**; sibling scoping is instance placement |
| `git_commit`, `webhook` generators | v4's code-delivery tier and external-post tier | keep the door open: repo commits, history and events as context and flow triggers | **reserved**, intent now recorded here |
| `produces: {owner: self}` | never appears; every v4 `produces` is `self.parent` | scrap if not in v4 | **retire**, with its runtime branch |
| gate `depth` | no gates in v4 | wanted: scaffolding reviews the whole tree, a feature reviews the system and component levels | **live**; the record sentence "0 is the rule" is wrong and goes |
| `lifetime: per_ticket` | no environments in v4 | PR-specific environments; semantics free | **reserved** with environments |
| `generator: synthesis` / `.synthesis` | reverse aggregation (`fanin`), readiness = all children approved | not needed for the default; a possible future want; open question on reconciliation | **rename** v5's join target; aggregation deferred until asked; reconciliation to seam entry 21 |
| `name:` on a status | no workflow in v4 | needed once several roles share review duties; unneeded today only because one gate per scope | **live** |
| sub-arrays (raised alongside) | no workflow in v4 | keep: default throwback, child-lead scoping, reconcile/merge scoping, visual grouping; the skeleton is the uncertain part | **keep**; seam entry 16 amended; skeleton to entry 21 |

## `scope_filter` — retire

v4 A.2.2: "a predicate further restricting which scope-parents the
tier attaches to ... evaluated at scheduler enumeration time." Every
v4 use served a mechanism v5 removed by a recorded decision:

- `presentational_comparch: scope_filter: awaits_domain_fanin`
  (v4 examples): the domain/presentational fan-in. v5 §4.1 replaced
  it with the product/backend/frontend split; `seed-docs/README.md`
  lists `fanin`, `domain_parent` and `kind: domain | presentational`
  as not carried forward.
- `scope_filter: in_cascade_visit_set` on every planning tier (v4
  examples §A.5): replaced by the `cascade_visit` scope kind, which
  `dsl-syntax.md` §3.1 records as the replacement.
- `scope: per(impl_owner) × phase` with `impl_owner` a named
  predicate: phases were dropped entirely (v5 §6).

The author's memory is confirmed on both counts: it mattered to the
v4 default bundle, and the conditional logic moved into scope kinds
and the family split rather than staying as a predicate. Nothing in
v5 needs the slot; the tree never uses it (report D). Retire it. The
evaluator hook in `ReadyScopes` goes with it, and the predicate
language survives only in the slots below.

## `cardinality.when` — reserved; `per_source` — retire

v4 A.2.3: "Cardinality can be conditional (`cardinality.when: kind ==
presentational`) and scoped (`cardinality.per_source(parent_tier)`)."
The default bundle's §4.1 is the real use:

> Every project must have at least one foundation top-level
> component. Every comparch must declare at least one foundation
> subcomponent. ... Implementation: a named predicate
> `has_foundation_child` plus cardinality on the comp tier and the
> subcomp tier: `count(decomposed_by(child) where child.is_foundation
> == true) >= 1` ... `cardinality.when: has_foundation_child`.

And A.2.8 gives the enforcement semantics: a violation "is rejected
at commit (the offending commit fails validation, the body file is
rejected, the agent sees a typed error and can retry)". So the author
is right: `when` was validation of what the agent produced when it
connected nodes, checked at projection, and it is a *cross-node*
invariant an XSD cannot express (`minOccurs` counts elements; it
cannot count elements with `is_foundation="true"`).

In the tree the invariant survived only as prompt instruction:
`sysarch.md.liquid:181` ("Exactly one component must carry a
self-closing `<foundation/>` marker") and `:204` ("every non-
foundation component must have a `<dep>` edge pointing at the
foundation component ... enforced by the validator"), with
`is_foundation` carried as a mint field. No validator enforces it;
`GraphConstraints` has no caller (report E). So the mechanism is
reserved with a clear consumer: **projection-time content
invariants, rejecting the commit with a typed error, per v4 A.2.8**,
and the predicate language stays for this slot. `per_source` was
never used, even in v4; retire it.

This corrects `seam-pass.md` entry 6, which argued cardinality was
"an XSD fact or a type tautology" in every shipped row. That is true
of the 62 plain `min`/`max` rows and they still move to the XSD;
`when`-conditioned bounds are the case the XSD cannot take.

## Edge `constraint` — retire

v4 A.2.6: "value conditions on an edge's endpoints (e.g. `source.kind
== presentational AND target.kind == domain`)". Its one purpose was
the domain/presentational split, removed with it. The sibling scoping
the author remembers was not `constraint:` in v4 either; it was a
scope qualifier on the instance ("subcomp deps scoped to
`within(comparch)` — both endpoints must live in the same parent's
fanout", v4 bundle §2.5), and acyclicity was always
`graph_constraint`. In the tree, `dependency.yaml`'s own comments say
the within-comp instances are "scoped to siblings under the same
comparch instance" by where the row is declared. Whether the locator
actually refuses a cross-parent target is for the prototype's tests;
the grammar needs no `constraint:` key for it. Retire.

## `git_commit` and `webhook` generators — reserved, intent recorded

v4 A.1.7 names four generators: `llm`, `git_commit` ("the body comes
from a git commit on the project repo ... code-delivery tiers whose
content is the actual source"), `synthesis`, `webhook` ("the body
comes from an external system posting to a Catapult endpoint"), plus
admin-approved additional types. A.10.4 specifies `git_commit`
(`code_repo_url`, `path_from_handle`) for the v4 `code` tier, whose
job v5 moved to delivery (tickets and PRs produce code; no chain
node holds it). v5 added `external`, `template`, `supplied` and
`reference` and never mentions the v4 two, which is why the matrix
found no intent.

The author's intent, recorded here since no record sentence carries
it: **other sources should be able to act as generators, so that
repository commits, history and events can serve as context and as
triggers for flows.** None need implementing in v0. Both rows move
to reserved; the contract doc marks them with this sentence and
names the flow engine and delivery's host port as the likely
consumers. `seam-pass.md` entry 3 is amended to match.

## `produces: {owner: self}` — retire

Every `produces:` in v4 (spec A.2.2's example, bundle §3, examples
§1) is `owner: self.parent`. `self` as an owner appears nowhere in
v4; it is a v5 addition with no use, and the engine discards it at
runtime (`:self_not_yet_known`, report E). Retire the value and the
branch. Entry 9's "owner implied" stands.

## Gate `depth` — live; correct the record

v4 has no gates: human review was `approve_draft` per node, after
every tier, which is the granularity entry 20 discusses. Depth is
v5's (§7.19): "omitted or `0` means the top level only; `1` adds
components; `2` adds subcomponents", with the simplifying assumption
that validation wanted at a nested level is wanted at every level
above it. The author's intent: **scaffolding reviews the whole tree;
a feature reviews the system and component artifacts and catches the
lower levels by reviewing the reconciled branch.** That is depth `2`
on scaffolding's gates and `1` on a feature's.

What made the key look questionable is one sentence in the spec,
`dsl-syntax.md` 2349: "Depth 0 is the rule for a gate, not merely its
default (v5 §7.19)", attributed to v5 but not in it, and repeated in
`gates/ux-review.yaml`'s comment (ORC-92). It contradicts the intent
above and is why all five gates carry `depth: 0`. The row is live
(the key stays, the value space is real); the enforcement is Phase 7
with the rest of gate scope; the sentence at 2349–2358 does not
survive the rewrite. Note for entry 20: depth and free status names
are orthogonal (names select positions, depth selects levels within
one), so freeing the names does not make depth redundant.

## `lifetime: per_ticket` — reserved with environments

No environments in v4. The author: `lifetime` exists so PR-specific
environments can be supported; the functionality is wanted and the
semantics are not fixed. Reserved with the rest of the environment
keys, consumer delivery Phase 7 deploy; the contract marks the value
with that intent.

## `synthesis` — one name, three things

v4 `generator: synthesis` (A.1.7, A.2.3) is **reverse aggregation**:
"the body is computed by aggregating the tier's children's handles.
Re-runs when any child's relevant content changes." The default
bundle's `fanin` tier used it (bundle §4.4), and readiness was not
special machinery: "just the default 'cardinality-many requires all
targets ready' applied to a synthesis tier's child-aggregation walk"
(A.2.5). v5 §4.1 removed `fanin`; v5 §5.1 then **reused the generator
name for join targets** ("`comp`/`subcomp` ... are `generator:
synthesis` join targets — no draft, no prompt"), which is a different
thing: a minted node with no computed body. `core_dsl#42` retired the
`.synthesis` projection because nothing consumed it. Separately the
`synthesis` **edge type** survives for flows' `plan_target`, and v5
4231 says "a chain bundle may attach a synthesis tier to a
`reconcile` position, and does not have to."

The author's position: the default does not need aggregation; the
doc-routing reason for summaries is gone; a component- or system-
level implementation summary for human review is a possible future
want; it broadens the class of DAG the DSL can model; let users ask
before building it; if ready scopes and cardinality are right it is
easy to add back. And an open question: is reconciliation modelled
in the chain as a synthesis node, or is it its own thing, possibly
folded into the fan-out declaration?

Resolutions:

- **Rename v5's join-target generator.** It is not synthesis; call it
  what it is (`join`, or the absence of a generator, which v4 A.1.1
  already allowed: "tiers can also exist as pure join targets"). That
  frees the word for the v4 meaning.
- **Aggregation is deferred until asked**, not in v0, with the note
  that v4's readiness rule for it is already what the engine
  implements (`all.<tier>` plus `drained?`), so re-admitting it is a
  generator with a computed body, not new readiness machinery.
- **Where reconciliation lives is seam entry 21.**

## `name:` on a status — live

No workflow in v4. The author: it is the only way to distinguish two
entries of one kind, which does not arise today because there is one
human gate per scope and the sub-array anchor syntax covers it, and
becomes essential once several people with different roles share
review responsibility on some things and not others. Live, kept. It
is also what entry 20's free-names proposal reuses, so it is load-
bearing twice.

## Sub-arrays and the skeleton — keep the arrays; the skeleton is the question

The author's decision on sub-arrays: keep. They give a default
throwback target (if the derived default is never used, the default
was chosen wrong; that is a fix, not a removal), they scope how far
ahead of a parent a child ticket may get, they scope reconcile and
merge behaviour, and they are the visual grouping the board renders.
The alternative, a `group:` label on flat entries, would need
consecutiveness enforced by a check; the array is form following
function. `seam-pass.md` entry 16's "prototype flat" recommendation
is withdrawn.

What the author is less sure of is the **ticket skeleton**: today it
is what relates a generation step to fan-out, to reconciliation, to
merge, and those relations read as implicit requirements of the fan-
out feature itself. That is a seam question of the first kind (is the
skeleton the engine's requirement, or a restatement in the workflow
of structure the chain already declares?) and it is taken up with
reconciliation in entry 21, because the two are one question: if the
chain's fan-out declaration carried its own fan-in, the skeleton's
generation → reconcile → merge relation would be derived from it.

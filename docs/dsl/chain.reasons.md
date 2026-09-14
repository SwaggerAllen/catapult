# chain — reasons

The reason behind each rule in `docs/dsl/chain.md`, keyed by the rule's id (conventions §12). Read one with `pipeline reasons chain#n` before changing the rule it belongs to.

## #2

A closed key set at every level is what lets a misspelling fail at
load instead of becoming a silent no-op; it is the same discipline the
first grammar's loader had, stated once here rather than per section.

## #3

Seventeen of 22 root tags, 19 of 22 grammars and nearly every prompt
path already equalled the derivation, and `executor` was `max` in all
ten uses. A default the author overrides where the value differs costs
nothing there and removes a line everywhere else. The block is limited
to scalars because a bundle-level default for context would reintroduce
the merge-by-tier rule that fused distinct reads at eighteen sites
(ORC-247, review 5). The effort reason is on the block itself because
a later pass simplifying `max` away would otherwise have nothing to
argue with.

## #5

The three kinds are what the engine already branches on: a draft to
validate or not, a source to pin or not. Making them a matter of which
keys are present, rather than a `kind:` field, means a tier cannot
declare one thing and carry the keys of another. The `synthesis` and
`reference` generators were the old way of saying "join target" and
"supplied by a write path", and both duplicated what the absence of a
draft or the value of `source:` already said.

## #6

`cascade_visit` is reserved with flows because its nodes are minted by
a traversal, not by a draft, and ORC-247's review 5 found its targets
never drain, so the readiness rule (#22) needs the flow engine to say
what `all.<tier>` means inside a flow ticket.

## #7

`agent_step` is gone because its intended consumer, the bindings file
mapping an agent kind to a runtime, is served by the executor profile
(#10), and its only shipped values were derivable (`design` on every
generating tier, `critique` on every review) while colliding with the
human `role: design` on a gate. `phase:` is required rather than
defaulted because under free position names there is no default to
derive (`bundle.md` #18).

## #8

A join target has no body of its own, so "no draft" is the fact and
a generator name for it was a second spelling of the same fact. The
reserved generators stay parseable so a bundle written against them
does not change shape when their consumer lands (`bundle.md` intro).

## #9

The five plan tiers are the only ones whose prompt lives with their
flow rather than under `prompts/`, so the default covers 17 of 22 and
the exception is written where it applies.

## #10

v5 §7.10 names agent kinds as protocol vocabulary and says the
project bindings file maps kind to runtime; the profile is that
mapping's input. Keeping it a map rather than an enum is what lets a
second agent implementation be a new bindings entry and zero grammar
change.

## #11

Checked against the tree at the redesign: none of the nine spine tiers
or ten join targets narrowed its handle; all 34 blocks were `[id] +
every field`. Information hiding between tiers is a real tool, so the
override stays, with the subset check that was missing.

## #12

`mint.parent.<kind>` relates two nodes (the child field is the
parent's fragment), so by `bundle.md` #10 it stays in the chain; a
draft's own element or a mint element's own attribute is a fact about
one document and moves to the schema. The four join targets that carry
these copies are the only `fields:` left, which is what makes the
chain file readable as a graph rather than a field inventory.

## #13

Every `produces` row in the first grammar and in v4 was `owner:
self.parent`; `owner: self` appeared nowhere in v4 and the engine
discarded it. A map keyed by kind is the shortest form that still
makes every produced kind visible in the declaration, which is what
derives the fragment vocabulary.

## #14

All 17 review tiers were seven keys of which four were constants and
one a byte-identical copy of the reviewed tier's context, with a load
rule that the copy be exact; `ContextAssembly` already ignored the
review tier's own walks and recomputed from the reviewed tier. A
property of the tier is the shape that was already true. The position
is derived because a review is one-to-one with the tier it reviews, so
"the first critique after mine" is the only place it can go; the
override exists for a workflow with more than one critique per
position. `default` is written explicitly rather than inferred from
the prompt file's existence so a reader of the chain file sees which
tiers are reviewed.

## #15

The author's: fan-outs need a reconcile because Phase 7 opens one PR
per child ticket and merges them into the parent predictably, with
gates possibly before and after; only the workflow can place a
position and gates around it, and only the chain knows what an agent
should say when the children are joined. The two are not mutually
exclusive: the prompt lives with the fan-out tier the way a review
prompt lives with the tier it reviews, and the position stays a
workflow entry. The five prompts the default names are new files.

## #16

Profiles are platform-shipped (v5 §2.14) and bind delivery gates such
as `codegen: restricted`; the chain names fixed vocabulary here and
never declares a profile, which is what keeps it composable with any
workflow (`bundle.md` #11).

## #17

`reference` and `supplied` were both "externally sourced, never
generated, never drained" and differed only in where the content came
from, which is a `source:` value. The author's condition on the merge
was that enough syntax stay to identify supplied nodes and propagate
changes from them; `generator: supplied` plus `source:` is that
syntax.

## #19

The walks are the DSL's core and survive unchanged: hop chains and
the reversed hop exist because a policy scoped through a
responsibility is two hops with the second against the edge's
direction, and no one-hop grammar can say it. The load-time check is
of well-formedness against declared edges, never of instance data.

## #20

The count that decided it: of the 165 walks the first grammar's
bundle declared, 107 were an
edge whose source was the tier or its scope parent, and the projection
varied by edge type, not by tier; every `dependency` read
`fragments[pubapi]`, every `reference` read the handle. Deriving
those from the edge declaration removes two thirds of the ceremony
and, because a derived read is named by its edge, removes the
merge-by-tier rule that fused distinct reads of one tier at eighteen
sites. The collision rule exists because the redesign's first
derivation silently overwrote `ui_coll → ui_coll` with `ui_coll →
design_system` under the one name `dependency`, and only a walk-by-walk
comparison against the tree caught it.

## #21

Additive only, because the count found no tier that had an edge from
itself or its parent and did not read it, once `fanout` edges carry
no context (#26). `all.*` and `input.*` are 56 of the 165 walks and
are not edges, so they stay explicit; naming them is what makes every
prompt variable visible in the declaration. The reserved names are the
ones `ContextAssembly` binds itself.

## #22

Context as the only readiness signal is v4 A.2.5's rule and the
engine's: readiness is `drained?` per tier plus every walk target
approved. `all.<tier>` inside the driver closure is refused because
adding `all.policy.handle` to `comparch`'s context was a permanent
deadlock when `policy` had `comparch` among its three fanout drivers
(ORC-247, review 3); single-sourcing `child_of` (#28) is what makes
`drained?` decidable at all. The flow-ticket case is reserved because
the redesign's traversability check first called a plan tier's
`all.sysarch` read an ordering error, and it is not: the plan reads
the approved graph it is about to regenerate, which is the flow
engine's semantics to state.

## #23

v5 §4.3: navigation edges connect screens for the journey's sake and
are structurally cyclic, so they can neither carry readiness nor be
walked for context without either a cycle or a read of nothing. The
`~` reversal check runs on every hop so a reversed hop cannot smuggle
one in.

## #26

`fanout` carries no context because the one subtraction case the
derivation met was exactly this: `feature_expansion → vocab` is a
fan-out from the parent of `journeys`, `screens` and `requirements`,
and none reads `vocab`, while `sysarch` does read its parent's
`resp` fan-out and declares that read explicitly. `synthesis` is the
edge a cascade rides and is reserved with the flow engine that runs
one.

## #27

Locators are explicit because the author prefers self-documentation
to a convention to remember, and the stakes are low either way. The
instance-level `context:` and `as:` exist because the derivation met
`ui_coll → design_system`, an edge instance whose target has no
fragments and which shares a source with another instance of the same
edge. The list form is the only form because the inline form existed
for four files and needed an exclusivity check against the list. A
list-valued `synthesis` target replaced twenty-one rows that differed
only in target.

## #28

The engine's requirement under its readiness model, not a style rule:
`drained?` is per tier, so a pool with several drivers cannot be
safely read with `all.<tier>` by any of them. The alternative was
per-instance readiness in the engine; the grammar constraint was
cheaper and the author chose three same-shaped tiers, which in one
file cost two lines each.

## #29

The mint form makes the locus explicit where the first grammar wrote
`policy.structural` and left a reader to guess whether that was a
draft path; it is the form the `policy_application` family needs once
a policy's own `<required>` child is what binds it.

## #30

v4 A.2.8's enforcement semantics: a violation is rejected at commit
with a typed error the agent can retry against, rather than
discovered at projection after the body is in the graph. The
`GraphConstraints` module carried this check with no caller in the
first tree; the commit path is its caller.

## #32

`bundle.md` #10: identity and fields are facts about one document.
The schemas carried no annotations before, so this is three facts
moved, not a reshuffle. The loader already walked every schema to
check `declared_in` and `produces` paths, so reading `xs:appinfo` is
more of the same; the cost is that the schema becomes the file an
author edits for document shape, which the author accepted.

## #33

The XSD was always the enforcer: the commit path validated every
draft against its grammar and nothing read the DSL's 62 cardinality
rows. Stating the plain bounds once, where they are enforced, removes
the copy; the cross-node case that `minOccurs` cannot state is #37's.

## #35

The variable set is exactly the context declaration, derived and
explicit, so a prompt author can read one tier's entry and know every
name. The partial rule is ORC-134's finding, restored at ORC-184: a
`{% render %}` without `with` or `for` builds the partial's context
with an empty variable map, so a guard inside the partial is
unreachable.

## #37

The predicate language is kept for exactly two slots because those
are the two the tree needs and cannot express otherwise: v4's
"foundation at every level" invariant counts children by a field
value, which no schema bound can, and a flow's completion is a
condition over nodes the flow minted. `scope_filter` and edge
`constraint`, the other two slots the first grammar had, served
mechanisms v5 removed.

## #38

Flows are reserved because nothing dispatches them yet, and their
shape is settled now so the five plan tiers and their `synthesis` edge
do not change when the engine lands. The flow names its type because
strict binding (#7) needs to know which type's positions to check a
tier against, and the first grammar paired flow and type by an
unchecked label convention. The seed flow is the scaffold pass (v5
§7.9), the whole chain from the raft with no prior graph.

## #39

v5 §9: the core is frozen and growth happens in extensions, so these
are vocabulary the registry installs rather than productions the
grammar owns. The author's intent for `git_commit` and `webhook`,
recorded because no record sentence carried it: other sources should
be able to act as generators so that repository commits, history and
events can serve as context and as flow triggers. `template` is kept
because it is cheap to implement and has uses; rendering a template in
the plane makes no model call.

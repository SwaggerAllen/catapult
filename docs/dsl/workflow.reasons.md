# workflow — reasons

The reason behind each rule in `docs/dsl/workflow.md`, keyed by the rule's id (conventions §12). Read one with `pipeline reasons workflow#n` before changing the rule it belongs to.

## #2

A closed key set fails a misspelling at load; `entry` is the only way
to name the root type and nothing reads it until provisioning does,
which is why it is live grammar with a named consumer rather than
reserved.

## #4

Three skeletons because the engine runs three lifecycles: a ticket
has a PR and a merge, a container has queues that open other work,
and a project is queues alone. The skeleton is what the loader checks
an array's shape against (#12, #16, #30) and what the runtime projects
a lifecycle from.

## #5

Three entry shapes because three things happen in a sequence: a
work item rests somewhere, a human signs off, or a result is promoted.
An environment is an entry rather than a property of `deploy` because
a type may deploy to more than one target in sequence, and the entry
form keeps the order visible.

## #6

The author's decision, against a flat array with a `group:` label:
sub-arrays give a default throwback target, bound how far ahead of a
parent a child may run, scope reconcile and merge behaviour, and are
the grouping the board renders, with consecutiveness free rather than
enforced by a check. They are anonymous because a reference reaches a
grouped entry through the entry's own name (#8), so a group name
would be a second way to say the same thing.

## #7

`name:` is what distinguishes two entries of one kind, which is every
generation position under free names and every critique that follows
one. The namespace is the sub-array rather than the type, and the flip
is why that matters more than it did: with the binding on the position
rather than on the tier, a position's name carries less weight and a
bundle is free to reuse short ones inside each group. `checks` and
`critique` recurring once per group is the ordinary shape, and
`<anchor>.checks` is how an author addresses one without inventing a
distinct name for every occurrence.

Derived rather than declared, because the anchor is already fixed at
one per sub-array (#6) and a declared identity could only restate or
contradict it. One level deep, because a second level would have to be
read off array order — which side of a `reconcile` an entry falls on —
and that is a fact about what a gate approves, not about what a
position is called.

## #8

The loader and the runtime disagreed in the first tree: the loader
resolved `blocks:` by namespace and refused a recurring kind, the
projection matched by bare kind and held on every occurrence. The
author chose the loader's semantics, so `blocks:`, `throwback:` and
`fills:` share one resolution and the projection is rewritten to it.

Uniqueness is a property of the reference, not the declaration: a bare
kind recurring across several groups is fine until something cites it
bare, and then it is refused rather than resolved to whichever
occurrence comes first. Refusing is the same posture every other
cross-reference in this grammar takes — validate the reference, never
guess the shape — and the qualified form is what the author writes
instead of being guessed for.

## #42

The check exists because a bundle-authored `name:` is what broke the
guarantee the resolver rested on. `Sequence.resolve_position/3` decides
whether a bare string names a gate or a status by membership in the
declared gate set alone, and its own documentation says that is safe
because a gate name is never also a declared status kind — true while
a status could only be a platform-fixed kind, and false the moment a
bundle can call a status anything it likes.

## #9

`flow:` on a queue entry resolves against this bundle's own types and
never a chain flow, because the two are different relations: a queue
opens an instance of a type, while a ticket type declares which chain
flows it serves (#40). Both live here, which is why they need telling
apart by key rather than by namespace.

## #10

The kinds are what the engine branches on (generation-shaped,
review-shaped, ball holder) and nothing more; under a fixed name
table every `llm` tier named one `generation` position and a gate
could not sit between two passes at one level. `design`,
`architecture` and `implementation` were the table's way of admitting
three positions; free names admit any number, so they return as the
default pair's `name:` values.

## #12

The backbone is what Phase 7's PR mechanics require of any chain that
fans out, not the default's taste: one feature branch with one PR to
main, each child ticket its own PR merging into the feature branch (v5
§7.5), CI against produced work before the join, the join read in
aggregate, the merge at the root. It is stated as relative order
rather than adjacency because gates, environments and a second
generation position may sit between any two members.

## #13

`merge`'s own ball is the plane, so without this rule a container's
own `setup` or `retro` sequence could merge twice with nothing read
first, which is what the first tree's milestone type did until
ORC-151.

## #14

`terminal` is the fixed end and a queue-shaped type has no universal
sequence to end (#30), so the two rules are one fact stated from
both sides.

## #16

v5 §7.8: `setup` grooms and fills `prep`, `retro` files into
`cleanup` and the next milestone's `prep`, and `main` is where the
milestone's features run. A population step needs the queue it
fills (#17), but a queue does not need its population step, since
humans fill queues too; so `main` is required, order is required
among the members present, and membership is implied by `fills:`
rather than fixed at five.

## #17

The author's, recorded here because it was not written down before:
a bundle for setup and retro needs a standard interface for
scheduling work, and this is it in two keys: `tiers:` on the position
says what runs there, `fills:` on the status says where its tickets
land. `fills:` is on the status rather than the tier because
"setup fills prep" is a relation between two positions in one array
and the workflow owns every relation of that shape; a tier carrying
it would be a second cross-axis hookup and would bind the chain to
one workflow's queue names. `retro`'s two targets are the case that
fixed the list form and the next-instance rule.

## #18

Entry-time rather than completion-time, because `retro`'s own output
lands back in `main` (adjudicated findings, filed debt), so a
completion hold would have `retro` blocking itself.

## #19

Minting and activating are different events: a milestone instance
can exist and accept groomed work into its future queues well before
the project's queue reaches it, and firing `setup` at activation is
what makes "runs once" true without leaning on mint timing (v5 §7.8).
Inline entries rather than `flow:` children because there is exactly
one container instance and one array position for each to occupy, so
no cardinality needs bounding.

## #21

A position is the unit that carries tiers and that a gate follows, so
it has to be a named generation-shaped entry rather than a shape:
under free names a shape no longer identifies one place in the
sequence.

## #22

The list is on the position rather than the tier for `bundle.md`
#11's reason. What it costs is that the mapping is stated at the
codomain, so neither totality nor uniqueness is syntactic: a tier
listed twice, and a tier listed nowhere, both have to be checked.
Both checks are cheap. Uniqueness is one pass over a single file, and
a tier no position lists is already caught downstream, since nothing
reading it can ever drain.

Join targets and supplied tiers are excluded rather than allowed and
ignored, because a bundle author who lists one has misunderstood
something the loader can name.

## #40

Derived rather than declared, so the chain keeps naming nothing here.
The predicate is the parser's own framing: scaffolding is the base
schema with a ticket face and an empty delta, which is why an empty
`delta` is the ordinary shape a scaffold declaration takes rather than
a special case. So "carries a delta" already separates a change from a
scaffold, and no new marker was needed on either side.

The list form exists because a derived default is invisible, and the
one flow that will need its own type is upward propagation, whose
positions differ in sequence rather than in gates. An outright claim
beats a predicate so that the narrow case does not have to restate the
broad one; two outright claims are an error because there is no
principled winner between them.

## #23

Free names make it possible to declare a workflow whose positions
contradict the chain's reads (a tier at `features` reading a node
written at `architecture`), which the fixed table made impossible by
having one position; the check restores the guarantee. It matters
more now than it did: the workflow author holds the ordering, and
they are the population least likely to have read the chain's
dependency graph, so the load error is their guardrail. Structural
reads only, because a global read is of the approved graph as of
dispatch (`chain.md` #22): the redesign's first check called every
plan tier's `all.sysarch` read an ordering error, and it was not.

## #41

The rule exists because its absence is what made the earlier design
declare two ticket types. A product position could not be no-op'd
below the root, so a component child running the same array would
re-run the product pass, and the way out was a second array. Computing
depth from the tier list closes that by making the question moot twice
over: the product position's tiers have no nodes at depth 1, and no
fan-out at a product tier opens a depth-1 ticket in the first place
(`chain.md` #42).

## #24

The depth rule's shape (v5 §7.19): a workflow may say more than a
chain has, and the difference degrades with a warning rather than an
error, because a workflow is meant to run over chains of different
shapes. The default pair never trips it, since `scaffold` omits the
plan position rather than leaving it unfilled; the rule is for the
fork whose chain fans out less than its workflow expects.

## #25

Every agent-balled position needs the wait state without exception,
which is how two were found missing their declared `pending` in the
shipped bundle; the projection already auto-passed `pending`, so the
engine treated it as transient. Making it a flag removes the
`pending` kind, the opens-with-pending and pending-precedes rules, the
sub-array-head rule, and the special case `retro`'s group carried.

## #26

The reason for adjacency was that a critique must read the draft it
reviews with nothing regenerating it in between, and only a
generation-shaped position regenerates; so order relative to
generation positions is the whole rule, and `checks` before a critique
(so neither an agent's critique nor a human gate reads a draft CI has
rejected) is allowed without a special case.

## #27

The author's: fan-outs need a reconcile position because
child PRs must merge into the parent predictably with gates possibly
before and after, and only the workflow can place a position and
gates around it; the prompt is the chain's (`chain.md` #15).

## #28

v5 §7.19's rule: "a child's effective sequence is the declared sequence
filtered to its depth", with the simplifying assumption that validation
wanted at a nested level is wanted at every level above.

Computed rather than declared, because a declared depth on a generation
entry could only restate what the tier list already says, and two
statements of one fact drift. The tier list is the better of the two
anyway: it says *which* work happens at a level, where a number says
only how deep the level is.

The author's decision, against giving a generation entry its own
`depth:` and against keeping two ticket types: one type across depths,
depth computed from the tiers a position references, and a child
simply never occupying the positions whose depth set excludes it.

The author's second correction is why the test is "at most the
deepest tier" rather than "a depth one of the tiers has". Every
implementation tier in the default is scoped to a subcomponent, so on
the narrower test a feature and a component would both skip the
implementation position — and with it the gate and the PR boundary at
those granularities, leaving review of produced code possible only at
the bottom of the tree. A ticket stands at a position either to
generate there or to hold the branch its children's work at that
position merges into, and both are reasons to be able to gate it.

## #30

The root has statuses because it is a node in the declaration graph,
the edge a project/container cycle runs on; it has no terminal
because a skeleton-less type has no universal sequence to end. Its
queue list is bundle content because a project's queue list is
exactly as declarable as any other content, and all but `scaffolding`
point at the same work for now (v5 §7.8). It declares no `serves:`
because nothing opens it but the project itself; a container is the
same case one level down.

## #32

`role` is checked against holders only when the identity component
supplies them, so the loader can run in Phase 3 without that
component; a gate with nobody to route to is otherwise
indistinguishable from a slow reviewer (v5 §7.16).

## #33

Depth sits on the citation because `delta` and `scaffold` cite the same
gate at different depths: the scaffold pass has no reviewed prior
graph to trust and wants its fan-out reviewed in full, while a
feature runs against a graph a human has read once and returns to the
system and component levels (v5 §7.19). The pair form keeps the
first-versus-later distinction available within one type. The default
of every depth is the author's: the first grammar's "depth 0 is the
rule" sentence contradicted v5 §7.19 and was why every shipped gate
carried `depth: 0`.

## #34

The command edge re-derives legality at throwback time anyway, so a
stored default would be a second home for a fact the array already
carries, and a workflow cutover could not re-resolve it. Under #25,
"kick back to the group's generation position" lands in that
position's waiting state.

## #35

The first grammar's rule that an ungrouped gate must declare a
throwback was in the contract and not in the loader, and the runtime
tolerated nil; the author's case is a gate between staging and prod
deploys, where most tickets would go back to no predictable position,
so a nil target is the honest declaration.

## #36

A position names tiers and a gate does not, which is the one place
the two halves of the seam part company. A gate's review set follows
from position and depth alone, so a position can gain or lose a tier
without any gate noticing, and who signs off stays out of the document
graph (v5 §7.16). A gate naming a tier would also make the chain's
tier names a published interface for the wrong reason: the position
already names them, one level up.

## #38

Nothing reads environments before delivery's deploy lands; the
shape is settled now so `dev`, `staging` and `prod` do not change when
it does. An environment sits before the `deploy` it configures because
it is not a resting position and never becomes one.

## #39

`lifetime` exists so PR-specific environments can be supported; the
author wants the functionality and the semantics are not fixed, so the
value is reserved with the rest of the block rather than dropped.

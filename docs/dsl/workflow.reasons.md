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
generation position under free names (`bundle.md` #18) and every
critique that follows one. It is a namespace per type because a
reference (#8) is resolved within the citing type and never across
types.

## #8

The loader and the runtime disagreed in the first tree: the loader
resolved `blocks:` by namespace and refused a recurring kind, the
projection matched by bare kind and held on every occurrence. The
author chose the loader's semantics, so `blocks:`, `throwback:` and
`fills:` share one resolution and the projection is rewritten to it.
Uniqueness is a property of the reference, not the declaration: a
bare kind that recurs is fine until something cites it.

## #9

`flow:` resolves against this bundle's own types and never a chain
flow because the workflow never references the chain (`bundle.md`
#11); the chain flow names the type instead (`chain.md` #38).

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
scheduling work, and this is it in two keys: `phase:` on the chain
tier says where it runs, `fills:` on the workflow status says where
its tickets land. It is on the status rather than the tier because
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

A position is the unit the chain binds to and a gate follows, so it
has to be a named generation-shaped entry rather than a shape: under
free names there is no other thing for `phase:` to point at.

## #22

Strict rather than degrading (`bundle.md` #11): the skeletons already
stipulate several positions of most shapes, so there is no single
shape-level position to fall back to, and a misspelled `phase:` under
a lenient rule would run a tier at the wrong position silently. The
flow names the type because the first grammar paired them by an
unchecked label convention, and a strict check has to know which
type's namespace it is checking against.

## #23

Free names make it possible to declare a workflow whose positions
contradict the chain's reads (a tier at `features` reading a node
written at `architecture`), which the fixed table made impossible by
having one position; the check restores the guarantee. Structural
reads only, because a global read is of the approved graph as of
dispatch (`chain.md` #22): the prototype's first check called every
plan tier's `all.sysarch` read an ordering error, and it was not.

## #24

The depth rule's shape (v5 §7.19): a workflow may say more than a
chain has, and the difference degrades with a warning rather than an
error, because a workflow is meant to run over chains of different
shapes and the five plan flows share `feature` without all naming
`plan`.

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

C.2 of the seam pass: fan-outs need a reconcile position because
child PRs must merge into the parent predictably with gates possibly
before and after, and only the workflow can place a position and
gates around it; the prompt is the chain's (`chain.md` #15).

## #28

v5 §7.19: "a child's effective sequence is the declared sequence
filtered to its depth", with the simplifying assumption that
validation wanted at a nested level is wanted at every level above.
The default is every depth because the author wants doing less review
to be the explicit choice, and "all depths" is well defined under this
rule where it was not expressible before.

## #30

The root has statuses because it is a node in the declaration graph,
the edge a project/container cycle runs on; it has no terminal
because a skeleton-less type has no universal sequence to end. Its
queue list is bundle content because a project's queue list is
exactly as declarable as any other content, and all but `scaffolding`
point at the same work for now (v5 §7.8).

## #32

`role` is checked against holders only when the identity component
supplies them, so the loader can run in Phase 3 without that
component; a gate with nobody to route to is otherwise
indistinguishable from a slow reviewer (v5 §7.16).

## #33

Depth sits on the citation because `feature` and `seed` cite the same
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

A gate names no tier because the workflow never references the chain
(`bundle.md` #11); its review set follows from position and depth
alone, which is what makes any workflow that declares a chain's
positions run it.

## #38

Nothing reads environments before delivery's deploy lands; the
shape is settled now so `dev`, `staging` and `prod` do not change when
it does. An environment sits before the `deploy` it configures because
it is not a resting position and never becomes one.

## #39

`lifetime` exists so PR-specific environments can be supported; the
author wants the functionality and the semantics are not fixed, so the
value is reserved with the rest of the block rather than dropped.

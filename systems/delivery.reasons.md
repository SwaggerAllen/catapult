# delivery — reasons

The reason behind each rule in `systems/delivery.md`, keyed by the rule's id (orchestration's DESIGN §4). Read one with `pipeline reasons delivery#n` before changing the rule it belongs to.

## #4

What it buys is an author and a rebuild path for a fixture repo, not test determinism
or seeded generation content.

## #5

Acceptable for a test repo the author owns; not fixed here.
`lib/catapult/delivery.ex`'s own config comment already names the GitHub App
installation token as the shape that scopes this per-repo, and that stays the answer —
ORC-10 doesn't owe it.

## #6

Both are needed, because only a copy survives the source file being deleted — a
content hash or a bare commit-SHA pin does not, once the commit that introduced the
file is no longer the one a later read would resolve the path against, and authors
delete input docs.

## #9

The toy seed's fixture directory (`docs/toy-seed/<role>.md`,
`test/support/toy_seed.ex`) predates this convention under a name chosen for that one
fixture and is reconciled to `docs/raft/` with the rest of the ticket.

## #12

The toy seed fixture and `reset_repo`'s own existing shape already commit this repo to
"the bound repo is where fixture content lives, the raft included"; a second intake
channel would fork that convention for no reader that needs both. This also matches
`docs/non-goals.md`'s "no absorption of existing codebases" entry, whose mocks
carve-out already names the shape a raft document takes — **seed evidence and pinned
artifacts**, read once and never absorbed — one level more general than mocks alone.

## #18

Target (Phase 7), alongside the rest of the workflow-bundle machinery this needs to
have a subject at all — there is no declared workflow sequence to cut over from before
then.

## #19

The `:live`-gates-`retro` interlock (§2.8) is Target (Phase 7), unticketed: it needs a
`:live`-verdict signal, which nothing in this system emits, and the maintenance
watcher this doc's own Initial-vs-target section files to Phase 7.

## #21

Nothing in this system's own dispatch logic changes shape for the acyclicity rule — it
is about what the loader accepts before this system ever sees a bundle.

## #24

A container-owned dispatch identity — pointing ORC-9's executor at the container
instance's own branch and PR when the dispatch subject is a container rather than a
ticket; giving a container instance file-map paths of its own for the mutex mapping to
key against, the identical shape a ticket's paths already take; keying `DispatchRun`
on the container instance's id in that case rather than assuming a ticket id — is
Target (Phase 7), unticketed: revisit when it is actually needed rather than the
per-entry synthetic flow. What `main`'s `blocks: [retro]` (`workflow.md` #18) means
once `retro` is `milestone`'s own inline entry rather than a population of unresolved
child tickets: `retro` cannot be *entered* while `main`'s own queue still carries
unresolved work — the identical entry-guard test `workflow.md` #18 states generally
(the `blocks:` entry below), applied to a guarded entry that is not itself a queue.

## #25

The fifth/sixth-pass singleton reading above bounded a *queue's* lifetime cardinality
— the mechanism `setup` and `retro` needed only because each was implemented as
`flow:` naming a separately minted, ticket-skeleton child. Once `setup` and `retro`
fold directly into `milestone`'s own array as ordinary agent-balled entries — no
`flow:`, no minted child, `types/setup.yaml`/`types/retro.yaml` deleted — neither is a
queue any more, so there is no cardinality left for a field to bound: "at most one,
ever" falls out of there being exactly one `milestone` instance and exactly one array
position each occupies. This system's dispatcher loses a check it was filed to build
(the singleton-lifetime rejection, ORC-104's, retired rather than built) and gains the
dispatch-target work named above in its place — a smaller Target list, not a larger
one, since folding removes the separately-dispatched child the old shape needed a
bound for.

## #27

This is also what keeps the `terminal` guard two bullets up reachable at all: the
shipped `milestone`'s only throwback to `main` is `milestone-signoff`, sequenced
*before* `retro` (`workflow.md` #16), so absent this manual return `retro` filing
work into `main` would leave `cleanup`/`terminal` blocked with no declared path back.
Every site the retired reading reached states this rule (ORC-177, merged `27e0bff`):
`Catapult.Delivery.ContainerLifecycle`'s `next_commands/2` performs no population
pre-check (below); `container_queues.ex`'s resolution condition 1 cites the retirement
directly rather than the reading it predated; and, in `container_queue_advanced.ex`,
both the moduledoc and the `reason` type are `:resolved | :throwback` — there is no
`:repopulated`, and the moduledoc does not give a resolved queue un-resolving as this
reason's justification for existing. A third `reason` value, for the explicit author
transition above, is that mechanism's own vocabulary to add once it is built, not
anticipated here. `container_lifecycle_test.exs` asserts against what replaces the
walk, below, never `reason: :repopulated`.

Position needs no re-derivation, because there is nothing left to derive: position
is not a function of queue population at all. `next_commands/2` has no
`earliest_unresolved/4` pre-check — deleted, not repurposed — and dispatches straight
to `forward_or_open/3` on every event. A container's position sits wherever the last
forward advance or one of the two remaining backward-move causes (a step's own
decline; the author's `retro` → `main` return) left it, and an earlier queue's
population refilling changes nothing about it. That is the whole answer: it doesn't
re-derive, and needing it to was the retired behavior.

`container_queues.ex`'s condition 1, `container_queue_advanced.ex`'s moduledoc and
`reason` type, and `container_lifecycle_test.exs` state this replacement, not a
placeholder for it.

## #29

This is the strongest of the three mechanisms considered (markers, endpoint-alone,
author-identity) because it needs no third party to cooperate with a convention it has
never heard of — but it is a revision of §7.4's text ("anything unmarked... is human
feedback") for the surface where we don't own the store, not a restatement of it.
Markers are unchanged for *our* own machine (marker-comment write); author-identity
filtering is what stands in for "unmarked" on the review-comment side. **Placement:**
`docs/v5-design-decisions.md` §7.4 carries this mechanism, its reason and its residual
directly — a revision to a recorded decision belongs in the document that records it,
or the source of truth disagrees with the system doc about which rule is live; this
bullet is the fuller argument the doc text points back to, not a second place the
decision was made.

## #31

That premise holds because no plane operation posts a line-anchored comment at all,
which is what makes the property cost nothing rather than something enforced. If a
later ticket adds one — a review-thread reply is an obvious want when declining a
decline — that comment would arrive through the same review-comment endpoint the
harvesting read otherwise treats as candidate human feedback, and it would harvest as
feedback on its own author's comment with nothing here to catch it. Should that
operation ever land, harvesting's read side needs the same author-identity filter the
entry above puts on review-comment read generally — excluding the plane's own GitHub
identity alongside third-party bots and Apps — not a return to string-parsing. Until
then, "unmarked" means: arrived as a review comment, and not filtered out by the
author-identity check above — not simply "arrived as a review comment."

## #32

Store-backing forge state may still turn out to be the right call — the fake surviving
a `Repo` restart, or the sim ring wanting to query forge state through the same
surface as everything else, are real arguments for it — but that argument wasn't made
here, so this entry doesn't make the decision on its behalf.

## #35

A process manager probed against the real tree — `use
Commanded.ProcessManagers.ProcessManager, application: Catapult.Engine.Application,
name: "..."`, with `interested?/1` clauses matching real event structs (`FlowOpened`,
`DraftCommitted`, `DraftApproved`) — compiles clean and leaves `mix xref graph --label
compile-connected --fail-above 0` at its existing zero. The reason is the same one
`Catapult.Engine.Router`'s own `use Commanded.Commands.Router, application:
Catapult.Engine.Application` line already demonstrates coexisting with the gate: the
edge that trips the ratchet is `Commanded.Commands.CompositeRouter.router/1` reading
`__registered_commands__/0` off an already-aliased module at compile time (a macro
call needing the callee compiled first), which neither `use ..., application: ...` nor
ordinary struct pattern-matching in a function head triggers — those are `use`/export
dependencies the tracer classifies as non-transitive, never compile-connected. No
`Module.concat/1` escape is needed for the process manager itself. (Scratch-verified
against this branch; the probe module itself was never committed, per DESIGN §5.)

## #38

The shipped single-phase `feature.yaml` never exercised the difference — one `checks`,
so first and last coincide — which is what let
`Catapult.Delivery.FeatureLifecycle.Sequence.positions/2`'s own
`take_through_boundary/1` anchor on the first occurrence and still read correct. The
multi-phase case is `dsl-syntax.md` §15.2's own `feature.yaml` worked example (three
`checks`, one per design/architecture/implementation sub-array — the same count this
doc's own ORC-155 entry, below, names for that same declaration); §15.11's
`component.yaml` is not it: that example carries only two `checks` (architecture and
implementation) and no `design` sub-array at all — §15.11's own prose is what rules
`design` out there, since `design` and `product-review` are feature-only. Every one of
§15.2's earlier `checks`/`critique`/gate cycles is ordinary reachable board structure,
not Phase 7 machinery — only what follows the *final* `checks` (that sub-array's own
`critique`, the type's trailing `reconcile`, `merge`, `deploy`, `terminal`) sits
behind it. Anchoring on the first occurrence instead silently drops every position
after it, however many phases and gates that is — a landmine the moment a bundle ships
§15.2's documented shape. `take_through_boundary/1` finds the *last* index carrying
`{:kind, :checks}` ahead of `merge`, not the first.

## #40

Reasoned from §7.10's own store test (does changing it change what is generated,
validated or enforced? no — a label is read, never branched on): a human-facing label
is presentation, and belongs with "the work surface renders" (this doc's own opening
paragraph), not with this projection and not with workflow-bundle content.
`dsl-syntax.md` §15.1's table already fixes labels for the twenty platform-fixed kinds
— `backlog`, `pending`, `generation`, `design`, `architecture`, `implementation`,
`critique`, `checks`, `reconcile`, `merge`, `deploy`, `validating`, `blocked`,
`stubbed`, `setup`, `prep`, `main`, `retro`, `cleanup`, `terminal` — across the two
default lifecycles; a *declared* gate's or environment's own name (`ux-review`, `dev`)
has no such table and needs one, but writing it is `systems/dashboard.md`'s decision
when UI v1 renders this projection — out of this ticket's own declared scope ("the
screens that render this, which are UI v1's") — not a new `label:` field on
`Catapult.Dsl.Gate` (that would put a presentation fact in graph state, exactly what
the store test rules out).

## #42

Nothing here adds to that decision; it is named only so the process manager's own
callbacks are read as an application of it rather than a fresh design.

## #43

That is engine's own file-map territory, and this doc does not reinterpret engine's "a
project has one aggregate, not two" to settle the rest; `systems/engine.md`'s own
§7.16 bullet is what keeps §7.16 open on its own terms: "a workflow gate is declared
delivery-bundle vocabulary, not an engine node, so what it pins is delivery's to
design when workflow gates land (`systems/delivery.md`'s Phase 7)... not this ticket's
to answer." What stays open: what a *passed* gate pins (§7.16's own still-open item),
and which node(s) a gate spanning more than Phase 4's single pre-gate `generation`
status would validate against — Phase 4's own mapping is a single node.

## #44

It does not touch what stays open above: what a passed gate pins, and which node(s) a
gate spanning more than one pre-gate `generation` status would validate against.

## #48

`Catapult.Delivery.FeatureLifecycle` is the instance that crashed (no `@derive
Jason.Encoder` on either itself or its nested `Projection`, and `Projection`'s
`blocked_from`/`pinned_to`/`passed` all carry or key on raw `Sequence.position()`
tuples), and the rule is general and has a second instance in the identical repository
state: `Catapult.Delivery.ContainerLifecycle` (ORC-104, above) carries no `@derive
Jason.Encoder` either. **Both instances are ORC-120's scope, not one filed and one
fixed** — a second ticket shipping against a rule this doc had already written down
one module over is the wrong shape. `ContainerLifecycle` differs from
`FeatureLifecycle` on both halves of the fix, which is why both are worth stating
rather than assuming the same shape twice: * **Encode:** the missing `@derive
Jason.Encoder`, and nothing more. `type_name` and `queue` are both `String.t() | nil`
— no `Sequence.position()`-shaped field anywhere on this struct — so none of
`blocked_from`/`pinned_to`/`passed`'s flattening work applies here. * **Decode:** a
`JsonDecoder` implementation is still required, for a different reason than
`FeatureLifecycle`'s. `state` is an atom (`:minted | :active | :closed`); `Jason`
encodes `:minted` to `"minted"`, and `struct(module, data)` restores it as that bare
string, in violation of the struct's own `@type` — the same reification gap named
above for `FeatureLifecycle.projection`, just not previously turned on the atom next
door. * **Latent, not live:** no `apply/2` or `handle/2` clause in
`ContainerLifecycle` matches on `state:` — every head is `%__MODULE__{} = pm`, and the
field is written but never matched (the one `state:` match in the file is on
`Catapult.Engine.Store.Container`, a database row, a different struct). The drift is
dormant today and goes live the first time a clause is added that matches on it — the
reason to close it now rather than after it bites, and also why it is not itself
gating. **The fix extends existing precedent rather than inventing a second one**:
`FlowResumed` already answers a bare position field by flattening it to the
two-nullable-strings shape `position_columns/1` (this doc's own store columns) already
uses; `FeatureLifecycle`'s `blocked_from` and `pinned_to` take the same flattening.
`passed` breaks new ground the existing precedent doesn't cover: a JSON object's keys
are always strings, so a map *keyed* on a position — not merely carrying one — cannot
round-trip as a JSON object at all, flattened or not, and becomes a list of flattened
`{position, signature}` records instead. Restoring either struct from a snapshot also
needs a `Commanded.Serialization.JsonDecoder` implementation, which no event here has
needed before now: `JsonSerializer.deserialize/2` calls `struct(module, data)` and
only *then* the decoder protocol, so a nested struct field
(`FeatureLifecycle.projection`) lands as a bare atom-keyed map, never reified, unless
the protocol does it — the gap every event here has avoided simply by nesting no
struct and needing no atom reconstructed.

**Both `Commanded` internals this entry rests on are confirmed against source** (deps
are vendored in this checkout). `ProcessManagerInstance`'s event-handling clause calls
`persist_state(event_number, state)` unconditionally on every successful
`mutate_state/2` — no flag, no opt-out
(`deps/commanded/lib/commanded/process_managers/process_manager_instance.ex:257`). And
`JsonSerializer.deserialize/2` really does build the struct before the decoder
protocol runs, not after: `Jason.decode!/2 |> to_struct(type) |>
JsonDecoder.decode()`, where `to_struct/2` is `struct(struct, data)`
(`deps/commanded/lib/commanded/serialization/json_serializer.ex:33-41`).

## #49

Attaching it to the close says the same thing about the same container without asking
the grammar for a magic word, and says it about *every* container — including one
whose author declared no backward-looking entry at all, which a `retro`-named check
would have let close over its findings silently. This is not a `blocks:` relation
either way (`workflow.md` #18's `blocks:` is an entry guard, checked once at
transition, ORC-148): nothing gates *entry into* `retro` on its own findings, since
the findings are what `retro` itself produces and adjudicates after it has already
begun. **In the shipped `milestone` type, `retro` is followed by `proposals-read`,
then `cleanup`, `deploy` and `terminal` — no `checks`, `reconcile` or `merge` at all
(ORC-155).** A checks/reconcile/merge sequence after `retro` would close a gap real
only while `retro` merged something of its own, and it does not: `retro` produces no
code, pushing its findings to `cleanup` rather than merging a docs-pruning draft
directly, so there is nothing for `checks`/`reconcile`/`merge` to check, join or land.
The finding-adjudication close gate above sits on `retro` itself, ahead of whatever
follows it, never on `cleanup`; `setup` takes the identical shape — both agent steps
drop the same three entries for the same reason, `setup` gaining a `kickoff-review`
gate in their place (`workflow.md` #5, #19).

## #50

This is what makes "features merge dark as they complete; the milestone lights up
together" (§7.8) real behavior rather than a grouping label on a query.

## #51

**The refusal this settles**: the tempting shape is the one orchestration shipped — a
backlog view keyed on a work item's key, title, priority and gating state, which
proposes a work item whose own description argues it isn't ready every close, because
nothing in that view can see the argument. This system doesn't reproduce that gap. A
work item already carries structured signals orchestration's flat view never had —
`Stubbed` status (§7.6, "committed work deliberately waiting"), and any unresolved
blocking edge or unmet context-walk dependency the engine already computes — and the
proposal query filters against those before a candidate is ever written to the
read-model, rather than surfacing every gating-state- eligible item and letting a
human filter prose out of a description field by hand.

## #53

`FeatureLifecycle` is pure projection — the read side v5 §7.10 wants rendered without
asking git anything — and wiring outbound GitHub calls into its own `handle/2` would
mean a GitHub outage or a bad credential risking the one component every status column
and every gate already depends on. Keeping them apart means a stalled
`FeaturePublisher` leaves ticket status exactly as readable as it always was, which is
the property worth the second module.

## #54

Neither named alternative survives on its own terms: opening at `FlowOpened` puts a PR
up with no diff and nothing for CI to check, which is exactly the "sitting empty,
notifying nobody" case the ticket record itself warns against; waiting for "the first
gate" lets a flow commit several tiers' worth of drafts before anything is visible
anywhere outside the plane's own store, which is worse than the empty-PR case it's
meant to avoid, not better. The branch is created off `main`'s current head at that
same moment rather than earlier — nothing exists yet to protect from drift before a
first artifact lands, so an empty branch parked identically to `main` gives the
merge-forward machinery nothing to do.

## #57

No tier in `bundles/default/tiers/*.yaml` declares a target-repo location for its own
draft — `draft:`'s `root_tag`/`grammar` name a validation contract, not a place in a
shipped project's tree, and nothing else in `chain.md` fills that gap either.
Deciding the real one — whether a shipped project ever sees this XML at all, or
whether a rendering step turns it into the kind of prose `systems/*.md` in *this* repo
is, and where that step would live — is a bundle-grammar question
(`core_dsl`/`platform_content`'s file maps), not this ticket's to answer by inventing
an unreviewed `produces: path:` field. The namespaced placeholder keeps this ticket
buildable without pre-empting that decision: nothing a hand-authored project file
would ever be named collides with it, and every path is mechanically derivable from
fields this system already has in hand (`tier`, `node_id`), no new lookup needed.
Revisit condition: the day a tier declares where its own body belongs, this reads that
instead of the placeholder — a one-function change here, not a new decision.

## #58

This is the "table of contents... so the PR is readable without reading the diff" the
ticket record asks for, on the reading corrected below of what reading it is actually
for.

## #59

**This is load-bearing for why `FeaturePublisher` may safely lag `FeatureLifecycle` by
however long an Oban retry takes**: a gate becomes visible off `FeatureLifecycle`'s
own projection, which reads engine state directly and never waits on git; native
review, when it lands, reads a committed body the identical way
(`Delivery.get_draft_body/2`, already synchronous today). GitHub being slow,
rate-limited or briefly down delays what the PR shows, never what the author is asked
to act on.

## #61

But nobody can act on a `Product review`/`Architecture review` gate until ORC-75
exists, whatever this ticket does with the PR in the meantime — naming it here is what
stops a reader concluding Phase 4 ships a working review loop on its own. Already
listed under "Depends on" below; this is that dependency's reason spelled out rather
than left to "the work surface renders."

## #62

"Reachability, settled" already leaves `merge` to Phase 7's own dispatcher — a
publisher that squash-merged on its own initiative would be driving a ticket into a
status this system's own lifecycle projection doesn't yet recognize reaching.

## #63

The ticket record's own scope paragraph described the PR's line-anchored comments and
a machine-vs-human author-identity filter as the thing to design against — the shape
ORC-31/ORC-33 had already built, for a different phase, before this ticket's own
design pass started. The ORC-33 entry above already names the gap in as many words
("Phase 4's declines are prose declines, read from the native review surface... not
from PR review comments"), and `docs/v5-design-decisions.md` §7.4 and
`docs/ui-spec.md` §3.2 both settle the same split independently of this ticket. So the
harvest designed below reads `document-review`'s own per-sentence comments, never
`HostPort`'s `review-comment read` — that operation, its author-identity filter and
its residual PAT gap stay exactly where ORC-31/ORC-33 left them, waiting on Phase 7's
child PRs, untouched by anything below.

## #65

Neither clause is new mechanism beyond what this process manager already is; it is the
increment ORC-32's own "what advancing past a gate dispatches to stays open" bullet
named and deferred, closed here on the aggregate side `systems/engine.md` settles and
amended into that bullet above.

## #67

`FeatureLifecycle`'s "advances the ticket to the next entry in its type's own
`statuses:` array after the gate's position" (above) and `DraftResolution`'s "does
that next entry leave this gate's own citing sub-array" are the same lookup read twice
by two independent handlers of the same event, deliberately — the two-computations-of-
one-fact shape this doc otherwise avoids is the price of the identical decoupling
`FeatureLifecycle`/`FeaturePublisher` already pay for `flow_name`/entry-tier
resolution, not a new exception. `systems/engine.md`'s own entry has the group-exit
rule and the discard-resets-to-absent fix; this system's only job is deciding *when*
to fire, off vocabulary this system already threads through for the gate-advance
mechanism beside it.

## #70

ORC-75's dev pass filed six write/read gaps against a working surface with nowhere to
read or write from; ORC-114 closed them together because they are that one rule
applied six times. The shapes themselves live in the code they landed in —
`Catapult.Delivery.Store` and `Catapult.Engine.Commands` each carry their own
reasoning at the point it would be edited. What this doc keeps is the four decisions
that bound future work rather than describe past work.

## #71

A need to diff against more than the immediately prior pass is a different and much
larger storage decision, not an increment on this one.

## #75

A module whose moduledoc asserts it branches on no status name cannot carry one name
check, and the fix is a grammar change rather than a code-only one, because the
exception was never this system's to invent: `merge` was agent-balled without being a
dispatch point only because one kind was doing two jobs (`docs/v5-design-decisions.md`
§7.19). **Reconciliation itself is Phase 7's.** `reconcile` is agent-balled and
dispatches like any other inline or chain-tier agent-balled entry — this system's
existing uniform dispatch (`ContainerLifecycle.open_for/3`'s `cond`, and the ordinary
`ready_scopes` path for a chain-tier `reconcile` on a ticket) needs no new branch to
carry it — but what a `reconcile` agent run actually reads, writes and approves, and
the mechanical merge effect `merge`'s own `plane` ball implies, are Phase 7's, the
same boundary every gate-mechanism entry above already draws. The loader recognizes
the kind (`systems/core_dsl.md`'s own ORC-151 entry), and `bundles/default-flow`'s
`feature.yaml` and `seed.yaml` both declare `reconcile` against it.

## #77

The tree-spawn recursion and parent-triggered merge cascade named above, spawning a
second type rather than a depth-filtered instance of one, are Phase 7's: this system's
dispatcher reaches them through the same uniform dispatch once that phase builds them.

## #78

`resolve_position/3`'s own doc states plainly why membership in `workflow.gates` alone
has always been enough to tell a gate from a status: "a gate name is never also a
declared status kind (the two live in disjoint vocabularies)." That is true only while
a status's whole identity is a platform-fixed kind no bundle can author; once a bundle
can name a `status:` entry (ORC-155), nothing but a check stops that name colliding
with a declared gate. Left unchecked, a collision resolves to `{:gate, name}`
unconditionally and a name matching neither raises inside `String.to_existing_atom` —
both on the throwback path, both invisible until a decline actually fires. The
load-time check `workflow.md` #42 states closes this the same way every other gap
in this class closes, at load rather than at the first decline that exercises it.

## #80

`Sequence.next_step/3` and `Sequence.earlier?/4` resolving a position with
`Enum.find_index/2` against the bare name `Sequence.name/1` returns — a `status:`'s
own `status`, a `review:`'s own gate name — with no anchor concept at all leaves two
occurrences of one kind in a single container's array not merely unlabeled the way a
bare ticket-axis `position()` was before ORC-155; they are **indistinguishable to the
lookup itself**, which resolves to whichever came first.

## #82

Latent only because `bundles/default-flow/types/milestone.yaml` puts its `environment:
prod` after both sub-arrays.

## #83

`sequence_test.exs`'s "a bare name recurring across two sub-arrays" describe block
exercises the lookup directly, against a synthetic recurring-name fixture, since no
shipped bundle recurs a name after ORC-155. Threading that same qualified identity
through every caller of these three lookups — so a qualified argument is what they are
actually given, not only what they can accept — is the ORC-171 entry below.

## #84

**Named, and outside this ticket's own reach: a human resuming to one specific
occurrence of an ambiguous position.**
`Catapult.Engine.Events.FlowResumed.to_kind`/`to_gate` (`system:engine`, outside this
record's own file map) carries no qualifying field, so `unflatten_position/2` resolves
a resume target correctly only for the unambiguous case — ORC-155's own "bare when
unambiguous" rule already covers exactly that case elsewhere. Checked against
`docs/non-goals.md`, since this decision's consequences reach
`CatapultWeb.Live.Positions`; nothing there blocks it, and this entry touches neither
`system:engine` nor `system:dashboard`.

`bundles/default-flow/types/milestone.yaml`'s `retro` group carries its own leading
`pending`, symmetric with `setup`'s (`docs/dsl-syntax.md` §15.2) — the canonical
identity is what makes `setup.pending` and `retro.pending` distinct positions rather
than one bare name arriving twice. Reverting that bundle to the symmetric shape and
the plumbing above are one dev diff.

## #86

`Projection` can answer which occurrence a resting ticket is actually at; retiring
`CatapultWeb.Live.Positions.resting_key/2`'s own first-match, best-effort guess
(`systems/dashboard.md`'s own ORC-116 entry) on the strength of that is a
dashboard-scoped pass's own decision, not this entry's — this ticket supplies the data
such a pass would consume, nothing in `system:dashboard`.

## #87

`FeatureLifecycle.Sequence .annotated_positions/2`'s inline-dispatch fallback (this
system's own ORC-176 entry, below) builds `setup`/`retro`'s fixed `pending`/ kind pair
by hand, with no declared type's `statuses:` array behind either entry — the same
reason each already carries `group_key: nil`. `Type.namespaced_positions/1`'s own
qualification is a property of a name's position inside a declared type's `statuses:`
array; an entry with no such array behind it is bare by the identical rule §15.12
already states for anything outside a sub-array, and unambiguous besides — a
synthesized two-entry list cannot recur a name against itself, and `setup`/`retro` are
two distinct `FeatureLifecycle` process-manager instances
(`ContainerLifecycle.open_inline/3` opens each as its own flow), so their two
`pending`s are never compared inside one `Projection` the way `feature.yaml`'s own
recurring group `pending`s are. So the canonical-identity field every other
constructor of `annotated_position()` supplies is present on these two maps too,
rather than the shape forking between callers — `annotated_positions /2` returns one
shape regardless of which branch built it — carrying `nil`.

## #90

Runtime position-tracking carrying the same canonical identity the loader already
resolves against is what makes accepting such a bundle safe; a load-time warning would
flag a legal shape instead.

## #91

`setup` and `retro` never resolve in `workflow.types`, by ORC-148's own design, so a
`positions/2` that only resolves a name there projects every setup/retro flow with
`status_kind`/`status_gate` both `nil` — not a crash, `warn_unplaceable/3`'s own log
line firing instead, but a real loss: `screens/board.md` renders
`Sequence.positions/2` as a card's own lane set, and `Store.tickets_for_project/1`
lists every open flow with no type filter at all, so a setup/retro card reaches the
board with no lane to sit in. **There is no "generation-to- deploy" progression to
place: the "Every carried finding leaves adjudicated…" entry above settles, at
ORC-155, that neither `setup` nor `retro` ever runs its own
`checks`/`reconcile`/`merge`/`deploy` at all ("both agent steps drop the same three
entries for the same reason"). Placement is in the two positions that are real for
either flow, `pending` and its own agent-balled kind.**

**Why the fixed sequence is exactly two entries and never more:**
`Projection.resting/3`'s own `Enum.find/3` never calls `passable?/2` on the *last*
position in the list it walks — `&(&1 != last and not passable?(&1, state))`
short-circuits before evaluating the right side once `&1 == last` — which is the only
reason a kind `passable?/2` has no clause for (`:setup` and `:retro`, and for that
matter `:design`/`:architecture`/`:implementation`/`:checks`/
`:reconcile`/`:merge`/`:deploy` — `passable?/2`'s two clauses cover only
`:pending`/`:generation`/`:critique` and any `{:gate, _}`) is never reached. The
two-entry list keeps the inline kind last by construction; a version that appended
anything after it would hand `passable?/2` a `{:kind, :setup}` in a non-last position
and crash the first time that flow's `commit_signature` is set. **`passable?/2`'s own
missing clauses for the four other named generation/review-shaped kinds are a separate
finding, filed against `systems/delivery.md`'s own file map** — latent rather than
live, since no shipped type gives `feature.yaml` a second, non-terminal
generation-shaped visit, and reachable only once one does.

`Sequence.positions/2` and `warn_unplaceable/3`'s narrowed trigger both carry this.

## #93

All four read `Type.namespaced_positions/1`'s `canonical`/`bare` fields — the
reference-resolution identity — to decide something about a *runtime* position
instead:

`annotate/4` (`sequence.ex:185`) computes the `anchor` ORC-171 added to
`annotated_position()` as `if namespaced.canonical == namespaced.bare, do: nil, else:
namespaced.namespace`. Two `status: pending` entries with distinct `name:` overrides
get `canonical == bare` — their names don't recur, so nothing marks them — and so both
get `anchor: nil`, indistinguishable from each other once paired with
`to_position/1`'s identical `{:kind, :pending}` for both: the exact failure ORC-171
closed, reopened through `name:`'s own escape hatch. Reads the new `kind_ambiguous`
field instead, through the shared `qualifier/1` the ORC-202 entry below gives all
three sites.

`resolve_kind_reference/3` (`sequence.ex:258-262`), called from `resolve_position/3`
(`sequence.ex:239-246`), carries two independent instances. Its own `anchor` line
(`sequence.ex:261`) is the identical `canonical == bare` test as `annotate/4`'s,
corrected the same way. Separately, it hands the resolved position's **`bare`** field
— ORC-155's own display name, not its kind — through `String.to_existing_atom/1` to
build `{:kind, atom}`. `to_position/1`, the only other builder of this shape, always
reads the entry's literal `status:` field. For a `status: pending, name: alpha` entry
the two disagree: `to_position/1` yields `{:kind, :pending}`, `resolve_position/3`
yields `{:kind, :alpha}` — a `throwback_to` resolving through the second names a
position the first never emits. `sequence.ex:203-208`'s own
`String.to_existing_atom/1` discipline note justifies itself on `status:`'s closed,
compile-time-literal vocabulary (`Catapult.Dsl.SystemStatus`); that argument holds at
`to_position/1`, where the input *is* `status:`, and does not carry to this site,
whose input is a bundle-authored `name:` with no reason to be in the atom table.
Corrected to read the resolved position's own `entry.status` —
`namespaced_positions/1` already carries the full `%Catapult.Dsl.Status{}` under
`entry` — rather than `bare`, so both builders of `position()` agree by construction.

`find_kind_entry/3` (`sequence.ex:315-322`), `Sequence.name/4`'s own helper, computes
`entry_anchor` the identical `canonical == bare` way to match against a
caller-supplied `anchor` and pick the entry a `{:kind, kind}` position displays under.
Once `annotate/4` above stores `kind_ambiguous`-derived anchors, an entry_anchor still
computed the old way silently stops matching the anchor `Projection.resting/3`
actually passes in, for exactly the `name:`-recurring-kind case this whole entry is
about — `name/4` would fall back to the bare kind (its own documented behavior for an
anchor that "does not resolve to a real occurrence") for a position that does have
one. Corrected the same way as `annotate/4`.

The case that separates it from the reference-ambiguity test — a type recurring a kind
under distinct `name:` overrides — is the shape no shipped bundle authors today,
latent rather than live, the same standing this ticket's own argument opened with.
`sequence_test.exs` seeds it twice over: once across two sub-arrays, where the group
anchor alone would have sufficed, and once inside a single namespace, where it does
not — the ORC-202 entry below is what that second fixture exists for.

## #94

ORC-198's three sites took the qualifier from `namespace`, which answers a different
question: it is the recurring group's own anchor name, and it separates two
occurrences only when they sit in *different* sub-arrays. For the case §15.12 actually
permits — one namespace, two names — both occurrences carry the same `namespace`, so
matching on it picks whichever comes first. That is the ORC-171 defect this field
exists to close, reopened one door over. At the top level it is also a type error:
`namespace` is the atom `:top_level` there, and `anchor()` is `String.t() | nil`.

**The choice was measured, not argued.** ORC-198's own fixture puts its two same-kind
entries in *different* sub-arrays, where the group anchor separates them and
`namespace` looks sufficient; no test covered one namespace holding both, which is why
this shipped. `sequence_test.exs`'s ORC-202 fixture is that missing case — two
top-level `pending` entries named `alpha` and `beta` — and it was run against both
schemes before either was chosen. Under `namespace` it fails three ways: `annotate/4`
hands back the atom `:top_level` against an `anchor()` of `String.t() | nil`, and
`name/4` answers `"pending"` for both occurrences, having found neither. Under
`qualified` all three pass and the rest of the suite stays green. A scheme that cannot
express the case §15.12 permits is not a narrower fix; it is the same defect with a
smaller blast radius.

## #97

No unique partial index enforces this: nothing but the boundary's own
milestone-cadence live suite calls this operation, and it never calls it twice without
the prior call's release/delete cycle having already run, so a concurrent second mint
is not a case this system defends against.

## #98

The growth rate this leaves behind is one project's worth of engine rows and one
EventStore stream per milestone (the live suite's own cadence, conventions §9) — small
and slow enough to defer. A later archive/delete design — this entry's own seed, not a
substitute for it — is where engine's own purge belongs, alongside the product-facing
flow that design is not either.

## #99

**A fourth operation enumerating test projects is a ticket of its own, still open.**
All three operations take the `project_id` an operator is trying to discover in the
first place, so finding the currently-active one during an incident (ORC-223) meant
grepping the runtime log for `sweepable_project?/1`'s own query — a real operator
hole. Nothing above depends on a list/enumerate operation existing or is harder to
build for its absence.

**Why not the dispatch-facing OIDC verification** (v5 §7.12.1, this doc's ORC-9
entry). `Oidc.verify/4` answers one question — does this token's `repository` claim
match *the repo a specific dispatch run was sent to*, read off that run's own
correlation record (`Dispatch.fetch_context/2`'s own `run.repo_owner`/`run.repo_name`)
— and every one of its inputs comes from a `DispatchRun` row that does not exist yet
at the moment a live-suite job asks to provision one. Making it answer the different
question a provisioning call actually asks — is this token the plane's own CI, calling
from `SwaggerAllen/catapult` rather than any bound project's repo — needs a second
expected-identity source (a plane-level "our own repo" config value nothing holds) and
drops the `run_id` half of the check entirely, since there is no run yet to match one
against. That is a second verification path wearing the first one's name, not a reuse
of it, and OIDC's actual argument for existing — no secret rides dispatch inputs
handed to arbitrary, ephemeral runner identities across the internet (v5 §7.12.1) —
does not transfer to a surface reachable only from this repo's own scheduled job,
firing at most once a milestone. A declared secret is the smaller addition: one more
line in `SETUP.md`'s required-env manifest, checked the same way
`DELIVERY_GITHUB_TOKEN` already is, against no new plane-level identity concept.

## #100

Provisioning is the first caller with anywhere to put a ref: `intake_raft/2` takes one
explicitly rather than defaulting to "whatever the default branch happens to be"
(`HostPort`'s own moduledoc, its ORC-107 paragraph on `read_directory/3`, already
refuses that default for the identical reason), and the fixture files `reset_repo/2`
just wrote are the only source of a ref guaranteed to postdate them without a second
read racing a concurrent write to the same shared `catapult-test` repo — the exact
hazard the "at most one active test project" invariant above exists to keep to one
writer at a time.

## #101

This system's own `Store.put_draft_body/4` sets a `body_sha` too, but on
`delivery_draft_bodies` — its cache of the reviewed tier's `draft` variable, whose
previous-body pair serves `document-review`'s per-sentence diff (ORC-114) — a
different column entirely from the one the terminal-status read above surfaces.

## #102

`Catapult .Delivery` gains a **sixth** `defexport` overall: it already carries five —
`fetch_context/2`, `report_result/2`, `provision_test_project/1`,
`release_test_project/2`, `test_project_dispatch_status/3` — all backing
`api_surface/0` entries. `test_project_dispatch_runs/2` delegates to
`Provisioning.runs/2` in the same shape its three provisioning-family siblings already
take (`provision_test_project/1`, `release_test_project/2`,
`test_project_dispatch_status/3`, each a `defexport` with a `@doc` pointing at the
`api_surface/0` declaration it backs), because `Catapult.Foundation.DispatchPlug`
dispatches by `apply(entry.component, name, [conn | params])` and only reaches a
boundary export, never a plain function. `Catapult.Delivery.api_surface/0` carries the
matching sixth entry, `{{:test_project_dispatch_runs, 2}, :get,
"/dispatch/test-project/:project_id/runs", version: "v1", audience: :internal}` — the
same `:internal` audience its three provisioning siblings carry, reached only by the
milestone boundary's own live-suite job — and that function's own comment ("a third,
fourth and fifth path on this one listener") widens to "a third through sixth path" in
the same change, since it names a count that drifts the moment a route lands without
it. `DispatchPlug` itself takes no edit: it matches every declared route generically
off `api_surface/0`'s own list, so a new path costs a declaration and an export and
nothing in the plug.

Naming only `ready/3` would read `remaining` as zero while a review round the sweeper
is about to fire sits invisible to it — the identical race quiescence existed to
hedge, reintroduced through the read meant to remove it. Zero across both means
nothing is dispatchable on either axis and nothing is running — a fact read directly
off plane state, the thing a green run of this test depends on.

Its quiet-since arithmetic (`test/support/quiescence.ex`) hedged exactly the race
`remaining == 0` reads directly — a sweep tick that fired but had not yet produced a
visible row — by waiting out a margin instead of seeing the ready node itself.
`ToySeedChainLiveTest` (the loop `systems/generation.md`'s entry rewrites) was its
only caller; once that loop polls `remaining`, nothing calls `next_quiet_since/5` or
`outcome/4` anywhere in the tree. A module kept alive with no caller is a defect —
ORC-229 and ORC-231 each found one elsewhere in this milestone — not a precedent to
repeat, so `test/support/quiescence.ex` and
`test/catapult/generation/quiescence_test.exs` are deleted rather than carrying tested
arithmetic nothing calls.

## #104

**Why not `Catapult.Engine.Commands.ApproveGate` against each open ticket's gate** —
read off `Store.tickets_for_project/1`, mirroring `document_review_live.ex`'s own
"approve" handler as closely as an unattended caller could — that mirrors the wrong
half. `tickets_for_project/1` reads `EngineFlow` rows, and the only place shipped code
ever dispatches `Catapult.Engine.Commands.OpenFlow` is
`Catapult.Delivery.ContainerLifecycle.open_inline/3` — reachable only from a
*workflow-bundle* container reaching a non-queue-shaped, non-review-shaped array entry
(`workflow.md` #19). Nothing in `lib/catapult/generation/**` ever dispatches
`OpenFlow` or `MintContainer` for a chain-axis node, and a toy-seed project intakes no
workflow-bundle content at all, so `tickets_for_project/1` returns nothing for it, on
every poll, forever — `ApproveGate` itself requires a `flow_id` valid against the
loaded `Catapult.Dsl.Workflow .t()` (its own moduledoc), so there is no ticket to open
one against, even by construction. Wiring a flow to open per chain-axis node needing
review is real work of its own — `ApproveGate`'s own moduledoc already names "the
general node(s)-per-gate mapping" as "Phase 7's" — and building it as a side effect of
an unattended-approval actor would be a second, larger ticket wearing this one's name.
`ApproveDraft` needs no flow at all: its own aggregate clause
(`Catapult.Engine.Aggregate`) is a bare compare-and-swap on `current_draft_id`, the
identical command `test/catapult/generation/toy_seed_chain_test.exs` already
dispatches directly, offline, to drive its own non-live walk. Reaching for it keeps
the actor test scaffolding, not product semantics — an unattended caller resolving a
real ticket's real gate was never the claim, only that something has to approve nodes
for the walk to proceed.

**What this leaves unexercised.** ORC-229's own mechanism — `GateApproved` reacting
through `Catapult.Delivery.DraftResolution` into `ApproveDraft` (`systems/engine.md`'s
ORC-229 entry) — is the path a real human approval takes, and `approve_drafts/2` does
not go through it: it dispatches `ApproveDraft` straight from the boundary surface,
the same bare compare-and-swap `toy_seed_chain_test.exs` already drives offline. So
the boundary suite proves the chain cascades correctly once nodes reach `:approved`,
and proves nothing about `DraftResolution` itself — that reaction stays covered only
by whatever exercises a real ticket's gate, which a toy-seed project, carrying no
workflow-bundle content, cannot be the subject of. Closing that gap needs a chain-axis
node that can carry a flow, which is Phase 7's mapping (`ApproveGate`'s own
moduledoc).

`Catapult.Delivery` gains a **seventh** `defexport`: it already carries six —
`fetch_context/2`, `report_result/2`, `provision_test_project/1`,
`release_test_project/2`, `test_project_dispatch_status/3`,
`test_project_dispatch_runs/2` — each backing an `api_surface/0` entry the identical
way. `test_project_approve_drafts/2` delegates to `Provisioning .approve_drafts/2`,
and `api_surface/0` carries the matching `{{:test_project_approve_drafts, 2}, :post,
"/dispatch/test-project/:project_id/approve-drafts", version: "v1", audience:
:internal}` entry — the same `:internal` audience its four provisioning siblings
carry, and the fifth operation behind `DELIVERY_PROVISIONING_TOKEN` (ORC-216's own
entry above). That entry's own comment ("a third through sixth path") widens to "a
third through seventh path" in the same change, for the identical reason the ORC-225
entry above already gives for keeping it in sync — and the identical phrase sits a
second, uncited place: `Provisioning`'s own moduledoc states "a third through sixth
path on the one listener" too. Both widen together; naming only `Catapult.Delivery`'s
comment is how the moduledoc's copy goes stale while the named one gets fixed.

## #110

The machinery is half-built already: `Catapult.Engine.Topics` rides `Commanded.PubSub`
with a per-project `engine:ready_scopes:<id>` topic, and `Phoenix.PubSub` is already
started (`application.ex`). Three grades, smallest first: a long-poll
(`?since=<cursor>&wait=`, the request process subscribes and blocks in `receive` —
same route, same bearer auth, degrading to today's behavior when the wait budget
expires); SSE over a chunked response; or a second websocket, since the endpoint
declares only `socket "/live", Phoenix.LiveView.Socket` today. Which grade fits turns
on how long App Platform's edge holds an idle HTTP response open, which is unmeasured
— answering it is a design of its own, not a side effect of widening `remaining`.

## #113

Live-suite run 25 dispatched four times against `SwaggerAllen/catapult-test` one to
two seconds before the fixed harness (ORC-223, PR #144) reached the repo:
`Store.mint_test_project/2` set `test_project_state: :active` before a single fixture
file was written, `sweepable_project?/1` reads `:active` as sweepable, and
`Catapult.Generation.Sweeper` ticks on a fixed interval with no knowledge of
`reset_and_intake/2`'s own progress — so any tick landing inside that write (one
Contents-API `PUT` per entry in the caller's `files` map,
`HostPort.Actions.put_all_files/2` — seventeen of them for `ToySeed.reset_files/0`'s
own map: nine `.catapult-stub/*.xml`, the workflow file, seven `docs/raft/*.md`; eight
for `Catapult.TodoAppSeed.reset_files/0`'s) dispatches against a repo that is only
partly written, whichever piece hasn't landed yet: the workflow file, a stub, or the
raft.

**Five more sites state the value set in prose and carry the same four values**:
`Catapult.Delivery.Store.Project`'s moduledoc (the enumeration stated above its own
`Ecto.Enum, values:` list), `Store.sweepable_project?/1`'s `@doc` (the same
enumeration), `Store.release_test_project/1`'s `@doc` (which states the matched
states, not "a no-op if `project_id` is not currently `:active`"),
`Store.mint_test_project/2`'s `@doc` (its own "at most one active" statement), and
`Catapult.Generation.Sweeper`'s moduledoc (which names a provisioning test project
beside "a released or deleted test project").

## #114

A *raised* failure — `reset_and_intake/2`'s last step, `Store.pin_input_documents/3`,
is `Repo.insert!/1` in a loop over the raft, and a `DBConnection.ConnectionError`
there propagates straight out of `provision/1` past that branch entirely, a measured
failure mode on this cluster rather than a hypothetical one — leaves the row at
`:provisioning` with no caller left to release it. Nothing catches that shape at the
call site, so the reclaim has to happen off two later `provision/1` calls rather than
one: this doc's own "at most one active-or-provisioning" entry above already states
`mint_test_project/2`'s own pre-mint update flips a stranded `:provisioning` row to
`:released` exactly as it already flips a stranded `:active` one, but that flip is
part of the *next* call's own mint, which `provision/1` runs *after* that call's own
reclaim step — so the stranded row still reads `:provisioning`, invisible to
`list_released_test_projects/0`, when that reclaim step runs, and only becomes
`:released` once that call's mint flips it. It is the call *after that* whose reclaim
step (`list_released_test_projects/0` → `delete_test_project/1`, run before that
call's own mint) deletes it — self-healing over two calls rather than the one an
ordinary missed release takes, since an ordinary release happens out of band rather
than off a mint's own pre-mint sweep. Neither widening alone covers both shapes;
`delete_test_project/1` needs no matching change of its own, since it already
transitions `delivery_projects`'s own row to `:deleted` unconditionally on
`project_id` alone, filtering on no current state, `:provisioning` included.

## #116

A per-file `Enum.reduce_while` PUT loop in `HostPort.Actions.put_all_files/2` — a
blob-sha read plus a `PUT …/contents/{path}` per entry in `files`, one commit each —
was 60 round trips at ORC-225's own 30-file fixture set, and `ToySeedChainLiveTest`'s
provisioning POST timed out inside it (run 27, `33994472868`, on `ee1843d`): per-file
cost measured flat at ~0.9s across two live-suite runs (0.88s/file at 17 files, run
26; 0.93s/file at 30, run 27), so the write alone crossed `@request_timeout`'s 30s
once the file count did what ORC-225 sized it to. `put_all_files/2` issues seven calls
total, independent of the file count, in this order: the workflow file's existing
blob-sha `GET …/contents/{path}` and its `PUT …/contents/{path}` land first, so
`.github/workflows/catapult-dispatch.yml`'s commit becomes the branch's head before
anything below reads it; `fetch_ref_sha/2` (already there, reused rather than
duplicated) then reads that head **commit** sha; `GET …/git/commits/{sha}`
dereferences it to its **tree** sha, since `POST …/git/trees`'s own `base_tree`
parameter is documented to take a tree object's sha, not a commit's. GitHub's
create-tree reference states what happens when `base_tree` is *omitted* (a new tree
built from only the entries given, every other path read as deleted) but says nothing
about what it does with a commit sha handed to that parameter instead, and that case
hasn't been measured here. The dereference is one cheap call against either unmeasured
outcome — a rejected 422, or a tree silently missing every file this reset doesn't
name — so it is taken rather than gambled on; `POST …/git/trees` with that tree sha as
`base_tree` and every non-workflow entry in `files` inline (`path`, `mode: "100644"`,
`type: "blob"`, `content`) — `base_tree` overwrites the named paths and deletes
nothing else, the identical semantics the per-file loop had; `POST …/git/commits`
against the new tree with the workflow file's commit as parent; `PATCH
…/git/refs/heads/{branch}` moves the branch to this new commit — the actual last write
of the seven, and the one `reset_repo/2` reports. Its contract is unchanged: `{:ok,
ref}`, this ref-update call's own resulting commit sha rather than a second
`fetch_ref_sha/2` read after a last PUT lands (this doc's own ORC-216 entry above: the
sha's *source* is this ref update; the contract it reports is the same) — and because
that commit's parent is the workflow file's own commit, this sha is the branch's
actual head once all seven calls land, matching the ORC-216 contract rather than
trailing it by one commit.

Two different sentences go stale here, not one, and they take different corrections.
**Five sites state the per-file write shape** — "blob-sha-then-PUT", or "the same
per-file Contents-API shape `reset_repo/2` already established" — **and carry the same
rule, `commit_files/4`'s per-file shape being its own and not `reset_repo/2`'s**:
`HostPort.Actions.reset_repo/2`'s own `@doc`; `HostPort.Actions.commit_files/4`'s own
`@doc` (both sentences — "the same per-file shape `reset_repo/2` uses" and "the same
idempotent-retry shape `reset_repo/2` already follows"); this doc's ORC-33 entry
above; this doc's `ArtifactPush` entry above; and
`lib/catapult/delivery/host_port.ex`'s own ORC-33 paragraph, which restates the
identical sentence a third time.

**Two more sites state a different sentence — the ref's *source*, not the write shape
— and carry the narrower rule:** this doc's own ORC-216 entry above and
`lib/catapult/delivery/host_port.ex:31-35`'s own ORC-216 paragraph, which restates the
identical sentence a second time — under one tree commit, with the workflow file's own
commit ahead of it, there is no last file landing, only a final ref update, so "the
default branch's head commit SHA once `files` lands" is the ref update's own commit,
not a re-read after a last PUT.

## #118

The write cost that grew with the fixture list is gone — seven calls, fixed, replace
what was 60 at 30 files — and the remaining sequential cost in `provision/1` is one of
those seven (`fetch_ref_sha/2`, reused rather than duplicated) plus `read_directory/3`
against `docs/raft` (1 + one per role doc, 7 today), bounded by the role list ORC-225
didn't touch, not the fixture list it did.

## #120

`Task .async_stream` over the existing PUT loop was the smaller diff and would have
left `reset_repo/2`'s contract untouched, but every Contents-API PUT against a branch
computes its parent from that branch's current head at request time — concurrent
writes to the same branch race on that parent rather than serializing, so the loop's
own "one file's failure does not roll back an earlier one" guarantee becomes "some
subset of files lands, order unspecified," which is worse than the timeout it would
fix. No probe against `catapult-test` was run to confirm GitHub actually behaves this
way under concurrent PUTs to one branch rather than serializing them server-side — the
same caliber of unmeasured claim the workflow-file question above was. It gets no
probe because none would change the conclusion: even if GitHub does serialize
concurrent PUTs safely, that safety isn't documented, and a mechanism this system
depends on needing GitHub to hold an undocumented guarantee is itself the defect
concurrency would introduce. A single tree-and-commit write needs no such guarantee:
every file's blob is independent, content-addressed into one tree, built and committed
as one object graph before the ref ever moves.

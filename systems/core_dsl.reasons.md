# core_dsl — reasons

The reason behind each rule in `systems/core_dsl.md`, keyed by the rule's id (orchestration's DESIGN §4). Read one with `pipeline reasons core_dsl#n` before changing the rule it belongs to.

## #8

None of these are extension points in the v5 §9 / `bundle.md` #8 sense — annotation
namespaces, declaration kinds, generator types, context-source *kinds*,
enforcement profiles are all vocabulary the grammar references, installed
or not; these four are the grammar's own productions (how many hops a walk
may chain, what scope kinds exist at all), which the extension registry has
no callback for and was never meant to carry. "The core is frozen; growth
happens in extensions" therefore doesn't route these anywhere — there is no
extension shaped to hold a scope kind. What actually governs a core grammar
change is the sentence right after: "a platform-versioned event with a
migration story." This entry is that story. All four landed inside a
content-porting ticket rather than a dedicated `core_dsl` ticket, under
that ticket's design-review sign-off, because a missing DSL construct is a
`chain.md` proposal, not a reason to ship the bundle without the capability
— and not a gap to record as a non-goal in its place; `mint.<name>`
(`chain.md` #12's join-target field-source addendum) landed the same way. Design review's
sign-off is the reviewed change; a dedicated ticket would be re-litigating
a decision already made in daylight, not making a new one. Every addition
is additive to the closed sets it extends (no existing bundle content stops
parsing) and ships with loader tests
(`test/catapult/dsl/context_walk_test.exs`,
`test/catapult/dsl/loader_test.exs`) exercising the new productions
directly, not only through `bundles/default/`'s own use of them. Revisit
condition: none for the mechanism split itself (extensions still own
vocabulary, core still owns grammar); a *fifth* grammar growth event still
wants the same daylight this one got, whether or not another ticket happens
to be carrying it.

## #9

It landed in the same ticket as the four above for the identical reason:
the author's decision on the chain's review mechanism is ticket direction,
reaching the branch before the pass that carries it starts, so the
`v5-design-decisions.md` edit is that pass's to make. `reviews:` is
implemented in `Catapult.Dsl.Tier`/`Catapult.Dsl.Chain`, with loader tests
exercising it directly (`test/catapult/dsl/loader_test.exs`), and
`bundles/default/` loads clean end to end (25 tiers — 17
generation/projection plus 8 review — 6 edges, 5 flows, 2 workflow gates).
Revisit condition: none — this *is* the daylight the entry above asked for.

## #10

Updating `bundles/**` content ahead of this landing fails every bundle
load; updating the parser without the content leaves the content silently
unable to say what the grammar argues it should. Neither order is safe done
alone, so this is one change, not two.

**Not built: a globbed directory for status participation generally.**
`statuses/<name>.yaml`, one file per configurable fixed kind, mirroring
`gates/` and `environments/`, is not the shape: there is exactly one
configurable kind (`critique`), and a directory earns nothing over a fixed
single path until a second kind actually needs the same knob. Revisit
condition: a second system status wanting a workflow-declared participation
depth — at which point the fixed path generalizes to a directory the same
way `gates/` already shows the shape for.

## #11

Revisit condition: none — the coupling this refuses is structural, not a
gap waiting on more flows to exist.

## #13

`queues/project.yaml` is optional and singular (`critique.yaml`'s shape)
and holds whatever queue array the workflow bundle authors — no anchor
check, no fixed count, no platform vocabulary to validate names against.
`queues/containers/<name>.yaml` is directory-shaped like `gates/` — a
bundle may declare many named containers — and each one's `queues:` array
must hold exactly the five platform-fixed anchor names, in exactly this
order, undeclarable by either axis for the identical re-resolution-anchor
reason system statuses are: `setup`, `prep`, `main`, `retro`, `cleanup`.
There is no per-container-kind sequence table and no kind registry —
`container:` names the declaration itself, the same way a `gate:` file
names its own gate. `types/<name>.yaml` registers a plain work-item type as
a list of the declared gates (`workflow.md` #5) it visits — inverting the gate's own
former `ticket_types:` field, which is retired outright — and shares one
namespace with container declarations: a bundle's containers and its plain
types are one registry. Every queue entry, project or container, carries
exactly one field, `flow:`, required, naming a member of that registry; the
loader does not branch on which kind of declaration the name resolves to,
only on what that declaration's own content contains. The loader gains two
structural checks with no exact precedent in the closed sets the load
rules already validate: **a declaration-graph check** over container names connected by
`flow:` edges whose target resolves to another container (an edge into a
plain type is not part of this graph — a plain type has no further `flow:`
of its own, so it is always a leaf), which must be acyclic with a
self-reference rejected as the degenerate one-node cycle — this is the
check that bars a container from nesting its own kind and the one that
bounds nesting depth, and it runs on *declarations* rather than on
*instances* because an instance-ancestry check leaves unbounded depth
declarable, caught only mid-flight; and a scoping check that a `blocks:`
entry must name a queue declared in the same file, never a queue nested
inside what the blocking queue's `flow:` opens. `boundary`, the single
static agent step this replaces, is retired from `workflow.md` #10's list outright —
nothing takes its slot there, because `retro` and `setup` dispatch as
ordinary chain flows through a declared queue rather than through a tier's
`delivery.agent_step`; `setup` specifically is its own anchor entry, first
in a minted container's own five-entry sequence — not a value stashed on
`prep`'s own `flow:`, which would run `setup` once per container instead of
once per mint — so there is nowhere `flow:` needs to name two things on one
declaration. The machinery this grammar drives — the dispatcher, the sweep,
the scan/setup/retro passes, and the ticket→milestone `Stubbed`/`Urgent`
interactions that give it a subject — is `systems/delivery.md`'s
(`Catapult.Delivery.ContainerLifecycle`).

## #14

The machinery is unaffected in shape beyond what it inherits from the
grammar being one file format instead of three.

## #16

**`singleton:` bounds "at most one, ever, over the queue's whole lifetime,"
not "0 or 1 unresolved right now"** — under a population bound, a queue
whose sole item has reached `terminal` looks exactly like an empty queue
with room, and a second work item is admitted and filed `Blocked`. It is
neither; the loader's own check is unaffected (still not a load-time
constraint, since assignment history is live state), but the dispatcher's
job is "a loud error, permanently, once one work item has ever been
assigned," not "admit and file `Blocked`." The dispatcher, the sweep, the
scan/setup/retro machinery, the entry-point load check and the
singleton-lifetime rejection check are ORC-104's, and carry it.

## #17

**Against the actual default bundle:** an *undeclared* `throwback:` under
the old `[]` default (`workflow.md` #32) left a gate with zero legal exits — an
unreachable gate, not a feature — which is why every declared gate in
`bundles/default-flow/gates/**` names one. Under the derivation, no gate
*needs* to declare anything: the derivation supplies a default and the
earlier-prefix rule supplies everything else a human might pick — but a
gate that wants a landing point other than its derived default still
declares one. `ux-review`'s `[pending]` is exactly that gate: `pending`
sits outside `ux-review`'s own sub-array and differs from the derived
default (`generation`), so the declaration is doing real work and survives,
narrowed to a bare `pending`. `engineering-review`'s `[generation,
ux-review]` is mixed: `generation` restates the derived default (redundant,
droppable), and `ux-review` is a second landing point the narrowed field
cannot hold beside it — which one `bundles/**` keeps is an ordinary
bundle-authoring call. `workflow.md` #10's fixed vocabulary loses none of its three
jobs (gates/environments/ critique position against it, chain tiers bind to
it, cutover re-resolution anchors on it) — only the middle job's
*legality*-bounding half, which no longer needs any bundle-declared list;
the landing-point half survives on the narrowed field.

**Not decided:** nested sub-arrays (a homonym risk against
`container`-skeleton nesting, `workflow.md` #9); and a throwback from a gate sitting
outside every sub-array, targeting into one. Whether a population anchor
can sit inside a sub-array, and the dispatch question behind folding
`setup`/`retro` into `milestone`'s own array, are ORC-148's, below. **Built
at ORC-141:** the loader changes this entry describes, in
`lib/catapult/dsl/workflow.ex` and `lib/catapult/dsl/gate.ex` — the
`throwback:` field narrows from a list to a single optional status
(`String.t() | nil`) and its load-time check narrows to match, and
`gate_throwback_problems/2`'s "earlier in the array" logic is reused at the
command edge as a runtime check for the undeclared case
(`Catapult.Engine.Commands.DeclineGate`).

## #18

A bounded allow-list on the gate could only ever have been the legality
check if `Catapult.Engine.Aggregate`'s `DeclineGate` clause enforced list
membership, and it doesn't: that check is the command edge's, per the
module's own moduledoc.

## #19

A list stops meaning anything the moment it stops bounding (naming several
targets said "any of these is legal," a legality claim), so the field
narrows to a single optional status rather than disappearing.
`Catapult.Dsl.Gate`'s `throwback: [String.t()]` narrows to `throwback:
String.t() | nil`, and `Catapult.Dsl.Workflow .gate_throwback_problems/2`'s
membership check narrows to match — a smaller field, not a removed one.

## #22

This is not plane logic branching on grouping: `docs/non-goals.md`'s
automation-protocol entry's admission rule is about states and, by
`workflow.md` #6's own extension, about groupings a bundle authors; tree shape is neither, so
that entry does not bar an implied-merge mechanism.
`docs/v5-design-decisions.md` §7.15's own child-spawn passage states the
same rule as §7.10. The loader and dispatcher side is the entry above's,
extended to `SystemStatus.@statuses`'s `fanout` removal and a
tree-shape-derived `reconcile`/`merge` dispatch rather than a
depth-filtered one.

## #23

The loader and dispatcher side is the entries above's, extended to the new
kind, the two-type split, and the tightened `pending`/gate checks.

## #28

`namespaced_positions/1` computes a single ambiguity set —
`Enum.frequencies_by(& &1.bare)` — and its `canonical` field answers one
question with it: is this entry's own *authored name* the string a
reference resolves to unqualified, or does it need `<anchor>.name` because
that bare string recurs elsewhere in the type's array? That is exactly
right for what `Catapult.Dsl.Workflow.resolve_reference/2` and
`earlier_names/2` need (`workflow.md` #8's own "stays bare when unambiguous" rule),
and the two stay in step because both are keyed on `bare`.

A second question gets asked of the same set, and ORC-155's `name:` is what
pulls it apart from the first: does this entry's own *runtime position* —
its `status:`/`review:`/`environment:` value, the field every `position()`
constructor reads and `name:` never touches (`workflow.md` #10: shapes are
all the engine knows about a position) — recur elsewhere in the array, so
that two occurrences collide once reduced to `{:kind, atom}` and need
their anchor carried at runtime regardless of whether they're also
nameable apart? Before `name:` existed the two questions had one answer,
because bare **was** kind. `name:` was built precisely so two same-kind
entries could carry distinct labels (`workflow.md` #7, ORC-155) — and a
bundle exercising exactly that, two `status: pending` entries with
distinct `name:` overrides, now recurs on kind while *not* recurring on
bare: `canonical` reads "unambiguous" for both (their names don't collide,
the point of naming them), while `Catapult.Delivery
.FeatureLifecycle.Sequence.to_position/1` — reading `status:`, never
`name:` — still builds `{:kind, :pending}` for both. Reproduces the "first
occurrence wins, silently" failure ORC-171 fixed, through the one door
`name:` itself opens, and ORC-171's own reproduction never exercised a
per-occurrence override so never hit it.

## #30

A user's design system is never in that registry; nothing publishes a
version for it to bump, so wiring `design_system` through `external` would
carry a staleness-cascade half with nothing to trigger it. A `ref` is ruled
out twice over: v5 §4.5 already says a supplied design system "rides §5.4's
node rather than a ref," and independently, a ref attaches via *reference*
edges from a singleton pool with no per-use kinds (§4.5's own "stay general
on purpose"), while `ui_coll → design_system` (§5.4's edge inventory) is a
typed *dependency* edge carrying cardinality and layering semantics a
reference edge was never built to hold.

## #31

`design_system` is a node kind, not an external and not a ref, declared
here — which is what earns the admission the paragraph above claims: a tier
is designed to read the role because this entry designs it.

## #33

**Coverage, as a checkable claim: the check as specified here catches all
nine of this ticket's own `declared_in` defects, not eight.** Eight sit one
segment under their tier's root element, inside that element's own inline
content model, and need no `type=` resolution to validate. The ninth —
`ui_coll → design_system`'s `design-system` segment, reached only by
following `primitives`'s `type="Primitives"` reference — is the one
instance that does, which is exactly why the same-file `type=` walk above
belongs in this check rather than waiting for a later ticket: without it,
this entry's own mechanism would not have caught the defect this ticket
exists to fix.

## #34

A tier's root element declares its own sequence inline
(`frontend_sysarch.xsd:78`, `comparch.xsd:182`, `ui_collarch.xsd:120`,
`screen_collarch.xsd:115`), but the children in that sequence carry their
content as named complexTypes rather than inlining it
(`frontend_sysarch.xsd`'s `<ui-dependencies type="Dependencies">`,
`ui_collarch.xsd`'s `<primitives type="Primitives">`, and so on). So a
path's first element segment — the one directly under `draft` — resolves
against the root's own inline sequence, and every segment past it sits
behind a `type=` reference. Treating a same-file reference as unresolvable
would leave the check able to validate that first segment and nothing
deeper, since that is how nearly every multi-segment path in this bundle is
shaped.

## #38

Their own schemas (`comparch.xsd` and its five siblings) declare
`<technical-specification>`, `<public-surface>`, `<private-surface>` and
`<failure-surface>` — hyphenated. Only `draft.policies`, present on
`comparch`, `screen_collarch` and `ui_collarch` alone (the other three
declare no `policies` fragment either), happens to be a single word and so
resolves. The defect reaches the boundary suite: the shipped toy-seed
fixture (`test/catapult/generation/fixtures /toy_seed/comparch.xml`)
carries the hyphenated element names its own schema requires, so the chain
that suite exercises writes four of `comparch`'s five fragments as `nil`
silently. The bundle-content rule, landing with the widened check: the six
tiers' `produces:` `authored:` values are spelled the hyphenated way the
schemas declare — the schemas and the fixture are the correct side, and
only the tier files reading them are wrong. `techspec` itself — the
fragment *kind* name and the `fields:` key alike, as in `chain.md` #12's
`mint.parent.techspec` example and the `subcomp.parent_techspec` one below
— is a single word and is spelled correctly. What those examples name is
empty all the same while the `authored:` source beneath it is misspelled —
`comparch`'s own `techspec` fragment carries `nil`, so
`mint.parent.techspec` copies nothing across every tier that reads it — the
identical silent-empty-context failure mode the widened check exists to
close.

## #40

In `bundles/default`, `comp`'s
`project_techspec`/`project_policies_summary` and every `parent_*` field on
`subcomp`/`ui_subcomp`/`screen_subcomp` are not row-local to a fanout
instance element at all — `subcomp`'s `parent_techspec` names the same
`techspec` fragment `comparch.yaml`'s own `produces:` writes onto its
`self.parent` (comp), computed in the identical commit that fans subcomp
out. Both `fields:` and `produces:` are already local values `Extraction`'s
own commit-time pass holds before `mints:` is built, so reading one of them
by name at mint time adds no navigation the extractor doesn't already do —
only a second place to read an already-computed value from, named so a
bundle author (or a loader) can tell "read off the instance element" apart
from "copy what this same commit already wrote about itself" without
guessing from the field name alone.

## #41

`design_system` is not in `systems/generation.md`'s own
dispatch/fixture-coverage totals (it has no `draft:` for
`Sweeper.dispatchable?/1` to match, same as every join-target tier);
`ref`'s absence from the swept set is `systems/generation.md`'s own ORC-236
entry.

## #45

Stated as one superseding entry rather than as edits to each entry it
touches, because the entries above are ticket-attributed records of
what a named pass decided, and rewriting them in place would put
words in those passes' mouths. What a later reader needs is which
rules still bind, and an entry that names them is checkable in a way
fifteen silently amended entries are not.
The entries above still carry their own citations, and those are
repointed at the rules that replaced the retired spec's sections
rather than left dangling: a citation is a pointer, not a claim a pass
made, so moving one puts no words in anyone's mouth. Where an entry's
prose would otherwise *state* a rule the contract now contradicts —
`ref`'s scope, a review tier's own file, two grains landing in one
collection — the spelling is corrected and the pass's conclusion left
as it stood. The retired spec's own sections are gone from this
document; `docs/dsl/retired-spec-index.md` maps them for a reader
holding an older citation from git history.

Each change is argued where its rule lives: `bundle.reasons.md`,
`chain.reasons.md` and `workflow.reasons.md` carry the reason behind
every rule of the contract. The sixth change is the one the redesign made rather than moved: an
ungrouped gate's forced `throwback:` bought nothing, because the
author's own case for it — a gate between a staging and a prod deploy
— is exactly where most tickets go back to no predictable position, so
the declaration it forced was a guess written to satisfy a check.
`workflow.reasons.md` #35 carries it.

The one reason worth repeating here,
because it is the one a later pass would otherwise re-derive: the
cross-axis reference runs from the workflow because the workflow is
the file a project forks, and a gate needs an ordering point, so
gating between two tiers batched at one position splits that position
and renames it. Under the other direction that renames every tier
naming it — eight of them at the default chain's architecture
position.

## #ORC-249-1

Elixir because the task calls the loader, and `erlef/setup-beam` is a
composite Action unreachable from a shell string — anything needing
`mix` inside an agent job installs its own toolchain, but `ci.yml`
already runs `mix` steps with the toolchain set up, so a `mix` task is
the cheapest thing that can call `Catapult.Dsl.Loader` directly rather
than shelling out to it. The root project rather than
`components/substrate`: substrate's own `mix catapult.audit` exists
because substrate ships into every generated project and needs its own
gate suite there: pulling this task in for that reason alone would put
`system:substrate` in every ticket touching the bundle pair's line
count, for a registry (`Catapult.Audit.Check`) built for boot-time
component checks this task has no component to register. Not a port of
`check.py`: three of its four jobs stop being a second implementation
the moment the loader reads `docs/dsl/`'s rules itself, and porting
them into a checker would be exactly the drift `docs/dsl/`'s own
existence is meant to end. The fourth job — the line-count bound — has
no loader rule behind it, because it is a readability property of the
file, not a load-time property of its content, so it stays a
stand-alone measurement rather than moving into the loader with the
other three.

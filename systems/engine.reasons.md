# engine — reasons

The reason behind each rule in `systems/engine.md`, keyed by the rule's id (orchestration's DESIGN §4). Read one with `pipeline reasons engine#n` before changing the rule it belongs to.

## #5

Generation and delivery both land after this ticket in the build order (`docs/build-plan.md` Phase
3/4), so the scheduler cannot call an enqueue function that doesn't exist yet and must not be built
to assume one particular shape for a consumer that hasn't landed. "The engine writes it; generation
and delivery consume it" (below) is a claim about which side owns the *readiness signal* — engine,
exclusively, which is what makes "nothing else initiates work" true — not about the engine
performing generation's or delivery's own outbox insert. When each consumer lands, its own ticket
names the cross-component edge, and conventions §7's pattern ("insert the job through the target's
exported enqueue function inside the local transaction") applies on *its* side of the subscription,
not this one's.

## #9

A pinned input document is not modeled as a synthetic `Node` flowing through the existing `{:ok,
[Node.t()]}` shape uniformly: that would need a fabricated `status` for every consumer's status
check to key off, and the one status that keeps both call sites correct (permanently `:approved`) is
a fact about the readiness query, not about the document, which is exactly the "special case grown
to fit an escape hatch" this system's standing decisions elsewhere refuse (see "Navigation edges get
no second check," above).

## #12

Restated here because a query written defensively (checking a property its input already guarantees)
is exactly the kind of drift-prone duplication `core_dsl.md`'s "all validation at load time where
possible" standing decision exists to prevent.

## #14

The bullet above's premise — every minted child eventually earns `:approved` through `DraftApproved`
— does not hold for exactly the tiers dsl-syntax.md §3 calls a **join-target tier** — one declared
with no `draft:` block (`comp`, `subcomp`, `resp`, `sysarch_policy` in `bundles/default`, all `generator:
synthesis` today, though the condition that matters is "no `draft:`," not the generator kind — see
below). Such a tier commits no draft, so no `DraftCommitted`/`ApproveDraft` pair ever runs for it,
and `Store.approve_node/2`'s one caller (`Reducer.apply(%DraftApproved{}, _)`) can never name it.
Minted at `:absent`, a join target sits there forever, and `walk_ready?/2`'s `status == :approved` —
dsl-syntax.md §7's "readiness requires all targets ready; context is the only readiness signal" —
never turns true for any tier whose context walk reaches it (`comparch`'s `per(comp)`
`self.parent.handle`, and the same shape for `subcomparch`). The chain stalls at the first join
target and never reaches the tiers downstream of it.

**Why the condition is "no `draft:`," not "`generator: synthesis`."** Every join-target tier in
`bundles/default` happens to declare `generator: synthesis`, but the causal fact is the missing
`draft:` block: that's what makes `DraftCommitted`/`DraftApproved` structurally unable to name the
node, and dsl-syntax.md §3 already has a name for a tier in that shape — "join-target tier" —
independent of which `generator:` it declares. Keying the mint-time default on `tiers
.<target>.draft == nil` rather than on the generator atom is what makes the default generalise to a
future `generator:` kind that also produces no draft (`external`, `template` per dsl-syntax.md §3.2,
neither of which happens to omit `draft:` in `bundles/default` today) without revisiting this
decision when one arrives: any tier a bundle author writes with no `draft:` gets the same mint-time
`:approved`, whatever its `generator:` says.

## #17

This keeps `Catapult.Engine.Events.DraftCommitted`'s own moduledoc true without qualification —
"extraction against the bundle's `declared_in` paths happens at the command edge... never inside the
reducer" — rather than having `apply_mint/2` load a `Chain` to answer the same question, which is
exactly the impure, bundle-content-dependent read this system's purity floor and the harvesting
entry's command-edge rule for `since_sequence` (below) both rule out for a different value.
`system:generation` carries ORC-117 alongside `system:engine` for that reason: the decision is
engine's (what a join target's status means), the computation is generation's (where the tier's
declaration is already being read).

## #18

That `Extraction.mints/4`'s `id`/`alias` identity fallback is verified only against `sysarch`'s own
`<component alias="...">` shape, and mints `resp`/`vocab`/`policy` (now split into `sysarch_policy`/
`comparch_policy`/`non_goals_policy`, `systems/platform_content.md#15`) a `nil` scope_key otherwise
(the module's own comment on `identity_value/2`, and `test/catapult/generation/toy_seed_chain_test.exs`'s
moduledoc, which is why that test seeds those by hand) is a real but separate gap in *identity
extraction*, orthogonal to a join target's *status*. `vocab` (`bundles/default/tiers/vocab.yaml`)
declares a `draft:` block and is unaffected. And `Catapult.Engine .Projections.Staleness.stale?/2`'s
early `:absent` clause ("not stale, merely not drafted") does not match a join target once it mints
at `:approved`, which is safe because every join-target tier in `bundles/default` declares no
`context:` of its own (there is nothing to gate its own generation on, since it is never dispatched
— `generation_tier?/1` requires `draft` non-nil), so `stale?/2`'s general clause
(`Enum.any?(tier.context, ...)`) degenerates to the same `false` the `:absent` short-circuit gave.
**Named rather than silently relied on:** nothing at load time stops a bundle from declaring
`context:` on a tier with no `draft:` the way `Catapult.Dsl.Tier`'s `@review_forbidden` already
stops one on a review tier — a gap in `core_dsl`'s own validation (`lib/catapult/dsl/tier.ex`,
outside this doc's file map), named so a future bundle author hitting it reads a known gap rather
than a surprise.

## #19

Recursion terminates because a node's `parent_node_id` chain is acyclic by construction: a node's
minting parent is committed, and exists as a stored row, strictly before the mint that names it as
parent, so no chain of `parent_node_id` lookups can revisit a node still being resolved. The tier
graph's own type-level acyclicity check (`core_dsl.md`'s standing decision) does not cover this
guarantee: that check covers which tiers may name which as `per(X)`/ `child_of(X)` targets at the
schema level, and says nothing about instance-level `parent_node_id` pointers, which is the thing
this recursion actually walks. A join-target chain in `bundles/default` today is one level deep
(`comp`'s minting parent is a `sysarch` node, which has a `draft:` and stops the recursion there),
but nothing in the rule assumes that depth. So `comparch`'s `self.parent.handle` requires the `comp`
it reads to trace back to an `:approved` `sysarch`, not merely a minted one, and the identical shape
covers `subcomparch` off `comparch`, `ui_collarch`/ `screen_collarch` off `frontend_sysarch`'s
minted `ui_coll`/ `screen_coll`, and every `all.journey.handle`/`all.screen.handle` read that lands
on a `journey`/`screen` node once one exists.

## #20

And the resolver does not reach every walk: `.fragments[kind]` reads (`self.parent.dependency ->
comp.handle.fragments[pubapi]` and its siblings) name a fragment a *different* node writes (the
`per(comp)` `comparch` node, via `produces:`, never `comp` itself), a provenance question `settled?`
as stated here does not answer — moot for every such read in `bundles/default` today for an
unrelated reason (`systems/generation.md`'s ORC-235 entry: every `.fragments[kind]`- typed walk in
this bundle walks a `dependency`-typed edge, and no `dependency` instance in this bundle is
extracted, because its `source` always names a join-target node type that never commits a
`DraftCommitted` under its own name — a source-identity gate, not an edge-type one, but one that
excludes this whole family regardless — so the walk resolves to `[]` and stays vacuously satisfied
whatever `settled?` says). Closing that gap is generation's; `.fragments[kind]` readiness, once
dependency extraction exists, extends `settled?` with a same-tier carve-out (a tier reading a
fragment its own sibling instance writes — `comparch` reading another `comp`'s pubapi — stays
ungated, preserving "a tier's own nodes fan out in parallel") rather than being treated as a fresh
problem.

## #21

A `per(X)` node has no stored row until it drafts (`ReadyScopes`'s own moduledoc: a transient,
never-persisted placeholder stands in until then), so the existing-row list at a `per(X)` tier is
never trustworthy as a final population on its own — zero rows there means either "none will ever
exist" or merely "hasn't drafted yet," and the only way to tell them apart is to check whether the
driving tier `X` is itself exhausted first. A `child_of(X)` node's row appears at its parent's mint,
not at its own draft, so once every minting parent `Xi` is exhausted the current row count at
`<tier>` is already final and the recursion needs no further condition on those rows themselves —
the asymmetry between the two branches below is this, not an inconsistency:

This is what tells `all.vocab.handle` (`vocab` is `child_of (feature_expansion)`) that zero vocab
entries is a legitimate, terminal answer once `feature_expansion` is `:approved`, apart from
`all.journey.handle`/`all.screen.handle`/`all.sysarch.handle` in a fresh `frontend_sysarch` context,
where `journeys`/`screens`/ `sysarch` (respectively
`per(feature_expansion)`/`per(feature_expansion)` /`per(requirements)`) have not drafted at all —
`drained?` is `false` for all three, so `frontend_sysarch` does not dispatch on the first sweep with
an empty context — the failure ORC-235 opened against.

## #22

In `bundles/default` today the scope graph is finite because every `per(X)`/`child_of(X)` chain
eventually reaches one of the bundle's four `singleton` tiers (`design_system`, `feature_expansion`,
`frontend_sysarch`, `non_goals` — `ref` is `scope: reference`, not `singleton`, above, and no
`per(X)`/`child_of(X)` chain in `bundles/default` names it as a parent), because the bundle's
authors have kept the scope graph a DAG by convention — not because anything checks it. Closing that
gap — extending `Chain.build`'s existing cycle detection to scope references alongside edge
instances — is a `core_dsl` loader change; `drained?`'s own correctness leans on a guarantee the
loader does not supply.

## #23

A separate ordering declaration would still need this same recursion to answer "is the tier before
me actually finished" — a sequence position alone cannot tell "zero nodes because none will ever
mint" from "zero nodes because nothing upstream has drafted yet" any more than a bare `Enum.all?/2`
fold can, since that is a fact about the scope/fanout graph, not about position in a list. A
sequence would therefore buy no simplification over deriving order from the graph
`context:`/`scope:` already declare, while adding a second, independently-authored representation of
the same fact — exactly the drift a declared order and a declared graph disagreeing would invite,
and exactly what `docs/dsl-syntax.md` §7/§7.2's "context is the only readiness signal" already
commits this system to not needing. `ready_scopes` stays derived from one graph, not two.

## #24

The Scope section above states the point of ordering `frontend_sysarch` after the backend as letting
"the front-end family read real component APIs on its first pass rather than a shape it has to guess
at." `drained?` delivers the ordering half — `frontend_sysarch` does not dispatch before `sysarch`
is approved — but not the reading-real-APIs half: `frontend_sysarch`'s `all.comp.handle` and
`ui_collarch`'s `self.parent.uses_shapes -> comp.handle.fragments[pubapi]` wait, via `settled?`,
only on the `comp` node's own minting `sysarch` — never on `comparch`, the tier that actually writes
the `pubapi` fragment `uses_shapes` reads (the `.fragments[kind]` provenance gap noted above). The
walk itself does resolve: `source_ref:`/`target_ref:` extraction (`systems/generation.md`'s ORC-235
entry, `systems/core_dsl.md`'s ORC-236 entry) extracts every `dependency` instance regardless of
which tier `declared_in` names, `uses_shapes`/`calls` included, so relocating a `dependency` edge's
declaration does not leave it resolving to `[]` for want of extraction. The one gap between
`drained?` and the Scope section's stated purpose is a same-tier `.fragments[kind]` provenance
carve-out in `settled?` — readiness's mint-ancestry-vs-fragment-authorship distinction, not an
extraction or mint-time-value question.

## #26

A `supplied` node is settled the moment it exists because nothing upstream in the generation chain
produced it and could still revise it; a `reference` node (`ref`, the tier `dsl-syntax.md` §3.1's
`reference` scope kind exists for) has the identical property for a different reason — its content
is written once, by a write path outside the chain, with no draft anywhere in its history to be
unapproved. Both clauses read "settled unconditionally, the moment the node exists," keyed on the
tier's own generator declaration rather than on `parent_node_id == nil`, for the reason the
three-way match above keeps the check declaration-keyed. This is what makes a `self.reference ->
ref.handle` walk (`docs/dsl-syntax.md` §3.3's own worked example) resolvable at all: a `ref` node
has no draft anywhere in its history, so there is no approval for `settled?` to wait on — it has to
read the node's `generator: reference` declaration and say "settled" the moment the node exists, the
same way it already reads `generator: supplied` for `design_system`.

## #27

`dsl-syntax.md` §13 places this at "projection time," not load time; which moment of projection time
is the load-bearing part, because the naive answer ("check on every `DraftCommitted`") produces
exactly this failure: `fulfills`'s `source: {min: 1}` ("every comp fulfills ≥1 resp") reads as
violated on every comp that hasn't drafted its `fulfills` edge yet, which is every comp for some
nonzero span of the chain's own run — a check that fires on every intermediate state is not a check,
it is noise indistinguishable from a real defect. The gate is the mechanism this system uses to tell
"not yet" from "never": a `{min, max}` bound on one side of an edge instance is evaluated only once
that side's own tier is `drained?/1` (above) — the identical "has everything that could ever exist
already committed and settled" question `all.<tier>` readiness answers, asked here of a cardinality
bound instead of a context walk. `max` bounds need no such gate (a count that has already exceeded a
ceiling stays exceeded; checking early costs nothing) and are evaluated as soon as they can be
violated, `min` bounds and `graph_constraint: acyclic`/ `no_self_loop`/`tree` (both real properties
of the whole instance graph, not of a single edge as it's written) wait on drainage the same way.

**Why a reported finding rather than a blocking gate or a retried draft.** Grammar validation
retries the agent that wrote the failing body — there is exactly one draft and one author to hand a
typed error back to (`systems/generation.md`'s "validation failure is feedback, not error"). A
cardinality or graph-constraint violation has neither: the defect is a property of the graph as a
whole, most often spanning several already-committed, individually-valid drafts (a `{min: 1}`
violated because a *different* tier's draft failed to reference this one, or never existed at all) —
there is no single agent whose retry could fix it and no single draft to decline. Surfaced as a
finding a human resolves, the same shape a policy enforcement gap already takes
(`docs/v5-design-decisions.md` §4.5's "enforcement gaps are plane-filed tickets, instantly visible")
rather than as a blocking state this system's readiness graph would have to reason about. This
system has no node status and no gate for it — the finding's own surface (a ticket, a dashboard
entry, or reuse of an existing structured-signal channel) is generation's/ delivery's to build
against this timing rule, not a new engine primitive.

## #29

`walk_ready?/2`'s own predicate — `Enum.all?(targets, &(&1.status == :approved))` — already requires
every node a context walk reaches to be `:approved` before the tier reading that walk can dispatch;
§7 states the same fact from the grammar side ("readiness requires all targets ready. Context is the
only readiness signal"). So a tier positioned in a workflow sub-array *after* a gate can never
become ready while the tier(s) the gate's own sub-array pins remain unapproved — not because
anything checks the workflow-axis grouping against the chain-axis node, but because there is no path
to `:approved` for the later tier that does not first satisfy the earlier one's own context walk.
**What this is not:** a claim that this system reads or enforces sub-array membership at all — it
doesn't, and gains no new code from this entry. The invariant is chain-axis readiness, restated for
a workflow-axis reader (ORC-116's navigation) who needs to know a fanned-out node cannot be "ahead
of" its own group's gate. If that reader ever needs something this system doesn't already expose —
the sub-array a given node's tier belongs to, say — that is a new query, not evidence this invariant
is wrong.

## #30

`Catapult .Repo`'s pool is a shared, finite budget, not this sweep's alone to spend — SETUP.md §2
sizes it against the projector's writes, Oban's workers as queues land, the health check, *and* this
sweep together, on the one reference cluster this code deploys to, and owns that number alone
(`docs/non-goals.md`: the instance's live facts have one home). `Task.async_stream`'s default width
(`System.schedulers_online`) is the idiomatic move and the wrong one here: on a run of any real size
it alone can reach for more connections than the pool holds, ahead of a request the pool exists to
serve. One project at a time keeps a tick's own footprint at a single checked-out connection
regardless of how many projects exist, which is affordable at 30s cadence because a readiness query
is cheap and the floor's whole job is convergence, not speed. Revisit condition: a measured tick
duration exceeding the cadence at real project counts — the fix then is a bounded width stated as a
number here, never the default.

## #31

`:local` placement would be defensible on redundant-computation grounds alone (a stateless read
costs cycles, not correctness, if every node repeats it), which does not price what "every node"
costs against a pool sized in the single digits: a rolling deploy runs two full instances briefly,
and `:local` turns one sweep into two, against the same budget the paragraph above already spends
down to one connection per tick. `:singleton` removes the doubling by construction — one sweeper
cluster-wide, like the projector beside it — rather than accepting it and arguing the size is fine;
the two processes share one placement rule for one reason (each must run exactly once, not once per
node) instead of each defending a different number. Registered via `processes/0` like any other
named process.

## #32

ORC-6 fixed the id column's *type* at `:string` rather than `:binary_id` deliberately, to leave the
scheme open — but fixed the primary key to `id` alone in the same migration, which only one of the
two legal schemes supports. Per-project is the scheme that holds. `scope_key` and `handle` are
already how a node is addressed *within* a project (`dsl-syntax.md` §3), and neither the command
edge nor a bundle's own vocabulary promises more than that. A caller-supplied string unique across
every project the plane will ever build is not a constraint anyone picks on purpose, and both
alternatives are worse: reopen the UUID door ORC-6 deliberately shut for no gain the DSL asks for,
or lean on bundle authors to hand-prefix every id with its project — a convention nothing enforces.

**The evidence is that authors already do not follow it.** Test modules deadlocked on shared bare
ids — `"sysarch"`, `"comp1"`, `"n1"` — independently written and each reaching for the same
plausible name, exactly as a bundle's own tier and scope vocabulary would. That is ordinary
authoring rather than a test artifact, which is why per-module id prefixing is the wrong fix: it
makes the suite pass without saying whether two real projects can collide the same way.

## #33

A natural key like `engine_edges`' `(edge_name, source_node_id, target_node_id)` gains nothing from
the primary key widening, and `Repo.insert!`'s `on_conflict: :nothing` names exactly one arbiter: a
*different* unique index the same insert violates either raises, or drops the row as an apparent
replay and leaves a graph silently missing an edge. The failure mode is silence by construction, so
a new table in this store carries the obligation whether or not a test has tripped over it yet.
`priv/repo/migrations/20260820000003_key_engine_store_by_project.exs` carries the per-table
mechanics and that arbiter subtlety in full, at the point either would be edited.

## #37

`struct/2` restores atom *keys*; it does nothing for a value that started life as an atom and
travelled the wire as a JSON string, and no consumer downstream ever casts on read — every `Store`
insert/upsert this system makes goes through `Ecto.Changeset.change/2`, which performs no casting,
which is exactly why the defect surfaces as `Ecto.ChangeError` against an `Ecto.Enum` column rather
than a silent coercion.

**`DraftCommitted` fails as `Ecto.ChangeError` one level in, not as `KeyError`, because `keys:
:atoms` reifies nested keys as well as top-level ones:**
`Commanded.Serialization.JsonSerializer.deserialize/2` only turns on `keys: :atoms` when its caller
supplies a `type:`, and it is the caller, not this function, that "always" applies to —
`EventStore.RecordedEvent.deserialize/2` calls it with `type: event_type` for event data and with no
`type:` at all for metadata, which is also why metadata stays string-keyed on arrival while event
data does not. Once `keys: :atoms` is on, it threads through every nested object Jason's own decoder
parses, not only the struct's top level (confirmed by reproducing the exact round trip against
`Catapult.Engine.Events.DraftCommitted`, not inferred from reading the library). A `mint`'s
`node_id`/`tier`/`edge_name` keys arrive as atoms already; dot access on them does not raise
`KeyError`. What survives the wire wrong is the same failure the other three events have, one level
in: `mint.status`/`mint.edge_type` and `edge.type` are JSON strings,
`Reducer.apply_mint/2`/`.apply_declared_edge/2` copy them unchanged into
`Store.mint_node/1`/`.insert_edge/1`, and both land on an `Ecto.Enum` column through the same
uncasted `Ecto.Changeset.change/2` — `Ecto.ChangeError`, not `KeyError`, and only once a committed
draft's `mints`/`edges` are non-empty, which is why nothing has fired yet.

**The comment that documented the serializer choice is the site that hid this defect, and it states
the atom-keyed/atom-valued distinction.** `lib/catapult/engine/event_store.ex`'s `init/1` carries:
"it round-trips the versioned event structs this component emits, including their atom-keyed fields,
which the library's own default `EventStore.JsonSerializer` does not attempt." That sentence is true
and, on its own, reads as covering atom-*valued* fields too, which it does not — atom-keyed is
exactly what `struct/2` restores, and atom-valued is exactly the gap the four decoders above close.
Left on its own, the next reader reaches this comment and draws the same conclusion the milestone's
worth of code that shipped around it did, so the comment states the distinction rather than leaving
true words to imply the wrong thing.

## #38

`keys: :atoms` also turns a map-valued field's own keys into atoms on the way back —
`DraftCommitted.scope_key` and `.fields` both go in string-keyed and come back atom-keyed — but
neither is atom- or `DateTime`-typed, so both sit outside the predicate above rather than inside a
gap it missed. They are safe today for a stated reason: every consumer re-encodes them straight to
jsonb without ever comparing a key in memory — `Store.Node.scope_key` is a `:map` column, and both
`mint_node/1`'s `conflict_target: [:project_id, :tier, :scope_key]` and `get_node_by_scope!/3`'s
`Repo.get_by` compare the dumped jsonb, where the Elixir key type has already stopped existing. The
day a map-valued field's keys are compared in memory rather than dumped whole, it joins this class
and this predicate widens to say so.

## #39

`ContainerLifecycle`/`FeatureLifecycle` are each safe by the argument their own moduledocs give: the
legal values are compile-time literals *in that module*, so they are in the atom table before any
decode runs. An event module's `@type` spec is not that — typespec atoms never reach the runtime
atom table — and loading only `Catapult.Engine.Events.ReviewWritten` and decoding confirms it:
`"ai"` resolves, because it is also the struct's default value and so a real literal, while
`"human"`, named only in the `@type`, raises `ArgumentError`. For `ActiveBundleFlipped` and
`FindingAdjudicated`, measured the same way, every legal value is missing outright until something
else happens to have already loaded their `Store.*` schema, whose `Ecto.Enum, values: [...]` list is
the actual literal. For `DraftCommitted`, measured with only its own module loaded, three of its six
legal values (`:absent`, `:approved`, `:reference`) resolved anyway, from atoms other already-loaded
modules happened to carry, while the other three (`:fanout`, `:dependency`, `:policy_application`)
still raised `ArgumentError` — and that partial result is the sharper evidence, not a softer one: a
decode that fails every time is a loud bug any smoke test catches, while one that succeeds on some
values and crashes on others depending on incidental load order is exactly the shape that passes
every offline check and only fires in production on the first unlucky value. The failure mode either
way is worse than the `Projector` crash above: decode runs before the reducer ever touches `Store`,
so a poison value here raises inside `JsonDecoder.decode/1` itself — before `Projector`'s handler,
and its `error/3`, are ever reached. `Catapult.Engine.Events .WireDecoding` (new,
`lib/catapult/engine/events/wire_decoding.ex`) is what recovers the same safety property
`ContainerLifecycle`'s idiom rests on, without keeping a second copy of any value set and, as the
entry below states, without calling `String.to_existing_atom/1` on the wire value at all: each
repaired field's legal atoms come from `Ecto.Enum.values/2` read against that field's own `Store`
schema and column at decode time (`Ecto.Enum.values(Store.Review, :kind)`, and the same call shape
for the other three), never from a list `WireDecoding` writes out itself. That call forces the same
`Store.*` module load that puts the real literals in the atom table — the exact property
`ContainerLifecycle`'s argument rests on — and it leaves no duplicate list for `Store`'s own enum to
drift out of step with: the day a value is added to `Store.Review.kind`'s `Ecto.Enum, values:
[...]`, `WireDecoding` sees it on the very next call, with nothing to edit and nothing that can fall
out of sync. A single `defimpl Commanded.Serialization.JsonDecoder, for: [ReviewWritten,
ActiveBundleFlipped, FindingAdjudicated, DraftCommitted]` block in the same file gives each struct
its own `decode/1` clause built on this lookup, rather than four `defimpl` blocks scattered across
the four event files each repeating the same three-line shape. This is a deliberate departure from
where `ContainerLifecycle`/`FeatureLifecycle` keep theirs (in the struct's own file) — each of those
is the only consumer of its own repair, and this one repair is six fields across five `Store`
schemas, not four call sites: `ReviewWritten.kind` → `Store.Review`, `ActiveBundleFlipped.axis` →
`Store.ActiveBundleVersion`, `FindingAdjudicated.disposition` → `Store.ContainerFinding`,
`DraftCommitted.mints[].status` → `Store.Node`, and `DraftCommitted.mints[].edge_type` alongside
`.edges[].type` — both → `Store.Edge`, because `Reducer.apply_mint/2` writes both `status:` and
`type:` from a single mint and `.apply_declared_edge/2` writes `type:` again from a declared edge,
so `Store.Edge` is read twice. Six is the count a shared file is sized against, and reading the
column's own set rather than the event's `@type` is strictly stronger, not merely equivalent:
`Store.Edge.type` declares five values (`:fanout`, `:reference`, `:dependency`,
`:policy_application`, `:synthesis`) where `DraftCommitted`'s own `@type` names four, so sourcing
from `Ecto.Enum.values/2` lets the decoder accept a value the column already considers legal even
where the event's own typespec has not caught up with it.

## #40

That is deliberate, not a default left unchosen: this entry has already established that raising
inside `decode/1` is the worse placement, landing before `Projector`'s handler and its `error/3`
exist to see it, and an unrecognised value — a schema migrated ahead of this decoder, say — is
exactly the case that placement would be worst for.

## #41

A handler that skipped a bad event instead would leave this doc's own "rebuild-from-zero... must
equal incremental state, always" quietly false for whatever that event should have folded — worse
than the crash-loop, and there is no mechanism (no alert, no parked-event queue, no replay-from-here
tool) to make a skip visible rather than silent. The four decoders above remove the only known way
to reach a poison event today; a *different* future defect reaching the same `:stop` is a real gap,
and designing what a human does about a skipped event is its own ticket.

## #42

No case asserts that `WireDecoding`'s value sets agree with `Store`'s `Ecto.Enum` declarations,
because there are no separate sets to agree — the `Ecto.Enum.values/2` lookup above reads `Store`'s
own list directly, so there is nothing a test would be checking for drift.

## #43

Built in from Phase 3 on the `events/0` precedent above: the discipline costs nothing before a
cutover exists and is a broken replay to retrofit after one has landed. **A ninth projection, not a
port** — the intro paragraph names eight; this one exists because the other eight can't be replayed
correctly across a bundle flip without it, not because the ticket asked for it by name.

## #46

Neither is built in Phase 3 (snapshots stay Target, below), but the value is decided now rather than
left for whoever builds them — snapshots are disposable projections like any other (v5 §8's
cold-storage rider agrees), so a wrong cadence costs a resweep, not a migration, and there is no
reason to leave it unstated in the meantime. Revisit condition: measured per-project event volume
disagreeing with v4's assumption enough to matter — nothing has run long enough yet to measure it.

## #48

The split is not new in kind, only new in direction — every writer into this aggregate so far has
been this system's own command edge, not another system's process manager. It does not reopen "the
scheduler dispatches to no component by name," several bullets up: that invariant is scoped to the
chain-axis generation signal (`ready_scopes`) specifically — a queue's resolved `flow:` that turns
out to open ordinary ticket work still dispatches through the existing `OpenFlow` path, driven by
nothing but `ready_scopes`.

## #52

The risk a cache carries, named precisely: a cache table is written asynchronously by whatever
process reacts to a decline, while the *sweeper* that would dispatch a regeneration is timer-driven
and reads readiness from projections the same reducer updates independently
(`Catapult.Generation.Sweeper`) — nothing orders the two, so a sweep tick landing between "the gate
declined" and "the cache row landed" dispatches with a blank `feedback`, indistinguishable from a
genuine zero-comment case at render time. That is exactly the ambiguity that must be resolved before
dispatch, and a cache cannot resolve it — only removing the asynchronous write can.
`Catapult.Engine.Projections .CommentFeedback.since_last_resolution(project_id, node_id)` reads
`Commanded.EventStore.stream_forward/2` directly, the same call `RunFailures.count_since_commit/2`
makes, and is a synchronous read of the log itself, not a projection anything writes ahead of time —
so there is no ordering gap for a sweep tick to land in, whatever the reset boundary is.

Having the validated boundary ride on the event that used it makes the two windows the same window
by identity rather than by an argument that has to stay true across every gate count. Walked through
the two-gate case: `GateDeclined@T4` carries `since_sequence: T1` — read off the command that
produced it, not re-derived — so the render folds since T1 and sees T2, the comment that actually
justified the decline, regardless of `GateApproved@T3` sitting between them in the log.

**A passed gate's already-answered feedback is never re-litigated by an unrelated later
re-dispatch** (staleness, a `RunFailed` retry). Under a position-based boundary, a re-dispatch
happening after a `GateApproved` would still fold from whatever position that inference produced,
which can resurrect comments the gate that approved already read. Under the stamped boundary, the
most recent resolution being a `GateApproved` renders `feedback` empty outright — nothing is
outstanding once a gate has passed, independent of what triggered the re-dispatch.

**`since_sequence` is a log position, not a content claim, and does not reopen §7.16's "what a
passed gate pins"** — the same distinction the sign-off entry below already draws for why neither
gate event carries a `body_sha`. It says only "here is where `CommentFeedback` should start
folding," never anything about what the gate approved or whether downstream content still matches
it.

## #53

Each of the two excluded boundaries makes this fold and `DeclineGate`'s own validation window
different queries that can each pass while the other sees something different, which reopens the
same blank-vs-zero ambiguity one level in:

## #54

`Catapult.Engine.Aggregate`'s own moduledoc states the constraint: "`execute/2` and `apply/2` read
only their own arguments; every id, timestamp and sequence number a resulting event carries is
already present on the command" — checked by `Catapult.Engine.Policies.PurityFloor`. Calling
`Catapult.Engine.Projections.GateComments.last_resolution_sequence/2` from inside `execute/2` would
break both halves at once: it is a `Commanded.EventStore.stream_forward/2` read, not a read of
`execute/2`'s own state-and-command arguments, and `since_sequence` is exactly "a sequence number a
resulting event carries" that would arrive by being computed there rather than by already being on
the command. The split is this system's own standing purity rule, above — "no clocks, randomness, or
generated ids in aggregate/reducer/projection code; inject at the command edge" — applied to a third
kind of value that rule always implied: a **log position** is injected the same way a clock or an id
is, not derived inside the aggregate. `Catapult.Engine.Projections.GateComments
.last_resolution_sequence(project_id, gate)` is the log position of the most recent
`GateApproved`/`GateDeclined` naming `gate`, or `nil` if neither has happened yet (so
`since_sequence` on a gate's first-ever `GateDeclined` is `nil`, and `CommentFeedback` folds from
the start of the log, the same as its own "no resolution has happened yet" case above) — and its
caller is wherever `DeclineGate` is built.

## #55

**What this does not pin: §7.16's "what a passed gate pins" stays open.** Neither event carries a
`body_sha` or any other content-identity field — they record only enough for a ticket's projected
status to move, forward or to a named throwback target, for the comment-count check above to run,
and ( `GateDeclined` only) the log position that check ran against — `since_sequence`, above, a
position in the log, not a claim about content — so they are not a second attempt at the
staleness-of-a-passed-gate question `systems/delivery.md`'s ORC-32 entry and this section's own
§7.16 bullet leave to Phase 7. Which node(s) a given gate reviews — the general question behind
"does what this gate approved still match what's downstream of it" — is likewise open; Phase 4's own
shipped `feature.yaml` runs exactly one `generation` status ahead of its gates, so nothing here
needs the general answer to work today. **The node(s)-per-gate answer is structural since ORC-115,
and the join is Phase 7's to build:** `docs/dsl-syntax.md` §15.10's sub-array grammar gives "which
node(s) a gate reviews" a structural answer — the citing sub-array's own one non-review-shaped
agent-balled entry, at the gate's declared `depth:` (`docs/v5-design-decisions.md` §7.16) — but
neither event gains a field from that alone; until the join is built, this entry's own claim (no
`body_sha`, position not content) holds. **Named rather than left to be found by a fan-out: the
decline check is project-wide and the render is per-node, and those are not the same scope.** A
comment on one node is enough to pass `DeclineGate`'s project-wide count, and the regeneration it
triggers can cover several nodes; `CommentFeedback` still renders exactly what landed on each node's
own log, so a sibling the comment never named regenerates with blank `feedback` — correct per-node,
not blank-vs-real-zero ambiguous, but not "justified by a comment" either. That gap is the same
node(s)-per-gate mapping this entry defers, not a new one; it is named here so the deferral reads as
a stated gap rather than an implied guarantee. Role authorization (does this `actor_id` hold
`gate.role`) is left exactly where §7.16 already leaves grant evaluation — identity's, a Phase 7
component — recorded the same way `actor_id` rides unvalidated on `DraftApproved` today. **How a
decline reopens a node for regeneration is closed at ORC-229 (below), off this same event.**
`GateDeclined` moves the ticket's own projected status (`systems/delivery.md`, below) and,
independently, `Catapult.Delivery.DraftResolution` dispatches `DiscardDraft` against the node this
gate reviews; `Reducer.apply(%DraftDiscarded{}, _)` resets that node's projection to `status:
:absent` with `current_draft_id`/`body_sha` cleared, so `ReadyScopes.ready/3`'s own `node.status ==
:absent` filter is what makes it eligible for `ready_scopes` again. This entry only guarantees that
whenever ORC-9's executor does re-dispatch, `feedback` cannot render blank where a real comment
justified the decline: `since_sequence` on `GateDeclined` is read from
`GateComments.last_resolution_sequence/2` at the same command-construction boundary that populates
the decline (the harvesting entry above has the mechanism, and why a stale read there is safe in the
direction that matters), and `CommentFeedback` (above) reads that stamped number back rather than
re-deriving one from the log's shape — independent of what triggers the re-dispatch, how long the
sweeper takes to notice, or how many gates the workflow declares.

## #57

`ApproveGate`'s `execute/2` clause bound no aggregate state at all (`def execute(%__MODULE__{},
%ApproveGate{} = cmd)`) and emitted `GateApproved` unconditionally; `DeclineGate`'s only check was
the comment-count mark above, which guards a different fact (has anyone commented since the last
resolution) and has never guarded staleness of the resolution itself. Two role-holders racing to
resolve the same gate — both looking at the same pending action, both dispatching around the same
moment — landed both writes; the second was never told. `docs/ui-spec.md` §3.1 already promises
otherwise for both screens that dispatch these commands: `ticket`'s "optimistic- concurrency
feedback: a rejected transition names who moved it and where (§7.16)" and `board`'s "the controls
are the same two transitions the ticket screen offers, under the same compare-and- swap (§7.16), so
a stale card fails the same way and says who moved it" — sentences already committed against
behavior the aggregate does not have.

**A second axis `gate_resolutions` alone cannot cover: staleness against a regenerated body, not
staleness against a resolution.** `DraftCommitted`'s own `apply/2` clears the whole
`gate_resolutions` map (above) — correctly, since a fresh commit does reopen the gate for review —
but reopening the *compare* also reopens the *action*: a reviewer who has `document-review` open on
the body a decline just threw back can still click Approve after a regeneration commits a new body
underneath them, and finds no key at `cmd.gate` to reject against, because the key that would have
named their view was just cleared by the very commit they never saw. `gate_resolutions` answers "has
this gate already been resolved since it last reopened," which is the right question for two writers
racing on one resolution and the wrong one for a single writer acting on a view of the wrong
resolution.

**This does not reopen §7.16's "what a passed gate pins."** `body_sha` rides the *command*, compared
and discarded before the aggregate decides whether to emit; `GateApproved`/`GateDeclined` carry no
content-identity of their own, so the content-pinning question this entry leaves to Phase 7 (above)
stays open. A command-side compare token and an event-side content pin are different mechanisms
answering different questions, the same distinction `since_sequence` already draws on `DeclineGate`
— a position the check ran against, not a claim about content.

## #58

A gate's own precondition turns out simpler than a container's, and the shape is smaller for a
stated reason rather than copied short: a container queue can be *any* of several named values, so
`AdvanceContainerQueue` has to say which one it believes it is leaving; a gate has exactly one
meaningful precondition — has this resolution already happened — so nothing about the command needs
to say what state it expects to find, only which gate it is resolving, which both commands already
carry. **This compare alone needs no new field** — the reopening-window fix below is a second,
independent one, guarding a different question.

## #59

The ABA exposure this carries is the same one `AdvanceContainerQueue` already carries and no worse:
a gate resolved, reopened by a commit, and resolved again looks identical, at the compare, to a gate
resolved once — which is correct, since a second legitimate resolution *should* succeed. What stays
closed either way is the case this fix exists for: two writers racing on the *same* still-open
resolution.

## #62

`Catapult.Delivery.FeatureLifecycle.Projection`'s own moduledoc records the gap precisely: "a block
clears only via a subsequent `DraftCommitted` retry — never a human action." `docs/ui-spec.md`
§3.1's `my-queue` names **unblock** as one of exactly three actions the plane ever asks a human for,
and J4 (§4) is "`board` (blocked, grouped under origin) → `ticket` → return to origin, or pick an
earlier status from the prefix" — a real write, with nothing in `lib/catapult/engine/commands/` to
dispatch.

## #64

**Closing this loop makes regeneration reachable, and regeneration leaves stale content downstream
with no path back.** A fresh `DraftCommitted` against a node that was already `:approved` needs no
new mechanism — `Reducer.apply/2` already sets `status: :drafted` unconditionally (above
`Node.status`'s own three values), so `ReadyScopes.ready/3` correctly re-blocks every downstream
context walk until the new draft is itself approved. What has no mechanism is content *already*
committed downstream, against the superseded approval: nothing moves it back to `:absent`, so it
stays put, stale, permanently.

`Catapult.Engine.Projections.Staleness` computes exactly this fact — `stale?/2`, `target_newer?/2`
comparing `committed_sequence` against each resolved context target's — and has no production
caller: every `lib/**` reference to it outside its own module is a doc comment
(`context_resolver.ex:8`, `:25`; `store/draft.ex:8`), not a call. Until a node can reach
`:approved`, nothing drafts against one and the case cannot occur; the dispatcher above is what
makes it live.

How staleness is consumed is settled above — "consumed by flow walks and the plane's out-of-band
ticket filing" — and `docs/v5-design-decisions.md`'s "staleness hints, never cascades" rules out an
auto-reopening `ready/3`. What is missing is the connection: neither named consumer calls
`stale?/2`. ORC-231 carries wiring it.

## #69

**ORC-6's own diff stops short of the scheduler and sweeper**, despite both being named Initial
above. The ticket's own scope paragraph enumerates "the Commanded application, per-project
aggregates and the event log, the reducer generic over bundle semantics, and the universal
projections" and names none of the reactive-runtime pieces; `ready_scopes` and staleness land as
this ticket's `Catapult.Engine .Projections.ReadyScopes`/`.Staleness` — pure queries against current
projections, exactly the "state-driven" shape the scheduler standing decision above describes — so a
later ticket's scheduler process has something to call rather than something to build from scratch.
Filed here rather than silently: this is a deviation from this doc's own Initial line, argued for in
ORC-6's hand-back.

---
paths:
  - bundles/*/workflow.yaml
  - lib/catapult/dsl/workflow.ex
  - lib/catapult/dsl/type.ex
  - lib/catapult/dsl/status.ex
  - lib/catapult/dsl/gate.ex
  - lib/catapult/dsl/system_status.ex
  - lib/catapult/delivery/feature_lifecycle/**
  - lib/catapult/delivery/container_lifecycle.ex
  - test/catapult/dsl/**
---

# The workflow

A workflow bundle declares the human cycle: the kinds of work item a
project has (types), the sequence of positions each moves through,
where a human signs off (gates) and where the result is promoted to
(environments). It also holds the whole of the seam: a position names
the chain tiers that run at it and a type names the chain flows it
serves, while the chain names nothing here. `bundle.md` is the
contract for the file's place and the seam; this is the contract for
`workflow.yaml`. Examples cite `bundles/default-flow/workflow.yaml` by
type and gate name. Markers: **live** is read by the engine today;
**reserved** names the consumer that will read it.

## #1 The file

- **#2 `workflow.yaml` has seven top-level keys**: `name`, `version`
  (reserved: the registry), `kind: workflow`, `entry`, `types`,
  `gates`, and the reserved `environments` (#38). `entry:` names the
  root type, the one a project instance is (`project`). A key outside
  this set, at any level, is a load error.

## #3 Types

- **#4 A type is a kind of work item: a name, an optional `skeleton`,
  a `serves:` where a chain flow opens it, and a `statuses` array.**
  `skeleton: ticket` is a unit of generated work with a PR
  (`scaffold`, `delta`); `skeleton: container` is a milestone-shaped
  thing with queues that dispatch other types (`milestone`); no
  skeleton is a queue sequence (`project`, #30).
- **#5 An entry is one of three things.** `{status: <kind>}` is a
  position the work item rests at, with the optional `name`, `tiers`,
  `flow`, `blocks`, `fills` and `depth` the sections below give;
  `{review: <gate>}` cites a declared gate (#31); `{environment: <env>}` cites a
  declared environment and configures the `deploy` that follows it
  (#38).
- **#6 A sub-array groups one agent-balled step with what reviews
  it.** It is anonymous, holds exactly one agent-balled entry that is
  not review-shaped — a generation position, or a container's `setup`
  or `retro` — plus the critique and gate entries around it, is the
  default throwback target of every gate inside it (#34), bounds how
  far ahead of a parent a child ticket may run, and is the board's
  grouping. That one entry is the group's **anchor**, and its name is
  the group's namespace (#7). `delta`'s `architecture` group is the
  position, its critique and `engineering-review`; `milestone`'s
  `retro` group is the retro step between its two author gates.
- **#7 An entry's name is its `name:` if it has one, else its kind,
  and a position's identity is `<anchor>.<name>` inside a sub-array,
  bare at the top level.** Identity is derived, never declared: the
  anchor's own name is the group's namespace, so everything sharing
  that group — its critique, an intervening `checks`, a gate citation
  — is addressed as `<anchor>.<its own name>`, and an entry outside
  every sub-array is addressed bare, the top-level array being its own
  namespace. One level only, and nothing qualifies an anchor by what
  it sits after or before. Names are unique within their own
  namespace, the top-level array and each sub-array alike, and two
  entries colliding on a *default* name are as much a load error as
  two declaring the same string. An anchor's name sits in both: it is
  its own group's namespace, and it is what the top-level namespace
  checks that group against, so two groups cannot share an anchor name
  any more than two bare entries can. `delta` declares ten generation
  entries and five `critique` entries, and no critique needs a `name:`
  because each is already `<its own group>.critique`.
- **#8 A reference stays bare when it is unambiguous and qualifies
  when it is not; ambiguity is a load error, never a silent pick.**
  `throwback:`, `blocks:` and `fills:` resolve against every
  namespaced position the citing type's own array declares. A bare
  name found in exactly one namespace resolves there; a bare name
  recurring across several has no single answer and is refused at
  load rather than resolved to whichever occurrence comes first, and
  `<anchor>.<name>` is what an author writes instead. A reference
  resolving to none is a load error too. The runtime matches by the
  same resolution, never by bare kind.
- **#42 A declared gate's name is disjoint from every addressable
  status name in the loaded union, checked at load.** A bare string in
  a citation is read as a gate or as a position by membership in the
  declared gate set, which is safe only while the two vocabularies
  cannot collide. A bundle-authored `name:` breaks that by
  construction, since nothing stops `name: ux-review` on a status
  entry in a bundle that also declares a gate called `ux-review`, so
  the loader refuses the pair rather than letting the reading depend
  on which set is consulted first.
- **#9 `flow:` on an entry names the type dispatched into that
  queue**, resolving against this bundle's own types, never against a
  chain flow. Reaching such an entry opens an instance of the named
  type (`milestone`'s `prep`, `main` and `cleanup` each open `delta`
  tickets; `project`'s `build-out` opens a `milestone`).
- **#10 A kind is one of the engine's shapes, and shapes are all the
  engine knows about a position.** Generation-shaped: `generation`,
  agent-balled, an agent writes. Review-shaped: `critique`, an agent
  reads what was written; `reconcile`, an agent joins children's
  output. Plane and world states: `backlog` (author), `checks`
  (world, CI), `merge` (plane), `deploy` (world), `terminal`,
  `validating`, `blocked`, `stubbed`. Container queues: `setup`,
  `prep`, `main`, `retro`, `cleanup`. The names the default workflow
  gives its generation positions (`plan`, `features`, `experience`,
  `requirements`, `architecture`, `implementation`) are `name:`
  values on `generation` entries, not kinds.

## #11 The ticket skeleton

- **#12 A ticket type declares, in this relative order, at least one
  generation-shaped entry, then `checks`, `reconcile`, `merge` and
  `deploy`, then `terminal` last and once.** The order is what one PR
  per child ticket requires (v5 §7.5): children generate, CI runs
  against produced work, the children's PRs are joined and read in
  aggregate, the join merges into the parent, the result deploys.
  Enforcement against dispatch is reserved: delivery Phase 7.
- **#13 `merge` is preceded by `reconcile` in the same array,
  whichever skeleton the type has.** Nothing merges without first
  having been read against its own argument.
- **#14 `terminal` is the fixed end kind and carries no `flow:`.** A
  ticket closes there; a queue-shaped type has none (#30).

## #15 The container skeleton

- **#16 A container type declares `main`, and whichever of `setup`,
  `prep`, `retro` and `cleanup` it declares in that relative order,
  then `terminal`.** `main` is the work queue the sub-flows run in;
  the others are the population steps and the queues they fill, and
  a container may omit any it does not use.
- **#17 A status whose agent step emits tickets declares where they
  land with `fills:`.** `setup` fills `prep`; `retro` fills
  `cleanup` and `prep`. Every queue named must be an entry of the
  same type, which is the whole of "a population step needs the
  queue it fills". A named queue that sits earlier than the filling
  position is the next instance's: `retro`'s `prep` is the next
  milestone's.
- **#18 `blocks:` names entries this queue holds closed while it
  carries unresolved work.** `main blocks: [retro]` means `retro`
  cannot be entered while `main` has open tickets; the hold is
  checked when a transition into the blocked entry is attempted, and
  the target resolves by #8.
- **#19 `setup` and `retro` are agent-balled entries directly in the
  container's array, run once per pass through their position.**
  `setup` runs when the container becomes the active instance at the
  queue that dispatched it, not when it is minted, which is what lets
  a milestone be groomed before it opens. Either may carry `tiers:`
  like a generation position (#22), and the default declares none:
  the chain ships no tier for a container's own passes.

## #20 Positions and the chain

- **#21 A position is a generation-shaped entry, named, that names
  the chain tiers running at it.** A gate sits after a position and
  reviews whatever those tiers produced; a critique after a position
  is where their reviews run.
- **#22 `tiers:` on a generation position names the chain tiers that
  run there, and every tier of a served flow sits at exactly one
  position of the serving type.** A name that is not a tier of the
  paired chain, or that names a join target or a supplied tier, is a
  load error; so is a tier listed at two positions of one type, and so
  is a tier active in a served flow that no position lists (`bundle.md`
  #11). A join target runs with its minting tier and a supplied tier
  never runs, so neither is ever listed. The one exception to sitting
  at a single position is a `cascade_visit` tier, which may be listed
  at several because its cascade rests at each (`chain.md` #40):
  `delta` lists all five plan tiers at each of its five plan
  positions.
- **#40 A ticket type names the chain flows it serves, and every flow
  is served by exactly one type.** `serves:` is a predicate over flows
  or a list of flow names; a type naming a flow outright beats one
  matching it by predicate, and two outright claims on one flow, or a
  flow no type serves, are each a load error. The predicates are
  `has_delta` and `no_delta`, a flow carrying a schema delta being a
  change and a flow carrying none being a scaffold (`chain.md` #38),
  which is what the default binds on: neither shipped ticket type
  names a flow at all. Only a ticket type declares `serves:` (#30).
- **#23 The tiers of a served flow fit the type's positions in
  order.** For every structural read (a walk from the tier or its
  parent, `chain.md` #22), the node read has a generating tier at the
  same or an earlier position; a join target takes its minting tier's
  position; a fan-out's children bind within the child's own filtered
  sequence (#28). A read that would need a later position is a load
  error. This is what stops a workflow reordering its positions into
  an order the chain's own reads cannot satisfy.
- **#24 A generation position none of whose tiers are active in a
  flow is a load warning, and the position is skipped for that
  flow.** No position of the default pair is ever empty: `scaffold`
  declares no plan position at all, and every delta flow activates one
  of the five plan tiers each of `delta`'s plan positions lists.
- **#25 Every agent-balled position carries an engine-set waiting
  flag until an agent picks the work up.** It is not declared; it is
  what a ticket rests in between reaching a position and dispatch,
  what a throwback lands in, and what the board renders as the
  position's waiting substate.
- **#26 A critique-shaped position follows the generation position
  it reviews with no other generation-shaped position between.**
  `checks`, gates and environments may sit between; a review runs at
  the first critique after its tier's position (`chain.md` #14).
- **#27 A reconcile block runs at the first reconcile-shaped position
  after its children's positions** (`chain.md` #15); the position
  itself is the workflow's and gates may sit before and after it.
- **#28 A child ticket runs the declared sequence filtered to its
  depth, and a position's depth comes from the tiers it lists.** A
  tier's depth is the number of ticket-spawning fan-outs (`chain.md`
  #42) between the project root and it, and **a ticket occupies a
  position when its own depth is at most the deepest tier listed
  there.** It stands there to generate where it has a tier of its own
  at that depth, and to receive where it does not: what its children
  produce at that position merges into its branch, which is what gives
  a gate and a PR at every granularity above the deepest one rather
  than only at the bottom. Nothing declares a depth on a generation
  entry, because the tier list already says how deep the position goes
  and a second statement could only disagree with it.

  In the default pair the architecture position runs to depth 2 with
  work of its own at every level, while implementation runs to depth 2
  with work only at depth 2 — so a feature and a component both stand
  at implementation, holding the branch their subcomponents' code
  merges into, and both can be gated there. The product positions stop
  at depth 0, no fan-out above them spawning a ticket (#41). A
  `cascade_visit` tier has no scope parent to count from and takes the
  depths of the position it is listed at, its nodes being minted per
  visited scope (`chain.md` #40).
- **#41 A child ticket exists only where a fan-out spawns one, so a
  position no fan-out reaches is never a child's to skip.** The
  product positions are depth 0 and stay there: the fan-outs at those
  tiers mint pools nobody generates from (`chain.md` #42), so no
  ticket is opened below them and the question of a child standing at
  a product position does not arise. A child's sequence begins at the
  position carrying the tier its fan-out spawned, and its content
  merges into its parent's branch before the parent leaves its own
  reconcile (#13).

## #29 Queue-shaped types

- **#30 A type with no skeleton is a sequence of queues and nothing
  else.** Each entry carries `flow:`; there is no generation, no
  `terminal` and no `serves:`, since a queue-shaped type and a
  container are both opened by another type's queue rather than by a
  chain flow; the instance closes when its last queue resolves with
  nothing open behind it. `project` is the one such type in the
  default, and its queue list is the bundle's own content, not a
  platform sequence.

## #31 Gates

- **#32 A gate declares `role`, `escalation` and optionally
  `throwback`; everything positional is on the citation.** `role` is
  the human role that signs off, checked against the identity
  component's holders when that check is enabled (reserved:
  identity, v5 §7.16); `escalation` is who is told when it stalls
  (reserved: delivery).
- **#33 `depth:` on a gate citation is where the gate applies, and
  defaults to every depth.** An integer is a maximum level: `0` is the
  top level only, `1` adds components, `2` adds subcomponents, and a
  depth deeper than the chain fans out applies at the levels that
  exist with a load warning (`bundle.md` #12). A pair `[first, rest]`
  gives one value for the project's first traversal of the position
  and another for every later one. A citation narrows where a *review*
  applies; where the work is, is #28's. Doing less review
  is the explicit choice: `delta` writes `depth: 1` on
  `engineering-review` and `scaffold` leaves it at the default.
- **#34 A gate inside a sub-array throws back to the group's
  generation position unless it declares otherwise; a declared
  `throwback:` must resolve (#8) to an earlier entry.** The landing
  point is derived at throwback time from the citing array, never
  stored, so a workflow cutover re-resolves it.
- **#35 A gate outside a sub-array may have no throwback at all.** A
  decline then lands on a human-chosen earlier position. A gate
  between a staging and a prod deploy is the case: most tickets there
  would go back to no predictable position.
- **#36 A gate's review set is whatever the chain produced at the
  position it follows, at the depths it applies.** Nothing on the
  gate names a tier.

## #37 Environments

- **#38 An environment is a deployment target an `environment:`
  entry cites before the `deploy` it configures** (reserved: delivery
  Phase 7). `dev`, `staging` and `prod` in the default.
- **#39 An environment declares `promote_from` and `lifetime`.**
  `promote_from` names the environment a deploy here is promoted
  from; `lifetime: persistent` is the shipped value and `per_ticket`
  is the PR-environment case, its semantics fixed when delivery
  builds it.

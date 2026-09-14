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
(environments). The chain names the positions its tiers run at; the
workflow declares them and everything around them. `bundle.md` is the
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
  and a `statuses` array.** `skeleton: ticket` is a unit of generated
  work with a PR (`feature`, `seed`); `skeleton: container` is a
  milestone-shaped thing with queues that dispatch other types
  (`milestone`); no skeleton is a queue sequence (`project`, #30).
- **#5 An entry is one of three things.** `{status: <kind>}` is a
  position the work item rests at, with the optional `name`, `flow`,
  `blocks`, `fills` and `depth` the sections below give; `{review:
  <gate>}` cites a declared gate (#31); `{environment: <env>}` cites a
  declared environment and configures the `deploy` that follows it
  (#38).
- **#6 A sub-array groups a generation position with what reviews
  it.** It is anonymous, holds exactly one generation-shaped entry
  plus the critique and gate entries that follow it, is the default
  throwback target of every gate inside it (#34), bounds how far
  ahead of a parent a child ticket may run, and is the board's
  grouping. `feature`'s `architecture` group is the position, its
  critique and `engineering-review`.
- **#7 An entry's name is its `name:` if it has one, else its kind,
  and names are a namespace per type.** A kind that recurs in one
  array is legal; a name that recurs is a load error. `feature`
  declares six generation-shaped entries under six names and five
  bare `critique` entries.
- **#8 A reference to an entry, from `throwback:`, `blocks:` or
  `fills:`, resolves by name within the citing type**, reaching a
  grouped entry through its own name the same way it reaches a
  top-level one. A reference that resolves to none, or to a bare kind
  that recurs, is a load error. The runtime matches by the same
  resolution, never by bare kind.
- **#9 `flow:` on an entry names the type dispatched into that
  queue**, resolving against this bundle's own types, never against a
  chain flow. Reaching such an entry opens an instance of the named
  type (`milestone`'s `prep`, `main` and `cleanup` each open
  `feature` tickets; `project`'s `build-out` opens a `milestone`).
- **#10 A kind is one of the engine's shapes, and shapes are all the
  engine knows about a position.** Generation-shaped: `generation`,
  agent-balled, an agent writes. Review-shaped: `critique`, an agent
  reads what was written; `reconcile`, an agent joins children's
  output. Plane and world states: `backlog` (author), `checks`
  (world, CI), `merge` (plane), `deploy` (world), `terminal`,
  `validating`, `blocked`, `stubbed`. Container queues: `setup`,
  `prep`, `main`, `retro`, `cleanup`. The names the default pair
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
  a milestone be groomed before it opens; its tiers are the chain's,
  naming `setup` and `retro` as their `phase:` like any other.

## #20 Positions and the chain

- **#21 A position is a generation-shaped entry, named, that the
  chain's tiers bind to.** A gate sits after a position and reviews
  whatever the chain produced there; a critique after a position is
  where that position's tiers' reviews run.
- **#22 Every position a chain tier names exists in the type its flow
  dispatches into, checked at load.** The pairing is the flow's
  `ticket: {type}` (`chain.md` #38); a `phase:` that resolves to no
  entry of that type is a load error, never a fallback to a shape.
- **#23 The flow's tiers fit the type's positions in order.** For
  every structural read (a walk from the tier or its parent,
  `chain.md` #22), the node read has a generating tier at the same or
  an earlier position; a join target takes its minting tier's
  position; a fan-out's children bind within the child's own filtered
  sequence (#28). A read that would need a later position is a load
  error.
- **#24 A generation-shaped position no tier of a flow names is a
  load warning, and the position is skipped for that flow.** The
  five plan flows share `feature` and only they name `plan`; the seed
  flow leaves it empty.
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
  depth**, and depth on a citation is a maximum: `0` is the top level
  only, `1` adds components, `2` adds subcomponents, the default is
  every depth, and a depth deeper than the chain fans out applies at
  the levels that exist with a load warning (`bundle.md` #12).

## #29 Queue-shaped types

- **#30 A type with no skeleton is a sequence of queues and nothing
  else.** Each entry carries `flow:`; there is no generation, no
  `terminal`, and the instance closes when its last queue resolves
  with nothing open behind it. `project` is the one such type in the
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
  defaults to every depth.** An integer is a maximum level; a pair
  `[first, rest]` gives one value for the project's first traversal
  of the position and another for every later one. Doing less review
  is the explicit choice: `feature` writes `depth: 1` on
  `engineering-review` and `seed` leaves it at the default.
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

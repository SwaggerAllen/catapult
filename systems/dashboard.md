---
paths:
  - lib/catapult_web/**
  - assets/**
  - test/catapult_web/**
---

# dashboard

The LiveView UI. **Screens, functionality and journeys:
`docs/ui-spec.md`** — that document is the inventory; this one is the
system and its file map.

**The working surface, not only a debugging one** (v5 §7.17, §7.4):
owning the tracker is what makes it one. It owns the work loop (`my-queue`, `board`, `ticket`,
`ticket-graph`), design-gate review at sentence granularity, and —
unchanged and still the hard part — event-log inspection,
replay-to-sequence, ready_scopes explain-why ("what is blocking this
scope" as a first-class query), staleness provenance, dispatch
history, agent-run transcripts.

**The name is now wrong** and is kept only to avoid churn mid-design;
renaming the system is a mechanical pass whenever it is worth doing.

Its screens are designed and delivered through **orchestration's
native screen machinery** — `screens/*.md` docs, stateless function
components, `.story.exs` variations, `screen:` labels — not through
Catapult's product tier (which doesn't apply to Catapult itself,
conventions §13).

## Standing decisions

- **This is the work loop's surface** (v5 §7.17). The temptation the
  old debugging-surface-only line guarded against is real and did not
  go away with it, so it has a successor with teeth, in
  `docs/ui-spec.md` §2: reads are projections and writes
  are commands; **no screen introduces protocol vocabulary**; and
  every screen answers a named question or performs a
  protocol-defined action. The second is the one that will get cited
  — the temptation is never "build a tracker", it is "add one field
  here", and a field here is vocabulary.
- **The two non-work-loop prongs were always in-bounds and are
  unchanged:** **admin/settings** (v5 §7.10's bindings UI —
  query-and-pick project wiring, tracker provisioning, plane-state
  tunables) and the **configuration surface** (registry consumption:
  policy tunings, component options — *graph* state, edited by
  composed PR: forms generated from declarations, save files a change
  through the normal entry machinery, review stays in the PR). The
  composer never bypasses a gate.
- **"Why is nothing happening" must be answerable in minutes** — the
  design bar for every view, and explain-why is what answers it, not
  a number. **But numbers are in-bounds where they are the answer**
  (`docs/ui-spec.md` §2, §3.3): instance health is a numeric
  determination, and throughput and cycle time are how the platform's
  value is demonstrated rather than asserted. The earlier phrasing —
  "explain-why over dashboards-of-numbers" — overshot; the target was
  decoration, not measurement. The test that replaces it: a number
  you cannot drill through to the tickets behind it is decoration.
- **LiveView + daisyUI, stateless presentational components** —
  orchestration's assumed stack, deliberately, so its design agent
  and storybook export machinery work on our own UI.
- Reads projections only; every mutation goes through engine
  commands. The dashboard can never be a second write path.
- **Every screen's navigation and every query it issues carries a
  project id, with no cross-project or "all projects" view anywhere in
  this system** (ORC-87, ORC-35 design pass). A node id is a
  per-project slug and a project's event stream is per-project too
  (`systems/engine.md`), so a route or a query missing the project
  resolves nothing rather than resolving the wrong project's data.
  `event-log` and `explain-why` (`screens/event-log.md`,
  `screens/explain-why.md`) are this decision's first two screens; it
  binds every screen after them the same way, which is why it is
  recorded here rather than in either screen doc alone.

  **Narrowed at ORC-75 for exactly one screen, on the rule's own
  stated reason rather than against it.** `my-queue` is cross-project
  — v5 §7.10 says so directly, about this exact screen: "at one human
  this degenerates correctly: 'My Issues' is exactly the
  **cross-project** list of tickets needing the author — the inbox
  property, with no filtering." That is not a route or a query missing
  a project id, which is the failure this bullet's own reasoning
  names; it is `my-queue` issuing one fully project-scoped query per
  project the actor has standing in and merging the rows for display.
  No route resolves without a project id and no query risks resolving
  the wrong project's data — the two ways this rule's reasoning says
  the mistake actually happens — so `my-queue` satisfies the reason
  the rule exists rather than being an exception carved out of it. A
  project switcher gating `my-queue` would trade away the property
  that makes it the daily entry point rather than a second `board`.
  `board`, `event-log`, `explain-why`, `ticket` and `document-review`
  are each explicitly single-project, unaffected by this narrowing;
  `screens/my-queue.md` carries the argument in full.
- **The gate action `ticket` and `document-review` render is real, not
  anticipatory** (ORC-75 design pass, correcting an earlier draft of
  this bullet written before ORC-34 landed the mechanism it was
  waiting on). `Catapult.Engine.Commands.ApproveGate{project_id,
  flow_id, gate, actor_id}` → `GateApproved`, and `Commands
  .DeclineGate{project_id, flow_id, gate, throwback_to, since_sequence,
  actor_id}` → `GateDeclined` are coded on `main`
  (`lib/catapult/engine/commands/{approve,decline}_gate.ex`,
  `systems/engine.md`'s ORC-34 entry), and `Catapult.Delivery
  .FeatureLifecycle` gained the two `interested?`/`handle` clauses that
  actually move a ticket's projected status off them: `GateApproved`
  advances to the next entry in the type's own `statuses:` array past
  the gate, `GateDeclined` moves straight to `throwback_to`
  (`systems/delivery.md`'s ORC-34 entry). Both screens' approve/throw-
  back controls target these directly, so dev's pass wires a working
  control rather than a disabled one naming a gap — the earlier draft
  of this bullet is wrong on that point and is corrected rather than
  struck through, since the command it was hedging against not
  existing now does. **What stays open is narrower than the earlier
  draft said**: §7.16's "what a passed gate pins" and which node(s) a
  gate spanning more than one status validates against are both still
  unanswered — `systems/engine.md`'s own ORC-34 entry leaves them so on
  purpose — but neither blocks v1, since Phase 4's own `feature.yaml`
  runs exactly one `generation` status ahead of each gate. `gate`/
  `throwback_to` legality is validated at the command edge: whatever
  constructs the command (dev's LiveView) checks that `throwback_to` is
  earlier in the citing type's own effective sequence — the same
  "earlier in the array" test `Catapult.Dsl.Workflow
  .gate_throwback_problems/2` already runs at load time for a
  *declared* target, generalized to every runtime pick now that ORC-115
  retires the declared list as a legality bound (`docs/dsl-syntax.md`
  §15.10, second design review; a third review narrowed the field
  itself to a single-target override on the derived default rather
  than retiring it outright, `docs/dsl-syntax.md` §15.4). `document-
  review`'s throwback picker offers the same full earlier-prefix
  Blocked-return's picker already gives (`docs/ui-spec.md` J4), one
  click landing on the gate's own declared `throwback:` when the gate
  names one, or its citing sub-array's own derived default otherwise —
  never bounded, either way, to a gate's own declared exits as an
  allow-list. **A decline
  naming no comment is rejected by `DeclineGate`'s
  own aggregate state, never by either screen** — the screen surfaces
  that rejection synchronously, the same compare-and-swap conflict
  rendering `ticket`'s stale-transition case already specs, but does
  not perform the check itself (`docs/ui-spec.md` §2 rule 1;
  `screens/document-review.md` and `screens/ticket.md` both name this
  precisely).

  **Corrected again at ORC-114, which built the compare-and-swap this
  bullet had been describing as already real.** It wasn't:
  `ApproveGate`'s `execute/2` bound no aggregate state and emitted
  unconditionally, and `DeclineGate`'s only check was the comment mark
  above — neither guarded a stale transition, the exact property both
  screens' own text asserted (`systems/engine.md`'s own entry, found
  reading the code against §7.16, not filed as a finding by either
  screen). `ApproveGate`/`DeclineGate` now carry `node_id` and
  `body_sha` beside the fields above, and the aggregate gains
  `gate_resolutions: %{gate => :approved | :declined}` (absent key
  means open): a second writer racing the first on one still-open
  resolution is rejected with `{:engine_gate_already_resolved, gate:,
  disposition:}`, naming the value the loser's command conflicted
  with; a resolution against a body the aggregate has already moved
  past — regenerated after the actor's view was rendered — is rejected
  separately with `{:engine_stale_gate_resolution, node_id:, current:,
  got:}`. Both run before either event is ever produced.

  **What the rejection names is the value, not the actor** — the same
  level of detail `AdvanceContainerQueue`'s own conflict already gives
  (`systems/engine.md`), and neither `gate_resolutions` nor the node's
  `body_sha` carries who wrote it. `docs/ui-spec.md` §3.1's "names who
  moved it and where" is satisfied in two parts rather than one: the
  synchronous rejection is the "where" (which disposition already
  landed, or that the body moved), rendered at the point of action per
  §7.16; "who" is a follow-up read of the project's event stream for
  the gate's most recent `GateApproved`/`GateDeclined` (both carry
  `actor_id`), the identical "read the log for a display fact" pattern
  `GateComments`/`CommentFeedback` already establish rather than a new
  mechanism. `screens/ticket.md` carries this precisely; `board` reuses
  it rather than redefining it.

  **`board`'s cards do not dispatch `ApproveGate`/`DeclineGate` in v1,
  reversing this doc's own earlier reading of `docs/ui-spec.md`'s "cards
  carry pass-forward and pass-back directly."** Both commands now
  require the `body_sha` of the body the actor is resolving against,
  and a card shows a ticket, not a body — filling it from the
  projection's current value would make the compare-and-swap pass
  unconditionally while the card *looked* guarded, which is worse than
  not offering the control at all. Every gate Phase 4's `feature.yaml`
  declares reviews a prose artifact, so a card's pass-forward/pass-back
  links into `document-review` instead, the identical move `ticket`'s
  own gate action already makes for the same reason
  (`screens/ticket.md`, `screens/board.md`). **`ORC-116` is where this
  is expected to resolve for real** — once a gate's node set is
  derivable, staleness is computable from any surface and a card needs
  no body view of its own; until then this is a v1 scope choice, not a
  defect.

  **`ResumeFlow{project_id, flow_id, to, actor_id}` → `FlowResumed`
  gives `ticket`'s blocked return control a real write path** (ORC-114):
  `Catapult.Delivery.FeatureLifecycle.Projection`'s own `resting/2` had
  no way off `{:kind, :blocked}` except a fresh commit — no command
  existed for a human to choose a return position, which is the gap
  `my-queue`'s `unblock` kind and `ticket`'s own "Blocked" section both
  assumed away. `to` is validated at the command edge against the
  effective-sequence prefix up to and including `blocked_origin`, never
  forward (`docs/ui-spec.md` §6) — the same bundle/projection-content
  split every other command edge on this aggregate already draws.
  `screens/ticket.md` carries the detail.

  **A ticket's title/argument, and the read both `board` and `my-queue`
  place a ticket from, both exist now.** `argument` is a reserved
  `fields:` name on a flow's entry tier (`docs/dsl-syntax.md` §3,
  `systems/platform_content.md`), folded into `Catapult.Delivery.Store
  .tickets_for_project/1` — one project-scoped read returning `id`,
  `ticket_ref`, `flow_name`, `entry_node_id`, `status_kind`,
  `status_gate`, `blocked_origin_kind`, `blocked_origin_gate` and
  `argument` per open flow, which is what `board`'s lanes and
  `my-queue`'s three action kinds both place a ticket from
  (`systems/delivery.md`'s ORC-114 entry). `my-queue` calls it once per
  project the actor has standing in and merges the rows, the identical
  fan-out its own "Cross-project, deliberately" section already
  describes for the query that predated this one.

  **`document-review`'s stale marking does not ship in v1, and this is
  a correction rather than a narrowing of something that worked.** The
  mechanism ORC-75's own earlier draft described — deriving staleness
  from whether a node's current `body_sha` matches what the gate's
  approval event recorded — cannot be built: `GateApproved`/
  `GateDeclined` carry no content identity, deliberately, and §7.16's
  "what a passed gate pins" was, at the time this entry was written,
  left open for Phase 7/ORC-115 by name in `systems/engine.md`'s own
  entry. `Catapult.Delivery.Store
  .get_previous_draft_body/2` (one previous body, not a log) answers
  the per-sentence **diff** `document-review` renders — a narrower
  question ("what changed since the last pass") than "has what this
  gate approved changed," which needs a content pin this ticket does
  not have. `screens/document-review.md` drops stale marking from v1
  rather than shipping a stopgap `body_sha` on the gate events that
  ORC-115 would be the first thing to delete.

  **ORC-115 has since answered §7.16's item at the design level** (
  `docs/dsl-syntax.md` §15.10; `docs/v5-design-decisions.md` §7.16):
  what a gate pins is its citing sub-array's one non-critique
  agent-balled entry, at the gate's declared `depth:`, derived rather
  than stamped on the event. This is still not a `body_sha` and still
  not built — the log join `systems/delivery.md`'s Phase 7 needs is
  unbuilt, and this v1 scoping decision (drop stale marking rather than
  ship a stopgap field) is unaffected. It is recorded here so a later
  pass reads "why isn't this built yet" rather than "is this still
  open" — the open question moved from *what* a gate pins to *building*
  the join against the answer.
- **No assignee or role-holder projection exists, and Phase 4's screens
  render the degenerate case rather than modeling an interim one**
  (ORC-114, design pass). `my-queue`'s two tabs, its `sign off`
  visibility rule, and `ticket`'s "shown only when the viewer's role
  holds the gate" all assume a human-to-role mapping; `Catapult.Engine
  .Commands.ApproveGate`'s own moduledoc places role authorization
  exactly where §7.16 already leaves grant evaluation — identity's, a
  Phase 7 component that does not exist yet. Phase 4 has exactly one
  author, so the correct rendering is the one identity will later
  narrow rather than one this system invents ahead of it: every gate
  action is shown to every viewer, `my-queue`'s **Assigned** and **My
  roles** tabs read the identical underlying set (there is no
  assignee column to tell them apart), and `board`'s `assignee` filter
  has no source to filter against — deferred beside `milestone` and
  `mutex label` for the identical reason. Each screen's own doc records
  this against its own controls; this bullet is the one place a reader
  sees why they all say it the same way.
- **A lane/rail key is a position's own namespaced identity
  (`docs/dsl-syntax.md` §15.12), rendered through `CatapultWeb.Live
  .Positions.key/2` rather than paired by this system** (ORC-116,
  superseding this bullet's own prior scan-and-pair scheme after
  ORC-155 landed the namespacing rule this system had been assembling
  by hand). §15.10's own anchor predicate — a sub-array's one
  non-review-shaped agent-balled entry (`generation`, `design`,
  `architecture`, `implementation`, `retro` or `setup`) — still picks
  the entry a group keys off; what §15.12 changes is what supplies the
  *other half* of the key. A `status:` entry now carries a
  bundle-authored `name:` (defaulting to its kind), and an anchor's own
  name *is* the sub-array's namespace: every other entry sharing that
  sub-array addresses as `<anchor-name>.<its-own-name>`, a top-level
  entry addresses bare, and the loader refuses a colliding pair before
  a bundle ever ships (§15.12's own uniqueness check). `Positions
  .key/2` already encodes exactly this — `"kind:" <> anchor <> "." <>
  name` when given an anchor, the identical bare `"kind:" <> name` it
  has always produced otherwise — so a lane or rail key is that string,
  not a runtime identity this system derives.

  **This retires the whole of the prior scheme, not just its collision
  case.** There is no more scanning backward to the nearest anchor, no
  `Catapult.Generation.NodeId.resolve/1` chain-node id and no
  `Catapult.Delivery.ContainerLifecycle.Ids.work_item_id/3` work-item
  id standing in as the anchor's own identity — both were needed only
  because the prior scheme had no bundle-authored name to key on and
  had to borrow one from a runtime concept instead. §15.12's namespace
  is a fact about the loaded declaration alone, so the key for any
  position is available the moment the workflow loads, with no read
  against `engine_nodes` or a container's own queue identity. The
  "Not yet covered" gap this bullet used to carry — two `critique` or
  `reconcile` entries in one sub-array colliding on the same
  `(anchor, kind)` pair — closes the same way: §15.12 requires distinct
  `name:`s the moment two entries share a sub-array, so the collision
  is a load error before this system ever sees the bundle, never a
  rendering gap for it to solve.

  **The anchor for a *resting* ticket — the gap §15.12 left open by its
  own admission — is `Positions.resting_key/2`** (ORC-116).
  `Catapult.Delivery.FeatureLifecycle.Projection`'s `passed`/
  `pinned_to`/`blocked_from` all still key on the bare `position()`
  tuple, with no namespace attached, so `resting_key/2` resolves this
  as a lookup against the loaded declaration, not a runtime identity:
  walk the citing type's own effective sequence for the sub-array, if
  any, containing the resting position, and key off that sub-array's
  own anchor name; a position outside every sub-array keys bare. That
  lookup is exactly what `Positions.key/2`'s `anchor` argument is
  already shaped to take — this system supplies the argument, not a
  new encoding. It is first-match, best-effort where the bare kind
  recurs: disambiguating *which* occurrence a resting ticket is
  actually at needs runtime position-tracking the projection does not
  carry, which stays open the same way `Sequence.name/3` already
  admits it for the declared-lane case.

  Recurrence itself is unchanged from what this bullet already found:
  `docs/dsl-syntax.md` §13 still lets a generation-shaped entry,
  `checks`, `merge`, `reconcile` and `pending` all recur, and `merge`,
  `deploy` and `terminal` need no carve-out of their own — each is an
  ordinary bare top-level name whenever it sits outside a sub-array
  (true of every recurrence in the current `bundles/default-flow`
  types), and the namespace rule above already covers a bare top-level
  name without naming any of the three specifically.
- **A non-root instance's own lane sequence ends at its last reachable
  position — never at a `merge` or `deploy` of its own** (ORC-116,
  `docs/dsl-syntax.md` §15.11). `merge` is depth-0 by rule and a
  non-root ticket merges only through its parent's `reconcile`, so
  `board` and `ticket` render no `merge`, `deploy` or `terminal` lane
  for one; its own effective sequence simply stops short of that
  machinery, the same way `Sequence`'s own `@reachable_boundary`
  already stops every instance's sequence short of `merge` today. The
  card leaves the board the moment the parent's `reconcile` resolves
  it, direct to `terminal` — v5 §7.6's `Merged → Done`, settled
  independent of tree position — with no lane in between to render it
  in. What a non-root instance's own `deploy` would mean stays exactly
  as open as `docs/dsl-syntax.md` §15.11 leaves it; this bullet only
  says the board renders nothing for that gap, not what fills it.
- **`board`'s lane set is derived per tree shape, not per declared
  type** (ORC-116, reversing ORC-129's own "wait for fan-out-as-
  separate-flows" — `docs/dsl-syntax.md` §15.11 is that). A leaf and
  an instance with children read different effective sequences off the
  identical array (§15.11's own "a leaf instance has nothing to join"),
  so a lane set keyed on `type_name` alone shows a `reconcile` column
  no leaf card ever reaches. `board` resolves this the way `ticket`
  already resolves fan-out depth for one ticket (`screens/ticket.md`'s
  "depth is shown, not explained"): a type's lane set is the union of
  every tree-shape's own effective sequence, and a lane never shows a
  card whose own resolved sequence excludes it — `screens/board.md`'s
  existing "a lane never shows a child it does not itself hold" rule,
  extended from membership to shape.
- **Cross-type fan-out roll-up is a card-level count, not a per-lane
  one** (ORC-116). `docs/dsl-syntax.md` §15.11 gives `component`/
  `subcomponent` their own declared type, sharing no array with
  `feature` ("two type declarations, not one spanning the whole
  tree"), so a component's own position has no corresponding lane on a
  feature's board at all — `docs/ui-spec.md` §3.1's "each lane rolls up
  only the children it holds" assumed children read off the parent's
  own lane set, which no longer holds across this boundary. Same-type
  nesting — a subcomponent inside a component — keeps the per-lane
  roll-up `screens/board.md` already describes, since both instances
  read the identical array; a feature's own component children instead
  roll up as one aggregate count on the card, wherever the feature's
  own lane happens to be, rather than projected onto a lane that
  doesn't exist for them.
- **Child roll-up has no data source in Phase 4, and of the two bullets
  above, only one fully closes on the type alone — the other's own
  per-card rule needs the same missing data** (ORC-129, naming what "wait
  for fan-out-as-separate-flows" above was shorthand for).
  `Catapult.Engine.Store.Flow` carries no parent-flow reference, and the
  `parent_node_id` that `Catapult.Engine.Store.Node` does carry is
  doc-graph scope structure — the chain-axis tiers an architecture
  ticket's own generation walks — not a ticket-delivery relationship, so
  there is no second flow instance and no query "these flows are this
  ticket's children" to run.

  §15.11's declared fan-out depth is what lets the roll-up-shape bullet
  (cross-type count vs. per-lane) resolve entirely from the type, and
  what lets the bullet above it resolve a type's own lane set — the union
  of every tree-shape's effective sequence — the same way. That bullet's
  other rule does not clear the same bar: "a lane never shows a card
  whose own resolved sequence excludes it" means knowing whether **this
  instance** has children, and `docs/dsl-syntax.md` says twice that no
  declaration states that — "whether a given instance runs [`reconcile`]
  is a fact about that instance's own children, not a declared ceiling"
  (§15.11; restated at §13). That fact takes exactly the relationship
  this bullet says is missing: `board` cannot distinguish a leaf card
  from one with children, both reading the identical type-and-depth
  sequence, so a leaf card can sit in a `reconcile` lane it never
  reaches — the case that rule exists to prevent. Enumerating which flows
  are a given ticket's actual children is the same fact under a
  different name, not a second gap.

  `board` and `ticket` both render an honest `children: []` rather than a
  nested board or a narrowed count (`screens/board.md`,
  `screens/ticket.md`); `board`'s per-card lane exclusion goes unenforced
  for the identical reason. Not gating: the source is
  `docs/build-plan.md`'s Phase 7 two-grain machinery — spawn and child
  lifecycle, minting a child as its own addressable flow correlated to
  the parent that spawned it — and nothing ahead of Phase 7 depends on it
  landing first.
- **A screen or LiveView branches on `Catapult.Dsl.SystemStatus`'s own
  predicates, never on a status-name literal** (ORC-116, generalizing
  the correction ORC-151's own dev pass already made to `Catapult
  .Delivery.ContainerLifecycle.inline_dispatch_point?/1` when it
  retired that module's `status != "merge"` check). `Positions`'s
  `{:kind, atom}` shape puts the raw status atom within reach of every
  LiveView that touches it, and four call sites already match on one
  directly (below). Blocked is a real orthogonal flavor rather than an
  array position, so branching on it is correct; the form is what
  ORC-151 already named as the thing to stop doing. `SystemStatus`
  already exports `ball/1`, `agent_balled?/1`, `generation_shaped?/1`,
  `review_shaped?/1` and `can_block?/1`; a screen wanting a distinction
  none of those five draws grows a sixth predicate there instead of
  re-deriving the answer locally. Dev's diff (`lib/catapult_web/**` is
  outside this pass's own reach) — recorded here as the rule that diff
  is written against, not a code change this pass makes.

  Four call sites match today: `{:kind, :blocked}` at
  `ticket_live.ex:112,161`, `board_live.ex:124` and
  `my_queue_live.ex:87`; `%{status_kind: "blocked"}` at
  `board_live.ex:137`.
- **Component modules live beside their story, under
  `storybook/screens/<name>/`, not under `lib/catapult_web/**`**
  (ORC-35 design pass — the first ticket to exercise this system's
  screen machinery). `component.ex` and `component.story.exs` are
  both design-owned and both committed there; the LiveView that mounts
  a screen for real is dev's, in this doc's own file map, and imports
  the component by its module name the same as it would from anywhere
  else in the tree — Elixir does not care which directory a module
  compiles from, only that `storybook/` is on the build's
  `:elixirc_paths`. This is the pattern every later screen in this
  system follows unless a later pass argues otherwise in writing.

  **The placement decision carries no qualification: `mix.exs`,
  `elixirc_paths` and `.formatter.exs` already carry the storybook
  tree, so `storybook/screens/<name>/` is simply the pattern.**
  `phoenix_live_view` and `phoenix_storybook` are direct dependencies
  and `phoenix` is transitive, all three named in `boundary: check:
  apps:`; `elixirc_paths` includes `storybook` in every environment;
  `.formatter.exs`'s `inputs` glob it too, with
  `:phoenix`/`:phoenix_live_view` in `import_deps` so `attr`, `slot`
  and `~H` format as markup; and `pipeline.config.json`'s
  `preview.buildCommand` runs `bash bin/preview-build.sh`. Components
  authored under this placement compile, format and gate like any
  other source in the tree.

  **`phoenix_storybook` v1.3 ships no static export**, so a preview
  deploy cannot simply run one: it is served from a live Phoenix
  route, with no export task standing in for one.

  **The export renders stories directly and never boots the
  application** (ORC-113) — on the merits, not because booting is
  impossible on the preview runner. The design-agent job
  (`.github/workflows/pipeline-agent-design.yml`) installs the pinned
  toolchain with `erlef/setup-beam@v1`, runs under `MIX_ENV: test`, and
  provisions a health-checked `postgres:16` service; `config/test.exs`
  seeds `DATABASE_URL`,
  `FOUNDATION_ENDPOINT_SECRET_KEY_BASE` and `DELIVERY_GITHUB_TOKEN`
  into `Catapult.Config.Static` for exactly that `MIX_ENV`. Under the
  job's own environment, `Catapult.Boot.load!/0` would succeed.
  `CLAUDE.md`'s "agent runs have no BEAM" is about what orchestration's
  own `setup-pipeline` action provides — Go and nothing else, because
  the pipeline is language-agnostic — and this project's workflow
  layers a toolchain and a database on top of it. Both are true at
  their own layer, so anything needing `mix` inside an agent job still
  supplies its own.

  What still stops a boot is `bin/preview-build.sh` itself, not the
  runner. The script sets its own `export MIX_ENV=prod`,
  unconditionally, to build the preview in the shape a real deploy
  would; `config/prod.exs` declares no `:config_source`, so under that
  `MIX_ENV`, `Catapult.Boot`'s compile-time default applies —
  `{Catapult.Config.Env, []}`, the real-environment reader. Nothing in
  the job sets `DATABASE_URL`, `DELIVERY_GITHUB_TOKEN` or
  `FOUNDATION_ENDPOINT_SECRET_KEY_BASE` as literal environment
  variables (only `PGHOST`/`PGUSER`/`PGPASSWORD`, which nothing outside
  `config/*.exs` assembles into a `DATABASE_URL`), so a boot attempted
  from inside this script, as it stands, still fails — a fact about
  this script's own chosen build shape, checked independently of the
  stale `CLAUDE.md` line rather than inherited from it.

  That is fixable — dev could set `MIX_ENV=test` for the export step
  alone — so this is a real choice against a buildable alternative, not
  a rule-out. It still lands on render-direct: stories are stateless
  function components by this system's own placement rule, so nothing
  about rendering them benefits from the request cycle, live PubSub or
  persisted event store a boot would supply — the placement rule
  already spent the effort of not needing them. Render-direct also
  never depends on `Boot.load!/0` succeeding, so it stays correct
  regardless of what a future component declares as required config; a
  boot-based export would instead be one new non-defaulted `config/0`
  entry away from a preview breaking over a change that has nothing to
  do with the dashboard. What boot buys over render-direct is what the
  next paragraph names — `phoenix_storybook`'s own navigation chrome —
  already weighed and already traded for a generated index.

  The alternative costs nothing this system's own placement rule
  didn't already spend: a story's variations are hardcoded assigns
  rendered by a stateless function component — "no socket, no live
  data" above is a property the export gets for free, not one it has
  to work around. Every `storybook/screens/<name>/component.story.exs`
  already declares its own `function/0` and `variations/0`
  (`PhoenixStorybook.Story`'s own `:component` shape); the export
  calls each variation's attributes straight into its story's
  component function and writes the rendered markup to `dist/` —
  compiled, but with `Catapult.Application` never entered, so no
  endpoint, no supervision tree, no database. What is lost is
  `phoenix_storybook`'s own navigation chrome (its sidebar, its live
  search): the export's index page is generated directly from the
  same variation list instead, one link per story and variation. That
  is the ticket's own named tradeoff, taken on merit against a
  buildable alternative, per the correction above — not because the
  alternative was impossible.

  **The CSS build is Tailwind's standalone CLI, wrapped by the
  `:tailwind` Mix package, with daisyUI vendored rather than resolved
  through npm** (ORC-183, design pass). No Node or npm dependency
  anywhere in the toolchain — the same discipline `bin/preview-build.sh`
  already keeps for OTP/Elixir itself (`Where things actually run`,
  `CLAUDE.md`), and the standalone CLI has no npm resolution to lean on
  in the first place. daisyUI ships as two vendored plugin files,
  `assets/vendor/daisyui.js` and `assets/vendor/daisyui-theme.js`,
  referenced from `assets/css/app.css` by a relative `@plugin` — Tailwind
  v4's CSS-native plugin/import syntax, no `tailwind.config.js` needed —
  the same shape Phoenix's own 1.8 generator settled on for the
  identical constraint. `mix assets.build` (dev) and `mix assets.deploy`
  (minified, then `phx.digest`, prod) compile to
  `priv/static/assets/app.css`; the release `Dockerfile` runs
  `assets.deploy` in its build stage — `MIX_ENV=prod`, after `mix
  deps.get --only prod` — before `mix release`, so the digested CSS
  ships inside the image. That is exactly why `:tailwind` cannot take
  `credo`/`sobelow`/`mix_audit`'s own `mix.exs` treatment: those three
  are `only: [:dev, :test], runtime: false`, so `deps.get --only prod`
  never fetches them, which is fine because nothing in a prod build
  needs them. `assets.deploy` is a prod build's own step, so `:tailwind`
  carries `runtime: false` and no `boundary: check: apps:` entry — the
  same build-time-only shape, never started as part of the release —
  but **no `only:` restriction**, since `prod` is exactly where it has
  to run.

  `CatapultWeb.Endpoint` gains a `Plug.Static` serving `priv/static` at
  `/assets` — absent today, so the live route serves no static asset of
  any kind yet, not only unstyled daisyUI classes.

  The export above already committed to relative asset paths rather than
  root-absolute ones, since a Pages hash subdomain has no fixed base path
  to hardcode against; this pipeline carries into the export the same
  way, unchanged reasoning, now with something to carry — the export
  copies `priv/static/assets/app.css` into `dist/assets/app.css` and
  each generated page links it with a relative `href`.

  That copy needs something to have built it first, and
  `bin/preview-build.sh` does not run any assets task today. This
  record decides where: `mix assets.build` runs right after the
  script's own `mix compile` step and before the export script, guarded
  by the same `|| fall_back "..."` discipline as every other step in
  that script (`Where things actually run`, `CLAUDE.md` — the script
  never exits non-zero, so a step that can fail must degrade to the
  placeholder itself rather than let a later step fail past it). Without
  that guard, a CSS build failure would not stop the export — nothing
  downstream reads `priv/static/assets/app.css` before copying it — so
  the script would still exit 0 and publish pages linking a stylesheet
  that was never built: this ticket's own symptom, reintroduced, with
  the job reporting success.

  `assets/**` is on this doc's own file map but is not design-owned
  (`pipeline.config.json`'s `designOwnedPaths` names `screens/**`,
  `storybook/**`, `systems/*.md`, `docs/*.md`, nothing under `assets/`):
  this paragraph is the decision dev's diff is written against, not a
  change this pass makes itself. That diff also touches `mix.exs`,
  `Dockerfile` and `bin/preview-build.sh` — each unowned by any file map
  (`systems/README.md`), git's textual conflict detection standing in
  for a mutex on those three the same way it already does for every
  other ticket that adds a dependency or touches the toolchain.

  **`--ignore Config.HTTPS` on the sobelow gate is permanent, and is
  not waiting on this system's endpoint** (ORC-131). It was once
  recorded here as a temporary suppression to drop the moment
  `lib/catapult_web` landed an endpoint; the endpoint landed at ORC-35
  and the reasoning did not survive it. App Platform terminates TLS
  and coerces HTTP to HTTPS at its edge with no setting to disable it,
  so a public request never reaches this app over http and
  `Plug.SSL`'s redirect could never fire on one — while the one path
  that does not come through the edge, App Platform's own health
  probe, would be answered with a 301 and fail the deploy. HSTS, the
  half the edge does not supply, is set on `CatapultWeb.Router`'s
  `:browser` pipeline, which the check cannot see because it reads
  endpoint config. `ci.yml`'s own comment carries this, and
  `test/catapult_web/router_test.exs` asserts HSTS is absent on
  `/health` so moving it to the endpoint turns a test red rather than
  a deploy.

- **The dispatch-facing listener's hand-wiring retires in favor of a
  registry-driven successor, not a hand-authored router** —
  `systems/foundation.md`'s own diff carries the decision and the
  reasoning (the compile-connected gate question ORC-9 raised); this
  bullet exists only so a reader of this doc knows the router question
  is answered one doc over rather than unaddressed. Dashboard's own
  screens (`event-log`, `explain-why`, and whatever v1 adds) get an
  ordinary `Phoenix.Router` with their routes declared directly, since
  no other component needs to declare a LiveView route the way several
  declare an `api_surface/0` one — only the boundary-export half of
  the listener needed a generic, registry-driven shape.

## Initial vs target

Staged in `docs/ui-spec.md` §5; summarised here. Initial (Phase 4,
v0) is unmoved by the reversal: event log + ready_scopes explain-why,
the debugging minimum for the authoring loop. **v1 is the working
surface** — `my-queue`, `board`, `ticket`, `document-review`
(`screens/my-queue.md`, `screens/board.md`, `screens/ticket.md`,
`screens/document-review.md`) — and it is **Phase 4's floor rather
than a later addition**: there is no third-party tracker in the loop
to lean on while it is missing (v5 §7.17), so until v1 exists the
authoring loop has no surface at all. v2 adds what makes the native
surface *better* rather than merely available (`ticket-graph`,
sentence-granular anchoring, and the comment navigation serving
ui-spec's R1/R2 — mechanism sketch-grade). v3 is ops and scale:
bindings, configuration, workflow, registry, milestone, triage,
health, metrics, and identity consumption for login (Phase 7; minimal
auth before that).

## Depends on

engine (projections), delivery (run/dispatch data), substrate.

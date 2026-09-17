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

## #1 Standing decisions

- **#2 This is the work loop's surface** (v5 §7.17). The temptation the old
  debugging-surface-only line guarded against is real and did not go away with it, so it has a
  successor with teeth, in `docs/ui-spec.md` §2: reads are projections and writes are commands;
  **no screen introduces protocol vocabulary**; and every screen answers a named question or
  performs a protocol-defined action.
- **#3 The two non-work-loop prongs were always in-bounds and are
  unchanged:** **admin/settings** (v5 §7.10's bindings UI —
  query-and-pick project wiring, tracker provisioning, plane-state
  tunables) and the **configuration surface** (registry consumption:
  policy tunings, component options — *graph* state, edited by
  composed PR: forms generated from declarations, save files a change
  through the normal entry machinery, review stays in the PR). The
  composer never bypasses a gate.
- **#4 "Why is nothing happening" must be answerable in minutes** — the
  design bar for every view, and explain-why is what answers it, not
  a number. **But numbers are in-bounds where they are the answer**
  (`docs/ui-spec.md` §2, §3.3): instance health is a numeric
  determination, and throughput and cycle time are how the platform's
  value is demonstrated rather than asserted. The earlier phrasing —
  "explain-why over dashboards-of-numbers" — overshot; the target was
  decoration, not measurement. The test that replaces it: a number
  you cannot drill through to the tickets behind it is decoration.
- **#5 LiveView + daisyUI, stateless presentational components** —
  orchestration's assumed stack, deliberately, so its design agent
  and storybook export machinery work on our own UI.
- **#6 Reads projections only; every mutation goes through engine commands.** The dashboard
  can never be a second write path.
- **#7 Every screen's navigation and every query it issues carries a project id, with no
  cross-project or "all projects" view anywhere in this system** (ORC-87, ORC-35 design pass).
- **#8 Narrowed at ORC-75 for exactly one screen, on the rule's own stated reason rather than
  against it.** `my-queue` is cross-project — v5 §7.10 says so directly, about this exact
  screen: "at one human this degenerates correctly: 'My Issues' is exactly the **cross-project**
  list of tickets needing the author — the inbox property, with no filtering." That is not a
  route or a query missing a project id, which is the failure this bullet's own reasoning names;
  it is `my-queue` issuing one fully project-scoped query per project the actor has standing in
  and merging the rows for display.
- **#9 The gate action `ticket` and `document-review` render is real, not
  anticipatory** (ORC-75, ORC-114). `Catapult.Engine.Commands
  .ApproveGate{project_id, flow_id, gate, node_id, body_sha, actor_id}`
  → `GateApproved`, and `Commands.DeclineGate{project_id, flow_id,
  gate, throwback_to, since_sequence, node_id, body_sha, actor_id}` →
  `GateDeclined` (`lib/catapult/engine/commands/{approve,decline}
  _gate.ex`, `systems/engine.md`'s ORC-34 entry), and `Catapult
  .Delivery.FeatureLifecycle`'s `interested?`/`handle` clauses move a
  ticket's projected status off them: `GateApproved` advances to the
  next entry in the type's own `statuses:` array past the gate,
  `GateDeclined` moves straight to `throwback_to`
  (`systems/delivery.md`'s ORC-34 entry). Both screens' approve/throw-
  back controls target these directly, so dev wires a working control
  rather than a disabled one naming a gap. What stays open is narrow:
  §7.16's "what a passed gate pins" has its design answer at the end
  of this entry, and which node(s) a gate spanning more than one
  status validates against is left open on purpose
  (`systems/engine.md`'s ORC-34 entry); neither blocks v1, since
  Phase 4's own `feature.yaml` runs exactly one `generation` status
  ahead of each gate. `gate`/`throwback_to` legality is validated at
  the command edge: whatever constructs the command (dev's LiveView)
  checks that `throwback_to` is earlier in the citing type's own
  effective sequence — the same "earlier in the array" test
  `Catapult.Dsl.Workflow.gate_throwback_problems/2` runs at load time
  for a *declared* target, generalized to every runtime pick, since a
  gate's declared `throwback:` is a single-target override on the
  derived default and not a legality bound (ORC-115;
  `docs/dsl-syntax.md` §15.10, §15.4). `document-review`'s throwback
  picker offers the same full earlier-prefix Blocked-return's picker
  gives (`docs/ui-spec.md` J4), one click landing on the gate's own
  declared `throwback:` when the gate names one, or its citing
  sub-array's own derived default otherwise — never bounded, either
  way, to a gate's own declared exits as an allow-list. **A decline
  naming no comment is rejected by `DeclineGate`'s own aggregate
  state, never by either screen** — the screen surfaces that rejection
  synchronously, the same compare-and-swap conflict rendering
  `ticket`'s stale-transition case specs, but does not perform the
  check itself (`docs/ui-spec.md` §2 rule 1; `screens/document-review
  .md` and `screens/ticket.md` both name this precisely).
- **#10 A gate resolution is a compare-and-swap inside the aggregate, run before either event
  is produced** (ORC-114). A command whose `execute/2` binds no aggregate state and emits
  unconditionally guards no stale transition — the exact property both screens' own text asserts
  (§7.16) — so `ApproveGate`/`DeclineGate` carry `node_id` and `body_sha` beside the fields
  above, and the aggregate holds `gate_resolutions: %{gate => :approved | :declined}` (absent
  key means open): a second writer racing the first on one still-open resolution is rejected
  with `{:engine_gate_already_resolved, gate:, disposition:}`, naming the value the loser's
  command conflicted with; a resolution against a body the aggregate has already moved past —
  regenerated after the actor's view was rendered — is rejected separately with
  `{:engine_stale_gate_resolution, node_id:, current:, got:}`.
- **#11 What the rejection names is the value, not the actor** — the same level of detail
  `AdvanceContainerQueue`'s own conflict already gives (`systems/engine.md`), and neither
  `gate_resolutions` nor the node's `body_sha` carries who wrote it. `docs/ui-spec.md` §3.1's
  "names who moved it and where" is satisfied in two parts rather than one: the synchronous
  rejection is the "where" (which disposition already landed, or that the body moved), rendered
  at the point of action per §7.16; "who" is a follow-up read of the project's event stream for
  the gate's most recent `GateApproved`/`GateDeclined` (both carry `actor_id`), the identical
  "read the log for a display fact" pattern `GateComments`/`CommentFeedback` already establish
  rather than a new mechanism. `screens/ticket.md` carries this precisely; `board` reuses it
  rather than redefining it.
- **#12 `board`'s cards do not dispatch `ApproveGate`/`DeclineGate` in v1; `docs/ui-spec.md`'s
  "cards carry pass-forward and pass-back directly" is met by a link, not a dispatch.** Both
  commands require the `body_sha` of the body the actor is resolving against, and a card shows a
  ticket, not a body — filling it from the projection's current value would make the
  compare-and-swap pass unconditionally while the card *looked* guarded, which is worse than not
  offering the control at all. Every gate Phase 4's `feature.yaml` declares reviews a prose
  artifact, so a card's pass-forward/pass-back links into `document-review` instead, the
  identical move `ticket`'s own gate action makes for the same reason (`screens/ticket.md`,
  `screens/board.md`).
- **#13 `ResumeFlow{project_id, flow_id, to, actor_id}` → `FlowResumed` gives `ticket`'s
  blocked return control a real write path** (ORC-114). Without it
  `Catapult.Delivery.FeatureLifecycle .Projection`'s own `resting/2` has no way off `{:kind,
  :blocked}` except a fresh commit, and both `my-queue`'s `unblock` kind and `ticket`'s own
  "Blocked" section need a human to choose a return position. `to` is validated at the command
  edge against the effective-sequence prefix up to and including `blocked_origin`, never forward
  (`docs/ui-spec.md` §6) — the same bundle/projection- content split every other command edge on
  this aggregate draws. `screens/ticket.md` carries the detail.
- **#14 A ticket's title/argument, and the read both `board` and `my-queue` place a ticket
  from.** `argument` is a reserved `fields:` name on a flow's entry tier (`docs/dsl-syntax.md`
  §3, `systems/platform_content.md`), folded into `Catapult.Delivery.Store
  .tickets_for_project/1` — one project-scoped read returning `id`, `ticket_ref`, `flow_name`,
  `entry_node_id`, `status_kind`, `status_gate`, `blocked_origin_kind`, `blocked_origin_gate`
  and `argument` per open flow, which is what `board`'s lanes and `my-queue`'s three action
  kinds both place a ticket from (`systems/delivery.md`'s ORC-114 entry). `my-queue` calls it
  once per project the actor has standing in and merges the rows, the identical fan-out its own
  "Cross-project, deliberately" section describes.
- **#15 `document-review`'s stale marking does not ship in v1.** Staleness cannot be read off
  whether a node's current `body_sha` matches what the gate's approval event recorded, because
  `GateApproved`/ `GateDeclined` carry no content identity, deliberately: what a passed gate
  pins is its citing sub-array's one non-review-shaped agent-balled entry, at the gate's
  declared `depth:`, derived rather than stamped on the event (ORC-115; `docs/dsl-syntax.md`
  §15.10; `docs/v5-design-decisions.md` §7.16), and reading staleness off that derivation is the
  log join `systems/delivery.md`'s Phase 7 carries.
  `Catapult.Delivery.Store.get_previous_draft_body/2` (one previous body, not a log) answers the
  per-sentence **diff** `document-review` renders — a narrower question ("what changed since the
  last pass") than "has what this gate approved changed," which needs the content pin the events
  do not carry.
- **#16 No assignee or role-holder projection exists, and Phase 4's screens render the
  degenerate case rather than modeling an interim one** (ORC-114, design pass). `my-queue`'s two
  tabs, its `sign off` visibility rule, and `ticket`'s "shown only when the viewer's role holds
  the gate" all assume a human-to-role mapping; `Catapult.Engine .Commands.ApproveGate`'s own
  moduledoc places role authorization exactly where §7.16 already leaves grant evaluation —
  identity's, a Phase 7 component that does not exist yet. Phase 4 has exactly one author, so
  the correct rendering is the one identity will later narrow rather than one this system
  invents ahead of it: every gate action is shown to every viewer, `my-queue`'s **Assigned** and
  **My roles** tabs read the identical underlying set (there is no assignee column to tell them
  apart), and `board`'s `assignee` filter has no source to filter against — deferred beside
  `milestone` and `mutex label` for the identical reason.
- **#17 A lane/rail key is a position's own namespaced identity
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
- **#18 The anchor for a *resting* ticket — the gap §15.12 left open by its own admission — is
  `Positions.resting_key/2`** (ORC-116). `Catapult.Delivery.FeatureLifecycle.Projection`'s
  `passed`/ `pinned_to`/`blocked_from` all still key on the bare `position()` tuple, with no
  namespace attached, so `resting_key/2` resolves this as a lookup against the loaded
  declaration, not a runtime identity: walk the citing type's own effective sequence for the
  sub-array, if any, containing the resting position, and key off that sub-array's own anchor
  name; a position outside every sub-array keys bare. That lookup is exactly what
  `Positions.key/2`'s `anchor` argument is already shaped to take — this system supplies the
  argument, not a new encoding. It is first-match, best-effort where the bare kind recurs:
  disambiguating *which* occurrence a resting ticket is actually at needs runtime
  position-tracking the projection does not carry, which stays open the same way
  `Sequence.name/3` already admits it for the declared-lane case.
- **#19 A non-root instance's own lane sequence ends at its last reachable position — never at
  a `merge` or `deploy` of its own** (ORC-116, `docs/dsl-syntax.md` §15.11). `merge` is depth-0
  by rule and a non-root ticket merges only through its parent's `reconcile`, so `board` and
  `ticket` render no `merge`, `deploy` or `terminal` lane for one; its own effective sequence
  simply stops short of that machinery, the same way `Sequence`'s own `@reachable_boundary`
  already stops every instance's sequence short of `merge` today. The card leaves the board the
  moment the parent's `reconcile` resolves it, direct to `terminal` — v5 §7.6's `Merged → Done`,
  settled independent of tree position — with no lane in between to render it in.
- **#20 `board`'s lane set is derived per tree shape, not per declared
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
- **#21 Cross-type fan-out roll-up is a card-level count, not a per-lane
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
- **#22 Child roll-up has no data source in Phase 4, and of the two bullets
  above, only one fully closes on the type alone — the other's own
  per-card rule needs the same missing data** (ORC-129, naming what "wait
  for fan-out-as-separate-flows" above was shorthand for).
  `Catapult.Engine.Store.Flow` carries no parent-flow reference, and the
  `parent_node_id` that `Catapult.Engine.Store.Node` does carry is
  doc-graph scope structure — the chain-axis tiers an architecture
  ticket's own generation walks — not a ticket-delivery relationship, so
  there is no second flow instance and no query "these flows are this
  ticket's children" to run.

  `board` and `ticket` both render an honest `children: []` rather than a nested board or a
  narrowed count (`screens/board.md`, `screens/ticket.md`); `board`'s per-card lane exclusion
  goes unenforced for the identical reason.
- **#23 A screen or LiveView branches on `Catapult.Dsl.SystemStatus`'s own
  predicates, never on a status-name literal** (ORC-116; the same rule
  `Catapult.Delivery.ContainerLifecycle.inline_dispatch_point?/1`
  follows since ORC-151 retired its `status != "merge"` check).
  `Positions`'s `{:kind, atom}` shape puts the raw status atom within
  reach of every LiveView that touches it. Blocked is a real orthogonal
  flavor rather than an array position, so branching on it is correct;
  the literal comparison is the form to stop using. `SystemStatus`
  exports `ball/1`, `agent_balled?/1`, `generation_shaped?/1`,
  `review_shaped?/1` and `can_block?/1`; a screen wanting a
  distinction none of those five draws grows a sixth predicate there
  instead of re-deriving the answer locally.

  The rule reaches every Blocked branch in `ticket_live.ex`,
  `board_live.ex` and `my_queue_live.ex` — a `{:kind, :blocked}` match
  and a `%{status_kind: "blocked"}` match alike.
- **#24 Component modules live beside their story, under
  `storybook/screens/<name>/`, not under `lib/catapult_web/**`**
  (ORC-35). `component.ex` and `component.story.exs` are both
  design-owned and both committed there; the LiveView that mounts a
  screen for real is dev's, in this doc's own file map, and imports
  the component by its module name the same as it would from anywhere
  else in the tree — Elixir does not care which directory a module
  compiles from, only that `storybook/` is on the build's
  `:elixirc_paths`. Every screen in this system follows this pattern.
- **#25 The build carries the storybook tree as ordinary source.** `phoenix_live_view` and
  `phoenix_storybook` are direct dependencies and `phoenix` is transitive, all three named in
  `boundary: check: apps:`; `elixirc_paths` includes `storybook` in every environment;
  `.formatter.exs`'s `inputs` glob it too, with `:phoenix`/`:phoenix_live_view` in `import_deps`
  so `attr`, `slot` and `~H` format as markup. Components authored under this placement
  compile, format and gate like any other source in the tree.
- **#27 The CSS build is Tailwind's standalone CLI, wrapped by the `:tailwind` Mix package,
  with daisyUI vendored rather than resolved through npm** (ORC-183). No Node or npm dependency
  anywhere in the toolchain, and the standalone CLI has no npm resolution to lean on in the
  first place. daisyUI ships as two vendored plugin files,
  `assets/vendor/daisyui.js` and `assets/vendor/daisyui-theme.js`, referenced from
  `assets/css/app.css` by a relative `@plugin` — Tailwind v4's CSS-native plugin/import syntax,
  no `tailwind.config.js` needed — the same shape Phoenix's own 1.8 generator settled on for the
  identical constraint. `mix assets.build` (dev) and `mix assets.deploy` (minified, then
  `phx.digest`, prod) compile to `priv/static/assets/app.css`; the release `Dockerfile` runs
  `assets.deploy` in its build stage — `MIX_ENV=prod`, after `mix deps.get --only prod` — before
  `mix release`, so the digested CSS ships inside the image. That is exactly why `:tailwind`
  cannot take `credo`/`sobelow`/`mix_audit`'s own `mix.exs` treatment: those three are `only:
  [:dev, :test], runtime: false`, so `deps.get --only prod` never fetches them, which is fine
  because nothing in a prod build needs them. `assets.deploy` is a prod build's own step, so
  `:tailwind` carries `runtime: false` — the same build-time-only shape, never started as part
  of the release — but **no `only:` restriction**, since `prod` is exactly where it has to run.
- **#28 `:tailwind` carries a `boundary: check: apps:` entry.** `Catapult.Audit.BoundaryApps`
  computes what a `:prod` build can reach from each dependency's `only:`, never from `runtime:`
  — so an application with no `only:` restriction is reachable regardless, and `:tailwind` names
  `Elixir.*` modules Boundary can restrain.
- **#29 `--ignore Config.HTTPS` on the sobelow gate is permanent, and is not waiting on this
  system's endpoint** (ORC-131). The endpoint (ORC-35) changes nothing: Render terminates TLS
  and redirects HTTP to HTTPS at its edge, so a public request never reaches this app over http
  and `Plug.SSL`'s redirect could never fire on one — while the one path that does not come
  through the edge, the platform's own health probe, would be answered with a 301 and fail the
  deploy. The second half is what makes this permanent rather than vendor-specific: a probe
  reaching the container directly is how a container health check works anywhere, which is why
  the rule moved off App Platform intact. HSTS, the half the edge does not supply, is set on
  `CatapultWeb.Router`'s `:browser` pipeline, which the check cannot see because it reads
  endpoint config. `ci.yml`'s own comment carries this, and `test/catapult_web/router_test.exs`
  asserts HSTS is absent on `/health` so moving it to the endpoint turns a test red rather than
  a deploy.

- **#30 The root layout serves no LiveView client, so no `handle_event/3` is reachable in
  production** (ORC-220).

  `:esbuild` occupies a fourth site the `:tailwind` half already
  occupies, beside the `mix.exs` dependency, the `assets.build`/
  `assets.deploy` alias, and the `boundary: check: apps:` entry below:
  `assets.setup` gains `esbuild.install --if-missing` next to the
  existing `tailwind.install --if-missing` line, so a fresh checkout
  installs both standalone binaries on first run rather than failing
  the first `assets.build` with neither present.

  The root layout gets a `<script>` tag beside its `<link
  rel="stylesheet">`, deferred so it runs after the DOM it attaches to.
  No CSRF plumbing changes: `phoenix_live_view`'s `LiveSocket` reads the
  token from a `meta[name="csrf-token"]` tag by convention, and
  `CatapultWeb.Layouts.root/1` already emits exactly that tag for the
  session infrastructure `CatapultWeb.Endpoint`'s own comment names.
- **#31 The fix is the standard LiveView client, built the no-Node way ORC-183 chose for CSS
  above, not a second toolchain decision.** `assets/js/app.js` imports `phoenix`, `phoenix_html`
  and `phoenix_live_view` — each already a direct or transitive dependency in `deps/`, so
  nothing is fetched through npm — bundled by the `esbuild` Mix package's own standalone binary.
  `mix esbuild catapult --minify` joins `assets.deploy` ahead of `phx.digest`, and `mix esbuild
  catapult` joins `assets.build` the same way `tailwind` does, so dev and prod both produce
  `priv/static/assets/app.js` through the identical alias shape this doc's own ORC-183 entry
  describes for the CSS half. `Plug.Static`'s existing `only: ~w(assets)` on
  `CatapultWeb.Endpoint` serves anything landing under `priv/static/assets`, so unlike ORC-183's
  CSS half this needs no endpoint change — the plug that serves `app.css` serves `app.js` for
  free the moment the build writes it there.
- **#32 The "nothing is fetched through npm" claim above rests on a `config :esbuild` profile,
  and the profile is what makes it true, not a detail beneath it.** Phoenix's own generator
  shape is the one this decision takes: `cd: Path.expand("../assets", __DIR__)`, `env:
  %{"NODE_PATH" => Path.expand("../deps", __DIR__)}`, entry `js/app.js`, args including
  `--bundle` and `--outdir=../priv/static/assets`.
- **#33 `:esbuild` takes the same `mix.exs` shape as `:tailwind`**: `runtime: false` since it
  is a build-time task never started as part of the release, but **no `only:` restriction**,
  since `assets.deploy` is a prod build's own step and `deps.get --only prod` has to fetch it —
  and a `boundary: check: apps:` entry from the day it lands, since
  `Catapult.Audit.BoundaryApps` computes `:prod` reachability from `only:`, never from
  `runtime:`, and an application with no `only:` restriction is reachable regardless.
- **#34 The storybook keeps its own client, untouched.** `live_storybook` mounts
  `storybook_assets()` (`CatapultWeb.Router`), `phoenix_storybook`'s own asset route,
  independent of `CatapultWeb.Layouts.root/1` and of this `app.js`; nothing in this decision
  touches the storybook's screens-as-dead-renders property, on either the live route or the
  static export.

- **#35 The dispatch-facing listener's hand-wiring retires in favor of a
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

## #36 Initial vs target

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

## #37 Depends on

engine (projections), delivery (run/dispatch data), substrate.

# dashboard — reasons

The reason behind each rule in `systems/dashboard.md`, keyed by the rule's id (orchestration's DESIGN §4). Read one with `pipeline reasons dashboard#n` before changing the rule it belongs to.

## #2

The second is the one that will get cited — the temptation is never "build a tracker", it is
"add one field here", and a field here is vocabulary.

## #7

A node id is a per-project slug and a project's event stream is per-project too
(`systems/engine.md`), so a route or a query missing the project resolves nothing rather than
resolving the wrong project's data. `event-log` and `explain-why` (`screens/event-log.md`,
`screens/explain-why.md`) are this decision's first two screens; it binds every screen after
them the same way, which is why it is recorded here rather than in either screen doc alone.

## #8

No route resolves without a project id and no query risks resolving the wrong project's data —
the two ways this rule's reasoning says the mistake actually happens — so `my-queue` satisfies
the reason the rule exists rather than being an exception carved out of it. A project switcher
gating `my-queue` would trade away the property that makes it the daily entry point rather
than a second `board`. `board`, `event-log`, `explain-why`, `ticket` and `document-review` are
each explicitly single-project, unaffected by this narrowing; `screens/my-queue.md` carries
the argument in full.

## #12

Once a gate's node set is derivable (ORC-116), staleness is computable from any surface and a
card needs no body view of its own; until then this is a v1 scope choice, not a defect.

## #15

`screens/document-review.md` drops stale marking from v1 rather than shipping a stopgap
`body_sha` on the gate events that the derived answer would be the first thing to delete.

## #16

Each screen's own doc records this against its own controls; this bullet is the one place a
reader sees why they all say it the same way.

## #17

**This retires the whole of the prior scheme, not just its collision case.** There is no more
scanning backward to the nearest anchor, no `Catapult.Generation.NodeId.resolve/1` chain-node
id and no `Catapult.Delivery.ContainerLifecycle.Ids.work_item_id/3` work-item id standing in
as the anchor's own identity — both were needed only because the prior scheme had no
bundle-authored name to key on and had to borrow one from a runtime concept instead.
`workflow.md` #7's namespace is a fact about the loaded declaration alone, so the key for any position is
available the moment the workflow loads, with no read against `engine_nodes` or a container's
own queue identity. The "Not yet covered" gap this bullet used to carry — two `critique` or
`reconcile` entries in one sub-array colliding on the same `(anchor, kind)` pair — closes the
same way: `workflow.md` #7 requires distinct `name:`s the moment two entries share a sub-array, so the
collision is a load error before this system ever sees the bundle, never a rendering gap for
it to solve.

Recurrence itself is unchanged from what this bullet already found: `workflow.md` #7
still lets a generation-shaped entry, `checks`, `merge` and `reconcile` all recur
(`pending` is an engine flag rather than an entry, #25),
and `merge`, `deploy` and `terminal` need no carve-out of their own — each is an ordinary bare
top-level name whenever it sits outside a sub-array (true of every recurrence in the current
`bundles/default-flow` types), and the namespace rule above already covers a bare top-level
name without naming any of the three specifically.

## #19

What a non-root instance's own `deploy` would mean stays exactly as open as
`workflow.md` #28 leaves it; this bullet only says the board renders nothing for
that gap, not what fills it.

## #22

`workflow.md` #28's declared fan-out depth is what lets the roll-up-shape bullet
(cross-type count vs. per-lane) resolve entirely from the type, and what lets the
bullet above it resolve a type's own lane set — the union of every tree-shape's
effective sequence — the same way. That bullet's other rule does not clear the same
bar: "a lane never shows a card whose own resolved sequence excludes it" means knowing
whether **this instance** has children, and no declaration states that: whether a
given instance runs `reconcile` is a fact about that instance's own children, not a
declared ceiling (`workflow.md` #28). That fact takes exactly the relationship this
bullet says is
missing: `board` cannot distinguish a leaf card from one with children, both reading the
identical type-and-depth sequence, so a leaf card can sit in a `reconcile` lane it never
reaches — the case that rule exists to prevent. Enumerating which flows are a given ticket's
actual children is the same fact under a different name, not a second gap.

Not gating: the source is `docs/build-plan.md`'s Phase 7 two-grain machinery — spawn and child
lifecycle, minting a child as its own addressable flow correlated to the parent that spawned
it — and nothing ahead of Phase 7 depends on it landing first.

## #24

**`phoenix_storybook` v1.3 ships no static export**, so a preview deploy cannot simply run
one: it is served from a live Phoenix route, with no export task standing in for one.

`CatapultWeb.Endpoint` serves `priv/static` at `/assets` through `Plug.Static`; without it the
live route serves no static asset of any kind, not only unstyled daisyUI classes.

**That is now how the preview works, rather than an obstacle to it.** The design review's
preview is a Render preview environment of the whole app, so the storybook is served from the
live Phoenix route this entry always said it had to be, and the hand-rolled static export that
stood in for one is gone with `bin/preview-build.sh` (rule #26, retired).

`assets/**` is on this doc's own file map but is not design-owned (`pipeline.config.json`'s
`designOwnedPaths` names `screens/**`, `storybook/**`, `systems/*.md`, `docs/*.md`, nothing
under `assets/`), so the CSS build is dev's diff. That diff also touches `mix.exs` and
`Dockerfile` — both unowned by any file map (`systems/README.md`), git's textual conflict
detection standing in for a mutex on them the same way it does for every other ticket that
adds a dependency or touches the toolchain.

## #26

retired: The rule described the static storybook export — it rendered stories directly and
never booted the application. There is no export. Design review reads the storybook from the
Render preview environment of the whole app, which does boot it, so the property the rule
named ("no socket, no live data") is not one the preview has any more.

Kept as the reason it was traded away, because the trade is the thing a later pass would
redo: the export avoided `Boot.load!/0`, so it could not break over a new non-defaulted
`config/0` entry that had nothing to do with the dashboard. A preview environment can. That
is a real cost of the move, paid knowingly — a preview whose boot fails now reports a failed
preview on the ticket (DESIGN §4) rather than silently serving stale stories, which is the
exchange: the failure is louder and the surface is larger.

## #28

The check carries no waiver for an application it finds this way — no ignore list, no
per-application escape (`components/substrate/lib/catapult/audit/boundary_apps.ex`'s own
documented shape) — so the only fix is the list entry itself; `mix.exs`'s own comment on the
dep carries this in full.

## #30

`CatapultWeb.Layouts.root/1` links `/assets/app.css` but no script; `assets.deploy` runs
`tailwind`/`phx.digest` only; `/assets/app.js` 404s on the reference instance. Every screen
still dead-renders correctly, which is what let this ship unnoticed through
`document-review`'s approve/decline and `board`'s and `ticket`'s gate actions — none of the
three connect a socket to fire on. **Why the omission survived**: every screen was reviewed
through the storybook export, a dead render by design (this doc's own ORC-113 entry above),
and the reference instance's screens were never driven live before Phase 5's proof
(`docs/build-plan.md`) needed them to be. The export never boots the application either, so it
exercised nothing here — the same dead-render property, hiding a second gap.

`assets/**` and `lib/catapult_web/layouts.ex` are on this doc's own file map but not
design-owned, the identical split this doc's own ORC-183 entry states for the CSS half, so the
client is dev's diff. That diff also touches `mix.exs` and `Dockerfile` — both unowned by any
file map (`systems/README.md`), git's textual conflict detection standing in for a mutex the
same way it does for every other ticket that adds a dependency or touches the toolchain.
`Dockerfile` needs no new step: `assets.deploy` already runs in its build stage, and folding
`esbuild` into that alias is enough for the existing `RUN mix assets.deploy` line to pick it
up.

## #32

Without `NODE_PATH` pointed at `deps/`, esbuild's bundler has nowhere to resolve a bare
`phoenix`/`phoenix_html`/`phoenix_live_view` import from, and the build fails rather than
silently reaching npm — dev meets the claim above as a build error, not as a working client,
if the profile is left out.

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
bundle-authored name to key on and had to borrow one from a runtime concept instead. §15.12's
namespace is a fact about the loaded declaration alone, so the key for any position is
available the moment the workflow loads, with no read against `engine_nodes` or a container's
own queue identity. The "Not yet covered" gap this bullet used to carry — two `critique` or
`reconcile` entries in one sub-array colliding on the same `(anchor, kind)` pair — closes the
same way: §15.12 requires distinct `name:`s the moment two entries share a sub-array, so the
collision is a load error before this system ever sees the bundle, never a rendering gap for
it to solve.

Recurrence itself is unchanged from what this bullet already found: `docs/dsl-syntax.md` §13
still lets a generation-shaped entry, `checks`, `merge`, `reconcile` and `pending` all recur,
and `merge`, `deploy` and `terminal` need no carve-out of their own — each is an ordinary bare
top-level name whenever it sits outside a sub-array (true of every recurrence in the current
`bundles/default-flow` types), and the namespace rule above already covers a bare top-level
name without naming any of the three specifically.

## #19

What a non-root instance's own `deploy` would mean stays exactly as open as
`docs/dsl-syntax.md` §15.11 leaves it; this bullet only says the board renders nothing for
that gap, not what fills it.

## #22

§15.11's declared fan-out depth is what lets the roll-up-shape bullet (cross-type count vs.
per-lane) resolve entirely from the type, and what lets the bullet above it resolve a type's
own lane set — the union of every tree-shape's effective sequence — the same way. That
bullet's other rule does not clear the same bar: "a lane never shows a card whose own resolved
sequence excludes it" means knowing whether **this instance** has children, and
`docs/dsl-syntax.md` says twice that no declaration states that — "whether a given instance
runs [`reconcile`] is a fact about that instance's own children, not a declared ceiling"
(§15.11; restated at §13). That fact takes exactly the relationship this bullet says is
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

The export links assets by relative path rather than root-absolute ones, since a Pages hash
subdomain has no fixed base path to hardcode against: it copies `priv/static/assets/app.css`
into `dist/assets/app.css` and each generated page links it with a relative `href`.

That copy needs something to have built it first, so `bin/preview-build.sh` runs `mix
assets.build` right after its own `mix compile` step and before the export script, guarded by
the same `|| fall_back "..."` discipline as every other step in that script (`Where things
actually run`, `CLAUDE.md` — the script never exits non-zero, so a step that can fail must
degrade to the placeholder itself rather than let a later step fail past it). Without that
guard, a CSS build failure would not stop the export — nothing downstream reads
`priv/static/assets/app.css` before copying it — so the script would still exit 0 and publish
pages linking a stylesheet that was never built, ORC-183's own symptom, with the job reporting
success.

`assets/**` is on this doc's own file map but is not design-owned (`pipeline.config.json`'s
`designOwnedPaths` names `screens/**`, `storybook/**`, `systems/*.md`, `docs/*.md`, nothing
under `assets/`), so the CSS build is dev's diff. That diff also touches `mix.exs`,
`Dockerfile` and `bin/preview-build.sh` — each unowned by any file map (`systems/README.md`),
git's textual conflict detection standing in for a mutex on those three the same way it does
for every other ticket that adds a dependency or touches the toolchain.

## #26

Booting is possible on the preview runner: the design-agent job
(`.github/workflows/pipeline-agent-design.yml`) installs the pinned toolchain with
`erlef/setup-beam@v1`, runs under `MIX_ENV: test`, and provisions a health-checked
`postgres:16` service, and `config/test.exs` seeds `DATABASE_URL`,
`FOUNDATION_ENDPOINT_SECRET_KEY_BASE` and `DELIVERY_GITHUB_TOKEN` into
`Catapult.Config.Static` for exactly that `MIX_ENV`, so under the job's own environment
`Catapult.Boot.load!/0` succeeds. (`CLAUDE.md`'s "agent runs have no BEAM" is about what
orchestration's own `setup-pipeline` action provides — Go and nothing else, because the
pipeline is language-agnostic — and this project's workflow layers a toolchain and a database
on top of it; both are true at their own layer, so anything needing `mix` inside an agent job
still supplies its own.) What stops a boot is `bin/preview-build.sh` itself: the script sets
its own `export MIX_ENV=prod`, unconditionally, to build the preview in the shape a real
deploy would; `config/prod.exs` declares no `:config_source`, so under that `MIX_ENV`
`Catapult.Boot`'s compile-time default applies — `{Catapult.Config.Env, []}`, the
real-environment reader — and nothing in the job sets `DATABASE_URL`, `DELIVERY_GITHUB_TOKEN`
or `FOUNDATION_ENDPOINT_SECRET_KEY_BASE` as literal environment variables (only
`PGHOST`/`PGUSER`/`PGPASSWORD`, which nothing outside `config/*.exs` assembles into a
`DATABASE_URL`). Setting `MIX_ENV=test` for the export step alone would lift that, so the
choice is made on merit: stories are stateless function components by this system's own
placement rule, so nothing about rendering them benefits from the request cycle, live PubSub
or persisted event store a boot would supply — "no socket, no live data" is a property the
export gets for free, not one it has to work around. Render- direct also never depends on
`Boot.load!/0` succeeding, so it stays correct regardless of what a future component declares
as required config; a boot-based export would instead be one new non-defaulted `config/0`
entry away from a preview breaking over a change that has nothing to do with the dashboard.
Every `storybook/screens/<name>/component.story.exs` declares its own `function/0` and
`variations/0` (`PhoenixStorybook.Story`'s own `:component` shape); the export calls each
variation's attributes straight into its story's component function and writes the rendered
markup to `dist/` — compiled, but with `Catapult.Application` never entered, so no endpoint,
no supervision tree, no database. What boot would buy, and what is traded away, is
`phoenix_storybook`'s own navigation chrome (its sidebar, its live search): the export's index
page is generated directly from the same variation list instead, one link per story and
variation.

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

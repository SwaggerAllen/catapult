# foundation — reasons

The reason behind each rule in `systems/foundation.md`, keyed by the rule's id (orchestration's DESIGN §4). Read one with `pipeline reasons foundation#n` before changing the rule it belongs to.

## #7

One shape in every environment is what makes `Repo.init/2` the same code
everywhere.

## #9

Which operator, which network, and why that control holds for this
deployment today are `SETUP.md` §2's facts, not this doc's to restate —
the gap `verify_none` accepts is real regardless (a compromised or
misconfigured resolver on the path is exactly what `verify_peer` would
catch and `verify_none` does not), and end-to-end operator control is what
makes that gap survivable rather than open. Backlog, not gating: nothing
in `docs/build-plan.md`, the engine milestone (Phase 3) included, depends
on verified TLS to the database.

**The record is here rather than in the docstring because a docstring
cannot re-surface itself.** The maintenance lane
(`docs/v5-design-decisions.md` §7.10) is a plane-side watcher over hex
advisories, `mix hex.outdated`, and GitHub security advisories — it has no
way to see a `verify_none` literal in application code, so a docstring
deferring the pinning to that lane re-surfaces nothing on its own. ORC-83
exists because a tech-debt scan caught exactly that: a self-reported
deferral with no tracked record. A docstring is prose a reader has to
already be looking at; this doc is what anyone touching
`cast_database_url/1` reads on the way in. Revisit condition: the moment
`DATABASE_URL` (or a successor) resolves over a path the operator does not
control end to end (`SETUP.md` §2 is where that stops being true, if it
ever does), at which point the cast pins a CA and switches to
`verify_peer`, and this bullet is what that ticket argues with.

## #10

`DATABASE_URL` does not stay in `runtime.exs` on the grounds that Ecto
wants app env anyway: that keeps a second reader of the environment alive,
and one reader is the whole point. One reader, one report, and the
libraries get their keyword lists.

## #12

Root glue in v5 §2.7's sense, and its own module rather than functions on
`Catapult.Application` for a reason implementation found: the application
is not the only entry point. `Catapult.Release.migrate/0` runs under
`eval` with the app loaded but not started, and mix's ecto tasks call
`Catapult.Repo.init/2` after `app.config` — both need configuration and
neither boots a supervision tree. Hanging the load off
`Catapult.Application` would put `Repo → Application → Foundation → Repo`
in the module graph, and `mix xref graph --format cycles --fail-above 0`
is a hard gate (conventions §2). The load being idempotent is what lets
three entry points ask for it without arranging who goes first; load-once
(`systems/substrate.md`) is what makes that safe rather than lucky.

## #13

That is a one-line diff and a short list right now, and it is N boundaries
at once at any later moment — worse, every carve-out between now and then
would land a boundary that has never been checked, so the retrofit grows
with exactly the work it is supposed to constrain. Arming the mode is
therefore not the same ticket as arming any of the four rules: the rules
arrive with the boundaries they constrain, in those systems' tickets, and
this decision is what makes each of them a `deps:` line instead of a
migration.

## #14

Strict additionally requires naming implicit boundaries *inside*
`:catapult_substrate`, and Boundary's cached view
(`Boundary.Mix.View.refresh/2`) drops a **path dep's** boundaries on every
incremental compile and rebuilds them only from loaded applications —
which the cache-hit path never loads. Measured, not inferred: `mix compile
--force` is clean and the very next `mix compile` reports all fifteen
substrate calls as forbidden, so the second compile in any CI job fails on
state rather than on code (`mix credo` compiles before `mix compile
--warnings-as-errors` in `ci.yml`, so this is the ordinary path and not a
corner). The app list is checked identically and stably, and the four
rules still arrive as `deps:` lines on the boundaries they constrain. What
is lost is the one thing strict adds beyond the list: a *newly added*
dependency is unchecked until it is named, and naming it is a §2.8
decision in the diff that adds it — review rather than a gate — which is
the gap the audit check below reports. Revisit condition: Boundary loading
a path dep's applications on the cache-hit path, at which point `type:
:strict` is a one-line change that deletes this list *and* renders that
check inert on its own terms.

## #15

A list of only the four rules' applications plus the HTTP listener —
`:ecto`, `:ecto_sql`, `:oban`, `:plug`, `:plug_cowboy`, `:req` — prices an
omission that gets noticed, and nothing noticed it: that list was short of
six applications the plane's own build resolves (`:db_connection`,
`:decimal`, `:jason`, `:mime`, `:plug_crypto`, `:postgrex`) from the day
it was written, each of them silently exempt rather than partially
checked. Two measurements decide the shape and both are cheap to re-run:
naming all eleven costs **zero** forbidden references, because the plane
calls none of them today — the expensive version of this ticket is the one
the engine would have filed — and naming `:catapult_substrate` costs
twelve and a red build, which is the path-dep defect above reproduced
through the list instead of through strict, so the path dep is excluded by
derivation rather than by a name anyone writes.

## #16

Computing the closure inside `boundary/0` at project-config time is the
tempting one-line version — nothing left to forget — and it fails on three
counts, in increasing weight. It runs on every mix invocation including
`deps.get`, before the compiled `.app` files the closure reads exist. It
is plane-local, so a generated project — whose `mix.exs` comes from
`bundles/default` and whose list drifts the same way — inherits nothing.
And it deletes the artifact review acts on: the list is the one place a
human reads which applications are constrained, and a derivation bug would
narrow it silently and in the permissive direction, which is the failure
this ticket was filed about wearing the fix's clothes. The check is the
half that has to be loud; the declaration is the half that has to be
readable, and they are different halves on purpose.

## #18

**A check that finds a *model call* cannot be built at the grade the audit
runs at, so it is not what gets built.** At AST grade the call is
`:httpc.request(:post, {url, headers, type, body}, [], [])` — whether
`url` reaches a model provider is data, decided at runtime and normally
read from configuration. Recognising a provider hostname in a literal
would catch a spelling nobody writes and report clean on every real
instance of the thing it is named after: a check that passed without
checking anything, which is the class ORC-37 was filed about and the class
this ticket is filed about. Following `url` back to its binding is the
dataflow inference this repo has refused twice already, in the
secret-taint case and the computed-config-key case
(`systems/substrate.md`, "What a check may infer"), each time for the same
reason — a shallow analysis reported as a guarantee.

**Now, rather than at a milestone where it has something to catch.** Phase
4 and Phase 6 are the obvious later homes, and both are wrong for one
mechanical reason: `:inets` ships with OTP, so `:httpc` requires no
dependency and will never appear in a `mix.exs` or `mix.lock` diff. There
is no arming moment for anyone to notice — which is *why* it is the
residue, and why "wait until it has a subject" is waiting for a signal
that cannot arrive. The rest is ORC-21's own argument for arming the app
list against one boundary, one level in: the run is green today, so the
diff is a module and a registration rather than a cleanup, and every plane
module written between now and Phase 6 would otherwise land unchecked. The
system's own precedent agrees from the other side — the live suite already
rejected `:httpc` on its merits ("HTTP client: Req" below), so this
codifies a decision foundation has made once already instead of
anticipating one. Revisit condition: none for the arming. The *list* is
expected to grow, and growing it is the reviewed diff the mirror-image
argument above asks for.

## #20

The obvious objection to banning named HTTP clients is that a determined
module can open a socket and write the request bytes itself; the objection
is correct and does not change the answer. Those applications are what
Postgres, the clustering transport and every other legitimate connection
ride on, so banning them means an escape tag at every real call site, and
a ban escaped everywhere is a ban nobody reads. The trade is asymmetric in
the direction that decides it: a plane module reaching a provider through
`:httpc` is a mistake somebody makes, while one hand-rolling HTTP over
`:gen_tcp` is a deliberate evasion, and no check in this repo is built to
stop an author who is trying. The named list grows by reviewed diff when a
real client is missing from it; that is a different move from descending a
layer.

## #21

Being AGPL plane code is exactly what makes holding Catapult's own policy
correct here, the same way `catapult.audit.all` is the sanctioned home for
knowing this repo's layout (`systems/substrate.md`).

## #22

Recorded here because the value is a fact about *this* project's tree, and
the day it stops being 0 the diff that raised it should have to say so.

## #23

Measured on this tree rather than reasoned, because "nothing changes in
the closure" is the whole point and a claim worth checking: before,
`licensing: inert — this project states no licensing policy, so nothing
was checked`; after, `licensing: unchecked against 6 identifiers — no
subject arms a dependency check (Catapult.Foundation :service
"AGPL-3.0-only")`. The verdict acquires a subject and a reason somebody
asserted, in place of a sentence about the absence of one.

**The half that is worth a ticket is the other one.**
`Catapult.Audit.License` never reaches `undeclared_problems/1` while a
project is inert, so today the missing declaration is not reported either
— the check and its own precondition are both dark. Measured: with the
policy stated and `licensing/0` deleted again, the audit fails with
*"Catapult.Foundation declares no licensing/0, so this project's policy
cannot place it"*. Stating the policy is therefore what makes every plane
component the engine adds state its class in the diff that adds it,
instead of a retrofit sweep across seven systems later — the retrofit
`LICENSING.md`'s declaration model is most exposed to, since a class
nobody was asked for is a class somebody guesses.

Both edits are one commit, and not because of an ordering hazard: the
`mix.exs` line alone fails the audit on the undeclared component, and
`licensing/0` alone changes nothing while the project is inert. It is one
decision landing in two files, one of which (`mix.exs`) is unowned by
construction (`systems/README.md`).

**`:service`, not `:internal`.** The plane is reached over a network by
people who are not its operator — the hosted tier is the product — which
is the case `:service` exists to name and the reason `LICENSING.md` chose
AGPL over plain GPL in the first place. `:internal` is the class whose
entire meaning is that nothing triggers, and asserting it about the one
program AGPL §13 was picked for would be a false declaration made in
public, which is precisely the failure the declaration model trades a path
rule for.

## #24

The other five hold although no dependency in this tree is measured
against them today, and the measurement is what holds them. The list is
consulted the instant any subject in this project arms the check, and
against the six identifiers above the plane's whole closure produces
exactly **one** problem — `cowboy_telemetry`, which declares `["Apache
2.0"]` and is the near-miss `systems/substrate.md` already names. Against
`["AGPL-3.0-only"]` alone it produces one per dependency. A list that is
correct only for as long as it is unused is a policy that gets written
under time pressure, inside the diff that first needed it and for reasons
that diff supplies.

**The seam this leaves.** `AGPL-3.0-only` is on the list, so if this
project's check ever armed for the *proprietary-`:service`* reason — AGPL
§13 obliging an offer of source to our own users — an AGPL dependency
would pass a check whose entire reason is that it must not. That is
one-list-per-project behaving exactly as recorded
(`systems/substrate.md`), and the guard is the decision below rather than
a second list keyed by class.

## #25

The two things that would break it already have somewhere else to be.
Anything **conveyed** — a published package, code generated into a
customer's tree — is Apache-2.0 under `components/**` or `bundles/**`
(`LICENSING.md`), and `components/*` are their own mix projects with their
own lockfiles and their own `allow:` lists. A hosted-tier proprietary
`:service` component under `LicenseRef-*` is its own mix project too, for
the reason `systems/substrate.md` records: dependencies are a mix
project's fact, and a project needing two policies needs two dependency
trees. So the day something in the plane's own tree wants a different
class is the day it is not in the plane's own tree.

## #26

ORC-74 would teach `Catapult.Audit.License` to resolve a **git**
dependency's terms from its own `licensing/0`, since a git dep has no
`hex_metadata.config`. Foundation's declaration is correct under both
readings — the terms this code carries are `AGPL-3.0-only` whether the
reader is this project's own audit or a consumer resolving a git dep — so
the two tickets are order-independent and this one adds no second spelling
for that resolver to disagree with. The coincidence is what makes the
ordering free, though, not an argument that the two facts are the same
fact: nobody git-deps the plane, so the plane's declaration is never
itself a resolution subject, and a component that *is* one would want
reading in ORC-74's terms rather than these.

## #27

This does not, on its own, get `docs/ui-spec.md`'s dashboard screens on
screen. Those need LiveView sockets — a `Phoenix.Endpoint` and a
`Phoenix.Router` with `live/2` routes — and unlike `api_surface/0`'s
boundary-export routes, dashboard's own screens are wholly this system's:
no other component needs to declare a LiveView route, so there is no
cross-component registry to design here, only an ordinary router naming
`event-log`, `explain-why` and whatever v1 adds directly
(`systems/dashboard.md`). **That router holds the `compile-connected
--fail-above 0` line, measured rather than predicted.** Phoenix is a
dependency of this tree (`systems/dashboard.md`'s placement bullet has the
detail), and the scratch probe ORC-32 established for exactly this kind of
question — compile it, uncommitted, read the gate, discard it — has been
run: a router carrying

```elixir scope "/", CatapultWeb do pipe_through(:browser)
live("/event-log/:project_id", ProbeLive, :index)
live("/explain-why/:project_id", ProbeLive, :show) end ```

compiles with `mix xref graph --label compile-connected --fail-above 0`
exiting 0 — the graph is empty — and `mix xref graph --label compile
--source lib/catapult_web/probe_router.ex` shows the router with no
outgoing compile edges at all, including none to either `live/2` target
module. The mechanism: `live/2` stores its target as data the dispatcher
reads at runtime, the same shape `DispatchPlug` uses over `api_surface/0`
above, not the
`CompositeRouter.router/1`-reading-`__registered_commands__/0` shape that
trips the ratchet. No `Module.concat/1` escape is needed for the dashboard
router, the same way ORC-32 found none needed for its process manager. A
real router that fails to hold `--fail-above 0` is a finding back to the
author, never a self-authorized raise of the number (conventions §2: the
cap lives nowhere a ticket can reach) — the ordinary backstop it is
everywhere else.

**The probe measures the ratchet and nothing else.** It carried no
`Phoenix.Endpoint` and no boundary declaration, and compiled reporting
`CatapultWeb.ProbeRouter is not included in any boundary`. The ratchet
result is about the router's own compile edges and holds regardless of
that gap, but how `lib/catapult_web/**`'s modules register with the
boundary compiler is a separate question this measurement does not answer
— and `mix compile --warnings-as-errors` has the boundary compiler in its
set, so that is a gate of its own, not a loose end the ratchet covers.

## #31

`Catapult.Delivery.Provisioning`'s 502 answers `{"error": inspect(
reason)}` and never raises, and App Platform replaces the body of an
upstream 502 with its own error page, so that reason reaches no caller and
exists nowhere else; five live-suite runs were read as an infrastructure
fault on that basis. Only `:stop` can supply it — `Plug.Telemetry` fires
from a `register_before_send` callback, and `Plug.Conn.send_resp/1` runs
those callbacks before handing the body to the adapter, then replaces
`resp_body` with whatever that adapter returns (verified against
`deps/plug/lib/plug/conn.ex`). Under `Plug.Cowboy` that return is `nil`
(verified against `deps/plug_cowboy/lib/plug/cowboy/conn.ex`), so the
callback is the only point where the body is readable at all — and the
trap is that `Plug.Test`'s adapter returns the body instead, so a test
reading `conn.resp_body` after the fact proves nothing about production.
`:error_rendered` fires before the error response is built and has no body
to give. Neither a `:logger` handler nor a fresh `Plug .ErrorHandler`
feeds it: both would duplicate the rescue-and-classify `render_errors.ex`
already performs for the raising half, and neither sees a response that
never raised at all.

## #32

`Plug.Builder`'s generated `call/2` wraps its plug chain in no `try` of
its own (verified against `deps/plug/lib/plug/builder.ex`), so a raise
inside a function plug — `plug :dispatch_plug`, which runs
`Catapult.Foundation.DispatchPlug`'s `apply/3` dispatch — propagates
unwrapped past every later plug in `CatapultWeb.Endpoint`'s own list,
including `Plug.Telemetry`'s `register_before_send`.
`Phoenix.Endpoint.__before_compile__`'s generated `call/2` catches it on
its bare `catch kind, reason ->` clause rather than the `rescue e in
Plug.Conn.WrapperError ->` one (verified against
`deps/phoenix/lib/phoenix/endpoint.ex`) — that clause only fires for a
raise `CatapultWeb.Router` itself wrapped, and a raise inside a function
plug ahead of the router never reaches it — and that bare clause hands
`Phoenix.Endpoint.RenderErrors.__catch__/5` the `conn` bound before the
pipeline ran, not the one `Plug.Telemetry` registered its callback on.
`[:phoenix, :endpoint, :stop]` fires on `register_before_send` callbacks
attached to the conn that's actually sent; a callback registered on a conn
nothing downstream ever sends is simply never invoked, so `:stop` does not
fire for this path at all — not late, not without a trace, not at all.
`:error_rendered` is fired from `__catch__` itself, unconditionally, so it
is this path's only event and has to be able to create the record alone. A
raise the router itself wraps (`Plug.Conn.WrapperError`, verified against
`deps /phoenix/lib/phoenix/router.ex`) carries the piped conn from inside
the router's own dispatch — by then already carrying `Plug.Telemetry`'s
callback, registered earlier in the same pipeline — so `:stop` still fires
there once `RenderErrors` sends the rendered response; wherever both
events fire, `:stop` arrives first and `:error_rendered` enriches it.

## #33

`Catapult.Delivery.Provisioning.provision/1` answers a `502` when reset or
intake fails (`lib/catapult/delivery/provisioning.ex:82`,
`error_response/3` calling `send_resp` directly, nothing raised) — exactly
the provisioning failure this ticket's own incident names, and one a grep
for raise-shaped call sites (`put_status(5`, `send_resp(5`,
`:internal_server_error`) missed by construction, because it isn't shaped
like the thing the grep was looking for. Naming three strings as a
stand-in for "nothing else produces a 5xx" was the mistake the grep made;
`conn.status >= 500` at the point a response leaves the listener is the
actual predicate. This provisioning 502 never raises, so it is unaffected
by the gap the paragraph above names — `:endpoint, :stop` fires for it
exactly as described — and a future deliberate, non-raising 5xx is fed the
same way this one is, with no diff required to widen anything.

## #34

Widening the feed to arbitrary process crashes is a different, unasked
decision, not a narrower reading of this one.

## #36

Reusing it would be one fewer required-env line, and it is refused on the
same argument that rules out `POOL_SIZE`/`HEALTH_PORT` above: the
provisioning token's name says delivery, because it is delivery's own
secret for delivery's own surface, and gating an unrelated
foundation-owned route on it would be exactly the kind of name a reviewer
can see is wrong the moment the two surfaces' owners diverge. Foundation
already declares its own secrets by its own slug; this is one more.
`FOUNDATION_OPERATOR_TOKEN` has its own entry in `SETUP.md` §2's
required-env manifest, beside `DELIVERY_PROVISIONING_TOKEN`'s.

# Catapult — confirmed non-goals

The negative space, recorded with reasons (v5 §1.1's doctrine, eaten
by us first). Proposing one of these is not forbidden — but per
orchestration's rule, do it knowing you are arguing against a
recorded decision, and say so explicitly.

**Schema** (orchestration's `nonasks` parser). One entry per `## `
heading; `scope:` is the line immediately under it — a blank line
between them makes it prose and the entry silently goes universal.
Scopes are the mutex labels, comma-separated, or `universal`. Everything
above the first heading is preamble and is never inlined into a prompt,
so this note is free. Name every system a refusal touches rather than
the closest one: an extra name costs a pass one paragraph, a missing one
hides the refusal from the pass that would have broken it.

**What belongs here, and what does not.** A refusal about exactly one
system is a standing decision of that system and lives in its
`systems/*.md`, beside the decision it qualifies — where the pass that
could violate it is already reading, and where it cannot drift from the
positive rule it is the negative half of. This file holds the two kinds
that have no such home: refusals every pass must see, and refusals that
span systems, which a per-doc home could only serve by being copied
into each one. That is the whole of the scope line's job. Entries are
still never deleted by a pass; relocating one is an author move, and
the citations that pointed here move with it.

## No self-bootstrap
scope: universal

Catapult is not built from its own doc
graph; orchestration delivers it (v5 §1.3). Reasons: the
self-modification crash risk (a bad deploy bricking the tool that
fixes it), the size mismatch (Catapult is smaller than its target
class, so self-hosting proves little), and the historical fact
that the byte-identity bootstrap requirement is much of why v4
never shipped. The sane residue: Catapult consumes the shared
components as an ordinary library user.

## No absorption of existing codebases
scope: universal

Projects enter as fresh
scaffolds; documentation and tracker history seed the feature set;
code is regenerated. The platform's structure is narrow by design
and existing apps won't conform to it; an absorption mode is a
different product. (Author decision, Polyphony conversation.
Revisit condition: none foreseeable soon — "so far out of scope we
may as well not think about it.") Boundary sharpened at the mocks
pass: user-supplied mocks and design systems enter as **seed
evidence and pinned artifacts** (v5 §4.1, §5.4) — read, rendered,
designed against, never absorbed; business logic still
regenerates.

## No workflow interpreter in the DSL, no bundle-side code, no Turing-complete predicates
scope: system:core_dsl, system:platform_content

(v5 §6, §7.10, §9). The plane's
Commanded aggregates are the semantics; declarations configure
them. Extensions are platform-shipped. This is a correctness
property the scheduler, audit, and security posture lean on.

## No per-project restructuring of the *automation* protocol
scope: universal

(v5
§7.10, §7.16). Projects bind tracker ids and tune marked
thresholds; the agent and queue states, and the graph connecting
them, are platform-fixed, because prompts, plane logic, and shared
vocabulary are all written against them. **Narrowed at §7.16 from a
flat "states and gates are platform-fixed":** review states — the
ones whose only job is routing a human — are *declared*, vary by
ticket type, and default to a UX review and an engineering review.
The entry's stated reason survives the narrowing intact, because
nothing dispatches from a review state and no prompt is written
against one. The admission rule that replaces the flat version:
**a state may be declared iff no plane logic branches on it.** We
fix the shape of the automation, not the shape of the
organization. What stays refused is a project rewiring the
automation graph itself.

## No inbound write path from a mirrored tracker
scope: system:delivery, system:dashboard

(v5 §7.17) — the
live half of the entry above. Mirroring outward is a read model
leaving the building and is safe by construction. Accepting
arbitrary state changes back in reintroduces unmapped states,
last-write-wins and unattributable writes into a system that just
escaped them. Anything inbound is a §7.1 signal, validated like any
other, never a state change adopted on the tracker's word.

## Catapult never executes target-project code
scope: universal

(v4 §A.10.5
carried forward, sharpened): agent runs execute code in their own
CI/runner environments; the plane dispatches and observes but
never runs generated code in-process. The plane's blast radius is
its own.

## No concurrent authoring of artifact bodies
scope: system:engine, system:dashboard

(v5 §7.16).
Narrowed, deliberately, from a former `No multi-writer projects`
entry — **small teams are supported**, and that entry contradicted
both §1's target class ("single-author / small teams") and §2.9's
identity component, which ships orgs, membership, invitations and
roles-as-data. It was inherited from v4 §A.0.1 commitment 4 rather
than decided here, and the narrowing is a reconciliation, not a
reversal. What remains out is what v4 actually carved out: two
people editing the same artifact body under merge semantics the
plane would have to invent. Bodies live in git, PRs already carry
those semantics, and the plane does not grow a second set.
Concurrent *action on the delivery protocol* — several people
holding a sign-off role, racing each other on transitions — is in,
and is optimistic concurrency (§7.16): first writer wins, a stale
`from` is rejected rather than applied.

## No experimentation/percentage-rollout flag machinery
scope: system:substrate, system:platform_content

(v5
§2.10): release flags, ops kill-switches, actor targeting — no
more. Machinery without a customer at this scale.

## No LiveView/React mixing within one frontend target
scope: system:client_ts, system:platform_content

(v5 §1.4):
one product tier, one stack per target.

## No hand-maintained inventories
scope: universal

: no code inventory in systems
docs (the code is the inventory), no hand-written permission
matrices, no hand-written API docs where generation exists.
Documents that mirror code drift silently; every such document is
generated or absent.

## No second home for the reference instance's live facts
scope: universal

App
name, region, public hostname, port, autodeploy, the migrate
PRE_DEPLOY job: `SETUP.md` §2 records them and nothing else
restates them. The README says the deployment exists, that
`/health` is the only served path, and points at §2 — nobody
opens a README to find a database cluster name, so the one home
is the file a reader is already in when the values matter.
(Author decision, ORC-40.) This is the entry above one level up
rather than a case of it: that rule is scoped to documents
mirroring *code*, and these are prose facts about a running
system, but the failure mode is identical and we have first-hand
evidence. ORC-2's README paragraph (`4a4aa91`) sourced the
deployment to `.do/app.yaml` one commit after `b5c878f` deleted
that file — the same paragraph, in its first week, citing
something that no longer existed. The next drift is a hostname or
a port, which a reader acts on. Corollary, and the reason no
check is added: **no doc-lint holding the two files in
agreement.** A lint is what a second copy needs; one home needs
nothing, and these facts leave the tree entirely at
open-sourcing, so the lint would be written to be deleted.
**Amended (ORC-29): the public hostname's home moves, it does not
multiply.** The live suite has to dereference that value and prose
cannot be dereferenced, so the hostname becomes
`config/test.exs`'s `:live_base_url` and §2 names the key where it
used to print the URL. Every other fact in §2 stays put. The
amendment is faithful to the reason rather than the letter: what
ORC-40 was written about is a stale copy nobody checks — a README
paragraph citing a file deleted one commit earlier — and a
hostname the live suite reads at every boundary is checked by
machine once a milestone, going red and naming itself when it
drifts. Prose never had that property. The rule the amendment
keeps: still one home, and a fact acquiring a code consumer moves
to where code can read it rather than getting a copy there.

## No vendored, pinned or freshness-checked copy of the advisory database
scope: system:substrate, system:foundation

(ORC-37). The obvious repair for `mix deps.audit`'s
fail-open — clone `mirego/elixir-security-advisories` ourselves,
assert it is non-empty and recent, fail the build otherwise — makes
us the maintainer of a fork of someone else's mirror of the GitHub
Advisory Database, with its refresh cadence as our build's
liveness dependency. The gate is bought far more cheaply by
sourcing the signal from Hex, which cannot report clean from a
fetch it did not make. Revisit condition: Hex's advisory feed
proving materially behind the GitHub database in practice, which
would be an argument for a real second source rather than for
babysitting this one.

## No removal of `mix deps.audit` now that Hex covers the gate
scope: system:substrate, system:foundation


(ORC-37). Demoted is not deleted: it reads the GitHub Advisory
Database, which is a genuinely different source, and it earned its
place the day it armed by catching the postgrex advisory and
forcing the series bump (ORC-3). Two sources disagreeing is the
condition this ticket made legible, not a defect to resolve by
dropping one until the Hex feed is shown to dominate it.

## No `:live` tag on a test that doesn't cross a real network boundary to a real external system
scope: universal

(ORC-29). The tag buys a seat
in the once-per-milestone suite and nothing else, so a `:live`
test that exercises the health plug in-process — or over a
listener this same job started — reproduces the empty gate this
ticket was filed about, one level in, and worse: `no-tests` at
least says nothing was checked, where a green run over a local
fixture claims the world was. If a test needs no deployed thing,
it belongs in the default suite, where its determinism is an asset
instead of a disguise.

## No `test/live/` directory
scope: universal

(ORC-29). Live tests sit beside the
system they exercise, under that system's file map, and the tag
alone decides the cadence. A directory is a second axis that can
disagree with the first, and one directory holding every system's
live tests would give a single file map a veto over every system's
tickets — the mutex collision the maps exist to prevent.

## No polling or retry-until-deployed in the live suite
scope: universal

(ORC-29).
Deploy detection is the plane's job and already exists (poll the
App Platform API, compare SHAs). A live check that waits out a
rollout is a second, slower deploy detector, and its long timeout
is exactly where a real outage hides. A bounded per-request
timeout is the whole budget.

## No asserting the deployed SHA equals this checkout's
scope: universal

(ORC-29).
Autodeploy fires on the merge to main and the boundary run follows
within minutes, so equality races the rollout and produces a flake
— and a flaky boundary signal costs more than the coverage it
would buy, which is the failure mode ORC-29 exists to stop. Assert
the SHA is stamped (not the `"dev"` fallback), which catches the
real defect — an image that never went through the build path —
without racing anything.

## No argv-sniffing in the `test` alias
scope: universal

(ORC-29). The tempting
version notices `--only live` and skips `ecto.create`/
`ecto.migrate` so the live-suite job needs no database, saving an
author-owned workflow edit. Rejected: that alias is what makes
`mix test` correct for every other run in the repo, and a version
that drops migrations on the strength of a flag fails silently and
in the one direction that matters — a suite passing against a
stale schema. The job gets CI's environment instead; the edit is
cheap and it is visible.

## No config-library dependency in `components/substrate/`, Vapor included
scope: system:substrate, system:foundation

(ORC-4). This is the third entry of the same shape and
the shape is now the rule: substrate is Apache-2.0 and ships into
every generated project, so a dependency it declares is one imposed
on trees we do not own. The measurement, because this one was an
open question rather than an instinct: `vapor 0.10.0`, released
2020-08-12 and the newest there is, declares `jason`, `norm`, `toml`
and `yaml_elixir` as ordinary runtime dependencies, so it would put
a TOML parser and a YAML parser into every generated release in
order to read environment variables — against three runtime
dependencies in substrate today. What remains of Vapor once the
casts, the aggregation, the store and the provenance keying are ours
(`systems/substrate.md` argues each) is `System.get_env/0`, so
substrate ships an environment source with no dependencies and the
plane runs that same source. **Not a ban on Vapor**, which is still
conventions §1's blessed answer and is still what a project reaching
for file, remote or non-string config should adopt — a ban on
substrate being the thing that decides that for everyone. Revisit
condition: config the environment genuinely cannot carry, in the
substrate itself rather than in one consumer, at which point the
port takes an adapter and this entry is what gets argued with.
**Sharpened at the second pass (ORC-4), because "the port takes an
adapter" was doing too much work:** the port's domain is flat,
string-valued named settings arriving over a transport other than
the environment, and that is what an adapter is for — a mounted
secrets file, a remote parameter store. A *structured* document,
with nesting and lists of maps, is not a config source in this
sense; it is content, and it belongs in `config/*.exs` or a real
document loader. Vapor is the right answer on that side of the
line and this port is the wrong one, so the revisit condition
splits: flat settings from a new transport are an adapter, and a
structured document is not a reason to argue with this entry at
all — it is a different problem that never wanted the config layer.

## No runtime reconfiguration
scope: system:foundation, system:substrate

(ORC-4). Config is read once, before
the root supervisor starts, and does not change until the next
boot: no watcher, no reload signal, no swapping a value on a running
node. Reason: a value that can change under a running process is a
value every reader must re-read and no reader can hold, which is a
distributed-systems problem bought in exchange for redeploying —
and this platform's deploy model is one environment, autodeploy on
green, so the redeploy is the cheap thing here. It is also the same
boundary the flag-machinery entry above draws: the cases that
actually want live change are kill switches and rollouts, and those
are named non-goals, not features waiting for a config watcher.
Load-once is what makes `:persistent_term` correct and what lets the
boot report be the only report. **Amended at the second pass (ORC-4)
with where the cost actually sits,** since design review asked what
happens if a remote source ever wants watch semantics: not in the
port. `Config.Source.load/2` is a pull, a remote fits it unchanged,
and push would arrive as an `@optional_callbacks watch: 2` that the
shipped sources decline — one module and one line. The reason this
entry stands is the *accessor*: a value that can change is a value
no caller may hold, and holding it is what `:persistent_term`
write-once buys. Whoever argues with this line is therefore arguing
for a re-validation path that can reject an update without killing
the node, a rule for readers holding stale values, and atomicity
across values that must change together — three decisions, not a
callback. Naming them is the point: the port stays cheap to grow so
that the expensive half is the half being debated.

## No `docs/0` callback, and no `cli/0` row in the roster yet
scope: system:foundation, system:substrate


(ORC-22). Both are named in v5 §2.2 and both are deliberately
outside the registry roster, for different reasons. `docs/` is a
directory whose path derives from the slug (conventions §3): there
is nothing to declare, nothing that can collide, and a callback
returning a path the spine already fixes would be a derivation
written twice — the failure the spine table exists to prevent.
`cli/0` is `api_surface/0`'s shape with an escript composer instead
of a router, and it stays out on a narrower argument than the one
this ticket is built on: the retrofit cost ORC-22 pays down is the
cost of components having already declared their names *somewhere
else*, and no component can declare a CLI command anywhere today
because there is no escript to declare it to. Nothing shadows it,
so nothing is being deferred except a table row. Revisit condition
for `cli/0`: the escript, at which point it is one row and this
entry is what says the wait was priced rather than forgotten.

## No `policies/0` scope glob that leaves the working directory
scope: system:substrate, system:foundation


(ORC-22). Absolute paths and `..` segments are a reported problem
in the declaration, not a discipline anyone has to remember. This
is the shape-level guard on the ORC-30 entry above: that entry
stops `mix catapult.audit` from being taught where this repository
keeps its components, and a registration surface accepting
`../../lib/**` would walk the same reach back in through the front
door while the task's own globs stayed innocent — worse, because it
would arrive as customer-authored data rather than as a diff to the
task. Revisit condition: none. A check needing to see another
project is a check registered in that project.

## No default version on an `events/0` entry, and no bare-atom form
scope: system:engine, system:foundation


(ORC-22). The obvious convenience — accept `:project_created` and
mean version 1 — is ruled out here so the next pass does not add it
as an ergonomic win. An unversioned event is the exact state v5
§2.4's upcasting discipline exists to prevent, and a default makes
the *first* version the one fact absent from the diff, which is the
version every later upcaster is written against. The shape is free
to fix now because nothing declares an event until the engine does,
and it will never be free again. Revisit condition: none — this is
the cheap half of the ES cliff, and the expensive half is what
happens if it is skipped.

## No `@optional_callbacks` on the component behaviour
scope: system:foundation, system:substrate

(ORC-22).
Every registry callback keeps an overridable empty default instead.
Incremental adoption is what the default already buys; optional
callbacks buy the same thing and charge the composer a
`function_exported?/3` guard at every call site, so an aggregation
that is total today becomes one that can silently skip a component.
"Declared nothing" and "does not implement" is a distinction with
no consumer, and the composer reporting every problem at once is
the property being protected. Revisit condition: a callback whose
empty default is a *meaningful* claim rather than an absence —
which would be a callback that should have been two.

## No `import Plug.Conn` beside `import Plug.Test` in a test module that calls nothing from it
scope: universal

(ORC-38). The deprecation being paid
off names its own replacement — "Please use `import Plug.Test` and
`import Plug.Conn` directly instead" — and `Plug.Test.__using__/1`
does expand to exactly those two lines, so the mechanical
translation is the one the compiler asks for and the one the next
pass will reach for. It is wrong at both call sites here: neither
health test calls a `Plug.Conn` function — they build a conn with
`conn/2` and read `status`, `resp_body` and `halted` off the struct
— so the second import is unused, and Elixir says so, in the same
place and at the same volume (`warning: unused import Plug.Conn`,
measured on both files before this was written). A warning traded
for a warning delivers nothing of what the ticket was filed for,
which was the recurrence and not the deprecation. The rule, stated
once so it survives the next test file the compiler gives the same
advice to: translate the `use` into the imports the module actually
exercises. Today that is `import Plug.Test` alone, and both suites
then run warning-free. Revisit condition: none, and none is needed
— a test that calls `put_req_header/3` or any other `Plug.Conn`
function adds the import as an ordinary consequence of using it,
and this entry is only the reason it is not there before then.

## No Credo-hosted platform checks, and no Credo in a generated tree
scope: system:substrate, system:foundation

(ORC-21), against v5 §2.14, which adopted "AST-grade custom
Credo checks" by name. The grade is adopted; the host is not, and
the reason is mechanical rather than preferential. `Credo.Check` is
a `__using__` macro, so a check module compiles only where Credo is
loadable, and Mix loads a dependency's own children with
`env: :prod` (`Mix.Dep.Loader`) — so substrate's `only: [:dev,
:test]` Credo never reaches a consumer, and a check shipped in
`lib/` would fail to compile in every tree that adopted it. Buying
the host means either a Credo dependency imposed on trees we do not
own — the fourth entry of that shape in this file — or a fourth mix
project and a second package on the release train, and both are
spent on IDE surfacing. `policies/0` + `Catapult.Audit.Check` is the
inheritance mechanism, it shipped in ORC-22, and a second one would
give `catapult:allow` two implementations. Revisit condition, and it
is cheap by construction: a project that wants editor surfacing
writes a `Credo.Check` delegating to `run/1`. That is a wrapper, in
the project that wants it, and no check logic moves — which is why
the report format (`path:line: message`) is part of the contract.

## No compile-connected cap anywhere a ticket can edit it
scope: universal

(ORC-21).
Not `config/*.exs`, not a module attribute in the audit, not a
checked-in baseline file: `mix xref graph --label compile-connected
--fail-above N` is stock and already exits 1, so the only question
is where N lives, and the pipeline answers it. An agent that adds a
compile dependency can raise a cap that sits in the tree, in the
same commit that made it necessary, with a plausible sentence in the
PR body — and a ratchet the ratcheting party can turn is not a
ratchet. `qualityGates` is author-owned, which is what makes v5
§2.14's "may never rise without a reviewed change" literal. The
accepted cost is that lowering it is also an author edit, including
on the runs where a refactor earned the lower number. Revisit
condition: none while agents write the diffs — this entry is about
who holds the number, and that does not change with scale.

## No `system_monitor`-based mailbox guardrail, and no kill grade for a full mailbox
scope: system:foundation, system:observability

(ORC-21), against v5 §2.5's "the BEAM itself
enforces them", which is true of the heap bound and false of the
queue bound. Verified rather than assumed:
`erlang:process_flag(:max_message_queue_len, _)` raises `badarg` —
there is no such flag — and `:erlang.system_monitor/2` is node-wide,
notify-only, and singular, so setting one discards the previous
settings and any dependency reaching for `long_gc` disables our
guardrail without a word. A check whose failure mode is silence is
the shape this repo has already refused twice. The mailbox threshold
is sampled and reported (`systems/observability.md`); killing is
rejected separately and on its own merits, since a process that is
behind is usually the only thing holding the work. Revisit
condition: a per-process, VM-enforced queue bound appearing in OTP —
at which point the field changes grade rather than the decision
changing shape.

## No taint analysis for secret config values
scope: system:foundation, system:substrate

(ORC-21). v5 §2.2
asks that secret-flagged values never appear in logs or error
payloads, and the tempting reading is a static check that follows a
value from the accessor to a `Logger` call. It is not built: a value
bound to a variable, put in a map, or passed to a helper is out of
reach of any check that is also free of false positives, and a
redaction check that misses is worse than none because it is
reported as coverage. The wrapper type is what holds the property
everywhere at once — a redacting `Inspect`, an explicit unwrap — and
the audit keeps only the exact, one-hop residue: an unwrap inside a
logging call. Revisit condition: none. If the wrapper is ever found
insufficient the answer is a narrower unwrap surface, not a deeper
analysis.

## Licensing subjects are declared, never discovered
scope: system:substrate, system:registry

What gets checked, and under which class, is what a project or
component declares about itself. Nothing is read off the tree, and
nothing is defaulted.

**No check that decides which projects to check by walking paths.** A
task that walks `components/*` knows where this repository keeps its
components, and it ships into customer trees where that glob means
nothing and where a permissive-deps requirement is not Catapult's to
impose. The sanctioned form is a declaration the project makes about
itself — `package: [licenses: [...]]`, checked when it names something
the allowlist contains, inert when it names nothing — read alongside a
component's own `licensing/0` (`distribution:` and `license:`). What
makes that safe rather than merely tidy is that the arming declaration
is one hex already demands: `mix hex.build` refuses a package with no
`licenses`, so nothing that ships can forget it.

**No defaulted distribution class.** The pair cannot be half-defaulted
— there is no license a component "probably" carries, and a defaulted
class paired with an absent identifier makes the component's
self-check a verdict about nothing. The deciding reason is the other
one: a default makes every project's audit print a policy verdict
nobody asserted. An undeclared component is reported instead, at audit
time, alongside every other structural absence.

**The class vocabulary is closed at three** — `:distributed`,
`:service`, `:internal`. The "ours versus proprietary" split the
`:service` rules turn on is read off the declared identifier instead:
SPDX already spells "no listed license applies" as `LicenseRef-<id>`.
A fourth class, or a `proprietary:` boolean riding alongside, would be
a second place to state a fact the identifier already states, and two
places that can disagree is how a check ends up enforcing the wrong
rule with complete confidence. The three describe *how code reaches
people*, which is what obligations key on.

Two rulings about the plane specifically, each decided rather than
derived from the above:

**No `package:` block on the root `mix.exs`, and never one added to
arm the check.** The symmetry with `components/substrate` — which
states `package: [licenses: ["Apache-2.0"]]` precisely *because* that
is the arming — is a trap. Adding one beside the plane's policy makes
`subjects/1` count the project itself as a `:distributed` subject,
arms the entire plane closure, and fails on exactly one dependency.
One override line from green is what makes it dangerous; a wall of
failures would have been self-correcting. And what the block asserts
is false: `package:` means somebody fetches this, and the plane is
published nowhere.

**No `:internal` class for the plane.** The reading that gets there is
not silly — the plane conveys nothing and we operate it — so it is
refused in writing. The plane is reached over a network by people who
are not its operator, which is the sole case `:service` exists to name
and the entire reason `LICENSING.md` chose AGPL-3.0-only over plain
GPL: §13 is the provision that makes copyleft mean anything for this
shape of program. Declaring `:internal` would assert that §13 does not
reach the one program it was chosen for.

Revisit conditions: for the class vocabulary, a real licensing
consequence that turns on something other than conveyance, network use
or neither — a fourth way code reaches people rather than a fourth
adjective for the same three. For the plane's `package:` block, the
plane genuinely being published as a package, which would be a
different product than `LICENSING.md` describes.

## The check infers nothing beyond the identifier
scope: system:substrate, system:registry

Two questions are asked about an identifier — is it spelled
`LicenseRef-*`, and is it on the project's list. Nothing else is
inferred, in either of the two directions that tempt.

**No classification of an identifier as copyleft.** There is no third
bucket and no small table of copyleft identifiers to produce one. The
residue of a project-stated list is not copyleft; it is whatever that
project did not write down, and reading it as copyleft leaves the tree
**unchecked** — an inference in the permissive direction, the one
direction this check may not fail in. Conveying under copyleft
deliberately is still expressible and better expressed: put the
identifier on the project's own list, and dependencies are checked
against a list containing it, which catches `GPL-2.0-only` inside an
`AGPL-3.0-only` work.

**No per-component attribution of dependencies.** The check does not
try to work out which component pulled `plug` in; a project's policy
is the strictest among every subject it composes. mix has no
per-component dependency declarations, so any attribution would be a
call-graph guess made offline, and its errors would run permissive
too. The shared-tree fact is also simply true: every dependency in a
project is available to every component in it, whatever brought it in.

Revisit condition: a real per-component dependency declaration in the
language, which is not a thing mix has and not a thing to build here.

## No per-file license headers, for now
scope: universal

Deferred at ORC-16, carrying the ticket's own deferral so it is not
re-proposed as the obvious adjacent win. The inventory check answers
what the *dependencies* impose; what carries attribution for our own
files — headers in every source file, or a `NOTICE` file at each
project root — is a separate decision with a real cost either way,
and taking it now would mean stamping thousands of lines against a
posture counsel has not reviewed. Revisit condition, and it is dated
rather than open: the repository opening to outside contributions,
which is when `LICENSING.md`'s `LICENSE` texts and CLA land and when
the attribution question has to be answered anyway.

## No licensing verdict at boot, and no allowlist inside the composer
scope: system:foundation, system:substrate

Decided at ORC-16. The composer validates that `licensing/0` is
well-formed, exactly as it does every other declaration and for the
same reason (it needs no environment); it never holds the allowlist
and never decides whether a license passes. Reason: the composer runs
at boot as well as under the audit, so an allowlist there means a
production node refusing to start because a transitive dependency's
license string is unrecognized — a catastrophic response to a
question with no runtime consequence at all. The severity that fits a
legal fact is CI red. This is not a claim that the check is
unimportant; it is a claim that the failure has to land where a human
is already reading, not where a deploy is already halfway out.
Revisit condition: none. There is no license question whose answer
changes what a running node should do. (The check does not hold the
allowlist either, for an unrelated reason — see "The license check has
no escape hatches" above. The composer does not hold it because it
runs at boot; the check does not hold it because it ships into other
people's projects.)

## No `licensing/0` row in the registry roster table
scope: system:registry, system:substrate

Decided at ORC-16 against the obvious consistency argument, and this
entry exists because that argument is a good one. The table is one
row per *name-claiming* registry, and its `:claim` and `:identity`
columns are the reason it exists: two components declaring
`Apache-2.0` is the ordinary case rather than a collision, so a
licensing row would carry two empty columns and the fold over
`rows/0` would need to skip it — the `function_exported?/3` guard
the no-optional-callbacks entry refused, arriving as a table row
instead of a callback. The shape does not fit either: a keyword list
*is* a list of two-tuples, so a table-driven aggregator reads one
declaration as two entries. It sits beside `config/0` on
`config/0`'s own recorded criterion — a consumer, and error messages
worth their specificity. Revisit condition: a second declaration of
this shape, at which point the argument is for a small table of
component-scalar facts and never for folding them into the claims
table.

## No dataflow inference for a computed config key, and no reading a dynamic `fetch!/2` as a wildcard
scope: system:foundation, system:substrate

(ORC-48). The declared↔read check
joins two literal atoms — the accessor's own slug and key — and a call
it cannot join is reported at its call site rather than resolved.
Chasing the value of a variable back to its binding is the shape the
secret rule already refused one registry over, for the same reason: a
shallow analysis pretending to be a guarantee. The cheaper alternative
is the one worth naming, because it is what the next pass will reach
for — treat `fetch!(:foundation, key)` as reading *everything*
`:foundation` declares, so nothing false-positives. That is a whole
slug's worth of coverage switched off by a call that says so nowhere,
in a check whose entire subject is dead declarations; the silence is
the defect, not the strictness. Reporting the unjoinable call keeps
the run red and names the cause, which is the same trade as reporting
an unparseable file instead of skipping it. Revisit condition: a
legitimate computed read, which would be an argument for a second
accessor that declares what it may reach, never for the check
guessing.

## No `catapult:allow` escape on either direction of the config declared↔read check
scope: system:foundation, system:substrate

(ORC-48). `Catapult.Audit.Declarations` already
refuses the tag for what it reports — the escape excuses a *line* the
parser found, and a dead declaration is the absence of one — and the
unjoinable-read direction does name a line, so the exception has to be
refused on its own merits rather than inherited. It is: an allow tag
on an unjoinable read would silently re-arm the false-dead report the
suppression exists to prevent, so the tag would quiet one line by
making another line lie, and the lying line's advice is *delete this
declaration* against a value the boot requires. Both remedies are one
line and always available — delete the declaration, or spell the key —
which is the condition under which this repo has consistently declined
to build an escape. Revisit condition: none. An escape here is a way
to keep dead configuration forever, which is the thing being checked.

## No reader-identity rule on config reads — the check does not police *who* reads a key
scope: system:foundation, system:substrate

(ORC-48), against ORC-4's own phrasing ("a
component reading a key it did not declare"), narrowed out loud rather
than quietly. Two reasons, and the second would stand alone. The
mechanical one: deciding that a call site belongs to a component means
a path→component map inside `mix catapult.audit`, which is the layout
knowledge this file refuses at that task's front door — worse here
than in the `components/*` case, because a generated project's spine
puts its components wherever it likes and the map would be wrong
rather than merely absent. The substantive one: `Catapult.Config
.fetch!/2` takes a slug *precisely* so a reader can name a value it
does not own, `Catapult.Repo` reading `:foundation`'s database URL is
the tree's own example, and whether a cross-component read is
acceptable coupling is a boundary question with a boundary compiler
already answering it. The check keeps the half that is a registry
fact: a key nobody declared. Revisit condition: none foreseeable —
ownership of a *call site* is not a fact the config registry holds.

## No exemption list on the boundary-apps check — no ignore entry, no `catapult:allow`, no per-application waiver
scope: system:foundation, system:substrate

(ORC-50). Three kinds
of application are outside the completeness requirement and every one
of them is *derived*, so no name is written and none can be spent:
`:boundary` itself (`Boundary.Checker.check_external_dep?/3` opens by
excluding it), applications contributing no `Elixir.*` modules
(`Boundary.Mix.app_modules/1` filters them out, so no list entry can
restrain a call into one), and path deps (read off `:path` in the dep
options; naming one reproduces ORC-21's defect at twelve forbidden
references and a red build, measured). This is the same line ORC-16
drew for licenses: nobody imposes a dependency on us, so the fix for
an unchecked application is naming it, and a waiver could only ever
be spent restoring the fail-open the check exists to close. Revisit
condition: none. A fourth exclusion would have to be a fourth
*mechanical* fact about what Boundary can restrain, discovered the
way these three were, and it would arrive as a derivation rather than
as a list.

## No destination-detecting model-call check — nothing reads a URL, a hostname or a provider name out of an HTTP call's arguments
scope: system:substrate, system:generation, system:llm


(ORC-52). The sentence this ticket retired promised "an audit check
for the Erlang ones", and the natural reading is a check that finds a
*model call*. It is refused because it cannot be built honestly: at
AST grade the call is `:httpc.request(:post, {url, ...}, [], [])` and
whether `url` reaches a model provider is data, decided at runtime and
normally read from configuration. Matching a provider hostname in a
literal catches a spelling nobody writes and reports clean on every
real instance of the thing the check is named after — a check that
passed without checking anything, which is what this ticket was filed
about, reintroduced by its own fix. Chasing `url` back to its binding
is the third request for dataflow inference in this file, and it gets
the answer the secret-taint entry and the computed-config-key entry
got: a shallow analysis reported as a guarantee is worse than a stated
gap. What is built instead bans the *transport* — no plane module
calls a pure Erlang HTTP client (`systems/foundation.md`) — which is
decidable, broader than §11, and exact. Revisit condition: none. The
destination is not a static fact and no amount of check will make it
one.

## No catalogue of the ecosystem's HTTP clients to close the Elixir half
scope: system:substrate, system:generation

(ORC-52). `check: [apps: [...]]` checks the applications it
names, so an Elixir HTTP client added as a dependency is unchecked
until it is named there — a real residue, corrected into
`systems/foundation.md`'s sentence rather than left implied. The
tempting closure is a check that knows `:tesla`, `:finch`, `:mint`,
`:httpoison` and the rest, reports one present in the closure and
absent from the list, and it is refused: its coverage is a list of
the world maintained by us, its failure mode is silence for every
client not on it, and silence is what this ticket was filed about. The
existing mechanism is better than the check would be — an Elixir
client cannot be called without being a dependency, a dependency is a
§2.8 named decision visible in the same diff, and the `check:` line
belongs in that diff. Revisit condition: none. This is the one half of
§11's enforcement where the thing being added announces itself.

## No `domain_parent` replacement edge in the default bundle's architecture chain
scope: system:platform_content, system:core_dsl

(ORC-84). v5 §4.1 replaces v4's domain/
presentational split — and `domain_parent`, the edge that let a
presentational comp read its domain parents' fan-in synthesis — with
the product/backend/frontend tier split; this ticket's chain is
backend-only, so nothing in its scope consumes a parent-link edge.
The tempting move is inventing one anyway "for symmetry" with v4's
five named edges. Refused: a frontend or product-tier parent-link
edge, if the eventual Phase 5 frontend architecture needs one, is
that phase's decision to make against tiers that actually exist by
then, not a placeholder wired against nothing today. Revisit
condition: Phase 5's frontend/product tiers landing with a real need
for a structural parent-link back to a backend component — at which
point the edge is argued against real consumers, not guessed at.

## ~~No `per(scaffold_tier)`-style flow planning-tier fan-out~~
scope: system:platform_content, system:core_dsl

**Reversed** (ORC-84, design review). The original entry recorded
`singleton`-scoped planning tiers as the answer, reasoning that v5's
closed scope set had no way to express "one node per node the
cascade visits" and that inventing one was `core_dsl` vocabulary
growth outside a content-porting ticket's remit. Design review named
this the wrong move in as many words: "a missing DSL construct is a
`docs/dsl-syntax.md` proposal, not a reason to ship the bundle
without the capability" — the same instruction this ticket already
gave for `mint.<name>`, generalized. `docs/dsl-syntax.md` §3.1 now
declares `cascade_visit`, a fourth scope kind ("one node per node a
flow's own cascade walk visits"), and every planning tier
(`tiers/*_plan.yaml`) uses it. The revisit condition in the original
entry — "a real cascade-position tier construct landing in the core
DSL" — is what happened; the entry stays as the record that the
first answer was wrong and named its own correction condition
accurately, not as a decision still in force. `edges/plan_target.yaml`
(a `type: synthesis` edge, dsl-syntax.md §4.1's `instances:` form)
supplies the plan→target pointer design review also asked for; its
own header names the reasoning. See also the `ticket.findings` entry
below this one, added the same pass — a still-open gap in the same
neighborhood, argued rather than routed around.

## No two-stage `assessment_plan` + `propagation_plan` split for `upward_propagation`
scope: system:platform_content, system:core_dsl

(ORC-84), against v4's own shape
(`catapult-default-bundle-v4-examples.md` §2.5). Sequencing two
flow-scoped planning tiers — open the downstream one only after the
upstream one's regeneration lands — needs instance-level flow state
(has the upstream stage closed yet) that this ticket's own stated
scope excludes ("projection-time instance checks" is out of scope).
One combined `upward_propagation_plan` tier stands in for both.
Revisit condition: flow instance state becoming a real, checkable
loader or engine concept — at which point the two-stage split is
worth relitigating on its own merits, not smuggled in under a
content port.

## No `fragments.yaml` or `plan.yaml` as separate bundle files
scope: system:platform_content, system:core_dsl

(ORC-84), against this same ticket's own Layout section, which names
both. Filed as a pipeline finding rather than quietly followed:
`Catapult.Dsl.Manifest` (the merged ORC-5 loader) reads `fragments:`
as an inline list inside `bundle.yaml` and has no parser for a
standalone `fragments.yaml` at all; `plan.yaml` has nothing left to
declare once v5 §6 drops the phase machinery it existed to compute,
and `dsl-syntax.md` §1's own canonical tree does not list one. The
loader as merged wins over the ticket's file list, per the same rule
that governs every other doc-vs-doc disagreement in this repo.
Revisit condition: none foreseeable for `plan.yaml` (there is no
phase concept left to give it content); for `fragments.yaml`, only a
future loader change that adds a standalone-file parser for it.

## ~~No context walk wiring "policies applied to me through my responsibilities" onto `comparch`~~
scope: system:platform_content, system:core_dsl

**Reversed** (ORC-84, design
review). Same shape as the `cascade_visit` reversal above and the
same review comment: recording the gap and calling it `core_dsl`'s
to invent was the wrong response to a missing construct, when the
right one — already demonstrated by `mint.<name>` — is proposing the
syntax. `dsl-syntax.md` §7.1 now allows a context walk to chain more
than one hop and to reverse a hop (`.<edge>~`, walker matches the
edge's `target` instead of its `source`); `comparch.yaml` wires both
the direct grain (`self.parent.policy_application~ -> policy.handle`)
and the through-responsibility grain
(`self.parent.fulfills.policy_application~ -> policy.handle`), and
§9 gains the rule that two entries landing on the same target tier
combine into one collection rather than colliding. The mechanism
needed no new edge: `policy_application`'s existing two instances
(policy→comp, policy→resp — dsl-syntax.md §4.1) already carry both
grains in the declared direction; reversal is a read-time walk
operation over them, not a new graph edge, so the type-level
acyclicity check (§13) sees nothing new. This entry stays as the
record of the wrong first answer, per this file's own discipline —
see the `cascade_visit` entry above for the fuller version of that
reasoning, which applies here unchanged.

## `edges/` is six files, not the five this ticket names
scope: system:platform_content

(ORC-84,
design review). Design review's remaining complaint — "still 14
files... it should just be done" — is addressed by
`dsl-syntax.md` §4.1's new `instances:` form: one edge name now
covers every site sharing its mechanism (`decomposition` folds in
six former fanout files — the three the ticket's own text names
plus `resp`'s and both of `policy`'s mint sources, since "the
mechanism is the same" argument the ticket makes for the first three
applies identically to the rest; `dependency` folds in two;
`policy_application` folds in two), landing at six files:
`fulfills`, `dependency`, `decomposition`, `policy_application`,
`reference`, `plan_target`. Two are not among the ticket's named
five. `reference` (comparch/subcomparch/impl attaching a `ref`) was
never named — the ticket's five-edge list is `fulfills`,
`dependency`, `domain_parent`, `decomposition`, `policy_application`,
and ref attachment is structurally none of those: not a mint
(`decomposition`'s sites are all fanout), not the comp↔resp binding
(`fulfills`), not a policy scope grain (`policy_application`).
Folding it into any of the other four to hit the literal count would
misname the mechanism rather than honor it, which is the actual
instruction in "the mechanism is the same" — same mechanism, one
name; different mechanism, a different one, whatever the count comes
to. `plan_target` is new — see the `cascade_visit` entry above; a
flow's planning tier needs a live pointer to what it's planning for,
which is a fact this ticket's redirect explicitly asked to be
fixed, not a fact the original five could be stretched to carry.
Revisit condition: none — this is the honest count once "same
mechanism, several sites" is applied consistently rather than
partially, not a target still being chased.

## No `ticket.findings` wired onto any planning tier
scope: system:platform_content, system:core_dsl

(ORC-84). Every
`cascade_visit`-scoped plan (`tiers/*_plan.yaml`) wants the ticket's
own prose — a feature request's description, a defect report's
observed/expected behavior — and `dsl-syntax.md` §7 already
documents `ticket.findings` as exactly that: "validation findings +
ticket thread for the scope, available to flow planning tiers only."
Wiring it was tried and reverted for a reason distinct from the two
reversals above: this is not a missing *grammar* construct
(`ticket.findings` already parses and is already spec'd) but a
missing *registration* — it is an extension-provided context source
(§12), and `lib/catapult/dsl/dialect.ex` says outright that neither
the `design` nor `runtime` dialect registers any extension yet
("context sources arrive with the delivery system... a promise that
they are populated today" is the one this file's own words deny).
Declaring it in a tier's `context:` fails load with "which is not
installed" — measured, not assumed. Unlike `cascade_visit` and the
reversed hop, there is no syntax to propose here: the syntax exists
and is correct; what's missing is a platform module implementing
`Catapult.Dsl.Extension`'s `context_sources/0` callback and
registering `"findings"`, which is `core_dsl`'s delivery-system
milestone (`systems/core_dsl.md`'s Initial vs Target split) — plane
extension code, not bundle content, and squarely outside what a
content-porting ticket may build unprompted (the same boundary that
keeps this ticket from writing the engine that actually walks a
cascade). `input.project_doc` — the frozen original intake — is what
every plan tier reads instead today; it is not the flow's own new
prose, and every plan tier's `context:` says so in a comment rather
than silently standing in for it. Revisit condition: the delivery
system's context-source extension landing, at which point this is a
one-line addition to five already-shaped `context:` lists.

## No ownership-vocabulary-leak self-check or domain/presentational decision test carried into `sysarch.md.liquid`
scope: system:platform_content

(ORC-84, rework). Siege's sysarch carries two techniques alongside the
domain/presentational subject matter the `domain_parent` entry above
already voids: a **decision test** ("if you deleted this component,
would the system lose state or business logic, or a way to expose
state/events to outsiders?") for sorting a component into `<kind>`,
and a **self-check** for `<owned-invariants>` / `<primary-operations>`
text that watches for ownership words (`persist`, `atomically`,
`commit`, `transaction`, `event log`, `consistency`, `concurrent
write`) leaking into a presentational component's contract, on the
theory that vocabulary belongs on the domain parent instead. Both are
void for the same reason the `domain_parent` edge is, not a separate
one: each technique's whole logic depends on two components sharing
one graph with two different vocabularies — one that owns state and
one that fronts it to outsiders — and this ticket's chain has only the
first. There is no presentational component anywhere in scope for
either technique to sort into or police against.

The named anti-pattern list and the wrong/right worked-example pairs
generalize past the void and are ported into `sysarch.md.liquid`'s
naming and purpose rules, because a generic shell name and a purpose
that parrots a larger scope are naming and framing failures any
component can commit, backend or not. These two techniques don't
generalize the same way: a decision test needs two categories to sort
between, and a vocabulary-leak check needs a *different* component's
contract for the vocabulary to have leaked from. Comparch's
subcomponents don't have that split either — they divide along
data/operation seams (writer / reader / cache) that are all equally
"domain" in v4's vocabulary, so a subcomponent's invariant claiming
"commits atomically" is never leaking someone else's ownership
vocabulary, because there is no non-owning role for it to have leaked
from. Inventing a same-shaped check there would be a plausible-sounding
guess, not a port — no tier in the current chain has the two-sided
structure either technique is checking, and comparch.md.liquid already
carries its own, stronger mechanisms for the underlying worry (a
subcomponent's contract text making a claim it doesn't back): "Names
create semantic obligations" and the "Rationale, not inventory" final
scan both catch category-speak and unbacked claims without needing a
presentational/domain split to check against.

Revisit condition: the same one the `domain_parent` entry above names
— Phase 5's frontend/product tiers landing with a real backend/frontend
split at some tier. At that point both techniques have a concrete site
again (a frontend-facing tier classifying against its backend
counterpart, and that tier's contract text needing a check against
backend-ownership vocabulary leaking in) and are worth porting on
their own merits, not guessed at now against a split that doesn't
exist yet.

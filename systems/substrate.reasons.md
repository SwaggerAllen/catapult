# substrate — reasons

The reason behind each rule in `systems/substrate.md`, keyed by the rule's id (orchestration's DESIGN §4). Read one with `pipeline reasons substrate#n` before changing the rule it belongs to.

## #4

Rationale: the audit grows for the life of the platform; a registry grows by entries, a monolith by
merge conflicts.

## #6

Plural, and not `Catapult.Component.Registry`, because the singular reads as the artifact registry
this repo also has a system doc for.

## #7

Without that line a roster ticket produces, in its own design doc, exactly the hand-maintained
mirror the roster exists to make unnecessary.

## #8

No component can declare a CLI command anywhere today, because there is no escript to declare it to,
so nothing shadows it and nothing is deferred except a table row. The escript's arrival is what adds
that row.

## #9

This is where §4.4's literal `{exported_function, path, verb, version, audience}` gets respelled
rather than transcribed: the same five facts as `{{fun, arity}, verb, path, opts}`, verb and path
adjacent because that is how every router in the language spells a route and the composition that
will consume this is a mechanical transform of that pair.

## #10

Making `events/0` breaking costs nothing today and could never be done cheaply again — nothing
declares an event until the engine does. That is the roster-before-consumers argument arriving as a
concrete saving rather than a principle.

## #11

The sketch above drew `cron: :string` and the composing half is what showed it under-specified:
`Oban.Plugins.Cron` takes `{expression, worker}` or `{expression, worker, opts}` (verified against
`oban 2.20`'s `validate_crontab/1`), and a worker's queue comes from its own `use Oban.Worker`. So a
schedule names *what* runs and the queue is downstream of that — one string on a queue entry can say
when but never what, and one queue hosting two periodic jobs cannot be spelled at all. The entry
becomes `{:engine_work, cron: [{"0 * * * *", Engine.SweepWorker}]}`: the queue stays the claimed
name and the address, the schedules ride as policy about it, which is the row grain rather than an
exception to it. It buys a cross-fact worth checking, too — a scheduled worker whose own `queue:` is
not the entry it was declared under is a job that will run somewhere nobody declared. Free to fix
here for the same reason `events/0` was: nothing declares a queue yet, and a wrong shape is only
cheap before it has entries.

## #13

Nobody imposes a permission atom, a queue name or an error kind on us; a registry that offered the
escape anyway would be offering a way to turn its own check off, which is the state the flag was
invented to avoid. Arming queues and telemetry, which never had the check, belongs in this ticket
for the same reason `events/0`'s shape change does: nothing declares either yet, and the check is a
table column.

## #18

That is a claim about routes rather than about a router, which is what makes it safe to hold here
while the composition that consumes it waits for a web layer.

## #19

Catapult will register none of these — its per-component admin surfaces are subsumed by the
dashboard (conventions §13) — which makes this the roster's clearest case of a registry whose first
consumer is not this repo, and a standing reminder that shipped substrate is not measured by what
the plane happens to use.

## #20

The gate-set decision below rules out teaching `mix catapult.audit` where this repository keeps its
components, and a registration surface that accepted `../../lib/**` would walk that reach back in
through the front door while the task's own globs stayed innocent. Each mix project composes its own
check set and runs the audit in its own directory; registration composes checks without touching
that, which is the product-facing payoff — the ES family's purity floor travels with the ES family
instead of being re-wired per project.

## #22

A registry aggregating into nothing is this ticket's deliberate state, and that state's failure mode
is not collision but rot: twelve registries nobody looks at between now and Phase 3. One census line
is the cheapest thing that makes an empty registry a fact somebody sees, and it keeps the inventory
surface from being the one unconsumed registry itself — the recursion a mechanism-only ticket opens
the moment nothing reads its output.

## #23

Incremental adoption is what the default already buys. An optional callback buys the same thing and
charges the composer a `function_exported?/3` guard at every call site: an aggregation that is total
is one that cannot silently skip a component, and "declared nothing" versus "does not implement" is
a distinction with no consumer.

## #24

This is what makes the registry load-bearing rather than descriptive: today the values are read ad
hoc from application env and nothing anywhere notices two readers of one variable disagreeing about
its meaning.

## #25

The flag earns its place by making the two cases distinguishable: without it every off-spine name
looks like sloppiness and the check has to be turned off to accommodate the one case that is not.
With it, the audit stays armed and the exceptions are a grep. What it does not do is confer
permission — an `external: true` on a name nobody else imposes is a lie a reviewer can see, which is
the most a declaration can offer.

## #27

Inert data is readable by the audit, by the composer's collision check, by the settings surface v5
§7.10 will need and by a human reading a diff; a callback returning a library's structs is readable
only by that library, and swapping the library then means editing every component instead of one
adapter.

## #28

Keeping them separate is what lets the build-time half be exhaustive instead of best-effort.

## #29

An invalid-value message that quotes the value it rejected publishes a malformed secret into the
boot log of the failing deploy, which is the log everyone then pastes into a ticket. `secret:
true`'s audit-checked ban on secrets in logs and error payloads (v5 §2.2) starts here, in the first
error payload the platform can emit, and it costs nothing to hold for every value rather than only
the flagged ones — the operator needs to know *which* variable and *why*, and already has the value.

## #30

Writing the values into application env would be more inspectable, and that is exactly its defect:
it leaves the old door open, and `Application.get_env` on a component's value would remain correct
forever, so the ad hoc reading this layer exists to end would end only by convention.
Write-once-at-boot is also the access pattern `persistent_term` is for. The accepted cost is that
values are not visible from a remote console without calling the accessor.

## #31

A value that can change under a running process is a value every reader must re-read and no reader
may hold — a distributed-systems problem bought in exchange for redeploying, and this platform's
deploy model is one environment with autodeploy on green, so the redeploy is the cheap thing here.
It is the same boundary the flag machinery is refused at (`docs/non-goals.md`): the cases that
actually want live change are kill switches and rollouts, which are named non-goals rather than
features waiting on a config watcher. Load-once is also what makes `:persistent_term` correct and
what lets the boot report be the only report.

## #32

The slug is the spine every other claimed name hangs off (conventions §3) and the composer already
fails the build on two components sharing one, so it is exactly as unique as the module and shorter
to read. It also keeps the accessor from putting a component module into the caller's module graph,
which is what a keyed-by-module store would have cost: `Catapult.Repo` reading
`fetch!(Catapult.Foundation, …)` closes a cycle through the component that lists the Repo among its
children, and cycles are a hard gate.

## #33

**The shape holds against a file source.** A `Catapult.Config.File` over a flat TOML or JSON
document implements `load/2` as one read, one parse and one `Map.take`, and it fits without the port
bending — because the port never asks it a second question. A `fetch(name)` port would leave that
same adapter three bad options: re-read and re-parse per key (N reads for N declarations, with no
guarantee they saw one document), cache in `:persistent_term` behind the layer's back (a second
store, absent from the report), or become a process whose lifecycle the port's shape does not model.
That is the port that can only ever be env, and `load/2` is the shape that is not it.

## #36

That is precisely where Vapor is the right answer and this port is not, and the non-goal entry is
written to that line rather than to a claim that the port handles everything.

## #37

Vapor's loader `Map.merge`s provider results, so two providers offering one name silently pick a
winner — already the reason it is not a dependency, and it would be no better for being our own
code. The case that would force layering is real, so it is named here to be recognised rather than
rediscovered: secrets from a mounted file, everything else from the environment. When it arrives,
layering is either per-declaration source selection or an ordered list **whose overlaps are a
reported problem** — the discipline the composer already applies to queues and topics, applied to
transports — and never a merge. Until then provenance is trivial: every value came from the one
place, and no report needs a field to say which.

## #38

A remote source (Vault, Parameter Store, Consul) fits `load/2` today, unchanged: one round trip at
boot for every name at once is what a remote is best at, and "unreachable" is exactly the `{:error,
_}` the file source proved was load-bearing. What a remote cannot do through this port is push, and
that limitation is not the port's to fix. Load-once is the rule (above); the thing actually standing
between us and watching is the accessor's contract — `:persistent_term`, written once before the
supervisor starts, read by callers who may hold what they read. A source pushing into a store nobody
re-reads has changed nothing.

So the growth path, named at its real size. The *port* takes it as `@optional_callbacks watch: 2`,
which the environment and static sources decline and the layer guards with `function_exported?/3`:
that part genuinely is one module and one line, and it is the answer to "does the shape fit." What
is not one line is what the accessor then owes — a re-validation path that can **reject** an update
without taking the node down (a boot report may exit; a running node's may not), a rule for the
process holding a value it read a minute ago, and atomicity for two values that must change
together. Four decisions and a supervision tree: a ticket, not a refactor, and nothing in this shape
prejudges any of them. The nearer cousin — a source needing to be a running process merely to
*load*, a remote with a connection pool — is smaller still and changes the call site rather than the
port: the layer would start the source under a bootstrap supervisor before calling `load/2`. One
place, recorded here so it is not met as a surprise.

## #39

Seeding post-cast values would be the obvious convenience and it is the wrong one: it would leave
every declared cast unexercised by every test that is not about casts, which is most of them.

## #42

`test/support` is compiled only in this project's test env and is absent from the hex tarball, so a
fake living there is a fake every generated project has to write again — and writing it again is
exactly how a test ends up reading real env, which is the rule the fake exists to keep.

## #43

A value that varies per test case is an argument wearing config's clothes, and the honest fix is the
function taking it; the dishonest one costs shared mutable state under `async: true`, which is the
flake class conventions §9 calls a protocol requirement to avoid, since two CI reds escalate to a
human. The case that would reopen this is a boundary export whose behaviour must genuinely differ by
a declared config value within one suite, where passing it as an argument would distort the
production signature — real enough to name, and not yet seen, which is why the sandbox's hardest
feature is not built on speculation.

## #44

Measured rather than asserted: `vapor 0.10.0` — the current release, dated 2020-08-12 — declares
`jason`, `norm`, `toml` and `yaml_elixir` as ordinary runtime dependencies, so adopting it here puts
a TOML parser and a YAML parser (`yamerl`, in turn) into the release of every project Catapult
generates, in order to read environment variables. Substrate has three runtime dependencies today.
The same argument that kept `mix_audit` out applies with the numbers larger: a dependency substrate
declares is a dependency imposed on trees we do not own, and this one is dormant, which matters
concretely now that `hex.audit` is armed — an advisory against `yamerl` would need a release from a
project that has not cut one in six years, and the acknowledgement machinery in the root's `mix.exs`
is what that looks like when it happens.

**And the residue is thin.** Once the casts are ours (they must be), the aggregation is ours (Vapor
drops it at the first raise), the store is ours (0.10 ships no store), the provenance keying is ours
(Vapor's loader `Map.merge`s provider results, so two components binding the same key name silently
pick a winner) and the file and dotenv providers are unused (12-factor: the environment is the
source), what Vapor contributes to the path we actually need is `System.get_env/0` and a struct.
Substrate therefore ships an environment source with no dependencies at all, and the plane runs that
same source — which is the property that matters most, because Catapult being substrate's first
consumer is how the shipped path gets exercised, and a plane on a Vapor adapter would leave the path
every generated project runs as the one nobody runs.

**That is true of the transports and not of the formats.** A flat file or a remote parameter store
*is* one module and one line: it answers `load/2` with named strings and every other decision in
this layer stands. A format the environment cannot carry — a nested document, lists of maps — is not
an adapter behind this port at all, and pretending otherwise is how a port ends up with a `term()`
value type and casts that accept two shapes. That case is a different problem which happens to share
the word "config", and Vapor as an ordinary library in the consumer that has it is a better answer
than Vapor squeezed through this seam. Saying which half is cheap matters more than saying it is
cheap: the reversal is real for the transports, and the case it does not cover is one this platform
has never had. That is also what makes this whole entry cheap to reverse: the placement question is
decidable by the author without redesign, because the port is the decision and the adapter is not.

## #46

Stated as the whole set rather than as a list, so a gate added to §2 later is in scope without
anyone re-enumerating — which is how `xref` (never named in the ticket) and `hex.audit` (added to §2
by ORC-37 after the ticket was written) are both covered. In the substrate the greps are the entire
value of the run: it declares no components, so the composer check validates an empty list and the
audit is exactly its two greps there.

## #47

This is not the cross-project reach ruled out above and the distinction is the point: the shipped
task stays cwd-rooted and layout-ignorant, while knowledge of where *this* repo keeps its components
sits in this repo's own `mix.exs` — AGPL plane code that never reaches a hex consumer and whose
literal job is knowing the project's layout. The audit is the one gate that earns an invoker,
because it is the only one whose absence is invisible: `mix credo` at the root plainly checks the
root, while `mix catapult.audit` at the root reads as though it audits the repository and does not.
That asymmetry is this ticket's bug, and a third mix project would reproduce it silently against a
convention held only in memory. Two costs, both accepted. The alias does not collapse the substrate
CI block — substrate must still run its own `deps.get` before anything resolves there, verified:
with `components/substrate/deps` absent the alias dies on dependency resolution. It dies loudly,
exit 1, which is the property that matters — an invoker that skipped a project it could not resolve
would be the fail-open this ticket exists to close. And the second leg's failures print
substrate-relative paths (`lib/catapult/clock.ex:3`) with nothing marking which project they came
from, which is the very confusion the stale file map caused. If that is worth fixing, it is fixed in
the task by naming the directory it audited — layout-ignorant, and true in every generated project —
never by the alias annotating output it does not own.

## #48

**Why not same-line only, as drawn:** `mix format` relocates *every* trailing comment onto its own
line above — verified across statement position, `def ..., do:` heads, list, map and argument
elements, with no form found that survives. Since `mix format --check-formatted` is itself a hard
gate with no escape of its own (conventions §2), a same-line-only rule is a hatch that no file in a
formatted tree can hold, and the two gates would simply contradict each other. This also re-reads
the evidence the sketch built on: `clock.ex`'s tag sits one line above the code it excuses not
because the hatch was unexercised, but because the formatter put it there. That the gap was
invisible from inside stands — the tag was written for a check that never looked at the file — but
the placement was never the tell.

## #49

This half of the decision is unchanged. The cost is real and accepted — the clock's moduledoc and
the audit's own cannot spell the construct they forbid. Turning the gate on was therefore not free:
the substrate audit failed on five hits, and four of them were prose — the clock's moduledoc and
three lines of the audit's own moduledoc and messages — reworded rather than tagged. The fifth was
`clock.ex`'s runtime `utc_now`, the single legitimate exception, whose tag was already correctly
placed under the amended rule.

## #50

`mix deps.audit` reads a third-party git mirror (`mirego/elixir-security-advisories`) cloned at run
time and matched by package name and version range, and it disagrees with Hex on the tree we
actually ship — verified against cowlib 2.19.0, three independent ways. The mirror's range for
GHSA-g2wm-735q-3f56 stops at `<= 2.16.1` where the advisory itself says "affects from 2.9.0" with no
patched release; GHSA-w4f7-4cxr-rv3c is filed there under `gun`, so a cowlib dependency never
matches it; and when the clone fails, `MixAudit.Repo.synchronize/0` discards the `git` exit status,
globs an empty directory, prints "No vulnerabilities found." and exits 0. That last one is the
reason for this decision: a gate whose failure mode is a clean report is worse than no gate. `mix
hex.audit` is a built-in Hex task — no dependency to add — it exits 1 on findings, and its data
rides the registry fetch that `deps.get --check-locked` already requires, so a fetch it could not
perform fails the build earlier instead of passing here. Both run; only the Hex one is load-bearing.
**Retirement is Hex's alone** — `mix_audit` has no retirement check at any version, so the gate set
did not cover retired packages until `hex.audit` joined it. Accepted residue, named so it is not
rediscovered: an advisory that reaches the GitHub database and not Hex's feed, on a run where the
mirror clone also failed, still reports clean.

## #52

It is Apache-2.0 and ships into generated projects (`LICENSING.md`), so a dependency added here
lands in every tree built from it; `hex.audit` needing nothing in `deps` is precisely what makes the
gate affordable at this end.

## #53

**Why both, measured rather than reasoned.** `components/substrate` declares no components at all —
the repo's only `use Catapult.Component` is `Catapult.Foundation`, in the plane's `lib/`, registered
by the *root* project's config. Substrate ships the mechanism, not components that adopt it. A check
armed solely by component class would therefore read the one tree ORC-16 was filed about, find no
subject, and report clean: the failure mode ORC-37 spent a whole ticket on. `package:` is what
covers a library that ships mechanism, and it is the one declaration nothing that ships can forget —
`mix hex.build` in `components/substrate` today exits `Missing metadata fields: description,
licenses, links`.

## #54

It is not even a true description of the tree: `components/*` will hold components that are not open
source at all, so the directory answers a question nobody asked it. Concretely: substrate's
`package: [licenses: ["Apache-2.0"]]` *is* the arming, the `licensing: [allow: [...]]` list beside
it is what it is held to, and `LICENSING.md` carries the classification section, names no
`components/*` path in its ladder bullet or its path rule, and its ladder's "Test" bullet describes
a check held to *the project's stated list* rather than to a permissive allowlist of the tool's,
naming substrate's `allow:` entry as the machine-readable form of the five identifiers this document
argues for. `LICENSING.md` is where Catapult's own policy belongs; the list is that policy in a form
the audit can read.

## #56

**One callback, not two,** because the facts are only meaningful as a pair. A license says nothing
about obligation until you know who receives the code; a class says nothing about terms. It is also
the roster's own grain applied to a subject that already has an address: the address is positional
and everything said *about* it is opts, the component *is* the address, `slug/0` spells it, and
licensing is the opts tail and nothing else. Two callbacks would also manufacture two half-declared
states that mean nothing and have to be reported anyway.

**Outside the table** for `config/0`'s stated reason and one more. The extra one: it claims no name.
Two components declaring `Apache-2.0` is the ordinary case rather than a collision, so the `:claim`
and `:identity` columns — the reason the table exists — sit empty, and the fold over `rows/0` grows
a row it must skip. That is the `function_exported?/3` guard the no-optional-callbacks decision
refused, wearing a hat: an aggregation that is total is one that cannot silently miss a component.
`config/0`'s own reason then applies unchanged — a consumer, and error messages worth their
specificity, which "your `:distributed` component declares `AGPL-3.0-only` for itself" is and no
uniform table report could be. One shape hazard: a keyword list *is* a list of two-tuples, so a
table-driven aggregator reads one declaration as two entries, and holding it in the table would mean
teaching `split/2` a no-positional-fields spelling.

## #57

The observation behind such a row is true — a recipient of an AGPL work has already accepted every
term a dependency could add — but acting on it needs the check to recognise copyleft, and a
project-stated list says nothing about which identifiers are. The residue of someone else's list is
not copyleft; it is whatever that project did not write down, and reading it as copyleft leaves the
tree **unchecked** — an inference running in the permissive direction, which is the one direction
this check may not fail in, and the same inference the no-normalization decision below refuses in
the same words.

The self-check passes (a subject is held to the standard it holds its dependencies to), the whole
arrangement is readable in one file, and the case such a row would pass in silence — `GPL-2.0-only`
inside an `AGPL-3.0-only` work, a real incompatibility — fails. Nothing in this repo sits on that
case either way: the plane is `:service`, substrate is `Apache-2.0` conveyed.

That is the self-check and the bucket rule being one rule instead of two, and it is what the list
means read plainly: *the terms acceptable in this tree*, ours included. A project that would rather
not answer states no policy and is inert.

## #59

The distinction is structural rather than remembered: a proprietary `:service` component failing on
a GPL dependency must not read as a shipped-layer failure, because nobody receives that component
and the allowlist protecting recipients is not what is being enforced. Its line says AGPL §13 and an
offer of source to our own users. Applying the shipped-layer allowlist with the shipped-layer
*reason* to a hosted-only component is not conservative, it is wrong, and a report that says which
reason armed it cannot make that mistake quietly.

## #60

"Everything except copyleft" cannot be enumerated, so a denylist would have the check deciding the
copyleft-ness of identifiers it has never seen, which is the inference the paragraph above refuses.
The cost of that strictness is an entry in a list the project owns.

## #61

With the list the project's, the self-check says something a platform-wide list could not: *you are
shipping under terms you would not accept from a dependency in this tree*. That is a contradiction
inside one file rather than a disagreement with Catapult's opinion, which is both a better verdict
and one a generated project can act on without arguing with us.

## #62

A `:distributed` component declaring `AGPL-3.0-only` in a project whose list does not contain it is
the defect one level up and strictly worse than a copyleft dependency: a dependency is one package a
consumer could route around, and the component *is* the thing shipping. It is free because it is not
a second predicate — the same list, with the subject's own identifier in place of the dependency's —
and it is why the table's first column reads "the subject's own terms" rather than "the
component's".

## #63

`:distributed` is the safe default for the dependency half and there is no safe default for the
other half: no license a component "probably" carries, and a defaulted class paired with an absent
identifier makes the self-check above a verdict about nothing. A pair whose halves cannot both be
defaulted has no default. The deciding argument is the second one, though: a default makes every
project's audit print a policy verdict nobody asserted, which is a check that passed without
checking anything — the exact shape the licensing check exists to remove from the ladder. The cost
is bounded and one-time (one callback, two facts, on a module that already declares a slug, with
every missing one reported at once) against an unbounded alternative where the first component whose
class was assumed wrong is discovered by counsel. Note what this is *not*: it is not a compile-time
requirement and not a boot failure. The empty default keeps `use Catapult.Component` sufficient to
compile, exactly as `errors/0`'s required `remedy:` does, and the absence surfaces where every other
structural absence does.

## #64

This is the "two reports at two times" line drawn along a second axis, and the reason is blunt: a
production node refusing to start because a transitive dependency's license string is unrecognized
is a catastrophic response to a question with no runtime consequence whatsoever. CI red is the
correct severity for a legal fact; a node that will not boot is not.

## #65

`Catapult.Audit.License` ships into every generated project. Five SPDX identifiers compiled into it
is Catapult's legal position imposed on codebases we know nothing about, and a project that needs
`MPL-2.0`, `EPL-2.0`, `Zlib` or `Unicode-3.0` is not evading a gate — it is enforcing its own. That
is a **policy difference**, and the line keeping it clear of the waiver: a policy is stated once,
applies uniformly to every dependency in the tree, and is reviewable *as* a policy, where a waiver
is stated per dependency and is read only by whoever added it. The check acquiring a different
subject is not the check being switched off.

For three reasons: it is where a project already speaks to mix, it puts both facts under one review,
and it spares a task that ships everywhere a path convention of its own. Measured rather than
assumed, because an unrecognized key in project config is exactly the kind of thing that turns out
to warn: a `mix new` project with this key added compiles clean and
`Mix.Project.config()[:licensing]` reads it back verbatim — the same door `:docs` and `:dialyzer`
come through, and the audit already reads `Mix.Project.config()[:app]`.

`ErlPL-1.1` is not among the five because it is applicable nowhere: measured across both trees,
every dependency is Apache-2.0, MIT or ISC. `ErlPL-1.1` and `MPL-2.0` do satisfy the predicate —
file-level copyleft binds the files it covers, not the work that links them — but their residues
differ from each other in patent and disclosure terms, and a residue is worth reading against a
package a reviewer can open rather than accepted in the abstract. Configurability is what makes
leaving them off cheap: the day a real dependency asks, the answer is a line in one project's
`allow:` list rather than a release of this package.

**What the check honestly claims** is that no dependency in a checked tree *declares* terms nobody
accepted. That is not verification — hex metadata is the publisher's own assertion, and the counsel
pass `LICENSING.md` schedules is what verification means. Saying so is the difference between a rung
on the v5 §4.5 ladder and a gate that flatters itself; what it buys is noticing, at merge time,
cheaply, forever.

## #66

Dependencies are a mix project's fact, which is the whole reason `package:` is what arms this check;
a list per class would leave a project composing a `:distributed` component and a proprietary
`:service` one resolving to the *intersection* of two lists over one shared `deps/`. That turns
strictest-wins from a total order back into a merge whose result is written in no file and citable
in no report — the defect the one-source config decision above refuses by name. A project that
genuinely needs two policies needs two dependency trees, which is two mix projects, which is what it
already had to be.

## #67

Not defaulted to ours: a default makes every project's audit print a policy verdict nobody asserted,
which is the undeclared-component ruling one level up and the same sentence. Not a failure either —
a project that states no policy has declined the check, in one visible place, and the census line
naming the absence on every run is what keeps declining from being silent. The seam a reader should
worry at is named rather than left to be found: deleting the `allow:` list disarms the gate. It
disarms it in a diff, in the file `package:` lives in, under one review, and every run afterwards
says on stdout that nothing was checked — which is more than any of the waiver shapes below would
have offered.

## #68

ISC is not decorative there: cowboy, cowlib and ranch are all ISC (measured), so the first shipped
component that serves HTTP lands on it.

## #69

The project-stated `allow:` list above is not the exception it can be mistaken for, and the two are
worth holding side by side because they are the same keyword list: `allow:` says *these terms are
acceptable in this tree* and every dependency is then measured against it, while a waiver would say
*this dependency is measured against nothing*. One is a statement a reviewer can disagree with once;
the other accumulates, is argued once and inherited forever, and turns a verdict into a negotiation.
The fix for a copyleft dependency is not taking the dependency. The asymmetry with
`ignore_advisories` above is the whole argument: an advisory is imposed on us by the world and often
has no action until an upstream we do not control ships, whereas nobody imposes a dependency on
anyone — it is the one supply-chain fact that is wholly our own choice. A hatch here could only ever
be spent breaking the rule `LICENSING.md` calls the most important one in it. Same line `external:
true` draws, for the same reason: an escape exists where an outside party imposes something on us,
and nowhere else.

## #70

A plane stating `licensing: [allow: ["AGPL-3.0-only"]]` places its own subject, prints the same
`unchecked` census and is exactly as green today as the full list, so the shorter one looks like the
one that claims less — and the no-hand-maintained-inventories rule looks like it applies. It does
not: the list is a policy statement about acceptable terms, not a mirror of anything in the tree.
The cost lands entirely on the day some subject first arms the check, and it is measured — against
Catapult's five plus `AGPL-3.0-only` the plane's closure produces one problem; against
`["AGPL-3.0-only"]` alone, one per dependency. That is a licensing policy written under time
pressure inside a diff that had another purpose. A list is stated once and read whenever the check
arms; writing it while nothing is at stake is the only time it is cheap.

## #71

The cost is measured and zero: every dependency in substrate's checked closure declares a clean
identifier, and the near-miss in this repo — `cowboy_telemetry`, which declares `["Apache 2.0"]` —
sits in the plane's tree, which the table above leaves unchecked. So no override is needed; the
mechanism exists because the first one will be a sentence in a diff rather than a silent coercion. A
normalization table is the cheaper fix and the wrong one: its failures are silent and biased
permissive, and teaching a reader that near-misses are handled invites the next one, which is a
string like `GPL-2.0-with-classpath-exception` whose distance from `GPL-2.0-only` is the entire
question. Text inference is the same defect with a bigger surface — a fuzzy match over prose
deciding a legal question, with no line in the diff where a human agreed. Overrides live in
`mix.exs` — `licensing: [overrides: [...]]`, the same keyword list the policy sits in — rather than
in a data file of their own: one placement for both facts, not an exception carved for one field.

## #75

Measured in substrate: 5 packages in scope of 8 on disk — plug, mime, plug_crypto, telemetry and
jason, all `Apache-2.0`, while credo, bunt and file_system are dev/test only and reach no generated
project. Excluding them is not laxity; it is what makes "no exceptions" affordable, because a rule
that failed the build over a linter's license would need a hatch inside a month and the hatch is
what the entry above refuses.

## #77

Unifying them imports this walk's path-dep exclusion into a check whose whole subject is
applications nothing constrains — a hole one level in, in the permissive direction. Two answers to
two questions is the correct count, and the day they agree by coincidence is not the day to merge
them.

## #78

**It arms green, and that is the point.** Every dependency in every checked tree passes today, so
the check finds nothing the day it lands. That is what a ratchet is, and it is the only moment
arming is free: the rung `LICENSING.md` files as "Test (planned)" costs one review now and nothing
afterwards, where the same rung added once a copyleft dependency is in costs the dependency.

## #79

That third state is the one the configurable list creates and the only one that could be mistaken
for a pass, which is why it is on stdout of every green run: a gate whose failure mode is a clean
report is the thing ORC-37 was filed about, and "inert" is that report.

## #81

Credo cannot host them without a cost this package has already refused three times. `Credo.Check` is
a `__using__` macro, so a check module compiles only where Credo is loadable; `Mix.Dep.Loader` loads
a dependency's own children with `env: :prod`, so substrate's `only: [:dev, :test]` Credo is never
fetched into a consumer's tree, and a check in `lib/` would fail to compile there. Both ways out are
worse than the thing they buy: a Credo dependency in every generated tree, or a fourth mix project
and a second package on the release train.

Meanwhile the mechanism these checks want shipped last ticket. `policies/0` registers a
`Catapult.Audit.Check` against a working-directory-relative scope, and the runner is this roster's;
a target project inherits exactly the checks its components declare, which is the whole argument for
that registry. Hosting the platform's own checks anywhere else would give `catapult:allow` a second
implementation one ticket after it got its first — the two-homes failure the registry idiom exists
against, and the reason this is one decision rather than a preference.

## #82

An escape list nobody prunes is how the next reader learns the ban is negotiable, and this repo has
already chosen that shape once — Hex warns that an `ignore_advisories` entry matching nothing can be
removed, so the acknowledgement expires by itself. Same property, same reason.

## #84

A baseline recorded after the first compile dependency lands is a baseline that already contains it,
so the strongest cap this metric will ever have is available exactly once, for the price of a line.
Measured rather than estimated at the time: `mix xref graph --format stats` reported 0 compile
dependencies at the root and 0 in `components/substrate`.

## #86

A generated project puts its web layer wherever its own spine says; the dependency is the thing that
is true in all of them.

## #87

`max_heap_size` is a real process flag, kills the process, and is exactly the runtime-grade
guardrail described. `erlang:process_flag(:max_message_queue_len, _)` does not exist — `badarg`,
verified on the pinned OTP — and the only queue-length facility in the VM is
`:erlang.system_monitor/2`'s `long_message_queue`, which notifies rather than kills, is node-global
rather than per-process, and is **singular**: setting a system monitor returns and discards the
previous one, so any dependency that wants `long_gc` silently disables our mailbox guardrail. A
guardrail a library can turn off by accident is the fail-open shape this repo has ruled on twice
already, and it is worse here than in the supply gate, because what stops being reported is a
process about to take the node down.

Renaming costs nothing today (nothing declares a guardrail yet) and the alternative is a field that
will be read as enforcement by every operator who ever greps for it.

## #90

* *Compile error was never on offer.* Elixir validates a struct literal's **keys** at compile time
and never its values, so no generator can make `%Engine.Error{kind: :invented}` fail to compile.
What the generated `new/2` does buy is that the vocabulary a caller can *build* is the vocabulary
the composer validated, with meaning and remedy carried from the declaration rather than copied —
and the residue is one narrow shape, a hand-built literal, instead of the open set an AST pass would
have had to cover. * *Reading `errors/0` while compiling the error module deadlocks the canonical
usage.* `Engine.Error` would wait for `Engine`, and conventions §8's own spelling has `Engine`
constructing `%Engine.Error{}`, which makes `Engine` wait for `Engine.Error`. That is a compile
cycle, and `mix xref graph --format cycles --fail-above 0` is a hard gate — a mechanism whose
adoption trips one of this repo's own gates is not a mechanism. `new/2` resolves against the
registry at call time, which costs a list scan on a failure path and buys back the whole hazard.

Everything downstream of the paragraph above is unchanged: the audit keeps exactly the
declared-and-never-constructed direction (`Catapult.Audit.Declarations`), and remedy presence stays
the composer's.

## #91

Two corrections, both found by writing it, and the second is the one that matters:

## #92

**The cost is one call site, today.** Every consumer of a secret must unwrap, and the only declared
secret in the tree is `DATABASE_URL` on its way into `Repo.init/2`. This is the `events/0` argument
again and it is the last time it will be cheap: the wrapper is free while there is one reader and a
migration once there are twenty.

## #94

That asymmetry is also why the Credo decision above went the other way — `use Credo.Check` runs at
the check module's own compile time, where quoting cannot help.

## #95

What this paragraph used to say — that the residue "stays an AST check" — named no module in `lib/`
and no entry in the audit's platform set, which is `WallClock`, `ProcessName`, `SecretInLog` and has
been since ORC-21. The sentence written to separate a gate from a belief about a gate was the
belief. The gap is named here and closed in `systems/foundation.md`; the split of labour is this
package's decision rather than a pointer, and it has two halves:

## #96

The entry above buys compile-grade enforcement for *named* applications, and the naming is where it
leaks: an application absent from `boundary: [default: [check: [apps: [...]]]]` is not partially
checked, it is silently exempt, and a clean `mix compile` over a dependency nobody constrained looks
exactly like a clean `mix compile` over one that is. ORC-21 priced the omission as "a line in the
same diff that added it"; the price assumes the omission gets noticed and nothing notices it. This
is the fail-open shape the platform has refused twice on its own merits — `mix_audit` reporting
clean from a clone it never made (ORC-37), the licensing check declining silently (ORC-16) —
arriving a third time with no equivalent tell, so it gets the same treatment: a check, and a census
line on every green run saying what the tell would have said.

**A plane-local test is not the cheap version of this.** An ExUnit case in the plane's
`test/catapult/` reading `Mix.Project.config()` would hold the property for that one repository at a
fraction of the cost, and it is refused for what it does not do: every project this task ships into
has the same list and the same drift, and a test in one plane's suite reaches none of them. The
census is the second reason — the complaint is that the fail-open has no tell, and a passing test is
not a tell where a line on stdout of every green run naming what was checked and what could not be
is. A test asserts; the audit reports. The assertion half exists too, as unit tests in this
package's own suite, which is the project that owns the code.

The limit worth knowing before the first carve-out: `Boundary.Definition.normalize!/3` merges a
module's own `check:` over the project default with `Map.merge`, so a boundary declaring any
`check:` key **replaces** the apps list rather than extending it. There are zero such boundaries
today, so no check is built for it — building enforcement for a pattern with no subject is what this
document refuses in three other places ("What a check may infer"). The revisit condition is the
first `use Boundary` in this tree carrying a `check:` key, which is an AST predicate of exactly the
shape `Catapult.Audit.Source` already serves.

## #97

Measured from a **dev**-env run against `MIX_ENV=prod mix run`'s own answer: the two sets are
identical, eighteen applications, so the audit reports the same subject in whatever env it is
invoked. That property is the reason for the mechanism rather than a bonus of it — a gate whose
subject changes with `MIX_ENV` reports different coverage on different runs and cannot be reasoned
about from its output.

## #98

Sharing the walker would have imported that exclusion as a hole one level in.

## #100

The residue that leaves — a typo'd or stale application name is inert rather than reported — is
named here rather than absorbed, and it is bounded by the fact that no name is load-bearing in the
permissive direction.

## #107

Deciding that a call site belongs to a component means a path→component map inside the task, which
is the layout knowledge this task refuses at its front door — worse here than in the `components/*`
case, because a generated project's spine puts components wherever it likes and the map would be
wrong rather than merely absent. The substantive reason stands alone anyway:
`Catapult.Config.fetch!/2` takes a slug *precisely* so a reader can name a value it does not own
(`Catapult.Repo` reading `:foundation`'s database URL is the tree's own example), and whether a
cross-component read is acceptable coupling is a boundary question the boundary compiler already
answers. The check keeps the half that is a registry fact: a key nobody declared. Ownership of a
*call site* is not a fact the config registry holds.

## #108

An allow tag there would silently re-arm the false-dead report the suppression exists to prevent: it
quiets one line by making another line lie, and the lying line's advice is *delete this declaration*
against a value the boot requires. Both remedies are one line and always available — delete the
declaration, or spell the key — which is the condition under which this repo has consistently
declined to build an escape. An escape here is a way to keep dead configuration forever, which is
the thing being checked.

## #109

This is the line ORC-16 drew for licenses: nobody imposes a dependency on us, so the fix for an
unchecked application is naming it, and a waiver could only ever be spent restoring the fail-open
the check exists to close. A fourth exclusion would have to be a fourth *mechanical* fact about what
Boundary can restrain, discovered the way these three were, and it would arrive as a derivation
rather than a list.

## #111

It is why this check can afford to be strict about literals where its neighbour cannot, and why the
refusals in "What a check may infer" above cost it nothing.

## #112

The census exists because most of the roster consumes nothing and an unconsumed registry rots
quietly. `config/0` is the one registry that never had that problem — it has a consumer, a boot half
and its own report — and from this check a dead entry is a red build rather than a number nobody
reads. A second inventory surface here would be a count restating what the check already asserts.

---
paths:
  - components/substrate/**
---

# substrate

The elixir-target platform substrate: everything a Catapult-built app
(and Catapult itself) adopts to honor the convention corpus. Shipped
as a hex package via the registry; Catapult consumes it as a path dep
— the plane is its first consumer.

## Owns

The component behaviour (`use Catapult.Component`) and its registry
callbacks (config/Vapor with secret flags, pubsub topics, Oban
queues with cron annotations, telemetry events, `events/0`,
`processes/0`, seeds, `errors/0` — boundary failure vocabulary with
remedies, `externals/0` — wrapped third-party services; v5 §2.2);
the compile-time root composer with collision checks; the
boundary-export macro (telemetry spans now, `@requires_permission`
enforcement when identity lands); the configuration layer that honors
`config/0` — the source port, the shipped environment source, the
static fake, the boot-time load and the single accessor;
`mix catapult.audit` and its check registry; the health-endpoint plug
(SHA + per-component readiness); the injected clock behaviour; the
seeds release task.

## Standing decisions

- **One macro layer, two concerns.** Telemetry instrumentation and
  permission enforcement ride the same boundary-export macro —
  built once, because both need the same interception point and two
  macro layers on one function is a composition bug farm.
- **The audit is a check registry, not a monolith.** Platform
  extensions (v5 §9) register checks; the ES family registers the
  purity floor, delivery registers file-map checks. Rationale: the
  audit grows for the life of the platform; a registry grows by
  entries, a monolith by merge conflicts.
- **Registries fail the build on collision, never warn.** A warning
  about a name collision is a collision that ships.
- **An env var name is a claimed name like a queue or a topic.** Two
  components binding `DATABASE_URL` is the same class of bug as two
  claiming `:engine_default`, so it is checked where the others are —
  one more entry in the composer's problem list, reported in the same
  breath as the rest. This is what makes the registry load-bearing
  rather than descriptive: today the values are read ad hoc from
  application env and nothing anywhere notices two readers of one
  variable disagreeing about its meaning.
- **Env var names are declared, not derived, and an off-spine name is
  marked.** Conventions §3 renders the spine as a mechanical
  derivation — component `engine` gets `ENGINE_*` — and this repo
  already contains the counter-example: `DATABASE_URL` is injected by
  App Platform under a name we do not choose, and
  `FOUNDATION_DATABASE_URL` is not on offer. So the declaration
  carries the literal variable name (it already does — `config/0`'s
  entries are `{key, env_var, opts}`), the audit checks the prefix,
  and a name off the spine is legal only with `external: true` on the
  entry. The flag earns its place by making the two cases
  distinguishable: without it every off-spine name looks like
  sloppiness and the check has to be turned off to accommodate the one
  case that is not. With it, the audit stays armed and the exceptions
  are a grep. What it does not do is confer permission — an
  `external: true` on a name nobody else imposes is a lie a reviewer
  can see, which is the most a declaration can offer.
- **The cast is total, and the report enumerates.** The requirement is
  the composer's: one boot failure naming every problem, because N
  restart cycles to discover N missing variables is hostile to the
  operator who is holding the deploy. Vapor supplies half of this and
  the half it withholds is the reason this layer is not a call to
  `Vapor.load!/1`. Its `Env` provider does aggregate *missing*
  variables ("ENV vars not set: A, B") and its loader concatenates
  those across providers — but a binding's `map:` function is invoked
  bare inside an `Enum.map`, so the first value that fails to parse
  raises out of the load with no aggregation, no key name and no
  component. `String.to_integer/1` on a fat-fingered `POOL_SIZE` is
  an `ArgumentError` from inside a config library, and the four
  variables that were also wrong are not in the message. Hence: a
  declared cast returns `{:ok, value}` or `{:error, reason}` and
  never raises, the layer collects both classes — missing and
  uncastable — into one exception, and the opts vocabulary is ours
  (`default:`, `cast:`, `secret:`, `required:`, `external:`) rather
  than any library's.
- **The registry declares data; provider structs are an adapter's
  business.** `config/0` returns inert `{key, env_var, opts}` tuples
  and nothing that has to be `Code.ensure_loaded?`d to be understood.
  Inert data is readable by the audit, by the composer's collision
  check, by the settings surface v5 §7.10 will need and by a human
  reading a diff; a callback returning a library's structs is
  readable only by that library, and swapping the library then means
  editing every component instead of one adapter.
- **Two reports, at two times, deliberately.** Structure —
  collisions, malformed declarations, an unknown opt — is validated by
  the composer, which means CI's audit catches it with no environment
  at all. Values are validated at boot, and only at boot, because the
  environment CI has is not the environment that matters and a gate
  that asserts otherwise would be asserting something it cannot see.
  Keeping them separate is what lets the build-time half be
  exhaustive instead of best-effort.
- **The report names variables and reasons, never values.** An
  invalid-value message that quotes the value it rejected publishes a
  malformed secret into the boot log of the failing deploy, which is
  the log everyone then pastes into a ticket. `secret: true`'s
  audit-checked ban on secrets in logs and error payloads (v5 §2.2)
  starts here, in the first error payload the platform can emit, and
  it costs nothing to hold for every value rather than only the
  flagged ones — the operator needs to know *which* variable and
  *why*, and already has the value.
- **Loaded values live behind one accessor, not in application env.**
  The load happens once, before the root supervisor starts, into
  `:persistent_term` under a private key; components read through the
  accessor and nothing else. The alternative — writing the values into
  application env — is more inspectable and that is exactly its
  defect: it leaves the old door open, and `Application.get_env` on a
  component's value would remain correct forever, so the ad hoc
  reading this layer exists to end would end only by convention.
  Write-once-at-boot is also the access pattern `persistent_term` is
  for. The accepted cost is that values are not visible from a remote
  console without calling the accessor.
- **The config source is chosen at compile time, because it is the
  bottom turtle.** v5 §2.12 has every external's real-vs-fake
  selection ride config; config's own source therefore cannot, since
  reading an environment variable to decide whether to read
  environment variables is the circle it looks like. The source is an
  `Application.compile_env` choice: the shipped environment source in
  every real build, the static fake in test — the same shape as the
  clock, and for the same reason.

  **Dev selects the static source too, and that is what settles
  `.env`.** v5 §2.2 sketched per-component `.env` files alongside
  prefixed env vars; they are not built, and the reason is that a
  dotenv file exists to feed environment variables to a process that
  reads the environment. Dev does not: its values already live in
  `config/dev.exs`, in the file a developer edits, under review, with
  no untracked local file to explain when someone's machine behaves
  differently from everyone else's. The environment source is what a
  deployment runs, which is where variables actually come from
  something other than us. **The fake is not a hole:** the static
  source validates its map against the same declarations — a missing
  key or a value that fails its cast is the same report — because a
  source that skipped validation would let a key enter the system
  undeclared, and the declaration is the whole product here.
- **The fake ships in `lib/`, not in `test/support/`.** Conventions §9
  says the fake ships with the port; for a package the sharper form is
  that it ships in the package. `test/support` is compiled only in
  this project's test env and is absent from the hex tarball, so a
  fake living there is a fake every generated project has to write
  again — and writing it again is exactly how a test ends up reading
  real env, which is the rule the fake exists to keep.
- **Vapor is not a substrate dependency.** The ticket's open question,
  answered against the placement this doc previously assumed (see
  *Depends on*). Measured rather than asserted: `vapor 0.10.0` — the
  current release, dated 2020-08-12 — declares `jason`, `norm`, `toml`
  and `yaml_elixir` as ordinary runtime dependencies, so adopting it
  here puts a TOML parser and a YAML parser (`yamerl`, in turn) into
  the release of every project Catapult generates, in order to read
  environment variables. Substrate has three runtime dependencies
  today. The same argument that kept `mix_audit` out applies with the
  numbers larger: a dependency substrate declares is a dependency
  imposed on trees we do not own, and this one is dormant, which
  matters concretely now that `hex.audit` is armed — an advisory
  against `yamerl` would need a release from a project that has not
  cut one in six years, and the acknowledgement machinery in the
  root's `mix.exs` is what that looks like when it happens.

  **And the residue is thin.** Once the casts are ours (they must be),
  the aggregation is ours (Vapor drops it at the first raise), the
  store is ours (0.10 ships no store), the provenance keying is ours
  (Vapor's loader `Map.merge`s provider results, so two components
  binding the same key name silently pick a winner) and the file and
  dotenv providers are unused (12-factor: the environment is the
  source), what Vapor contributes to the path we actually need is
  `System.get_env/0` and a struct. Substrate therefore ships an
  environment source with no dependencies at all, and the plane runs
  that same source — which is the property that matters most, because
  Catapult being substrate's first consumer is how the shipped path
  gets exercised, and a plane on a Vapor adapter would leave the
  path every generated project runs as the one nobody runs.

  **This is a scoping of conventions §1's blessed list, not a
  substitution, and the sketch says so out loud** (§1: don't
  substitute without a systems-doc decision — this is that decision).
  Vapor remains the sanctioned answer the day a project needs config
  from a file, a remote source, or a format the environment cannot
  carry; nothing here needs that, and the port means adopting it then
  is one new module and one compile-time line, not a migration. It is
  also what makes this whole entry cheap to reverse: the placement
  question is decidable by the author without redesign, because the
  port is the decision and the adapter is not.
- **The gate set is a property of a mix project, not of the repo.**
  The audit's greps are `Path.wildcard("lib/**/*.ex")`, rooted at the
  working directory — deliberately, because this task ships into
  every generated project and the shape of *this* tree is not a fact
  it may hold. The consequence is the rule: every mix project here
  runs the whole conventions §2 set in its own directory, and adding
  a mix project means adding its gate block. Stated as the whole set
  rather than as a list, so a gate added to §2 later is in scope
  without anyone re-enumerating — which is how `xref` (never named
  in the ticket) and `hex.audit` (added to §2 by ORC-37 after the
  ticket was written) are both covered. In the substrate the greps
  are the entire value of the run: it declares no components, so the
  composer check validates an empty list and the audit is exactly
  its two greps there.

  **The invoker that names both projects lives in the root
  `mix.exs`,** as a `catapult.audit.all` alias running
  `catapult.audit` and then `cmd --cd components/substrate mix
  catapult.audit`. This is not the cross-project reach ruled out in
  `docs/non-goals.md` and the distinction is the point: the shipped
  task stays cwd-rooted and layout-ignorant, while knowledge of
  where *this* repo keeps its components sits in this repo's own
  `mix.exs` — AGPL plane code that never reaches a hex consumer and
  whose literal job is knowing the project's layout. The audit is
  the one gate that earns an invoker, because it is the only one
  whose absence is invisible: `mix credo` at the root plainly checks
  the root, while `mix catapult.audit` at the root reads as though
  it audits the repository and does not. That asymmetry is this
  ticket's bug, and a third mix project would reproduce it silently
  against a convention held only in memory. Two costs, both
  accepted. The alias does not collapse the substrate CI block —
  substrate must still run its own `deps.get` before anything
  resolves there, verified: with `components/substrate/deps` absent
  the alias dies on dependency resolution. It dies loudly, exit 1,
  which is the property that matters — an invoker that skipped a
  project it could not resolve would be the fail-open this ticket
  exists to close. And the second leg's failures print
  substrate-relative paths (`lib/catapult/clock.ex:3`) with nothing
  marking which project they came from, which is the very confusion
  the stale file map caused. If that is worth fixing, it is fixed in
  the task by naming the directory it audited — layout-ignorant, and
  true in every generated project — never by the alias annotating
  output it does not own.
- **`catapult:allow` spans one line or two, and marks code, never
  prose.** *(Amended in implementation, ORC-30 — the sketch said
  same-line only; see below.)* The tag is honored on the matching line
  or on the comment line directly above it, and on no wider span,
  because any wider one asks each reader to work out how far a given
  escape reaches and an escape whose extent is arguable is worse than
  none. The line above must itself be a comment, or a tagged violation
  would excuse an untagged one on the next line.

  **Why not same-line only, as drawn:** `mix format` relocates *every*
  trailing comment onto its own line above — verified across statement
  position, `def ..., do:` heads, list, map and argument elements, with
  no form found that survives. Since `mix format --check-formatted` is
  itself a hard gate with no escape of its own (conventions §2), a
  same-line-only rule is a hatch that no file in a formatted tree can
  hold, and the two gates would simply contradict each other. This also
  re-reads the evidence the sketch built on: `clock.ex`'s tag sits one
  line above the code it excuses not because the hatch was unexercised,
  but because the formatter put it there. That the gap was invisible
  from inside stands — the tag was written for a check that never
  looked at the file — but the placement was never the tell.

  **Documentation that names a banned construct is reworded, not
  tagged:** an allow tag asserts "this occurrence is a deliberate
  exception", and spending it on a sentence *about* the ban degrades
  the one signal review has, in a package whose docs get published.
  This half of the decision is unchanged. The cost is real and accepted —
  the clock's moduledoc and the audit's own cannot spell the
  construct they forbid. Turning the gate on was therefore not free:
  the substrate audit failed on five hits, and four of them were
  prose — the clock's moduledoc and three lines of the audit's own
  moduledoc and messages — reworded rather than tagged. The fifth was
  `clock.ex`'s runtime `utc_now`, the single legitimate exception,
  whose tag was already correctly placed under the amended rule.
- **The supply gate is Hex-sourced; `mix_audit` is a second opinion,
  not the signal.** `mix deps.audit` reads a third-party git mirror
  (`mirego/elixir-security-advisories`) cloned at run time and
  matched by package name and version range, and it disagrees with
  Hex on the tree we actually ship — verified against cowlib 2.19.0,
  three independent ways. The mirror's range for GHSA-g2wm-735q-3f56
  stops at `<= 2.16.1` where the advisory itself says "affects from
  2.9.0" with no patched release; GHSA-w4f7-4cxr-rv3c is filed there
  under `gun`, so a cowlib dependency never matches it; and when the
  clone fails, `MixAudit.Repo.synchronize/0` discards the `git` exit
  status, globs an empty directory, prints "No vulnerabilities
  found." and exits 0. That last one is the reason for this decision:
  a gate whose failure mode is a clean report is worse than no gate.
  `mix hex.audit` is a built-in Hex task — no dependency to add — it
  exits 1 on findings, and its data rides the registry fetch that
  `deps.get --check-locked` already requires, so a fetch it could not
  perform fails the build earlier instead of passing here. Both run;
  only the Hex one is load-bearing. **Retirement is Hex's alone** —
  `mix_audit` has no retirement check at any version, so the gate set
  did not cover retired packages until `hex.audit` joined it.
  Accepted residue, named so it is not rediscovered: an advisory that
  reaches the GitHub database and not Hex's feed, on a run where the
  mirror clone also failed, still reports clean.
- **An advisory we cannot act on is acknowledged in `mix.exs`, never
  absorbed by a blind gate.** Arming a Hex-sourced gate against a
  tree with two unpatched cowlib advisories fails every build until
  upstream ships a release we do not control, so the gate needs a way
  to say "seen, and nothing to do yet": Hex's
  `hex: [ignore_advisories: [...]]`, listing advisory IDs, which
  prints them under *Ignored advisories* and exits 0. The exit code
  matches today's; the epistemic status does not, and that is the
  entire change — "No vulnerabilities found." becomes a named list
  with an author behind it. It stays honest in both directions: an
  advisory that is not on the list still fails the build, and an
  entry matching nothing in the lockfile warns that it can be
  removed, so the acknowledgement expires by itself the day the
  dependency is bumped. Acknowledgements are per-ID and never
  per-package — ignoring `cowlib` wholesale would re-blind the gate
  to the next advisory against it, which is the failure this
  decision exists to prevent.
- **Substrate carries its own supply gate and never takes an audit
  dependency to get one.** It resolves its own lockfile, so the
  root's audit does not cover it — the versions coincide today, which
  is luck rather than a property, and nothing would report the day
  they diverge. It is Apache-2.0 and ships into generated projects
  (`LICENSING.md`), so a dependency added here lands in every tree
  built from it; `hex.audit` needing nothing in `deps` is precisely
  what makes the gate affordable at this end.

## Initial vs target

Initial (Phase 1): behaviour + registries, export macro
(telemetry-only), audit v0, health, clock, seeds. Target: permission
enforcement wired to identity's principal behaviour; the full check
registry; published on the release train.

The config layer arrives whole rather than as a stub — port, source,
fake, load, accessor — because a registry the composer does not honor
is the state ORC-4 exists to end, and half of it would be the same
state with more files. What is deferred is the audit's side: the
declared↔read check (a value declared and never read, a component
reading a key it did not declare) and `secret: true`'s enforcement
beyond the boot report, both of which want the check registry to grow
first.

## Depends on

Nothing in this repo (it is the bottom). Boundary and PromEx as
library deps.

**Vapor was named here and is not, per the standing decision above**
(ORC-4). Recorded as an amendment rather than a quiet deletion,
because the line was a real prediction from the Phase 0 pass and the
next reader of conventions §1 will expect to find it: the config layer
is a port with a zero-dependency environment source, and Vapor — if it
is ever wanted — is an adapter in a project that wants it, never a
dependency this package imposes.

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
the compile-time root composer with collision checks; the boundary-export macro (telemetry
spans now, `@requires_permission` enforcement when identity lands);
`mix catapult.audit` and its check registry; the health-endpoint
plug (SHA + per-component readiness); the injected clock behaviour;
the seeds release task.

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
- **`catapult:allow` is same-line, and marks code, never prose.** The
  check reads the tag off the matching line only — literally
  `String.contains?(line, "catapult:allow #{tag}")` — so a comment
  on the line above is not an escape, however plainly it is written.
  Kept same-line because any other span asks each reader to work out
  how far a given escape reaches, and an escape whose extent is
  arguable is worse than none. Documentation that names a banned
  construct is reworded, not tagged: an allow tag asserts "this
  occurrence is a deliberate exception", and spending it on a
  sentence *about* the ban degrades the one signal review has, in a
  package whose docs get published. The cost is real and accepted —
  the clock's moduledoc and the audit's own cannot spell the
  construct they forbid. Turning the gate on is therefore not free:
  the substrate audit fails today with five hits, one of which is
  `clock.ex`, the runtime clock and the single legitimate exception,
  whose `catapult:allow utc_now` sits one line above the code it
  excuses. An escape hatch written in a form its own gate rejects is
  what an unexercised hatch looks like, and it is the clearest
  evidence in the tree that the gap was invisible from inside.
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

## Depends on

Nothing in this repo (it is the bottom). Vapor, Boundary, PromEx as
library deps.

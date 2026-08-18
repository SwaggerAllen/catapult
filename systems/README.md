# Unowned paths, deliberately

The protocol's rule: every path is either in exactly one system's
file map, or it is unowned **on purpose and listed here** (the first
real design pass found this list missing — its absence was the
finding). For unowned paths, git's textual conflict detection is the
mutex; nothing else arbitrates.

- **Repo-root prose and build files** — `README.md`, `SETUP.md`,
  `LICENSING.md`, `CLAUDE.md`, `Dockerfile`, `mix.exs`, `mix.lock`,
  `pipeline.config.json`, `.tool-versions`, `.formatter.exs`,
  `.gitignore`, `preview/index.html`. Shared by construction (v5
  §2.7's `mix.exs` argument): a system claiming any of these would
  take a mutex over every ticket that adds a dependency or touches
  the toolchain. Deps stay a named-decision rule; lockfile churn is
  accepted textual-conflict territory.
- **`.github/workflows/**`** — author-owned by GitHub's own rule:
  `GITHUB_TOKEN` may never modify workflow files, so agents cannot
  edit them and no file map could grant what the platform forbids.
  Changes are the author's by construction.
- **`docs/**`** — the design corpus (v5 decisions, conventions,
  non-goals, DSL grammar, build plan). Governed by review of the
  documents themselves, not by any one system; no system has
  standing to own the record of decisions that shaped all of them.
- **`systems/*.md`** (including this file) — design-owned via
  `designOwnedPaths`: design passes change them through sketch
  diffs. Listed for completeness; the owner is the design process,
  not a system.
- **`lib/catapult.ex`** — the top-level Boundary declaration, root
  glue in v5 §2.7's sense: it changes only when a new system carves
  out of the coarse boundary, which is always a sketched, reviewed
  structural change.
- **`catapult.yaml`** (repo root) — created by ORC-7 to pin the chain
  and workflow bundles (dsl-syntax.md §1); it is the loader's own
  input, distinct from the bundle *content* under `bundles/**` that
  `platform_content` owns. Listed here rather than claimed, because
  ORC-5 (core_dsl, in flight on another branch as of this writing)
  already reasons that this file belongs on core_dsl's map — "the
  loader's own input... it belongs on core_dsl's map" — and that is
  core_dsl's decision to land, not this ticket's to preempt. Whichever
  of ORC-5 or ORC-7 merges second should move this entry into
  `systems/core_dsl.md`'s file map rather than leave it here
  contradicting a decision already made.

Everything else in the tree belongs to a file map. A new unowned
path is a decision: it gets an entry and a reason here, in the same
change that creates it.

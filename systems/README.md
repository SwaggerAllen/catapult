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
- **`systems/*.md`** (including this file and each doc's
  `<name>.reasons.md` sibling), **`screens/**`** and
  **`storybook/**`** — design-owned via `designOwnedPaths`: design
  passes change them through sketch diffs. Listed for completeness;
  the owner is the design process, not a system. `storybook/**` is
  the one design-owned tree carrying authored Elixir
  (`screens/<name>/component.ex` plus its `.story.exs`), and it is on
  `elixirc_paths` in every environment deliberately — off it the gate
  set would be blind to exactly the code no dev pass reviewed.
- **`seed-docs/**`** — vendored upstream reference from SiegeEngine
  (the v4 spec and bundle documents, and siege's own prompt chain),
  frozen at a named commit and never edited. Unowned because it is
  not ours to own: a system file map claims paths a system is
  responsible for keeping true, and the whole value of this corpus
  is that nobody maintains it. Changes are re-vendoring, which is an
  author decision. See `seed-docs/README.md` for why it exists and
  where it disagrees with v5.
- **`lib/catapult.ex`** — the top-level Boundary declaration, root
  glue in v5 §2.7's sense: it changes only when a new system carves
  out of the coarse boundary, which is always a sketched, reviewed
  structural change.

Everything else in the tree belongs to a file map. A new unowned
path is a decision: it gets an entry and a reason here, in the same
change that creates it.

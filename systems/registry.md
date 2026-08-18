---
paths:
  - lib/catapult/registry/**
  - test/catapult/registry/**
---

# registry

The artifact service (v5 §3.1): extracted handles, handle diffs,
whole-app operator releases (shaped, later), harness baselines, and
bundle/policy-pack index entries. Publishes from this monorepo on a
single release train with per-component semver.

**Not a package server.** Components resolve as ordinary `mix deps`
from git (public releases additionally to hex.pm); bundles and policy
packs are git repos, forked and merged. What remains here is the set
of artifacts the *plane computes* and neither git nor hex can produce
— which is the upgrade flow's whole substance.

## Standing decisions

- ~~**Hex tooling, not hex.pm** — the mini_repo pattern.~~
  **Revised (v5 §3.1): git for distribution, public hex.pm for public
  publishing.** Hex's two unique capabilities — retirement signalling
  and diamond resolution — are for public code consumed by strangers;
  the single release train designs the diamond away and Catapult's own
  components appear in no advisory database, while third-party deps
  stay ordinary hex packages and keep their audit coverage. Private
  org-blessed registries, the thing mini_repo was bought for, are
  ordinary private git repos. **This shrinks the system rather than
  redirecting it: package *serving* leaves; everything below stays**,
  because handles, diffs and baselines are plane-computed artifacts
  with no home in either git or hex.
- **The release train tests the set** — every release publishes all
  packages + handle artifacts together; "which auth works with which
  catapult" is permanently a non-question.
- **Artifact kinds are named entries** (v5 §8): adding a kind is an
  entry, not a debate. Current kinds: handle, handle-diff,
  release-artifact (later), harness-baseline, and **bundle-index** /
  **policy-pack-index** — pointers with provenance, not content,
  since the content is a git repo. `package` is retired with the
  mini_repo revision above; components resolve from git.
- **Static-first**: v0 is artifacts behind a web server; the service
  (handle-diff queries, release notifications) grows behind the same
  URLs. No consumer should be able to tell when the upgrade happens.
- **Artifact identity includes origin registry, from the first
  artifact** (v5 §8, hosted discipline): the parked hosted direction
  is per-org instance registries federated with a central community
  one, and origin-in-identity makes that federation a namespace
  rather than a migration. Costs nothing now; retrofitting rewrites
  every pin. Corollary, same entry: the central registry accepts no
  outside artifact before its contribution terms exist — community
  content compiles into customer applications.

## Initial vs target

Initial (Phase 3-adjacent, as packages need publishing): static
serving of substrate + llm. Target (Phase 7): the service — publish
pipeline, handle extraction + diffing, per-release upgrade docs.

## Depends on

substrate. Consumes build artifacts from components/*.

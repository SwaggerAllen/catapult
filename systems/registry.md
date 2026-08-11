---
paths:
  - lib/catapult/registry/**
  - test/catapult/registry/**
---

# registry

The self-hosted, hex-compatible component registry (v5 §3.1):
serves the shared components as ordinary `mix deps`, plus the other
artifact kinds the platform accumulated — extracted handles, handle
diffs, whole-app operator releases (shaped, later), harness
baselines. Publishes from this monorepo on a single release train
with per-component semver.

## Standing decisions

- **Hex tooling, not hex.pm** — the mini_repo pattern: ordinary
  client machinery, lockfiles and all, no ecosystem fork and no
  repo-per-package pressure (v5 §3.1's monorepo argument).
- **The release train tests the set** — every release publishes all
  packages + handle artifacts together; "which auth works with which
  catapult" is permanently a non-question.
- **Artifact kinds are named entries** (v5 §8): adding a kind is an
  entry, not a debate. Current kinds: package, handle, handle-diff,
  release-artifact (later), harness-baseline.
- **Static-first**: v0 is artifacts behind a web server; the service
  (handle-diff queries, release notifications) grows behind the same
  URLs. No consumer should be able to tell when the upgrade happens.

## Initial vs target

Initial (Phase 3-adjacent, as packages need publishing): static
serving of substrate + llm. Target (Phase 7): the service — publish
pipeline, handle extraction + diffing, per-release upgrade docs.

## Depends on

substrate. Consumes build artifacts from components/*.

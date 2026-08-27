# Signpost — non-goals

- **No custom short codes.** Every code is generated; nobody gets to
  request `sp.internal/sale`. Vanity codes are a namespace-squatting
  problem this toy project doesn't need to have an opinion on.
- **No link expiry.** A link lives until an owner retires it by hand.
  Time-based expiry is a real feature for a real link shortener and a
  distraction from this fixture's actual job.
- **No cross-team analytics dashboard.** Click counts are recorded per
  link; rolling them up into a team-level or org-level view is a
  different product, not this one.
- **No custom domains.** Every short link lives under one fixed host.
  Bring-your-own-domain is real complexity (cert provisioning, DNS
  verification) this seed does not need to demonstrate.

This document exists to force the `non_goals` input role to have real
content, per ORC-10's scope — it is read as raft evidence, not
asserted to shape any generated tier's output (`systems/generation.md`'s
ORC-10 entry: `input.<role>` resolution is Phase 4).

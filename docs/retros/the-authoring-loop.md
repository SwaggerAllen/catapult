# Retro — The authoring loop

Shipped (archived from the tracker; this note is what duplicate detection reads, and what the rehearsal reset reverts):

- ORC-104 — Make containers plane state, and run their queues (merged a73ee91f43e4f183789014bc35f8e2517a4de822)
- ORC-105 — Containers: one nestable status model for projects, milestones and their queues (merged 61d8f1a4ac876b460206f691a8bf3982c85be72a)
- ORC-114 — Give the work surface the protocol it needs (merged 892358b18d4a4d1c68cc7e7b7240be6562aeeed7)
- ORC-117 — Synthesis join targets can never reach :approved, and the chain test hides it (merged 6e92f0d5c510843a4e4d5d2f67a48f5abb30c6a9)
- ORC-120 — Both delivery process managers' persisted state crashes on snapshot against a real event store — no Jason.Encoder, and no decoder for what does not survive the round trip (merged c3c425e288063c022e770065264418dcddc09775)
- ORC-132 — config/dev.exs's hardcoded SECRET_KEY_BASE is 62 bytes, 2 short of Plug.Session.COOKIE's 64-byte minimum — every :browser-piped route 500s in dev mode (merged be88b3e591f5b0cc464ab7b8ec29426d51fe5332)
- ORC-31 — Extend the Host port with the branch, PR and review operations (merged 3fa7ece87fcd1e6ff3a3bdda70a89ce111368344)
- ORC-32 — Project the feature-ticket lifecycle (merged 30abdac3c2768e16b2f5384d8cd56f3630e28ab6)
- ORC-33 — Manage the feature branch and its single PR (merged 1ca1bfc9f0e5bb1b0496212e9772cff434cfb152)
- ORC-34 — Harvest declines from PR review into regeneration feedback (merged 9f0d170efdbe1ca953e13bebae9a0cbf61908757)
- ORC-35 — Dashboard v0: event-log inspection and explain-why (merged 307a78fc2ea33620af1da153a78b6b1c1a90a2c3)
- ORC-36 — Prove the authoring loop end to end (merged 0bab7337ee52fa9651d8db1656ce7910c42c4848)
- ORC-75 — UI v1: the working surface, and the authoring loop's floor (merged f876406c26592d1bc2362ac551ad760e30b20cd9)

# Retro — Tech debt · before the engine

Shipped (archived from the tracker; this note is what duplicate detection reads, and what the rehearsal reset reverts):

- ORC-16 — Add the license-inventory check to the audit
- ORC-21 — Promote the sleeper checks into the audit and substrate
- ORC-22 — Complete the registry mechanism for the full v5 §2.2 roster
- ORC-29 — Give the milestone-boundary live suite at least one :live test
- ORC-3 — Bump the pinned dependency series onto the pinned toolchain
- ORC-30 — Bring the substrate suite up to the plane's gate set
- ORC-37 — Close the gap between deps.audit and the advisories Hex already prints
- ORC-38 — Replace the deprecated use Plug.Test in the two health tests
- ORC-4 — Wire Vapor through the component config registry
- ORC-40 — Point the README at SETUP for the reference instance's facts
- ORC-48 — Config's declared↔read check, deferred by ORC-4 on a blocker ORC-22 has since removed (merged b7d8226c89d963446aabd84008021a8b5196781f)
- ORC-49 — Arm the gates that are green locally and armed nowhere
- ORC-50 — Close the boundary externals fail-open before the engine adds applications (merged 98e496cd1431c8d104545363439d9612ea5c16ed)
- ORC-51 — The plane states no licensing policy, so its half of ORC-16's ladder is dark (merged fd44f0956b9941c1c7ccea6787419c11ecd12d93)
- ORC-52 — conventions §11's Erlang half is documented as covered and is not built (merged 88965ec5ba6553d05de0f4333eef37b7021104e8)
- ORC-53 — Agent runners provision no Postgres, so the `mix test` gate is hand-bootstrapped or silently skipped
- ORC-74 — Git-distributed components fail the license check, and the escape is a hand-maintained inventory (merged a7b886cca1ce0e9da801286a61c40f34e6fd2671)

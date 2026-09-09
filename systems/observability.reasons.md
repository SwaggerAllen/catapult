# observability — reasons

The reason behind each rule in `systems/observability.md`, keyed by the rule's id (orchestration's DESIGN §4). Read one with `pipeline reasons observability#n` before changing the rule it belongs to.

## #3

A buffer that stores nothing past a restart and answers no request from
outside this instance shares no domain with anything, because it isn't
reporting to a second system at all — it's the first system holding its
own recent failures long enough for its own operator to read them before
they're gone. `systems /foundation.md`'s ORC-218 entry is the concrete
mechanism: what the buffer holds, how it's fed, and the route that reads
it back. Bound and mechanism live there because the code does —
`lib/catapult /foundation/**`, not a shared component — and this bullet
is what stops that read from looking like a quiet reversal of the rule
above it.

## #8

`processes/0`'s heap guardrail is a BEAM process flag and stays
substrate's; the message-queue half has no per-process flag at all, and
the VM's only queue facility — `:erlang.system_monitor/2`'s
`long_message_queue` — is node-global, notify-only, and singular, so any
library setting a system monitor silently replaces ours
(`systems/substrate.md` records the verification). A declared threshold
sampled per registered process and emitted as telemetry is what is
actually on offer, and this component is where it belongs by the rule
directly above: substrate declares, this component consumes the
registries. Sampling also survives what a monitor does not — several
samplers coexist, and a reading nobody clobbers is the difference
between a signal and a guardrail that reports clean because something
else armed first.

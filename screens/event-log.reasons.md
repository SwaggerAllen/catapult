# event-log — reasons

The reason behind each rule in `screens/event-log.md`, keyed by the rule's id (orchestration's DESIGN §4). Read one with `pipeline reasons event-log#n` before changing the rule it belongs to.

## #2

It is not named in `docs/ui-spec.md` because it answers a narrower question than the other three:
"everything about this one node," not "everything of this kind."

## #3

`Commanded.EventStore.stream_forward/3` returns the *current* struct for every event, never the
originally-stored one — `{:review_written, 1}` and `{:review_written, 2}` are a live pair
(`lib/catapult/engine/events.ex`) with a real upcaster behind them, and a v1 event read today comes
back as a `ReviewWritten` v2 struct: `score` already multiplied onto the 0-100 scale, `kind`
already defaulted to `:ai`. An inspector that renders that payload with no version marker is
telling the operator the log always looked like this, which is false and is exactly the lie
`explain/2`'s own moduledoc warns an inspector must not tell.

The temptation, once the disclosure above exists, is to go one step further and show what was
actually serialized — the literal `0.73` before it became `73`. Refused: the only way there is a
read path that bypasses `Commanded.Event.Upcaster`, which means this screen reaching around the
store's own API rather than through it (v5 §2.4, "reached only through their APIs"), for a fact
that changes nothing about what replay will do. The recorded version number is the honest answer to
"was this upcast," and it is what `events/0`'s registry already makes a first-class fact — the
payload underneath does not need to be reconstructed to prove it.

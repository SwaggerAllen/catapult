# document-review — reasons

The reason behind each rule in `screens/document-review.md`, keyed by the rule's id (orchestration's DESIGN §4). Read one with `pipeline reasons document-review#n` before changing the rule it belongs to.

## #2

Per-sentence anchoring activates later **without a protocol change**: the field already exists on
the command, unpopulated; a future pass teaches this screen to compute and send a real one, and
nothing downstream has to change to read it.

## #5

What v1 has instead — `Catapult.Delivery.Store .get_previous_draft_body/2`, one previous body rather
than a log — answers "the diff" above, a narrower question ("what changed since the last pass") than
"has what this gate approved changed," which needs a content pin this ticket does not have. Recorded
here rather than silently dropped, since `docs/ui-spec.md` never named this mechanism and a reader
diffing this screen against an earlier commit would otherwise have to guess whether the gap is an
omission.

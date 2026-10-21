# Manual tests

Judged tests against a running preview, in `Checks`, before reconcile
(orchestration's `ops-free-pipeline.md` §8, DESIGN §9). One file per test:
`tests/manual/<id>.md`.

**They replace the brittle integration layer, not the unit suite.** The
fast deterministic tests under `test/` stay exactly as they are. What
these are for is the defect this pipeline keeps finding and a green unit
suite keeps missing: a seam where both sides are correct and the crossing
is unasserted — a chain handing every agent an empty context, atoms
reaching a projector as strings, `declared_in` paths spelling with
underscores what the schema spells with hyphens.

## The front matter is the selection

```
---
covers:
  - system:engine
  - screen:board
---
```

`covers` names the **docs that own the code the test exercises**, never
path globs. The globs already live in each `systems/*.md` and
`screens/*.md` front matter, and the pipeline reads a diff through them —
restating them here would be a second copy of one rule, which is how the
two drift. Per PR, a test runs when the diff touches a seam it covers; the
whole set runs at the milestone boundary.

**A test covering a seam no doc declares fails the audit.** It could never
be selected and so could never fail, which would make it a claim nothing
checks — the thing letting this directory accumulate was supposed to
avoid. A renamed system doc breaks its tests loudly, which is the point.

## What a test file contains

Preconditions, steps, expected observations, and **what would make this
test wrong**. That last section is not decoration: the judge is told to
report it if the condition now holds, and to give the verdict the test as
written produces anyway. A stale test that fails loudly gets fixed; one
the judge silently reinterprets passes and teaches nobody anything.

## The rules that will surprise you

- **A pass with no evidence is a failure.** Screenshots, transcripts and
  the observation log are run artifacts, and a verdict with nothing
  attached cannot be told from a judge that never ran.
- **The judge never sees the diff**, or the implementation, or the ticket.
  Its checkout is this directory and `pipeline.config.json`. A reader who
  can see the answer is not a reader.
- **A new test is proven by breaking the thing.** Run it against the
  feature commit reverted and record the failure beside the test. A manual
  test that has never failed is unproven, and here that proof is cheap in
  a way a unit test's is not.
- **Two verdicts differing for one test on one commit is a finding about
  the judge**, not about the code: recorded `neutral`, filed to Triage,
  and it does not count toward the two failures that block a ticket.

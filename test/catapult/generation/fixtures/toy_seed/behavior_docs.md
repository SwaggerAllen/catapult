# Signpost — behavior docs

Observed/expected behavior, the kind an intake pass would distill
into requirements once it exists (Phase 4):

- Redirecting a short code that does not exist returns a 404, not a
  redirect to some default page — a broken link should look broken.
- A redirect is logged (for the click count) even when the underlying
  target is itself unreachable; the click happened, the failure is the
  target's problem.
- Creating a link validates the target URL is well-formed before a
  short code is minted — an obviously-broken target never gets a code
  at all.
- Retiring a link is immediate: the very next redirect attempt against
  that code 404s, not a soft "grace period" delete.

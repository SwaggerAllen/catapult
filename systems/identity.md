---
paths:
  - components/identity/**
---

# identity

The platform-maintained identity component (v5 §2.9, consolidated):
accounts, magic-link + optional-password auth, DB sessions, MFA/TOTP,
API tokens, org/membership model, **role-carrying invite links**
(single-use or reusable, revocable; an admin mints a link granting a
named role — the dependency-free staff-onboarding floor),
first-account-superadmin bootstrap (partial-unique-index pinned,
un-demotable), versioned consent with re-consent, roles-as-data with
the platform-seeded defaults, and the **pluggable principal
behaviour** that `@requires_permission` binds against. OIDC client
(assent) as the enterprise tier; SAML deferred.

## #1 Standing decisions

- **#2 Platform-maintained, never generated-and-abandoned** (v5 §2.9's
  argument against the phx.gen.auth model): one component, versioned,
  security patches propagate via the upgrade flow.
- **#3 Consumption is optional; the principal is pluggable** — projects
  with domain-native identity (Haven's keypairs) consume this for
  the ops plane only and substitute their principal for domain
  surfaces.
- **#4 Permissions are code; roles are data** (v5 §2.9). This component
  stores grants and evaluates them; it never defines a project's
  permission atoms.
- **#5 Options are design-time** (v5 §3.4): `passwords`, `registration`,
  `tenancy`, `sso`, consent versions — each varies the resolved
  handle *and* the required-screen UI contract.

## #6 Initial vs target

Initial (Phase 7; dashboard runs minimal auth until then): core auth
+ invites + superadmin + sessions, consumed by the dashboard. Target:
full option portfolio, org/tenancy machinery, OIDC, UI contract
published in the handle.

## #7 Depends on

substrate. Dashboard is the internal consumer; target projects the
external ones.

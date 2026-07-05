# Accounts and Workspaces

Reference for OTS's account/tenancy model (issue #2892).

## Industry pattern

OSS and SaaS converge on a single User identity with scoped memberships.
Provisioning origin (self-signup, invite, JIT/SSO) is metadata, not a user
class. GitHub, GitLab, Sentry, Notion, and Slack all do this — what you can
see and do is determined by role within a workspace, not by how the account
came into being. Origin matters for lifecycle (deprovisioning, recovery,
audit) and occasionally for copy, rarely for UX gating.

## Applied to OTS

A custom-domain-signed-up account, logging into canonical, is a valid identity
with no canonical-scope role. Two coherent shapes:

1. **Standard workspace UI, scoped/empty state.** They see OTS chrome but only
   the workspaces they actually belong to (the custom domain's). Mirrors how an
   org-only GitHub user experiences github.com.
2. **Bounce to origin.** Canonical session suppressed for domain-only accounts;
   they're redirected back to the domain they signed up at. White-label
   semantics — preserves the illusion that they signed up for "Acme Secrets,"
   not OTS.

Tradeoff: (1) is consistent with the data model and makes workspace switching
work, but exposes OTS branding to a user who never agreed to it. (2) honors the
signup expectation but introduces two classes of session and breaks if the user
later joins something on canonical.

## Terminology vectors

Two orthogonal axes:

- **Origin**: `domain_signup` / `invite` / `sso_jit` / `canonical_signup` — a
  metadata field, not a class.
- **Role**: `member` / `admin` / `owner` — what they can do within a workspace.

When copy needs to surface origin: "domain member" vs "invited member" vs "SSO
member". All three share the role "member"; the adjective describes how they
arrived, not what they can do.

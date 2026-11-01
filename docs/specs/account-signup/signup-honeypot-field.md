# Signup honeypot field (`skill`)

Status: Draft — 2026-10-22. Written 2026-08-01 during the signup rate-limiter
work; re-verified against `main` on 2026-10-22. The control is still dead. No
issue is filed.

## What it is

A hidden form field named `skill` on the signup form. Standard anti-bot: the
field is invisible to a real person, so a human never types anything into it.
A bot that fills in every input it finds will put something there. If the field
comes back with a value, the submission is automated.

## Current state

- The frontend still renders the field: `src/apps/session/components/SignUpForm.vue:75`
  and `InviteSignUpForm.vue:290` and `:681`. The invite flow's composable no
  longer sends it to the new invite endpoint (`useInviteAuth.ts:128`).
- The backend captures it in `CreateAccount#process_params`
  (`apps/api/account/logic/account/create_account.rb:41`):

  ```ruby
  @skill = sanitize_plain_text(params['skill'], max_length: 60)
  ```

  The comment above it states the intent: if it has a value, quietly redirect
  to the home page and fake a success response, so the bot cannot tell it was
  caught.

- Nothing reads `@skill`. It is captured, sanitized, exposed via `attr_reader`
  (`:26`) and never checked. The 2026-07-30 security audit
  (`docs/security/audits/security-audit-2026-07-30.md:80`) records it as a dead
  control: the code looks like a defense and does nothing at runtime.

## Why it was not wired up with the rate limiter

Turning it on changes who gets rejected at signup. If any real client
populates the field (a password manager autofilling, a browser extension, an
integration posting the form) those people would start silently failing to
sign up with a fake success message, which is close to impossible to debug
from a support ticket. That deserves its own change with its own tests, not a
rider on a rate-limiting PR.

## Proposed direction

1. Observe first. Log and count non-empty `skill` values at
   `process_params` for a release without changing the outcome. This answers
   whether real clients ever populate it.
2. Then either enforce (the quiet redirect the comment describes, with a spec
   for the fake-success path and an audit entry) or remove the field from both
   forms and the backend. Leaving a dead control in place is the one outcome
   to rule out.

# Runbooks

Operational procedures for diagnosing and resolving specific production
conditions. Each runbook is scoped to one symptom: what you observe, why it
happens, and the steps to resolve or verify.

## Contents

- [dns-validation-failures.md](./dns-validation-failures.md) — Diagnosing custom
  domain DNS validation failures.
- [favicon-fetch-worker.md](./favicon-fetch-worker.md) — Manually triggering the
  custom-domain favicon fetch job, running its worker, and the feature flags that
  gate it.
- [duplicate-plans-on-plans-page.md](./duplicate-plans-on-plans-page.md) —
  Resolving duplicate plan entries surfaced on the plans page.
- [feedback-rate-limit-verification.md](./feedback-rate-limit-verification.md) —
  Verifying the feedback rate limit behaves correctly end-to-end.
- [raw-email-field-serialization.md](./raw-email-field-serialization.md) —
  Handling raw email field serialization issues.
- [secret-rotation.md](./secret-rotation.md) — Backing up and rotating the
  root SECRET; diagnosing and recovering from a SECRET mismatch.
- [sentry-retention-policy.md](./sentry-retention-policy.md) — Sentry data
  retention policy and its operational implications.

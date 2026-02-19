Added
-----

- New ``DlqEmailConsumerJob`` scheduled job replays auth-critical emails from
  the dead-letter queue (``dlq.email.message``) on a 5-minute cycle. Raw
  Rodauth emails (password reset, verify account, email change) are always
  replayed; templated auth emails are replayed only if the underlying Rodauth
  key is still valid; non-auth emails (secret links, expiration warnings) are
  discarded as stale. Enabled by default; set
  ``JOBS_DLQ_CONSUMER_ENABLED=false`` to disable. PR #2530

AI Assistance
-------------

- Claude assisted with implementation of ``DlqEmailConsumerJob``, including
  idempotency design, token expiry validation, channel management, and
  tryout test coverage.

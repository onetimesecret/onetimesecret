.. A new scriv changelog fragment.

Added
-----

- Delivery events for outbound notifications. The application now records
  what it queued, sent, skipped or failed for email and webhook
  notifications, with the queue hand-off kept separate from the email
  worker's result. ``bin/ots notifications deliveries`` lists the feed with
  channel, stage, outcome and correlation filters, and ``--counts`` shows
  per-day totals. The feed is capped and time-bounded; provider bounces,
  complaints and suppressions stay on the email deliverability pages.
  (#4479)

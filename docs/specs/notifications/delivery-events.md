# Delivery events for outbound notifications

Issue: #4479. Code: `lib/onetime/models/delivery_event.rb`,
`lib/onetime/operations/notifications/list_delivery_events.rb`,
`lib/onetime/cli/notifications/deliveries_command.rb`.

This document describes what the code does now. Sizing figures are
arithmetic, not production measurements.

## What it is

A channel-neutral record of what the application attempted for an outbound
notification and what its own workers observed. It fills the gap between
"notification emitted" and provider-level deliverability data. It is not a
replacement for that data: bounces, complaints, suppressions, provider
health and provider message history remain on the colonel email
deliverability endpoints (`/api/colonel/email/deliverability/*`) and
`bin/ots email sync-feedback`.

## Pipeline and write points

```text
event producer
  -> notifications.alert.push
  -> NotificationWorker (source message id)
  -> DispatchNotification
      -> via_email   -> email.message.send        [email, stage queue]
                        -> EmailWorker -> backend [email, stage delivery]
      -> via_webhook -> HTTP POST                 [webhook, stage delivery]
```

| Channel | Writer                 | Stage      | Outcomes                  |
|---------|------------------------|------------|---------------------------|
| email   | `DispatchNotification` | `queue`    | `queued` `failed` `skipped` |
| email   | `EmailWorker`          | `delivery` | `sent` `failed` `skipped`   |
| webhook | `DispatchNotification` | `delivery` | `sent` `failed` `skipped`   |

`queued` is only valid at stage `queue` and `sent` only at stage
`delivery`; `DeliveryEvent.build` rejects any other pairing. A queue
acceptance is therefore never readable as a delivery.

`EmailWorker` writes a terminal event for every message it processes, not
only for notification emails, so an operator can also follow a direct
`Publisher.enqueue_email` message (password reset, invitation) to its
outcome.

## Record shape

Stored as JSON in one sorted set, nil fields omitted. Every value passes an
allowlist pattern; a value that does not fit is dropped.

| Field                 | Type    | Notes |
|-----------------------|---------|-------|
| `id`                  | string  | unique per event |
| `occurred_at`         | float   | epoch seconds, the sorted-set score |
| `channel`             | enum    | `email`, `webhook` |
| `stage`               | enum    | `queue`, `delivery` |
| `outcome`             | enum    | `queued`, `sent`, `failed`, `skipped` |
| `correlation_id`      | string  | source notification message id |
| `message_id`          | string  | downstream queue message id (email only) |
| `event_type`          | string  | e.g. `secret.viewed` |
| `template`            | string  | template name; `raw` for raw emails |
| `customer_id`         | string  | customer extid (`ur...`) only; never an objid, email or legacy custid |
| `reason`              | code    | see below |
| `error_class`         | string  | exception class name |
| `error_message`       | string  | scrubbed, at most 200 characters |
| `http_status`         | integer | webhook only |
| `target_host`         | string  | webhook only; host, never path or query |
| `provider`            | string  | email only; configured transport name |
| `provider_message_id` | string  | email only; when the backend response carries one |
| `duration_ms`         | integer | |
| `attempt_count`       | integer | in-process attempts behind one terminal event |

Reason codes in use: `no_recipient`, `no_target`, `publish_failed`,
`http_status`, `blocked_target`, `timeout`, `invalid_url`, `error`,
`not_dispatched`, `permanent`, `retries_exhausted`, `invalid_message`.

## Correlation

`DispatchNotification` takes `context[:source_message_id]` (the
`notifications.alert.push` message id set by `NotificationWorker`) as the
correlation id and copies it into the email payload as a top-level
`correlation_id`, together with `event_type` and `customer_extid`. Only the
payload's `data` reaches the template. `EmailWorker` reads the three keys
for its event.

- No source id (CLI or test invocation): a `gen-<uuid>` id is generated so
  the events of one dispatch still link.
- Legacy email payload without `correlation_id`: the worker uses its own
  queue message id as the correlation id, so the event is still findable by
  `message_id`.
- Redelivered queue message: dropped by the worker's idempotency claim
  before any event is written.
- DLQ replay that is processed again: a second terminal event under the
  same correlation id. The newest event for a (correlation_id, channel,
  stage) is the current state.

## Retries

One terminal event per processed message, after in-process retries finish,
with `attempt_count`. There is no per-attempt event.

- Email: `EmailWorker` retries transient errors up to three times. Exhausted
  transient retries record `failed` / `retries_exhausted`; a non-transient
  `DeliveryError` records `failed` / `permanent` with `attempt_count` 1.
- Webhook: no retry. A non-2xx response records `failed` / `http_status`
  with the status and target host and no message (the exception text
  quotes the response body). Other failures record their class and a
  scrubbed message.
- A backend that returns nil (suppressed recipient, or delivery disabled)
  records `skipped` / `not_dispatched`.

## Privacy

Not stored: notification or secret payloads, secret or receipt keys, URLs,
rendered bodies, subjects, webhook paths or query strings, recipient
addresses, internal object ids. `DeliveryEvent.scrub_message` replaces
URIs, email addresses, known provider credential shapes and any
alphanumeric run of 20 or more characters, collapses whitespace and cuts to
200 characters. The webhook response body is never passed in.

Recipient lookup is not part of this feed. An operator who needs to trace a
recipient uses the customer extid filter (when the producer supplied one)
or the provider surfaces.

## Storage

- `delivery_event:events`: one sorted set, member JSON, score occurred-at.
  Trimmed on every write to `MAX_EVENTS` (50,000) and `RETENTION` (14
  days). ZADD and each trim are single atomic commands; between them the
  set can exceed the cap by at most the number of concurrent writers, and a
  trim never removes more than the overflow it sees.
- `delivery_event:counts:<YYYYMMDD>`: one hash per UTC day, field
  `channel:stage:outcome`, expiry 90 days, at most 12 fields a day. These
  totals outlive the individual events and do not grow with volume.

Sizing: an event is roughly 300-400 bytes of JSON, so the cap is about
20-25 MB. A notification email writes two events and any other email one.
The cap holds about five days at 10,000 emails/day; below about 3,500/day
the 14-day window is the binding limit.

Writes are fail-open: `DeliveryEvent.record` never raises, and both
writers wrap the call again. A recording failure is logged and delivery
proceeds unchanged.

## Reading

`Onetime::Operations::Notifications::ListDeliveryEvents` is the single
read path: newest first, filters on channel, stage, outcome,
correlation_id, event_type and template, limit and offset, and a `more`
flag. A filtered read walks the feed in pages and costs at most one pass
over the retained events.

CLI:

```console
$ bin/ots notifications deliveries
$ bin/ots notifications deliveries --channel email --outcome failed
$ bin/ots notifications deliveries --correlation <id>
$ bin/ots notifications deliveries --counts 7
$ bin/ots notifications deliveries --format json
```

No colonel API endpoint or admin UI is included. Both would be adapters
over the same operation.

## Relationship to #4348

This owns the record shape, correlation, retention and reader. Webhook
kill-switch state, its audited operations, the pre-egress check and
webhook-specific presentation belong to #4348 and should write and read
through `DeliveryEvent` rather than a separate log.

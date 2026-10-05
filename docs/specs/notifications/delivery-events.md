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

| Channel | Writer                 | Stage      | Outcomes                    |
| ------- | ---------------------- | ---------- | --------------------------- |
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

`EmailWorker` outcomes:

| Settled | Outcome   | Reason              | When                                                                                    |
| ------- | --------- | ------------------- | --------------------------------------------------------------------------------------- |
| ack     | `sent`    |                     | a mail provider accepted the message                                                    |
| ack     | `skipped` | `log_only`          | the logger backend printed the message instead of sending it                            |
| ack     | `skipped` | `not_dispatched`    | suppressed recipient, or delivery disabled                                              |
| reject  | `failed`  | `invalid_message`   | not JSON, unknown schema version, wrong payload shape, no message id, or mailer refusal |
| reject  | `failed`  | `permanent`         | non-transient `DeliveryError`                                                           |
| reject  | `failed`  | `retries_exhausted` | still failing after the in-process retries                                              |
| reject  | `failed`  | `error`             | any other error, including one raised before delivery started                           |

`sent` means a mail provider accepted the message. Each delivery backend
declares whether it transmits (`Delivery::Base#transmits?`); the logger
backend does not, including when an unknown `emailer.mode` falls back to
it, so its deliveries are never recorded or counted as `sent`. The
`provider` field is the transport the mail backend is built for
(`Mailer.backend_provider`), so that fallback shows `logger`, not the
unknown name. A `skipped` / `not_dispatched` event with provider `disabled`
or `none` is an install with delivery turned off; with any other provider
it is a suppressed recipient.

Every message the worker rejects writes exactly one `failed` event, whether
or not a delivery was attempted. Three paths write nothing: a duplicate
dropped by the idempotency claim (acked), a ping message (acked), and a
process-level exception such as a shutdown signal, which is re-raised
without settling the message.

## Record shape

Stored as JSON in one sorted set, nil fields omitted. Every value passes an
allowlist pattern; a value that does not fit is dropped.

| Field                 | Type    | Notes                                                                                           |
| --------------------- | ------- | ----------------------------------------------------------------------------------------------- |
| `id`                  | string  | unique per event                                                                                |
| `occurred_at`         | float   | epoch seconds, the sorted-set score                                                             |
| `channel`             | enum    | `email`, `webhook`                                                                              |
| `stage`               | enum    | `queue`, `delivery`                                                                             |
| `outcome`             | enum    | `queued`, `sent`, `failed`, `skipped`                                                           |
| `correlation_id`      | string  | source notification message id                                                                  |
| `message_id`          | string  | downstream queue message id (email only)                                                        |
| `event_type`          | string  | e.g. `secret.viewed`                                                                            |
| `template`            | string  | template name; `raw` for raw emails                                                             |
| `customer_id`         | string  | customer extid (`ur...`) only; never an objid, email or legacy custid                           |
| `reason`              | code    | see below                                                                                       |
| `error_class`         | string  | exception class name                                                                            |
| `http_status`         | integer | webhook only                                                                                    |
| `target_host`         | string  | webhook only; host, never path or query                                                         |
| `provider`            | string  | email only; transport the mail backend is built for                                             |
| `provider_message_id` | string  | email only; when the backend response carries one                                               |
| `duration_ms`         | integer |                                                                                                 |
| `attempt_count`       | integer | positive in-process attempts behind one terminal event; omitted when delivery was not attempted |

Reason codes in use: `no_recipient`, `no_target`, `publish_failed`,
`http_status`, `blocked_target`, `timeout`, `invalid_url`, `error`,
`not_dispatched`, `log_only`, `permanent`, `retries_exhausted`,
`invalid_message`.

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
  stage) is the current state. A message rejected after its idempotency
  claim was taken releases the claim, so its replay is delivered rather
  than dropped as a duplicate. The claim is kept once delivery finished.
- Duplicate email on replay: email delivery is at-least-once. If the
  provider accepted the message but the delivery call then raised (a read
  timeout after the accept, or an error after the send), the worker records
  `failed`, releases the claim and rejects the message. A replay of that
  message sends the email a second time and records a second terminal
  event.

## Retries

One terminal event per processed message, after in-process retries finish,
with `attempt_count`. There is no per-attempt event.

- Email: `EmailWorker` retries transient errors up to three times. Exhausted
  transient retries record `failed` / `retries_exhausted`; a non-transient
  `DeliveryError` records `failed` / `permanent` with `attempt_count` 1.
  An `ArgumentError` from the mailer (for example an unknown template) is
  not retried and records `failed` / `invalid_message`.
- Messages that are not JSON, are not a JSON object (`null`, an array, a
  string, a number, a boolean), or carry an unknown schema version record
  `failed` / `invalid_message` using the queue message id for both
  identifiers. No payload-derived fields or attempt count are stored
  because the payload was not accepted and delivery was not attempted.
- Messages that are a JSON object with the wrong shape (`data` not an
  object, `template` not a string or blank, a raw message without an email
  object or recipient) or no message id are rejected before the
  idempotency claim and record `failed` / `invalid_message` with no attempt
  count. `correlation_id`, `event_type`, `template` and `customer_extid`
  are copied only when they are strings.
- An error raised before delivery starts (for example the idempotency
  claim failing) records `failed` / `error` with no attempt count.
- Webhook: no retry. A non-2xx response records `failed` / `http_status`
  with the status and target host. Other failures record their class and
  reason code. Exception text is omitted for every channel.
- A backend that returns nil (suppressed recipient, or delivery disabled)
  records `skipped` / `not_dispatched`. The logger backend records
  `skipped` / `log_only`.

## Privacy

Not stored: notification or secret payloads, secret or receipt keys, URLs,
rendered bodies, subjects, webhook paths or query strings, recipient
addresses, internal object ids. Arbitrary error messages are omitted;
upstream errors can echo subjects, bodies or addresses that pattern-based
redaction cannot reliably identify. Reason codes and exception class names
remain available. The reader also excludes error text from older records;
existing stored records are not rewritten.

Recipient lookup is not part of this feed. An operator who needs to trace a
recipient uses the customer extid filter (when the producer supplied one)
or the provider surfaces.

## Storage

- `delivery_event:events`: one sorted set, member JSON, score occurred-at.
  Appending, trimming to `MAX_EVENTS` (50,000) and `RETENTION` (14 days),
  and setting expiry run atomically. The key expires at the newest retained
  event's retention deadline, even without another write. Reads and retained
  counts also remove aged events from a still-active feed. Existing keys
  acquire expiry on their next write, read or explicit trim.
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
flag. A filtered read walks the feed in pages and deduplicates event ids
before applying offsets and limits. This prevents concurrent inserts from
counting the same event twice; the read is not a fixed snapshot.

CLI:

```console
$ bin/ots notifications deliveries
$ bin/ots notifications deliveries --channel email --outcome failed
$ bin/ots notifications deliveries --correlation <id>
$ bin/ots notifications deliveries --counts 7
$ bin/ots notifications deliveries --format json
```

Text output preserves the full correlation id for reuse with `--correlation`.
`--format` accepts only `text` or `json`, in either mode. `--counts` accepts
1–90 days and returns unfiltered daily totals; it cannot be combined with
`--channel`, `--stage`, `--outcome`, `--correlation` or `--template`.

No colonel API endpoint or admin UI is included. Both would be adapters
over the same operation.

## Relationship to #4348

This owns the record shape, correlation, retention and reader. Webhook
kill-switch state, its audited operations, the pre-egress check and
webhook-specific presentation belong to #4348 and should write and read
through `DeliveryEvent` rather than a separate log.

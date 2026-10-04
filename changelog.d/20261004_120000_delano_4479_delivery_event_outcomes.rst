.. A new scriv changelog fragment.

Changed
-------

- Email delivery is now at-least-once. The email worker releases its
  idempotency claim when a delivery fails, and the dead letter queue
  replays release it again before they republish, so a replayed email is
  sent rather than skipped as a duplicate. (#4479)

  **Deployment note: duplicate emails are possible.** If a mail provider
  accepted a message before the delivery call raised, for example a read
  timeout after the provider accepted it, the worker records ``failed`` and
  rejects the message to the dead letter queue. A replay, by the automatic
  DLQ email job (``jobs.dlq_consumer``, for auth emails) or by an operator,
  then sends a second copy. Before this release a replay within the hour
  was acknowledged as a duplicate and the email was not sent.

- Email messages that cannot be delivered as written are now rejected to
  the dead letter queue: a message with no AMQP message id (previously
  acknowledged as if it were a duplicate), a blank or missing template, and
  a raw email with no recipient address (the recipient must be a non-blank
  string, or a list whose first entry is one). Expect these in the DLQ
  instead of being dropped or failing later. (#4479)

- ``pending_email_delivery_status`` on a customer is now ``skipped``
  instead of ``sent`` when the email-change confirmation was only logged
  or was not dispatched (logger backend, delivery disabled, suppressed
  recipient). (#4479)

Fixed
-----

- Delivery events no longer record a log-only email as sent. With the
  logger mail backend, including when an unknown ``emailer.mode`` falls
  back to it, the email worker now records ``skipped`` with reason
  ``log_only``, and the event's ``provider`` is ``logger`` rather than the
  unknown name. (#4479)

- Every email message the worker rejects now leaves one ``failed``
  delivery event. Messages with an invalid payload shape or no message id
  are rejected as ``invalid_message`` before any delivery attempt, and an
  error raised before delivery starts is recorded as ``error``. Messages
  that are not valid JSON or use an unknown schema version are now sent to
  the dead letter queue instead of being left unacknowledged. (#4479)

- The email worker no longer retries a message the mailer refuses as
  invalid, such as one naming an unknown template. (#4479)

- A failed email is no longer skipped as a duplicate when it is replayed
  from the dead letter queue. The email worker releases its idempotency
  claim when delivery fails, and the automatic DLQ email job releases it
  again before it republishes, so a replay within the hour is delivered
  even when the worker's release failed. If the datastore fails while the
  job releases the claim or marks the message as replayed, the message now
  stays in the dead letter queue for the next run and is counted as
  ``deferred``; it was previously dropped. (#4479)

- ``ots queue dlq replay`` and the colonel replay endpoint now release a
  message's idempotency claim before republishing it. The DNS record
  check, domain validation, notification, billing and favicon fetch
  workers keep their claim when they reject a message, so a message
  replayed within the hour was reported as replayed but skipped by the
  worker as a duplicate. A message whose claim cannot be released stays in
  the dead letter queue and is counted as failed. (#4479)

- ``ots queue dlq replay`` and the colonel replay endpoint now republish a
  message and remove it from the dead letter queue in one AMQP
  transaction, so a failed removal no longer leaves the message both
  republished and in the dead letter queue. A message whose republish or
  removal fails stays in the dead letter queue, is counted as failed, and
  is not tried again in the same replay. It was previously requeued
  straight away, and the replay could pick the same message up again
  instead of the ones behind it. If the broker does not confirm a commit,
  the replay stops and reports the message as failed with an "outcome
  unknown" error, because it may already be republished. (#4479)

- A favicon fetch that times out is now retried once when the broker
  redelivers it. The favicon worker kept its idempotency claim when it
  requeued the message, so the retry was skipped as a duplicate and the
  domain's favicon fetch stayed in ``processing``. A fetch that times out
  again on the retry goes to the dead letter queue, and so does one whose
  claim cannot be released, since its redelivery would be skipped. (#4479)

- Queue workers now reject a message whose body is JSON but not an object
  (an array, string, number or boolean) to the dead letter queue, with one
  log line. Such a body was previously handled as an unexpected error, and
  raised out of the billing worker. (#4479)

- Queue workers now reject messages that are not valid JSON or use an
  unknown schema version, sending them to the dead letter queue. They were
  previously left unacknowledged, each holding a prefetch slot. (#4479)

- Queue workers no longer mix up message envelopes when one worker
  processes several messages at once. The message id used for the
  idempotency claim and the schema version check now always belong to the
  message being processed. (#4479)

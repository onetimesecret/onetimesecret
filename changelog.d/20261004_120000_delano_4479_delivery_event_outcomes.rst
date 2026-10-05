.. A new scriv changelog fragment.

Changed
-------

- Email messages that cannot be delivered as written are now rejected to
  the dead letter queue: a message with no AMQP message id (previously
  acknowledged as if it were a duplicate), a blank or missing template, and
  a raw email with no recipient. Expect these in the DLQ instead of being
  dropped or failing later. (#4479)

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
  claim when delivery fails, so a replay within the hour is delivered.
  (#4479)

- ``ots queue dlq replay`` and the colonel replay endpoint now release a
  message's idempotency claim before republishing it. The DNS record
  check, domain validation, notification, billing and favicon fetch
  workers keep their claim when they reject a message, so a message
  replayed within the hour was reported as replayed but skipped by the
  worker as a duplicate. A message whose claim cannot be released stays in
  the dead letter queue and is counted as failed. (#4479)

- A favicon fetch that times out is now retried once when the broker
  redelivers it. The favicon worker kept its idempotency claim when it
  requeued the message, so the retry was skipped as a duplicate and the
  domain's favicon fetch stayed in ``processing``. A fetch that times out
  again on the retry goes to the dead letter queue. (#4479)

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

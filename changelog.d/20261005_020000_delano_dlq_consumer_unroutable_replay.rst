.. A new scriv changelog fragment.

Fixed
-----

- The automatic DLQ email job (``jobs.dlq_consumer``) no longer removes an
  auth email from the dead letter queue when the queue it is replayed to
  does not exist. The broker accepted such a publish without error, so the
  job counted the email as replayed and it was lost. The job now publishes
  the replay as mandatory and commits it before it removes the message from
  the dead letter queue. If the broker returns the replay as unroutable,
  the message stays in the dead letter queue, the job logs a
  ``Replay unroutable`` error with the queue name and message id, and the
  batch summary counts it under ``unroutable``. The job tries again on every
  run until the queue exists.

Changed
-------

- The automatic DLQ email job commits the republish and the removal from the
  dead letter queue separately, where it committed them in one AMQP
  transaction. If the removal fails after the republish is committed, the
  message stays in the dead letter queue; a run within the next hour removes
  it without republishing. A message without a message id, or one the job
  does not reach again within that hour, is republished and the email is
  sent a second time. If the broker does not confirm the republish commit
  and it had applied, the email is sent a second time after the one-hour
  reservation expires.

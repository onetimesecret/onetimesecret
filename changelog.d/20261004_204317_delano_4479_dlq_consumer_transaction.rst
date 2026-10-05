.. A new scriv changelog fragment.

Fixed
-----

- The automatic DLQ email job (``jobs.dlq_consumer``) now republishes an
  auth email and removes it from the dead letter queue in one AMQP
  transaction, as ``ots queue dlq replay`` already does. A connection
  failure between the two could previously leave the email republished
  and also back in the dead letter queue, where an operator replay sent it
  a second time. If the republish or removal fails before the commit, both
  are rolled back and the message stays in the dead letter queue, counted
  as ``deferred``. It is already marked as replayed at that point, so the
  next run removes it without sending it. If the broker does not confirm a
  commit, the job stops the batch and logs an ``outcome unknown`` error
  with the message id; messages not yet processed wait for the next run.
  (#4479)

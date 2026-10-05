.. A new scriv changelog fragment.

Fixed
-----

- The automatic DLQ email job (``jobs.dlq_consumer``) no longer drops an
  auth email when republishing it fails. The job marked a message as
  replayed before it republished it, so a failed republish, or a datastore
  timeout after the mark was written, discarded the message. The job now
  marks a message as replayed only after it is republished and removed from
  the dead letter queue. A message whose replay fails stays in the dead
  letter queue for a later run and is counted as ``deferred``.

  If the republish or the removal from the dead letter queue fails, the job
  cannot tell whether the copy went out. It waits up to an hour before it
  replays that message again, and that replay can send the email a second
  time. After upgrading, a message the previous version marked as replayed
  waits until that mark expires (at most an hour) and is then replayed.
  Messages waiting this way do not count against the batch of 50, so a run
  continues to the messages behind them (it passes over at most 500).

Changed
-------

- The automatic DLQ email job now leaves a message in the dead letter queue
  on an unexpected processing error, counted as ``deferred``, instead of
  discarding it. Messages that are not a JSON object, or whose ``data``
  field is not an object, are still discarded.

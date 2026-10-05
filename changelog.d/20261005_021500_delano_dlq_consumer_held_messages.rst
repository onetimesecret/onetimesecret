.. A new scriv changelog fragment.

Fixed
-----

- The automatic DLQ email job (``jobs.dlq_consumer``) no longer lets messages
  it cannot replay use up every batch. Such messages return to the front of
  the dead letter queue, so 50 of them filled each batch of 50 and the auth
  emails behind them could expire before the job reached them. A message
  with a malformed ``x-death`` header (not an array of tables, or without a
  queue name) raised an error on every run and stayed at the front; it is
  now discarded like a message with no ``x-death`` header, with a
  ``No original queue`` error that carries the message id. A message whose
  id another replay has reserved, whose original queue does not exist, or
  whose processing raises an unexpected error stays in the dead letter
  queue and no longer counts against the batch: the run continues to the
  messages behind it, passing over at most 500. The batch summary counts
  these under ``held``.

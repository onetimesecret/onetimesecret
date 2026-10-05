.. A new scriv changelog fragment.

Fixed
-----

- Listing a dead-letter queue (``ots queue dlq list <queue>`` and the colonel
  DLQ console) now shows each message once instead of repeating the first
  message. ``ots queue dlq show --id`` and ``--index`` now find messages
  beyond the first one. Inspection still leaves every message on the queue.
  While a listing or lookup runs, the messages it has read are held back from
  other consumers and returned to the queue when it finishes, possibly in a
  different order. (#4650)

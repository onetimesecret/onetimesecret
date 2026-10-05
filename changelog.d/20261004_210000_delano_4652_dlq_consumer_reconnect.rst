Fixed
-----

- Automatic email dead letter queue replay no longer reconnects midway
  through a batch, which could report a replay while silently skipping its
  acknowledgement. Each batch uses a separate connection; a disconnect
  fails the batch rather than resuming it. Shared publisher recovery is
  unchanged. (#4652)

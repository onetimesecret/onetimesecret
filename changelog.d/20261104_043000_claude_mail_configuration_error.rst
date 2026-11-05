.. A new scriv changelog fragment.

Fixed
-----

- A mail delivery backend that cannot be built from its configuration (no
  SMTP host, an unsupported ``SMTP_AUTH`` with SMTP credentials set, missing
  SES, SendGrid, Lettermint or SMTP2GO credentials) no longer reports each
  queued email as ``Invalid message format`` and sends it to the
  dead-letter queue. The email worker logs
  ``Mail configuration error (provider: smtp): SMTP host must be configured``
  instead, keeps the message on ``email.message.send`` and tries it again
  every 15 seconds, so the emails go out once a worker starts with a
  working configuration. Malformed messages (unknown template, wrong
  payload shape) are still rejected to the dead-letter queue as before.

Added
-----

- Boot builds the mail delivery backend once and logs
  ``Mail configuration error, email cannot be sent`` with the provider and
  the reason when the configuration cannot build it, so a bad mail setting
  shows up on deploy instead of on the first send. Boot continues; only
  mail is affected.

Changed
-------

- While the mail configuration is broken, queued emails wait on
  ``email.message.send`` instead of collecting in ``dlq.email.message``, and
  the queue grows with the send rate until the configuration is fixed.
  Emails held for a long time are sent late once it is, and links in them
  may have expired by then. A DLQ depth alert does not fire for this case;
  watch for the log line above or for ``email.message.send`` depth.

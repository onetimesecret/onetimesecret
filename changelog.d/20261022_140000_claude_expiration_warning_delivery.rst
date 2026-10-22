.. A new scriv changelog fragment.

Fixed
-----

- Expiration warnings are now sent on installs that run the job system.
  The job queued each warning for delayed delivery on
  ``email.message.schedule``, a queue nothing consumed: the message expired
  into the email dead-letter queue, where non-auth templates are discarded,
  so no warning ever reached an owner. The job now publishes to
  ``email.message.send`` on the scan that finds the secret inside the warning
  window, which is what installs without the job system already did. The
  warning arrives between ``warning_hours`` and ``warning_hours`` minus
  ``check_interval`` before the secret expires; lower ``warning_hours`` to
  warn closer to expiry.

Removed
-------

- ``Onetime::Jobs::Publisher.schedule_email`` and the
  ``email.message.schedule`` queue. Nothing read the queue. A broker that
  declared it keeps the durable queue; delete it with
  ``rabbitmqctl delete_queue email.message.schedule`` once the deploy is
  running everywhere (``lib/onetime/jobs/queues/maintenance.md``).

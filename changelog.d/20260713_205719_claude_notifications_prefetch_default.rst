.. A new scriv changelog fragment.

Fixed
-----

- The notifications worker's prefetch default in
  ``etc/defaults/config.defaults.yaml`` now reads ``5`` instead of ``10``,
  matching the value the worker actually runs with. ``NotificationWorker``
  declares its queue with ``ENV.fetch('NOTIFICATION_WORKER_PREFETCH', 5)``, so
  when the env var is unset the worker has always prefetched 5 messages while
  the config file misreported 10. This aligns the documented default with
  runtime and with the sibling ``billing`` worker (also 5); the high-throughput
  ``email`` worker keeps its 10. No runtime behaviour changes for a default
  deployment. Surfaced during #3777 review.
  (#3777)

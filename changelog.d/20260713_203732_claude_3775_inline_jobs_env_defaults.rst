.. A new scriv changelog fragment.

Removed
-------

- The 32 tuning/toggle ``JOBS_*`` environment variables (per-job ``enabled``,
  ``interval``/``check_interval``, ``batch_size``, ``cron``, ``*_hours``,
  ``sample_size``, ``rate_limit``, and ``auto_repair`` across the domain-refresh,
  expiration-warnings, phantom-cleanup, data-audit, participation-gc,
  index-rebuild, instances-rebuild, housekeeping, plan-cache-refresh,
  catalog-retry, dlq-consumer, and maintenance jobs) no longer take effect;
  their defaults are now inlined directly in
  ``etc/defaults/config.defaults.yaml``. Nothing outside that YAML ever read
  these vars, so no runtime behaviour changes for a default deployment. To
  enable or tune one of these jobs, set the value in the ``jobs:`` block of your
  ``etc/config.yaml`` override file (which deep-merges over the shipped
  defaults) instead of exporting an env var. The three genuine deploy-time
  switches — ``JOBS_ENABLED``, ``JOBS_FALLBACK_SYNC``, and
  ``JOBS_SCHEDULER_ENABLED`` — are unchanged and remain env-overridable.
  (#3775)

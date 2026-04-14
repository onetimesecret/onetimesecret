# Sentry Retention Policy Runbook

## Overview

Sentry self-hosted defaults to 90-day event retention. For data minimization compliance, we limit retention to 14 days.

## Configuration

In the Sentry self-hosted `.env`:

```bash
SENTRY_EVENT_RETENTION_DAYS=14
```

Restart Sentry services after changing.

## Known Issue

ClickHouse may not honor the retention setting ([getsentry/self-hosted#3421](https://github.com/getsentry/self-hosted/issues/3421)). Verify cleanup is occurring.

## Verification

Check ClickHouse table sizes:

```bash
docker exec -it sentry-clickhouse clickhouse-client --query \
  "SELECT table, formatReadableSize(sum(bytes)) as size \
   FROM system.parts GROUP BY table ORDER BY sum(bytes) DESC"
```

Monitor disk usage over 2+ weeks to confirm purging.

## Compliance

This implements data minimization — debugging data should not be retained longer than necessary for its purpose.

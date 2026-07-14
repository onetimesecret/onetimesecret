# Favicon fetch worker: manual triggers & operation

**Symptom.** A custom domain's auto-fetched favicon is missing, stale, or you
want to re-fetch on demand. The favicon-fetch job (#3780) discovers and stores a
domain's icon over HTTPS through an SSRF-guarded fetcher, but it is **disabled by
default** — so nothing fetches until the feature flag is on.

## Feature flags (gate everything)

| Flag | Default | Effect when off |
| ---- | ------- | --------------- |
| `jobs.favicon_fetch.enabled` | `false` | Every enqueue site is skipped; the worker acks-and-drops any message it receives (`favicon_fetch_worker.rb:159`). The HTTP endpoint still returns a "queued" success but enqueues nothing. |
| `jobs.favicon_backfill.enabled` | `false` | Nightly backfill scan does nothing. Requires `jobs.favicon_fetch.enabled` **also** on. |
| `jobs.enabled` | — | When off (dev/test default), the publisher has no RabbitMQ channel and runs the fetch **inline, synchronously, on the calling thread** instead of queueing. |

To exercise any path end-to-end against the real queue you need both
`jobs.favicon_fetch.enabled: true` and `jobs.enabled: true`.

## Queue topology

- Queue: `domain.favicon.fetch` → DLX `dlx.domain.favicon` → DLQ
  `dlq.domain.favicon` (`lib/onetime/jobs/queues/config.rb:72`)
- Worker: `Onetime::Jobs::Workers::FaviconFetchWorker`
  (`lib/onetime/jobs/workers/favicon_fetch_worker.rb`)
- Unit of work: `Onetime::Operations::FetchDomainFavicon`
  (`lib/onetime/operations/fetch_domain_favicon.rb`), fetching via
  `Onetime::Http::SafeFetch`
- Enqueue chokepoint: `Onetime::Jobs::Publisher.enqueue_favicon_fetch(domain_id, force:)`
  (`lib/onetime/jobs/publisher.rb`)

## Running the consumer

Run the worker for **only** this queue:

```bash
bin/ots worker --queues domain.favicon.fetch
```

`--queues` is a comma-separated filter over auto-discovered `Sneakers::Worker`
classes, matched on each worker's `queue_name` (`worker_command.rb:378`). It
filters *which worker classes load* — it does **not** create the queue; all
exchanges/queues are declared at boot regardless. Omit `--queues` to run every
worker. With `jobs.favicon_fetch.enabled` off, the worker connects, consumes, and
acks-and-drops.

## Manual triggers

All of these converge on `enqueue_favicon_fetch` (which queues, or inline-runs
the operation when `jobs.enabled` is off).

**1. HTTP endpoint** — `POST /api/domains/:extid/icon/refresh`.
Hardcodes `force: true`; no client `force` param. Gated on `manage_org` +
`custom_branding` entitlement (`refresh_domain_favicon.rb`).

```bash
curl -X POST https://<host>/api/domains/<extid>/icon/refresh -H "Cookie: <session>"
```

**2. UI button** — "Refresh favicon from domain" in the Brand Manager
(`SimpleBrandPanel.vue`, `data-testid="domain-favicon-refresh"`). Calls the
endpoint above. Disabled for user-uploaded icons.

**3. Console** (`bin/ots console`). Note `domain_id` is the CustomDomain
**identifier** (`domainid` == `objid`), **not** the route `extid`:

```ruby
# Enqueue (inline-runs if jobs disabled). Not flag-gated itself:
Onetime::Jobs::Publisher.enqueue_favicon_fetch("<domain_identifier>", force: true)

# Skip the queue entirely, run the fetch synchronously in-process:
Onetime::Operations::FetchDomainFavicon.new(domain_id: "<domain_identifier>", force: true).call
```

**4. Nightly backfill, kicked manually** — `FaviconBackfillJob` scans eligible
domains and enqueues each. The scan method is private; needs both flags on for
real enqueue:

```ruby
Onetime::Jobs::Scheduled::FaviconBackfillJob.send(:backfill_favicons)
```

Automatic (non-manual) triggers, for context: on domain add
(`add_domain.rb`, `force: false`) and on the first verify→verified transition
(`verify_domain.rb`).

## Overwrite guard

`force: true` re-fetches but still will **not** overwrite a `user_upload` (or
legacy untagged) icon — only an empty slot or an existing `auto_fetch` icon is
replaced (`fetch_domain_favicon.rb:175`). The UI button is only meaningful when
the icon is empty or `auto_fetch`.

## Verify the outcome

The result lands on the `CustomDomain`, not in the HTTP/enqueue response (the
POST returns immediately; the icon arrives later via the worker). Inspect from
console (`custom_domain.rb:102-108`):

| Field | Meaning |
| ----- | ------- |
| `favicon_fetch_status` | `PENDING` / `PROCESSING` / `COMPLETED` / `FAILED` |
| `favicon_fetched` | `true` once an icon was actually stored |
| `favicon_fetch_error` | last failure message |
| `favicon_fetch_started_at` | epoch secs a `PROCESSING` run began (stale-in-flight window) |
| `favicon_fetch_completed_at` | epoch secs of the last terminal outcome |
| `favicon_fetch_attempts` / `favicon_fetch_next_at` | backoff counter + earliest eligible re-fetch |

A message that fails terminally lands in `dlq.domain.favicon`. A run stuck at
`PROCESSING` with no `favicon_fetch_completed_at` is re-enqueued by the nightly
backfill once its stale-in-flight window elapses.

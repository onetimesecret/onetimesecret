# e2e/visual/README.md

---

# Visual regression — quick reference

Details: `docs/specs/qa/visual-regressions/qa-visual-regressions-approach.md` and `bin/visual --help`.

## Check the current tree against the committed baselines

```bash
pnpm run build
bin/visual
pnpm exec playwright show-report e2e/playwright-report   # only if it failed
```

## Compare the current tree against a released version

```bash
pnpm run build
oras pull ghcr.io/onetimesecret/onetimesecret/visual-baselines:v0.25.11 \
  -o e2e/visual/.artifacts/v0.25.11
bin/visual --compare e2e/visual/.artifacts/v0.25.11
pnpm exec playwright show-report e2e/playwright-report
```

In the report, open a failure and use the **Slider** tab. Every diff is a
customer-visible change between that release and your tree.

## Update the committed baselines (after an intentional UI change)

Regenerate against an **empty datastore**, then verify against a freshly
emptied one:

```bash
pnpm run build
VALKEY_URL='redis://127.0.0.1:6379/15' bin/visual --update   # unused DB index
VALKEY_URL='redis://127.0.0.1:6379/15' bin/visual            # verify: expect all cells pass
git add e2e/visual/*-snapshots/
```

Why: `bin/visual` pins every *renderable* config surface (see `VISUAL_ENV`) but
deliberately does not pin the datastore — it inherits ambient `VALKEY_URL` /
`REDIS_URL`, and `rake qa:visual:seed` only writes fixtures, it never flushes
(by design; see the approach doc). Reusing a store that a previous run or
another suite touched leaves a stale secret-verifier behind, and the
`secret--revealed` cells then fail with a 500 that looks exactly like a product
bug rather than dirty state.

Substitute your own host/port — the example above is not a real deployment.
The URI's DB index is what actually selects the logical database: the
`site.redis.dbs` map reads like a per-data-type override, but nothing consumes
it except the startup log banner (`initializers/print_log_banner.rb`), so
appending an unused index to the URI is enough to isolate a run. A throwaway
instance works equally well. Two caveats: the worktree forest shares one Valkey
instance, so pick an index no other worktree or agent is using, and pass the
**same** URL to the verify run — a verify against a different store proves
nothing.

One more ambient variable can stop the run before it renders anything. An
`AUTH_DATABASE_URL` inherited from a dev `.env` **wins** over `bin/visual`'s
ephemeral sqlite fallback, so if it points at a Postgres whose migrator
credentials no longer work, boot dies at `[4/24] Rodauth Migrations FAILED`
with a `PG::ConnectionBad`. The visual pages are all noauth and the authdb only
has to exist and migrate, so clear it (along with
`AUTH_DATABASE_URL_MIGRATIONS`) and let the sqlite fallback take over rather
than repairing the dev database:

```bash
env -u AUTH_DATABASE_URL -u AUTH_DATABASE_URL_MIGRATIONS \
  VALKEY_URL='redis://127.0.0.1:6379/15' bin/visual --update
```

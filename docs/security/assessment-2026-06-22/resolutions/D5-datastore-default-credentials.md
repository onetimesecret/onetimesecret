# D5 — Unauthenticated Valkey (host-exposed) and `guest:guest` RabbitMQ defaults

- **Severity:** Medium
- **Status:** Proposed fix
- **Affects default config?** **Yes** — both compose files run Valkey unauthenticated; the simple compose
  publishes `6379` to the host; the full compose defaults RabbitMQ to `guest:guest`.
- **Related:** Finding 06 #5 and #6 (consolidated here). Config-drift §5.
- **Primary files:** `docker/compose/docker-compose.simple.yml:57` (`--bind 0.0.0.0`), `:68-69`
  (`ports: - '6379:6379'`); `docker/compose/docker-compose.full.yml:99` (`--bind 0.0.0.0`), `:113`
  (`expose: '6379'`), `:129-130` (`RABBITMQ_DEFAULT_USER/PASS ...:-guest`), `:167`,`:205`
  (`amqp://${RABBITMQ_USER:-guest}:${RABBITMQ_PASS:-guest}@rabbitmq:5672`); `etc/examples/valkey.conf:7`
  (`#requirepass CHANGEME`).

## Problem (recap)

**Valkey has no authentication in either compose file**, and the simple compose exposes it to the host:

- `docker-compose.simple.yml` starts `valkey-server ... --bind 0.0.0.0 --port 6379` (`:57-58`) with **no
  `requirepass`/ACL**, and publishes it to the host: `ports: - '6379:6379'` (`:68-69`). On any host
  without an external firewall, the secret store — which holds encrypted secrets and session data —
  is reachable on the host/LAN with **no authentication**.
- `docker-compose.full.yml` is better: Valkey is `expose:`-only on the internal `onetime-network` bridge
  (`:113`, not host-published) — but it still runs `--bind 0.0.0.0` with **no `requirepass`** (`:99`), so
  anything that reaches the internal network (a compromised sibling container, a misconfigured network)
  has unauthenticated read/write to the datastore.
- The shipped example `etc/examples/valkey.conf:7` has `#requirepass CHANGEME` **commented out**, so even
  operators who mount it get no password by default.

**RabbitMQ defaults to `guest:guest`** in the full stack:

- `docker-compose.full.yml:129-130` — `RABBITMQ_DEFAULT_USER=${RABBITMQ_USER:-guest}` /
  `RABBITMQ_DEFAULT_PASS=${RABBITMQ_PASS:-guest}`, and the workers/scheduler connect with
  `amqp://${RABBITMQ_USER:-guest}:${RABBITMQ_PASS:-guest}@rabbitmq:5672` (`:167`, `:205`). Ports are
  `expose:`-only (`:140-142`, not host-published), so blast radius is the internal network, but shipping
  well-known default credentials is poor hygiene and a footgun if anyone ever publishes the port.

## Root cause

The compose files prioritize zero-config startup over secure defaults: Valkey is started with no
`requirepass` (and host-published in the simple variant), and RabbitMQ falls back to the vendor's
`guest:guest` rather than failing closed on missing credentials — unlike the app's `SECRET`, which the
same files correctly gate with `${SECRET:?...}` (`docker-compose.simple.yml:27`,
`docker-compose.full.yml:65`).

## Prescribed resolution

### Implementation steps

1. **Require a Valkey password and pass it to the app.** Generate one in `install.sh` alongside the other
   secrets (it already uses `SecureRandom`-based generation and `chmod 600` on `.env`), write it to
   `.env`, then wire it in:

   - **Valkey command** (both compose files, `:50-62` simple / `:92-104` full) — add a password and bind
     to the container interface only:
     ```yaml
     command: >
       valkey-server
       --appendonly yes
       # ... existing flags ...
       --requirepass ${VALKEY_PASSWORD:?VALKEY_PASSWORD must be set — run ./install.sh}
     ```
   - **App / worker / scheduler `VALKEY_URL`** — include the password (currently
     `redis://maindb:6379/0`, `:26`/`:63`/`:165`/`:203`):
     ```yaml
     - VALKEY_URL=redis://:${VALKEY_PASSWORD}@maindb:6379/0
     ```
   - **Healthcheck** must authenticate too (`:74` simple / `:119` full):
     ```yaml
     test: ['CMD', 'valkey-cli', '-a', '${VALKEY_PASSWORD}', 'ping']
     ```
   Use `:?` (fail-closed) for `VALKEY_PASSWORD` in the same way `SECRET` is gated, so the stack refuses to
   start with an empty password rather than silently running open.

2. **Do not publish 6379 to the host in the simple compose.** Drop the host port mapping at
   `docker-compose.simple.yml:68-69`. If host access is genuinely needed for debugging, bind to loopback
   only:
   ```yaml
   # remove:
   #   ports:
   #     - '6379:6379'
   # if local debugging is required, scope to localhost only:
   ports:
     - '127.0.0.1:6379:6379'
   ```
   The full compose already does the right thing (`expose: '6379'`, `:113`) — keep that. Consider keeping
   `--bind 0.0.0.0` (necessary so other containers on the docker network can connect) but rely on
   `requirepass` + network isolation rather than the bind address for security.

3. **Update `etc/examples/valkey.conf`** so the mounted-config path is also safe by default: change `:7`
   from `#requirepass CHANGEME` to an active, documented `requirepass` (or a clear note that it MUST be
   set), and keep `bind 127.0.0.1` for the non-Docker local case.

4. **Require non-default RabbitMQ credentials.** In `install.sh`, generate `RABBITMQ_USER` /
   `RABBITMQ_PASS` and write them to `.env`. Then change the full compose to fail closed instead of
   falling back to `guest`:
   ```yaml
   # docker-compose.full.yml:129-130
   - RABBITMQ_DEFAULT_USER=${RABBITMQ_USER:?RABBITMQ_USER must be set — run ./install.sh}
   - RABBITMQ_DEFAULT_PASS=${RABBITMQ_PASS:?RABBITMQ_PASS must be set — run ./install.sh}
   ```
   and the worker/scheduler URLs (`:167`, `:205`):
   ```yaml
   - RABBITMQ_URL=amqp://${RABBITMQ_USER}:${RABBITMQ_PASS}@rabbitmq:5672
   ```
   Document credential rotation (regenerate, update `.env`, recreate the RabbitMQ container so the new
   default user takes effect, or use `rabbitmqctl` to change the password in place).

5. **Document the upgrade path** for existing deployments: setting `requirepass` on an existing Valkey
   requires the app's `VALKEY_URL` to carry the password simultaneously (restart both together), and
   rotating the RabbitMQ default user on an existing volume requires either recreating the broker or an
   in-place `rabbitmqctl change_password`.

### Alternatives considered

- **Valkey ACL users instead of a single `requirepass`:** stronger (least-privilege per client), and
  recommended if the threat model warrants — but a single strong `requirepass` plus network isolation is
  a proportionate baseline and far simpler to wire through `install.sh`. ACLs can layer on top later.
- **TLS between app and Valkey/RabbitMQ:** valuable for hostile networks, but heavier (cert management);
  out of scope for closing the default-credentials gap. The container network + auth is the priority fix.
- **Leave RabbitMQ on `guest:guest` because ports aren't published:** rejected — defence-in-depth; a
  single port-publish mistake or a compromised sibling container would expose a trivially-guessable login.

## Test / verification

```bash
# 1. Stack refuses to start without credentials (fail-closed)
unset VALKEY_PASSWORD RABBITMQ_USER RABBITMQ_PASS
docker compose -f docker/compose/docker-compose.full.yml config   # expects error on the :? vars

# 2. With creds set, Valkey rejects unauthenticated access
docker compose -f docker/compose/docker-compose.simple.yml up -d
docker exec onetime-maindb valkey-cli ping                 # -> NOAUTH Authentication required.
docker exec onetime-maindb valkey-cli -a "$VALKEY_PASSWORD" ping   # -> PONG

# 3. 6379 is not reachable from the host in the simple compose
nc -z -w2 127.0.0.1 6379 ; echo $?    # non-zero (refused) unless intentionally bound to 127.0.0.1

# 4. RabbitMQ has no guest login
docker exec onetime-rabbitmq rabbitmqctl authenticate_user guest guest   # -> fails

# 5. App + workers function end to end with the new creds
curl -s http://localhost:3000/api/v2/status     # 200; create + retrieve a secret round-trips
```

## Effort & risk

- **Effort:** Medium — touches both compose files, `valkey.conf`, and `install.sh` (credential
  generation + `.env` writes), plus migration docs for existing deployments.
- **Risk:** Medium. The breaking edge is coordinating the password across Valkey + every consumer
  (`VALKEY_URL`, healthcheck) and rotating an existing RabbitMQ default user on a persisted volume —
  sequence the rollout (set creds → recreate datastores → restart app/workers) and document it.

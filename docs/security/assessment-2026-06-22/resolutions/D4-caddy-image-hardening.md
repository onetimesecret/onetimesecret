# D4 — Internet-facing Caddy proxy image is poorly hardened

- **Severity:** Medium
- **Status:** Proposed fix
- **Affects default config?** Yes for the **full stack** — `docker-compose.full.yml` builds and runs this
  image as the TLS-terminating, internet-facing proxy. (The simple compose has no proxy.)
- **Related:** Finding 06 #4; D3 (this image re-serves the same `public/web` source maps).
- **Primary files:** `docker/variants/caddy.dockerfile:85` (`FROM debian:bookworm-slim`, unpinned, no
  `USER`), `:91-97` (apt without `--no-install-recommends`, installs curl/bind9-dnsutils/iputils-ping/netcat),
  `:114` (`COPY ./public/web ${PUBLIC_DIR}`). Reference hardening: `Dockerfile:1,62,237-238,303,331-338,348-349,407`.

## Problem (recap)

The custom Caddy build (`docker/variants/caddy.dockerfile`) is the internet-facing proxy in the full
stack, yet its runtime stage is the least-hardened image in the repo:

- **Runs as root** — there is **no `USER` directive** anywhere in the file; the final `CMD ["caddy", ...]`
  (`:125`) executes as `root` (PID 1).
- **Base image not digest-pinned** — `FROM debian:bookworm-slim` at `:85` is a floating tag. (The
  *builder* stage `:61` *is* pinned: `golang:1.26-bookworm@sha256:8e8aa801…`, and the main `Dockerfile`
  pins everything — `ruby:3.4-slim-trixie@sha256:3f335cdd…` at `Dockerfile:62`.) The runtime stage breaks
  this convention and undermines reproducibility/supply-chain integrity.
- **`apt-get install` lacks `--no-install-recommends`** (`:91-97`), pulling recommended extras, and it
  installs debugging/network tooling that does not belong in a production proxy: `curl`,
  `bind9-dnsutils` (`dig`), `iputils-ping`, `netcat-openbsd`. These broaden the attack surface and are
  handy post-exploitation primitives.
- It also copies the whole `public/web` tree (`:114`), which includes the `.js.map` source maps — see D3.

## Root cause

The Caddy variant was written for convenience (debug tools, simple base) and was not brought in line with
the hardening already applied to the main `Dockerfile` (non-root UID 1001, digest-pinned bases,
`--no-install-recommends`, minimal package set).

## Prescribed resolution

Align the runtime stage with the main image's posture.

### Implementation steps

1. **Digest-pin the runtime base.** Resolve the current digest and pin it (matching the style of
   `Dockerfile:62` and the builder stage `:61`):
   ```dockerfile
   # docker/variants/caddy.dockerfile:85
   FROM debian:bookworm-slim@sha256:<resolved-digest>
   ```
   Resolve with:
   ```bash
   docker pull debian:bookworm-slim
   docker inspect --format='{{index .RepoDigests 0}}' debian:bookworm-slim
   ```

2. **Drop `--install-recommends` and the debugging tools.** Caddy needs only `ca-certificates` at runtime
   (TLS to upstreams/ACME). Replace `:91-97` with:
   ```dockerfile
   RUN apt-get update && apt-get install -y --no-install-recommends \
           ca-certificates \
       && rm -rf /var/lib/apt/lists/*
   ```
   Remove `curl`, `bind9-dnsutils`, `iputils-ping`, `netcat-openbsd`. (If a container healthcheck needs
   an HTTP probe, use Caddy's built-in `/health` or the admin API on `:2019` rather than shipping `curl`;
   the compose healthcheck for the proxy can hit the admin endpoint.)

3. **Run as a non-root user.** Create a dedicated user and switch to it before `CMD`. Caddy binds 80/443,
   which are privileged ports — grant the binary the capability to bind low ports instead of running as
   root:
   ```dockerfile
   # after COPY of the caddy binary (:100) and before VOLUME/CMD
   RUN groupadd -r caddy && useradd -r -g caddy -d /data -s /sbin/nologin caddy \
       && setcap 'cap_net_bind_service=+ep' /usr/bin/caddy \
       && mkdir -p /data /config ${PUBLIC_DIR} \
       && chown -R caddy:caddy /data /config ${PUBLIC_DIR}
   # ...
   USER caddy
   ```
   (Requires `libcap2-bin` at build time for `setcap`; install it in the apt step and it can be removed,
   or use a multi-stage `setcap`. Alternatively keep `cap_net_bind_service` and confirm the orchestrator
   doesn't drop it.) Verify the `/data` and `/config` `VOLUME`s and the served `${PUBLIC_DIR}` are owned
   by `caddy` so cert storage and config persistence keep working.

4. **Stop shipping source maps** (ties into D3): after the `COPY ./public/web ${PUBLIC_DIR}` at `:114`,
   strip maps:
   ```dockerfile
   RUN find ${PUBLIC_DIR} -name '*.map' -type f -delete
   ```

5. **Re-test the full stack** end to end (ACME/cert acquisition is the main thing that can break under a
   non-root user + capability model).

### Alternatives considered

- **Base on the official `caddy:2` image (already non-root-friendly):** attractive, but this build uses
  `xcaddy` to compile in plugins (`caddy-ratelimit`, `caddy-security`, `transform-encoder`, a `caddy-dns`
  module — `:78-82`) that the stock image lacks, so a custom runtime stage is required. Keep the custom
  build but harden it.
- **Keep root, rely on the container runtime's user namespacing:** rejected — not every deployment uses
  userns remapping; the image should be safe by default, consistent with the main image (`USER appuser`,
  `Dockerfile:303,407`).
- **`USER` without `setcap`, remap ports:** would force binding 8080/8443 and pushing port translation to
  the host — more fragile for an ACME/HTTPS proxy than `cap_net_bind_service`.

## Test / verification

```bash
# 1. Base is digest-pinned
grep -n 'FROM debian' docker/variants/caddy.dockerfile        # expect @sha256:

# 2. No debug tooling in the image
docker buildx bake -f docker/bake.hcl caddy
docker run --rm --entrypoint sh onetime-caddy:latest -c 'command -v dig ping nc curl; echo done'
#    -> none found

# 3. Runs as non-root
docker run --rm --entrypoint sh onetime-caddy:latest -c 'id -u'   # expect non-zero (not 0)

# 4. No source maps served
docker run --rm --entrypoint sh onetime-caddy:latest -c 'find /var/www/public -name "*.map"'   # empty

# 5. Functional: full stack comes up, proxy obtains/serves TLS, upstream app reachable
docker compose -f docker/compose/docker-compose.full.yml up -d
curl -sk https://localhost/api/v2/status     # 200 through the proxy
```

## Effort & risk

- **Effort:** Small–Medium. The digest pin and `--no-install-recommends` are trivial; the non-root +
  `cap_net_bind_service` change needs a build/run test pass (port binding and `/data` ownership for ACME
  certs are the things to validate).
- **Risk:** Low–Medium. The main risk is the privileged-port bind under a non-root user; `setcap
  cap_net_bind_service` resolves it. Validate ACME cert acquisition and persistence to `/data` after the
  ownership change before rolling out.

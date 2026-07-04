# Testing OCI Builds & Version Pipeline

How to verify that the version flows correctly from git tag → package.json → Docker build arg → built image.

## Quick reference

| Method | What it tests | Time | Where |
|--------|--------------|------|-------|
| `bake --print` | Bake config resolution | ~2s | Local |
| `bake --no-cache` | Full build with VERSION fallback | ~3min | Local |
| `docker run --entrypoint cat` | Version in final image | ~5s | Local |
| `workflow_dispatch` | Full CI pipeline end-to-end | ~10min | GitHub |
| `check-oci-image` (ci.yml T4) | Container boots and serves | ~3min | GitHub |
| `debug-oci.yml` | Interactive container debugging | ~5min | GitHub |
| docker-compose stacks | Multi-service integration | ~2min | Local |

---

## Local testing

### 1. Dry-run: verify bake config resolves correctly

```bash
VERSION=0.0.1-test IMAGE_TAG=v0.0.1-test \
  docker buildx bake -f docker/bake.hcl --print main
```

Confirm `VERSION`, `COMMIT_HASH`, `ALLOW_DEV_VERSION`, tags, and platforms are correct in the JSON output.

### 2. Build with simulated CI args (reproduces the failure scenario)

```bash
# On Apple Silicon, add: --set '*.platform=linux/arm64'
docker buildx bake -f docker/bake.hcl \
  --set '*.args.VERSION=0.0.1-test' \
  --set '*.args.COMMIT_HASH=abc1234' \
  --no-cache \
  --load \
  main
```

Watch for the `NOTICE:` line in build output — confirms the VERSION build arg fallback activated. Without `--no-cache`, cached layers may mask the test.

### 3. Verify version in the built image

The final image has Ruby but no Node. Use `cat` or `ruby`:

```bash
docker run --rm --entrypoint cat \
  $(docker images -q --filter 'label=org.opencontainers.image.source=https://github.com/onetimesecret/onetimesecret' | head -1) \
  package.json | grep '"version"'
```

Should show `0.0.1-test`, not `0.0.0-rc0`.

### 4. Build with ALLOW_DEV_VERSION (skip version gate)

```bash
docker buildx bake -f docker/bake.hcl \
  --set '*.args.ALLOW_DEV_VERSION=true' \
  --load \
  main
```

Useful for local iteration where you don't care about the version value.

### 5. Podman via bakah

```bash
pnpm run podman:build    # main target through bakah
pnpm run podman:run      # run the built image
pnpm run podman:image:metadata:latest  # inspect OCI labels
```

`bakah` translates bake JSON output into podman build commands.

### 6. Docker Compose stacks

```bash
# Simple: app + Redis
docker compose -f docker/compose/docker-compose.simple.yml up

# Full: app + Redis + Mailpit
docker compose -f docker/compose/docker-compose.full.yml up

# Root docker-compose.yml (default)
docker compose up
```

---

## CI testing

### 7. Manual workflow dispatch (no git tag needed)

```bash
gh workflow run build-and-publish-oci-images.yml \
  --ref fix/2651-version-arg \
  --field version_tag=0.0.1-test \
  --field registry_target=custom \
  --field platforms=linux/amd64
```

- `registry_target=custom` avoids publishing to public registries
- The pre-build audit step prints the resolved bake config
- The post-build audit step pulls the image via podman and checks the version

### 8. CI container validation (ci.yml, Tier 4)

The `check-oci-image` job in `ci.yml` builds with `ALLOW_DEV_VERSION=true` (no real version needed), then:

1. `generate-test-secrets` action creates ephemeral crypto secrets
2. `test-docker-container` composite action starts the container, waits for health, tests endpoints, and cleans up

Triggers automatically on PRs that touch Dockerfile, docker/, or frontend code.

### 9. Debug workflow (interactive)

```bash
gh workflow run debug-oci.yml --field debug_enabled=true
```

Builds the image, starts it with a Valkey service container, runs health checks, and optionally drops into a tmate session for live debugging.

---

## Inspecting CI runs

### View recent build runs

```bash
gh run list --workflow=build-and-publish-oci-images.yml --limit 5
```

### Check workflow dispatch inputs

GitHub's API doesn't expose dispatch inputs directly. Recover them from the log:

```bash
# Get the run ID from the list above, then:
RUN_ID=23120101542

# Dispatch inputs (version_tag, registry_target, etc.)
gh run view "$RUN_ID" --log 2>&1 | grep "INPUT_VERSION_TAG:" | head -1

# Resolved build config from audit step
gh run view "$RUN_ID" --log 2>&1 | grep "Audit — resolved" | grep -E "(VERSION|PLATFORMS|REGISTRY_MODE):" | grep -v debug

# Post-build version verification
gh run view "$RUN_ID" --log 2>&1 | grep "Audit — verify" | grep -E "(Expected|Actual):"
```

### Watch a running build

```bash
gh run watch "$RUN_ID"
```

### Re-run a failed build

```bash
gh run rerun "$RUN_ID" --failed
```

---

## Version pipeline flow

```
git tag v1.0.0
    ↓
workflow: update-version.sh (patches package.json on runner)
    ↓
workflow: node -p "require('./package.json').version"  →  step output VERSION
    ↓
bake: *.args.VERSION=$VERSION  →  Dockerfile ARG VERSION
    ↓
Dockerfile build stage:
  1. COPY package.json (from build context — may still have 0.0.0-rc0)
  2. Check: if 0.0.0-rc0 AND VERSION arg is valid → patch in-container
  3. Check: if still 0.0.0-rc0 → fail (unless ALLOW_DEV_VERSION=true)
  4. pnpm run build (Vite uses correct version)
  5. Write commit_hash.txt
    ↓
final stage: COPY --from=build package.json (patched version)
```

## Key files

| File | Role |
|------|------|
| `.github/scripts/update-version.sh` | Host-side version injection (jq) |
| `Dockerfile` (build stage) | In-container VERSION fallback + gate |
| `docker/bake.hcl` | Build orchestration, `_common` target passes VERSION arg |
| `.github/workflows/build-and-publish-oci-images.yml` | Release build + audit steps |
| `.github/workflows/ci.yml` (`check-oci-image`) | PR container validation |
| `.github/workflows/debug-oci.yml` | Interactive debugging |
| `.github/actions/test-docker-container/` | Reusable container test harness |
| `.github/actions/generate-test-secrets/` | Ephemeral secret generation |
| `package.json` (`docker:*`, `podman:*` scripts) | Local build shortcuts |
| `docker/compose/*.yml` | Multi-service stacks |

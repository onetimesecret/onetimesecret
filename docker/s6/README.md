# S6 Overlay Multi-Process Container Setup

This directory contains S6 overlay service definitions for running multiple processes in a single container with proper supervision and graceful shutdown.

## Quick Start

Build with S6 overlay using the build script:

```bash
./docker/s6/build.sh
```

Or manually using the main Dockerfile:

```bash
docker build --target final-s6 -t onetimesecret:s6 .
```

The S6 build is a multi-stage target in the main `Dockerfile` that adds process supervision to run web + scheduler + worker in a single container.

## Overview

The S6 overlay provides a production-ready init system (PID 1) and process supervisor for Docker containers. It solves common container problems:

- **Zombie process reaping**: Properly handles orphaned child processes
- **Automatic restart**: Services restart on crash
- **Graceful shutdown**: Coordinated shutdown of all services
- **Service dependencies**: Ensures services start in correct order
- **Signal handling**: Proper SIGTERM/SIGINT forwarding

## Directory Structure

```
scripts/s6-rc.d/
├── redis-ready/          # Oneshot: Redis connectivity check
│   ├── type
│   └── up
├── config-check/         # Oneshot: Config validation (v0.24.0 migration)
│   ├── type
│   └── up
├── web/                  # Longrun: Puma/Thin web server
│   ├── type
│   ├── dependencies
│   ├── run
│   └── finish
├── scheduler/            # Longrun: Job scheduler
│   ├── type
│   ├── dependencies
│   ├── run
│   └── finish
├── worker/               # Longrun: Job worker
│   ├── type
│   ├── dependencies
│   ├── run
│   └── finish
└── user/                 # Bundle: Groups all services
    ├── type
    └── contents.d/
        ├── web
        ├── scheduler
        └── worker
```

## Service Types

### Oneshot Services (Pre-Flight Checks)

Run once at container startup before longrun services start.

- **redis-ready**: Validates Redis/Valkey environment configuration
- **config-check**: Ensures config migration for v0.24.0 is complete

### Longrun Services (Supervised Processes)

Continuous processes supervised by S6. Automatically restart on crash.

- **web**: Puma or Thin web server (controlled by `SERVER_TYPE` env var)
- **scheduler**: Job scheduler (`bin/ots scheduler`)
- **worker**: Job worker (`bin/ots worker`)

### Bundle

The `user` bundle groups all three longrun services. When S6 starts, it brings up the entire bundle.

## Build Options

The build script accepts all standard Docker build arguments:

```bash
# Multi-platform build
./docker/s6/build.sh --platform linux/amd64,linux/arm64

# No cache
./docker/s6/build.sh --no-cache

# Custom tag
TAG=myregistry/onetimesecret:s6 ./docker/s6/build.sh

# Build args
./docker/s6/build.sh --build-arg VERSION=1.0.0
```

## Usage Patterns

### 1. All Services (Default - Multi-Process Container)

Run web + scheduler + worker in a single container:

```bash
# No command override needed - S6 starts all services
docker run -p 3000:3000 \
  -e REDIS_URL=redis://redis:6379/0 \
  -e SECRET=your-secret \
  onetimesecret
```

**Use case**: Development, staging, single-server deploys

### 2. Web Server Only

Run only the web server (like original `entrypoint.sh`):

```bash
docker run -p 3000:3000 \
  -e REDIS_URL=redis://redis:6379/0 \
  -e SECRET=your-secret \
  onetimesecret \
  bin/entrypoint.sh
```

**Use case**: Production multi-container setup, separate web scaling

### 3. Individual Services (Advanced)

Run specific services using S6:

```bash
# Web only (supervised by S6)
docker run -p 3000:3000 onetimesecret:s6 \
  /init with-contenv s6-rc -u change web

# Scheduler only
docker run onetimesecret:s6 \
  /init with-contenv s6-rc -u change scheduler

# Worker only
docker run onetimesecret:s6 \
  /init with-contenv s6-rc -u change worker
```

## Environment Variables

### Web Server Configuration

- `SERVER_TYPE`: Server to run (`puma` or `thin`, default: `puma`)
- `PORT`: Port to bind (default: `3000`)

### Puma Configuration (when SERVER_TYPE=puma)

- `PUMA_WORKERS`: Number of worker processes (default: `2`)
- `PUMA_MIN_THREADS`: Minimum threads per worker (default: `4`)
- `PUMA_MAX_THREADS`: Maximum threads per worker (default: `16`)

### S6 Configuration

- `S6_BEHAVIOUR_IF_STAGE2_FAILS`: Behavior when services fail (default: `2` - continue)
- `S6_CMD_WAIT_FOR_SERVICES_MAXTIME`: Max wait for services (default: `0` - no timeout)
- `S6_VERBOSITY`: Logging verbosity (default: `2` - info)

## Debugging

### Check Service Status

```bash
# List all services
docker exec <container> s6-rc-db list all

# Check specific service status
docker exec <container> s6-svstat /run/service/web
docker exec <container> s6-svstat /run/service/scheduler
docker exec <container> s6-svstat /run/service/worker

# View service logs (real-time)
docker exec <container> s6-tail /run/service/web
```

### Manual Service Control

```bash
# Restart a service
docker exec <container> s6-svc -r /run/service/web

# Stop a service
docker exec <container> s6-svc -d /run/service/worker

# Start a service
docker exec <container> s6-svc -u /run/service/worker
```

### Common Issues

**Container exits immediately**
- Check logs: `docker logs <container>`
- Verify config migration: Look for "Migration required" message
- Check Redis connectivity: Set `ONETIME_DEBUG=1` for verbose output

**Service keeps restarting**
- View service logs: `docker exec <container> s6-tail /run/service/<name>`
- Check exit codes in finish script output
- Verify dependencies are met (Redis connectivity)

**Graceful shutdown timeout**
- Increase Docker stop timeout: `docker stop -t 60 <container>`
- Check Puma `worker_shutdown_timeout` in `etc/puma.rb`

## Architecture Details

### Service Dependencies

```
user (bundle)
├── web
│   ├── redis-ready (oneshot)
│   └── config-check (oneshot)
├── scheduler
│   ├── redis-ready (oneshot)
│   └── config-check (oneshot)
└── worker
    ├── redis-ready (oneshot)
    └── config-check (oneshot)
```

All longrun services depend on pre-flight checks completing successfully.

### Process Hierarchy

```
S6 PID 1 (/init)
  └─ s6-svscan (supervisor)
       ├─ s6-supervise web
       │    └─ puma master
       │         ├─ puma worker 1
       │         ├─ puma worker 2
       │         └─ puma worker N
       ├─ s6-supervise scheduler
       │    └─ bin/ots scheduler
       └─ s6-supervise worker
            └─ bin/ots worker
```

**Important**: S6 supervises the master process. Puma's fork hooks work unchanged - S6 doesn't interfere with worker forking.

### Graceful Shutdown Sequence

1. Docker sends SIGTERM to PID 1 (S6 init)
2. S6 stops services in reverse dependency order
3. Each service receives SIGTERM
4. Finish scripts run (log exit codes)
5. Container exits cleanly

## Puma Integration

Existing Puma configuration in `etc/puma.rb` requires **NO changes**. S6 supervises the master process only.

```ruby
# etc/puma.rb (unchanged)
before_fork do
  Onetime::Boot::InitializerRegistry.cleanup_before_fork
end

before_worker_boot do
  Onetime::Boot::InitializerRegistry.reconnect_after_fork
end
```

**What S6 adds**:
- If Puma master crashes, S6 restarts it automatically
- Graceful shutdown: S6 → Puma master → workers (clean connection close)
- Stdout/stderr logging from master and all workers

## Migration from Legacy Entrypoints

### Before (entrypoint.sh)

```dockerfile
CMD ["bin/entrypoint.sh"]
```

### After (S6 multi-process)

```dockerfile
ENTRYPOINT ["/init"]
CMD []
```

### Rollback Plan

To revert to legacy entrypoint behavior, override the entrypoint:

```bash
docker run --entrypoint bin/entrypoint.sh onetimesecret
```

Or update Dockerfile:

```dockerfile
ENTRYPOINT []
CMD ["bin/entrypoint.sh"]
```

## Production Considerations

**Memory overhead**: S6 adds ~3-5 MB RSS (negligible)

**Health checks**: Verify critical services

```dockerfile
HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=3 \
    CMD s6-svstat /run/service/web && curl -f http://127.0.0.1:3000/health
```

**Deployment strategy**:
- Test multi-process container in staging first
- Monitor for 24-48 hours
- Compare metrics: restart rate, memory, response times
- Roll out to production gradually

## References

- [S6 Overlay Documentation](https://github.com/just-containers/s6-overlay)
- [S6 Service Management](https://skarnet.org/software/s6/overview.html)
- [Execline Language](https://skarnet.org/software/execline/) (used in run/up scripts)

# Systemd Unit Files for Onetime Secret Job System

This directory contains systemd service files for running the Onetime Secret job system in production.

## Installation

1. Copy the service files to the systemd directory:

```bash
sudo cp etc/systemd/*.service /etc/systemd/system/
sudo cp etc/systemd/ots.target /etc/systemd/system/
```

2. Reload systemd:

```bash
sudo systemctl daemon-reload
```

3. Enable services to start on boot:

```bash
# Enable the target (which includes all workers and scheduler)
sudo systemctl enable ots.target

# Or enable individual services
sudo systemctl enable ots-scheduler.service
sudo systemctl enable ots-worker@email.service
sudo systemctl enable ots-worker@notifications.service
sudo systemctl enable ots-worker@default.service
```

## Usage

### Start all services

```bash
sudo systemctl start ots.target
```

### Start individual services

```bash
# Start scheduler
sudo systemctl start ots-scheduler.service

# Start specific worker
sudo systemctl start ots-worker@email.service
```

### Check status

```bash
# Overall target status
sudo systemctl status ots.target

# Individual service status
sudo systemctl status ots-scheduler.service
sudo systemctl status ots-worker@email.service

# Or use the CLI status command
bin/ots jobs status
```

### View logs

```bash
# Scheduler logs
sudo journalctl -u ots-scheduler.service -f

# Worker logs (specific queue)
sudo journalctl -u ots-worker@email.service -f

# All job system logs
sudo journalctl -u 'ots-*' -f
```

### Restart services

```bash
# Restart all
sudo systemctl restart ots.target

# Restart individual service
sudo systemctl restart ots-scheduler.service
sudo systemctl restart ots-worker@email.service
```

### Stop services

```bash
# Stop all
sudo systemctl stop ots.target

# Stop individual service
sudo systemctl stop ots-scheduler.service
sudo systemctl stop ots-worker@email.service
```

## Service Instances

The worker service is a template unit (`ots-worker@.service`) that can be instantiated multiple times with different queue names:

- `ots-worker@email.service` - Processes email queue
- `ots-worker@notifications.service` - Processes notifications queue
- `ots-worker@default.service` - Processes default queue

To add a new worker instance:

```bash
sudo systemctl enable ots-worker@myqueue.service
sudo systemctl start ots-worker@myqueue.service
```

## Configuration

### Environment Variables

Environment variables can be set in two ways:

1. System-wide: `/etc/onetime/environment`
2. Application-level: `/opt/onetime/.env`

Both files are loaded via `EnvironmentFile` directives in the service units.

Example `/etc/onetime/environment`:

```bash
RACK_ENV=production
RABBITMQ_URL=amqp://user:pass@localhost:5672
REDIS_URL=redis://localhost:6379/0
LOG_LEVEL=info
```

### Worker Configuration

Each worker instance processes specific queues. The queue name is passed via the `%i` instance specifier.

To modify concurrency for a specific worker, edit the service file or create an override:

```bash
sudo systemctl edit ots-worker@email.service
```

Add:

```ini
[Service]
ExecStart=
ExecStart=/opt/onetime/bin/ots jobs worker --queues email --concurrency 20 --environment production
```

### Security

The service files include security hardening (requires systemd 252+, Debian 13+):

- Run as unprivileged `onetime` user/group
- `NoNewPrivileges=true` - Prevents privilege escalation
- `PrivateTmp=true` - Isolated /tmp
- `ProtectSystem=strict` - Read-only system directories
- `ProtectHome=true` - Inaccessible home directories
- `ReadWritePaths` - Only /opt/onetime/tmp and /opt/onetime/log are writable
- `ProtectClock=true` - Cannot modify system clock
- `ProtectHostname=true` - Cannot change hostname
- `ProtectProc=invisible` - Hides other processes in /proc
- Kernel protection and namespace restrictions

### Graceful Shutdown

Workers and scheduler support graceful shutdown:

- `TimeoutStopSec=90` - 90 seconds to finish in-flight jobs before SIGKILL
- `KillMode=mixed` - SIGTERM to main process, SIGKILL to stragglers
- `SuccessExitStatus=0 143` - SIGTERM exit (143) is considered success

### Scheduler Reload

The scheduler supports USR1 signal to log scheduled job status:

```bash
sudo systemctl reload ots-scheduler.service
sudo journalctl -u ots-scheduler.service -n 20
```

### Resource Limits

Default resource limits per service:

**Workers:**
- Memory: 512MB max, 384MB high watermark
- Tasks: 50 max

**Scheduler:**
- Memory: 256MB max, 192MB high watermark
- Tasks: 20 max

Adjust these in the service files or via overrides if needed.

## Troubleshooting

### Service won't start

Check dependencies are running:

```bash
sudo systemctl status rabbitmq-server.service
sudo systemctl status redis.service
```

Check logs:

```bash
sudo journalctl -u ots-worker@email.service -n 50
```

### High memory usage

Check memory limits in service file and adjust if needed. Monitor with:

```bash
systemctl show ots-worker@email.service -p MemoryCurrent
```

### Workers not processing jobs

1. Check RabbitMQ connectivity:

```bash
bin/ots jobs status
```

2. Verify queue exists and has messages:

```bash
sudo rabbitmqctl list_queues name messages consumers
```

3. Check worker logs for errors:

```bash
sudo journalctl -u ots-worker@email.service -f
```

## Dependencies

Services depend on:

- `network-online.target` - Network is up
- `rabbitmq-server.service` - RabbitMQ is running
- `redis.service` - Redis is running

If using different service names, adjust the `After=` directives in the unit files.

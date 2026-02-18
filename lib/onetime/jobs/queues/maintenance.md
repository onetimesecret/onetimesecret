# Queue Maintenance

RabbitMQ queue arguments are **immutable** after declaration. Changing an argument (e.g. adding `x-message-ttl` to an existing DLQ) causes `PRECONDITION_FAILED` errors. Two approaches handle this gracefully; a third exists for dev or when message loss is acceptable.

## 1. Policies over Arguments (preferred)

Use RabbitMQ **policies** for operational parameters (`x-message-ttl`, `x-max-length`, etc.) instead of queue arguments. Policies are mutable at runtime.

```bash
# Set TTL on all DLQs via policy (no code deploy needed)
rabbitmqctl set_policy dlq-ttl "^dlq\." '{"message-ttl": 604800000}' --apply-to queues

# Change it later without touching any queue definitions
rabbitmqctl set_policy dlq-ttl "^dlq\." '{"message-ttl": 259200000}' --apply-to queues
```

Reserve queue arguments for structural properties that truly define the queue's identity. Move operational tunables (TTL, max-length, overflow behavior) to policies.

## 2. Versioned Queues (when arguments must change)

Two-phase migration, analogous to a DB column rename across releases:

**Release 1** — Add the new queue, bridge consumers:
- Declare `dlq.email.message.v2` with updated arguments
- Deploy consumers that read from both v1 and v2
- Route new dead letters to v2

**Release 2** — Remove the old queue:
- Confirm v1 is drained (no pending messages)
- Remove v1 consumer bindings
- Delete the old queue

## 3. Nuclear: `bin/ots queue reset --force`

Deletes and recreates all queues from `QueueConfig::QUEUES` definitions. **Destroys in-flight messages.** Acceptable for dev environments and for DLQs in production where messages are already-logged failures. Not suitable for primary work queues with unprocessed messages.

```bash
bin/ots queue reset --force
```

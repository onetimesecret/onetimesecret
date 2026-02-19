# Queue Maintenance

RabbitMQ queue arguments are **immutable** after declaration. Changing a queue argument on an existing queue causes `PRECONDITION_FAILED` errors on startup. Two approaches handle this gracefully; a third exists for dev or when message loss is acceptable.

## 1. Policies over Arguments (preferred)

Use RabbitMQ **policies** for operational parameters (`x-message-ttl`, `x-max-length`, etc.) instead of queue arguments. Policies are mutable at runtime — no queue recreation, no message loss.

DLQ TTL is managed this way. `bin/ots queue init` applies the `dlq-ttl` policy automatically via the Management API. `bin/ots queue status` reports active policies.

To change the TTL without a deploy:

```bash
# Update TTL on all DLQs at runtime (no queue deletion, no code deploy)
rabbitmqctl set_policy dlq-ttl "^dlq\." '{"message-ttl": 259200000}' --apply-to queues
```

Or update `DLQ_MESSAGE_TTL` in `lib/onetime/jobs/queues/config.rb` and re-run `bin/ots queue init`.

Reserve queue arguments for structural properties that define the queue's identity (e.g. `x-dead-letter-exchange`). Move operational tunables (TTL, max-length, overflow behavior) to policies.

## 2. Versioned Queues (when a structural argument must change)

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

Deletes and recreates all queues from `QueueConfig::QUEUES` definitions. **Destroys in-flight messages.** Acceptable for dev environments. Not suitable for primary work queues with unprocessed messages.

```bash
bin/ots queue reset --force
```

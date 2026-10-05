# RabbitMQ Architecture

RabbitMQ implements AMQP (Advanced Message Queuing Protocol), which separates message routing from message storage. This separation is the core architectural insight.

## Big Parts

### Exchanges

An exchange receives messages from publishers and routes them to queues based on rules. It never stores messages—it's purely a routing mechanism. Think of it as a mail sorting facility.

**Exchange types:**

**Direct**: Routes based on exact routing key match. A message with routing key `email.welcome` goes only to queues bound with that exact key. Most straightforward for job queues.

**Fanout**: Ignores routing keys entirely, copies the message to every bound queue. Useful for broadcasting—audit logs, cache invalidation, notifications that multiple services care about.

**Topic**: Pattern matching on routing keys using wildcards. `email.*` matches `email.welcome` and `email.password_reset`. `email.#` matches those plus `email.marketing.weekly`. Gives you flexible subscription semantics.

**Headers**: Routes based on message header attributes rather than routing key. Rarely used in practice—topic exchanges cover most use cases more simply.

### Queues

Queues store messages until consumers acknowledge them. They're the durable part of the system. Key properties:

**Durability**: Survives broker restart if declared `durable: true` *and* messages are published as `persistent`. Both matter—a durable queue with transient messages still loses data on restart.

**Exclusivity**: An exclusive queue is deleted when its declaring connection closes. Useful for reply queues in RPC patterns.

**Auto-delete**: Queue deletes itself when the last consumer disconnects. Useful for temporary work queues.

**Arguments**: Configuration like message TTL, max length, dead letter routing, queue type (classic vs quorum).

### Bindings

A binding connects an exchange to a queue with optional routing criteria. One queue can bind to multiple exchanges. One exchange can route to multiple queues. The binding is where you express "messages matching X go to queue Y."

```ruby
# Queue 'email' receives messages from 'jobs' exchange
# when routing key is 'email'
channel.queue_bind('email', 'jobs', routing_key: 'email')
```

### Consumers and Channels

**Connection**: A TCP connection to the broker. Expensive to create, so you typically maintain one per application instance.

**Channel**: A lightweight virtual connection multiplexed over a single TCP connection. Each thread should use its own channel—channels aren't thread-safe. Creating channels is cheap.

**Consumer**: Attaches to a queue via a channel and receives messages. You control parallelism through prefetch count (`basic_qos`)—how many unacknowledged messages a consumer can hold.

```ruby
channel.basic_qos(10)  # Consumer receives up to 10 messages before acking
```

Higher prefetch = better throughput but worse distribution across consumers. Lower prefetch = fairer distribution but more network round-trips.

### Message Flow

```
Publisher
    │
    │ basic_publish(exchange, routing_key, payload)
    ▼
Exchange ──[binding rules]──► Queue ──► Consumer
                                │
                                ▼
                            (on reject/expire)
                                │
                                ▼
                           DLX Exchange ──► DLQ
```

### Acknowledgments

Messages stay in the queue until explicitly acknowledged. Three options:

- `basic_ack`: Success, remove from queue
- `basic_nack` or `basic_reject`: Failure, either requeue or send to DLQ
- No response (consumer dies): Message requeues after timeout

This is why idempotency matters—a crash after processing but before acking means the message gets redelivered.

### Practical Topology for Job Processing

A common pattern:

```
                              ┌─► queue.email ─► email workers
                              │
publisher ─► exchange.jobs ───┼─► queue.sms ─► sms workers
         (direct)             │
                              └─► queue.webhook ─► webhook workers

Each queue has:
  x-dead-letter-exchange ─► dlx.jobs ─► dlq.{type}
```

One exchange, multiple queues distinguished by routing key, each with its own DLQ for failures. Workers scale independently per queue based on load.

---

## Idempotency in Background Job Processing

Idempotency means a job can be delivered multiple times but will only be processed once. This matters because message brokers like RabbitMQ guarantee *at-least-once* delivery, not *exactly-once*. Network hiccups, worker crashes, or manual retries can cause duplicate deliveries.

### The Pattern

**Publisher side**: Attach a unique ID to each message using AMQP's standard `message_id` property:

```ruby
channel.basic_publish(
  payload,
  routing_key: 'email',
  message_id: SecureRandom.uuid
)
```

**Worker side**: Check Redis before processing, mark as done after:

```ruby
def process(delivery_info, properties, payload)
  key = "processed:#{properties.message_id}"
  return if redis.exists?(key)  # Already handled

  do_actual_work(payload)

  redis.setex(key, 3600, "1")  # 1-hour TTL
end
```

The TTL handles cleanup automatically—no maintenance required. An hour is typically enough since duplicates arrive within seconds or minutes of the original.

### Why Redis?

You need shared state across worker processes/machines. Redis is fast, ephemeral (appropriate for this use case), and you likely already have it. The alternative—database checks—adds latency and load to your primary datastore for what's essentially transient bookkeeping.

---

## Dead Letter Queues (DLQ)

A DLQ captures messages that can't be processed: rejected messages, expired messages, or messages that exceed retry limits. Without a DLQ, failed messages either disappear forever or clog your main queue.

### Declaration Order Matters

RabbitMQ requires the dead letter exchange to exist *before* you declare a queue that routes failures to it. The setup sequence:

```ruby
# 1. Dead letter exchange
channel.exchange_declare('dlx.email', :direct, durable: true)

# 2. DLQ bound to that exchange
channel.queue_declare('dlq.email', durable: true)
channel.queue_bind('dlq.email', 'dlx.email', routing_key: 'email')

# 3. Main queue with DLX configuration
channel.queue_declare(
  'email',
  durable: true,
  arguments: {
    'x-dead-letter-exchange' => 'dlx.email',
    'x-dead-letter-routing-key' => 'email'
  }
)
```

### What Ends Up in the DLQ

- Messages explicitly rejected with `requeue: false`
- Messages that exceed `x-max-length` on the main queue
- Messages that expire via TTL
- Messages rejected after exhausting retry attempts

The DLQ preserves the original message plus headers showing why it was dead-lettered, letting you inspect failures, fix bugs, and replay messages after deploying fixes.

`bin/ots queue dlq replay <queue>` (and the colonel replay endpoint) republishes each message to its original queue under its original message id. Workers keep a one-hour idempotency claim on each message id and skip a second message with the same id, so the replay releases that claim first: the worker processes a replayed message again rather than acking it as a duplicate. Side effects the first attempt completed before it failed (an email, a webhook call) can repeat. A message whose claim cannot be released because the datastore is unreachable is left in the DLQ and listed under `Errors:`.

The replay's channel is in transaction mode: the republish and the ack that removes the message from the DLQ take effect together at `tx_commit`. A message whose publish or ack fails is rolled back and listed under `Errors:`. Like a message whose claim cannot be released, it is left unacked rather than nacked with requeue, which could put it back at the head of the DLQ for the same replay to pop again. Closing the channel at the end of the replay returns it to the DLQ, so each message is tried at most once per replay. If the broker does not confirm a commit, the replay stops and reports the message with an outcome-unknown error: the republished copy may be live, and replaying the message again may repeat its side effects.

`DlqEmailConsumerJob` (`jobs.dlq_consumer`, every five minutes) replays auth emails from `dlq.email.message` automatically (raw Rodauth emails always, templated ones while their token is valid) and discards the rest. An auth email whose `x-death` header does not name its original queue (the header is missing, is not an array of tables, or has no queue name) cannot be replayed and is discarded too, with a `No original queue` error that carries the message id. It also releases the email worker's claim right before it republishes, so the replay is delivered rather than acked as a duplicate.

While it replays a message id, the job holds a reservation on it that only that run can release or finalize (`dlq:replay:reservation:<id>`, five minutes, extended to one hour when publishing starts). The publish and the ack that removes the message from the DLQ are committed separately on the job's own connection, publish first. The publish is mandatory: if no queue has the original queue's name, the broker returns the message before it confirms the commit, and the job then leaves the message in the DLQ. In a single transaction the ack would already be applied when the return arrives. The job marks the id completed (`dlq:replayed:<id>` set to `completed`, one hour) once the broker confirms the publish commit without a return, and only then acks the DLQ delivery. A completed marker means the replay was published to an existing queue, not that the email was sent. A copy of the same id that reaches the DLQ again within that hour is acked without a publish. A copy that arrives while another run holds the reservation is left for a later run.

A message the job cannot settle is left unacked and returns to the DLQ when the job closes its channel at the end of the run. It is not nacked with requeue, which could put it back at the head of the DLQ for the same run to pop again. Besides a copy that another run holds and an unexpected error while processing a message, this covers:

- A datastore error before the publish. The job releases its own reservation and the next run retries.
- A publish error. The transaction is rolled back, so no copy is live. The job releases its reservation and the next run retries.

  In both cases, if the release fails too, the reservation's TTL bounds the wait: five minutes, or one hour if publishing had already started.
- A replay the broker returns as unroutable, because the original queue no longer exists. No copy is live. The job logs an error naming the queue, counts the message under `unroutable`, releases its reservation, and tries again on every run until the queue exists or the DLQ's message TTL (seven days) removes the message. For the rest of that run, later messages for the same queue are held without a reservation or a publish; a queue recreated during a run is tried again on the next run.
- A publish commit the broker does not confirm. The copy may or may not be live, so the job stops the batch and keeps the publishing reservation. The message returns to the DLQ and is replayed once the reservation expires (up to an hour). If the commit had applied, that replay sends a second email.
- An ack, or its commit, that fails after the publish is committed. The copy is live and the message returns to the DLQ. The job stops the batch. The id is already marked completed, so the next run acks the message without publishing it again. An operator replay of the message before that run sends a second email.
- A `dlq:replayed:<id>` value of `1`, written by earlier versions before they published. It does not show that the replay happened, so the message waits until the marker expires (at most an hour) and is then replayed.

If the completed marker cannot be written after the publish commit, the job logs the failure and counts an error; the publishing reservation still holds off another replay for up to an hour. Messages without a message id get no reservation or marker, so one whose ack fails after its publish is committed is published again by the next run. Deferred messages return to the front of the DLQ. A message deferred because its id is reserved or has an earlier-version marker, because its original queue does not exist, or because processing it raised an unexpected error is held: it does not count against the batch of 50, so the run continues to the messages behind it. A run stops popping messages after 240 seconds, so a run passes over as many held messages as fit in that budget; held messages for a queue the run already found missing cost no broker or datastore round trip. A message deferred after a datastore or publish error does count against the batch, since each can cost a timeout; if a whole batch is deferred that way, the messages behind it wait for the next run. Email delivery is at-least-once: if the provider accepted an email before the delivery call raised (a read timeout, for example), the replay sends it a second time.


## Cascading Failure Scenario

```
  | Step                  | Time          | Effect                         |
  |-----------------------|---------------|--------------------------------|
  | RabbitMQ goes down    | t=0           |                                |
  | Request 1 tries email | t=0           | Worker 1 blocked               |
  | Retry 1 + sleep       | +0.5s         | Worker 1 still blocked         |
  | Retry 2 + sleep       | +1.5s         | Worker 1 still blocked         |
  | Retry 3 + sleep       | +3.0s         | Worker 1 still blocked         |
  | Sync SMTP call        | +3.0s to +33s | Worker 1 blocked for SMTP      |
  | Requests 2-N          | queued        | All workers eventually blocked |
```

With 4 Puma workers, after ~4 email requests your entire app becomes unresponsive.


## Adding a Queue

| Component | Restart Required? | Why                                                             |
|-----------|-------------------|-----------------------------------------------------------------|
| Puma      | Yes               | Initializer declares queues at boot (setup_rabbitmq.rb:109-114) |
| Workers   | Yes               | Workers only consume queues they're started with                |

Workflow:
1. Add queue to QueueConfig::QUEUES
2. Create the worker class
3. Restart Puma (declares the queue in RabbitMQ)
4. Restart workers (starts consuming from new queue)

Removing a Queue

| Component | Restart Required? | Why                                   |
|-----------|-------------------|---------------------------------------|
| Workers   | Yes               | Stop consuming before removing        |
| Puma      | Optional          | Won't declare it anymore, but no harm |

Workflow:
1. Stop workers first (drain in-flight messages)
2. Remove from QueueConfig::QUEUES
3. Restart workers
4. Optionally delete queue from RabbitMQ: rabbitmqctl delete_queue <name>

Hot Reload?

RabbitMQ itself doesn't require restart - queues can be declared anytime. But your code references QueueConfig::QUEUES at runtime, so:

- Publishers check this constant
- Workers are configured at startup
- Initializer declares on boot

No hot reload - you need process restarts to pick up queue config changes.

## Scheduler

Scheduled jobs (`lib/onetime/jobs/scheduled/`) run inside one long-lived process, `bin/ots scheduler`, on rufus-scheduler timers. They do not go through RabbitMQ.

**Run one scheduler process per datastore.** Nothing coordinates between scheduler processes: there is no cross-process lock or leader election for scheduled jobs. The `SET NX` calls in this directory (`BaseWorker`, `DlqEmailConsumerJob`) are per-message idempotency claims, not job locks. A second scheduler on the same datastore runs every job a second time.

- `docker/compose/docker-compose.full.yml` defines a single `scheduler` service with a fixed container name, so it cannot be scaled by accident.
- The S6 image runs web, scheduler and worker in one container. Replicating that container replicates the scheduler; additional replicas should run the web server only (see `docker/s6/README.md`, "Web Server Only").

Within the one process, rufus-scheduler does not stop a job from overlapping itself when a run outlasts its interval. A job that must not overlap passes `overlap: false` to `every` / `cron` (`DomainRefreshJob` does): a tick that fires while the previous run is still working is skipped, not queued. `MaintenanceJob` documents why its jobs tolerate overlap instead.

If a deployment ever needs more than one scheduler, add one shared lock helper to `ScheduledJob` (`SET NX EX` with a TTL above the job's worst-case run time, released in `ensure`) and use it from every job, rather than adding a lock to a single job.

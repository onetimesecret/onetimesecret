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

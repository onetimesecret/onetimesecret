# RabbitMQ: Console Debugging

Globals set by `SetupRabbitMQ` initializer (runs only when `jobs.enabled` is truthy):
- `$rmq_conn` — `Bunny::Session`
- `$rmq_channel_pool` — `ConnectionPool` of `Bunny::Channel`

## Config

```ruby
OT.conf.dig('jobs', 'enabled')
OT.conf.dig('jobs', 'rabbitmq_url')
OT.conf.dig('jobs', 'channel_pool_size')
```

## Connection state

```ruby
$rmq_conn&.open?
Onetime::Runtime.infrastructure.rabbitmq_configured?
```

## Manual connectivity test

```ruby
conn = Bunny.new(OT.conf.dig('jobs', 'rabbitmq_url'))
conn.start
conn.open?
conn.close
```

## Inspect queues

> **Why pool-per-check?** `Bunny::NotFound` is a channel-level AMQP exception —
> the broker closes the channel, not just the operation. If you reuse a single
> pooled channel across the loop, the first `NotFound` kills it and every
> subsequent check fails. Acquiring a fresh channel from the pool for each queue
> isolates failures and keeps the pool consistent (no leaked or stale channels).

```ruby
# Single queue
$rmq_channel_pool.with do |ch|
  q = ch.queue('email.message.send', passive: true)
  q.message_count
  q.consumer_count
end

# All queues — Bunny::NotFound closes the channel, so we acquire a fresh one per check.
Onetime::Jobs::QueueConfig::QUEUES.each_key do |name|
  $rmq_channel_pool.with do |ch|
    q = ch.queue(name, passive: true)
    puts "#{name}: #{q.message_count} msgs, #{q.consumer_count} consumers"
  rescue Bunny::NotFound
    puts "#{name}: NOT DECLARED"
  end
end
```

## Dead letter queues

```ruby
Onetime::Jobs::QueueConfig::DEAD_LETTER_CONFIG.each_value do |cfg|
  $rmq_channel_pool.with do |ch|
    q = ch.queue(cfg[:queue], passive: true)
    puts "#{cfg[:queue]}: #{q.message_count} msgs"
  rescue Bunny::NotFound
    puts "#{cfg[:queue]}: NOT DECLARED"
  end
end
```

## Publish test message

```ruby
require 'onetime/jobs/publisher'
Onetime::Jobs::Publisher.enqueue_email(:ping_test, { test: true })
```

## Re-declare topology

```ruby
$rmq_channel_pool.with { |ch| Onetime::Jobs::QueueDeclarator.declare_all(ch) }
```

## Reset connection

```ruby
$rmq_conn&.close
$rmq_conn = nil
$rmq_channel_pool = nil

conn = Bunny.new(OT.conf.dig('jobs', 'rabbitmq_url'), heartbeat: 60)
conn.start
$rmq_conn = conn
$rmq_channel_pool = ConnectionPool.new(size: 5, timeout: 5) { $rmq_conn.create_channel }
```

## CLI equivalents

```
bin/ots queue status                    # connection, exchanges, depths, scheduler
bin/ots queue status -w 5               # watch mode
bin/ots queue ping                      # test messages to all queues
bin/ots queue ping -q email             # ping one queue
bin/ots queue dlq list                  # DLQ message counts
bin/ots queue dlq list billing.event    # specific DLQ
bin/ots queue dlq replay billing.event  # replay back to origin
```

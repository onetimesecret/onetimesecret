# lib/onetime/jobs/queue_config.rb
#
# frozen_string_literal: true

module Onetime
  module Jobs
    # Queue topology and configuration for RabbitMQ
    #
    # Queue Naming Convention (Erlang/Elixir style)
    # Pattern: {domain}.{entity}.{action}
    #
    # - domain: Business area (email, webhooks, billing, notifications, system)
    # - entity: What's being processed (message, payload, event, alert)
    # - action: Operation verb (send, deliver, process, schedule)
    #
    # Dead Letter: dlx.{domain}.{entity} → dlq.{domain}.{entity}
    #
    # Phase 1 uses Direct exchanges for named queues. Topic exchanges will be
    # introduced only when multiple distinct services need to subscribe to the
    # same message for different purposes.
    #
    # Each queue includes:
    # - durable: true/false - survives RabbitMQ restart
    # - arguments: AMQP queue arguments like dead-letter exchanges and TTL
    #
    module QueueConfig
      QUEUES = {
        'email.message.send' => {
          durable: true,
          arguments: { 'x-dead-letter-exchange' => 'dlx.email.message' }
        },
        'email.message.schedule' => {
          durable: true,
          arguments: {
            'x-dead-letter-exchange' => 'dlx.email.message',
            'x-message-ttl' => 86_400_000 # 24 hours in milliseconds
          }
        },
        'notifications.alert.push' => {
          durable: true
        },
        'webhooks.payload.deliver' => {
          durable: true,
          arguments: { 'x-dead-letter-exchange' => 'dlx.webhooks.payload' }
        },
        'billing.event.process' => {
          durable: true,
          arguments: { 'x-dead-letter-exchange' => 'dlx.billing.event' }
        },
        'system.transient' => {
          durable: false,
          auto_delete: true,
          arguments: {
            'x-message-ttl' => 300_000 # 5 minutes in milliseconds
          }
        }
      }.freeze

      # Dead letter exchange and queue configuration
      # These must be declared BEFORE the main queues that reference them
      DEAD_LETTER_CONFIG = {
        'dlx.email.message' => { queue: 'dlq.email.message' },
        'dlx.webhooks.payload' => { queue: 'dlq.webhooks.payload' },
        'dlx.billing.event' => { queue: 'dlq.billing.event' }
      }.freeze

      # TTL for processed message idempotency keys (1 hour)
      IDEMPOTENCY_TTL = 3600

      # Schema versioning constants
      CURRENT_SCHEMA_VERSION = 1

      # Message format versions
      module Versions
        V1 = 1
      end
    end
  end
end

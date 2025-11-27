# lib/onetime/jobs/queue_config.rb
#
# frozen_string_literal: true

module Onetime
  module Jobs
    # Queue topology and configuration for RabbitMQ
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
        'email.immediate' => {
          durable: true,
          arguments: { 'x-dead-letter-exchange' => 'dlx.email' }
        },
        'email.scheduled' => {
          durable: true,
          arguments: {
            'x-dead-letter-exchange' => 'dlx.email',
            'x-message-ttl' => 86_400_000 # 24 hours in milliseconds
          }
        },
        'notifications.push' => {
          durable: true
        },
        'webhooks.deliver' => {
          durable: true,
          arguments: { 'x-dead-letter-exchange' => 'dlx.webhooks' }
        },
        'billing.events' => {
          durable: true,
          arguments: { 'x-dead-letter-exchange' => 'dlx.billing' }
        }
      }.freeze

      # Schema versioning constants
      CURRENT_SCHEMA_VERSION = 1

      # Message format versions
      module Versions
        V1 = 1
      end
    end
  end
end

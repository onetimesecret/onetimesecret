# lib/onetime/jobs/queues/config.rb
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
    # - auto_delete: true/false - deleted when last consumer disconnects
    # - arguments: AMQP queue arguments like dead-letter exchanges and TTL
    #
    # IMPORTANT: All queue options MUST be explicit. Do not rely on defaults
    # because different code paths (Puma, workers, CLI) may have different
    # defaults. Kicks/Sneakers deprecated option mapping does NOT handle
    # auto_delete, so workers MUST use queue_options: hash.
    #
    module QueueConfig
      QUEUES = {
        'email.message.send' => {
          durable: true,
          auto_delete: false,
          arguments: { 'x-dead-letter-exchange' => 'dlx.email.message' },
        },
        'email.message.schedule' => {
          durable: true,
          auto_delete: false,
          arguments: {
            'x-dead-letter-exchange' => 'dlx.email.message',
            'x-message-ttl' => 86_400_000, # 24 hours in milliseconds
          },
        },
        'notifications.alert.push' => {
          durable: true,
          auto_delete: false,
          arguments: { 'x-dead-letter-exchange' => 'dlx.notifications.alert' },
        },
        'webhooks.payload.deliver' => {
          durable: true,
          auto_delete: false,
          arguments: { 'x-dead-letter-exchange' => 'dlx.webhooks.payload' },
        },
        'billing.event.process' => {
          durable: true,
          auto_delete: false,
          arguments: { 'x-dead-letter-exchange' => 'dlx.billing.event' },
        },
        'system.transient' => {
          durable: false,
          auto_delete: true,
          arguments: {
            'x-message-ttl' => 300_000, # 5 minutes in milliseconds
          },
        },
      }.freeze

      # Dead letter exchange and queue configuration
      # These must be declared BEFORE the main queues that reference them
      #
      # DLQ TTL (7 days) prevents unbounded growth from unmonitored failures.
      # Messages older than this are dropped. Use `ots queue dlq replay`
      # to reprocess messages before they expire.
      DLQ_MESSAGE_TTL = 604_800_000 # 7 days in milliseconds

      DEAD_LETTER_CONFIG = {
        'dlx.email.message' => {
          queue: 'dlq.email.message',
          arguments: { 'x-message-ttl' => DLQ_MESSAGE_TTL },
        },
        'dlx.notifications.alert' => {
          queue: 'dlq.notifications.alert',
          arguments: { 'x-message-ttl' => DLQ_MESSAGE_TTL },
        },
        'dlx.webhooks.payload' => {
          queue: 'dlq.webhooks.payload',
          arguments: { 'x-message-ttl' => DLQ_MESSAGE_TTL },
        },
        'dlx.billing.event' => {
          queue: 'dlq.billing.event',
          arguments: { 'x-message-ttl' => DLQ_MESSAGE_TTL },
        },
      }.freeze

      # TTL for processed message idempotency keys (1 hour)
      IDEMPOTENCY_TTL = 3600

      # Schema versioning constants
      CURRENT_SCHEMA_VERSION = 1

      # Message format versions
      module Versions
        V1 = 1
      end

      # TLS configuration for amqps:// connections
      #
      # Returns a hash of TLS options suitable for merging into Bunny or Sneakers config.
      # Managed services (Northflank, CloudAMQP) provide valid certificates that work
      # with system CA bundle - no custom certs needed.
      #
      # Environment variables:
      # - RABBITMQ_VERIFY_PEER: 'true' (default) or 'false' for local dev
      # - RABBITMQ_CA_CERTIFICATES: Optional path to custom CA cert file
      #
      # @param url [String, nil] RabbitMQ connection URL
      # @return [Hash] TLS options hash (empty if URL is not amqps://)
      #
      # @example
      #   config.merge!(QueueConfig.tls_options(amqp_url))
      #
      def self.tls_options(url)
        return {} unless url.to_s.start_with?('amqps://')

        options = {
          tls: true,
          verify_peer: ENV.fetch('RABBITMQ_VERIFY_PEER', 'true') == 'true',
        }

        ca_certs_path                 = ENV.fetch('RABBITMQ_CA_CERTIFICATES', nil)
        options[:tls_ca_certificates] = [ca_certs_path] if ca_certs_path

        options
      end
    end
  end
end

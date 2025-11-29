# lib/onetime/jobs/publisher.rb
#
# frozen_string_literal: true

require 'securerandom'
require_relative 'queue_config'

module Onetime
  module Jobs
    # Thread-safe RabbitMQ publisher with configurable fallback behavior
    #
    # Uses connection pool for thread safety in multi-threaded environments
    # like Puma. Fallback behavior is configurable per-call:
    #
    #   - :async_thread - Spawn a thread to deliver (non-blocking, default)
    #   - :sync         - Block and deliver synchronously
    #   - :raise        - Raise an error on failure
    #   - :none         - Log and return false silently
    #
    # Example:
    #   # Default: async thread fallback (best for Puma)
    #   Onetime::Jobs::Publisher.enqueue_email(:secret_link, { secret_id: 'abc123' })
    #
    #   # Critical auth flow: block if needed
    #   Onetime::Jobs::Publisher.enqueue_email(:password_reset, data, fallback: :sync)
    #
    #   # Non-critical: just fail
    #   Onetime::Jobs::Publisher.enqueue_email(:feedback, data, fallback: :none)
    #
    class Publisher
      # Valid fallback strategies
      FALLBACK_STRATEGIES = %i[async_thread sync raise none].freeze

      # Default fallback - async thread is non-blocking for Puma
      DEFAULT_FALLBACK = :async_thread

      class << self
        # Enqueue an email for immediate delivery
        # @param template [Symbol] Email template name
        # @param data [Hash] Template data
        # @param fallback [Symbol] Fallback strategy if RabbitMQ unavailable
        # @return [Boolean] true if published to queue, false if fallback used
        def enqueue_email(template, data, fallback: DEFAULT_FALLBACK)
          new.enqueue_email(template, data, fallback: fallback)
        end

        # Schedule an email for delayed delivery
        # @param template [Symbol] Email template name
        # @param data [Hash] Template data
        # @param delay_seconds [Integer] Delay in seconds
        # @param fallback [Symbol] Fallback strategy if RabbitMQ unavailable
        # @return [Boolean] true if published to queue, false if fallback used
        def schedule_email(template, data, delay_seconds:, fallback: DEFAULT_FALLBACK)
          new.schedule_email(template, data, delay_seconds: delay_seconds, fallback: fallback)
        end

        # Enqueue a raw email (non-templated) for immediate delivery
        # Used for Rodauth integration where emails are pre-formatted
        # @param email [Hash] Raw email with :to, :from, :subject, :body keys
        # @param fallback [Symbol] Fallback strategy if RabbitMQ unavailable
        # @return [Boolean] true if published to queue, false if fallback used
        def enqueue_email_raw(email, fallback: DEFAULT_FALLBACK)
          new.enqueue_email_raw(email, fallback: fallback)
        end
      end

      def initialize
        @pending_template = nil
        @pending_data = nil
        @pending_raw_email = nil
      end

      # Enqueue email for immediate delivery
      def enqueue_email(template, data, fallback: DEFAULT_FALLBACK)
        validate_fallback!(fallback)
        @pending_template = template
        @pending_data = data

        # Gracefully fallback if jobs are disabled (no pool initialized)
        unless jobs_enabled?
          OT.ld "[Jobs::Publisher] Jobs disabled, using fallback #{fallback}: #{template}"
          return execute_fallback(fallback, :templated)
        end

        with_fallback(fallback, :templated) do
          publish('email.immediate', { template: template, data: data })
          OT.ld "[Jobs::Publisher] Enqueued email: #{template}"
          true
        end
      end

      # Schedule email for delayed delivery
      def schedule_email(template, data, delay_seconds:, fallback: DEFAULT_FALLBACK)
        validate_fallback!(fallback)
        @pending_template = template
        @pending_data = data

        # Gracefully fallback if jobs are disabled (no pool initialized)
        unless jobs_enabled?
          OT.ld "[Jobs::Publisher] Jobs disabled, using fallback #{fallback}: #{template}"
          return execute_fallback(fallback, :templated)
        end

        with_fallback(fallback, :templated) do
          publish(
            'email.scheduled',
            { template: template, data: data },
            expiration: (delay_seconds * 1000).to_s # Convert to milliseconds
          )
          OT.ld "[Jobs::Publisher] Scheduled email: #{template} (+#{delay_seconds}s)"
          true
        end
      end

      # Enqueue raw email (non-templated) for immediate delivery
      # Used for Rodauth integration where emails are pre-formatted
      def enqueue_email_raw(email, fallback: DEFAULT_FALLBACK)
        validate_fallback!(fallback)
        @pending_raw_email = email

        # Gracefully fallback if jobs are disabled (no pool initialized)
        unless jobs_enabled?
          OT.ld "[Jobs::Publisher] Jobs disabled, using fallback #{fallback} for raw email"
          return execute_fallback(fallback, :raw)
        end

        with_fallback(fallback, :raw) do
          publish('email.immediate', { raw: true, email: email })
          OT.ld "[Jobs::Publisher] Enqueued raw email to: #{email[:to]}"
          true
        end
      end

      # Publish generic message to a queue
      # @param queue_name [String] Queue name
      # @param payload [Hash] Message payload
      # @param options [Hash] Additional AMQP options
      # @return [String] The message_id assigned to this message
      def publish(queue_name, payload, **options)
        unless $rmq_channel_pool
          raise Onetime::Problem, 'RabbitMQ channel pool not initialized. Check config[:jobs][:enabled]'
        end

        message_id = SecureRandom.uuid

        $rmq_channel_pool.with do |channel|
          channel.default_exchange.publish(
            payload.to_json,
            routing_key: queue_name,
            persistent: true,
            message_id: message_id,
            headers: { 'x-schema-version' => QueueConfig::CURRENT_SCHEMA_VERSION },
            **options
          )
        end

        message_id
      end

      private

      # Validate fallback strategy
      def validate_fallback!(fallback)
        return if FALLBACK_STRATEGIES.include?(fallback)

        raise ArgumentError, "Invalid fallback strategy: #{fallback}. Valid options: #{FALLBACK_STRATEGIES.join(', ')}"
      end

      # Check if the job system is enabled and initialized
      # @return [Boolean] true if RabbitMQ channel pool is available
      def jobs_enabled?
        !$rmq_channel_pool.nil?
      end

      # Wrap publish operation with fallback logic (no retries, no sleeps)
      # @param fallback [Symbol] Fallback strategy
      # @param email_type [Symbol] :templated or :raw
      def with_fallback(fallback, email_type)
        yield
      rescue Bunny::ConnectionClosedError, Bunny::NetworkFailure => e
        OT.li "[Jobs::Publisher] RabbitMQ unavailable, using fallback #{fallback}: #{e.message}"
        execute_fallback(fallback, email_type)
      rescue StandardError => e
        OT.le "[Jobs::Publisher] Unexpected error publishing message: #{e.message}"
        OT.le e.backtrace.join("\n") if OT.debug?
        execute_fallback(fallback, email_type)
      end

      # Execute the configured fallback strategy
      # @param fallback [Symbol] Fallback strategy
      # @param email_type [Symbol] :templated or :raw
      # @return [Boolean] false (fallback was used, not queued)
      def execute_fallback(fallback, email_type)
        case fallback
        when :async_thread
          send_via_thread(email_type)
          false
        when :sync
          send_synchronously(email_type)
          false
        when :raise
          raise Onetime::Mail::DeliveryError, 'RabbitMQ unavailable and fallback disabled'
        when :none
          OT.li "[Jobs::Publisher] Fallback disabled, email not sent"
          clear_pending_state
          false
        end
      end

      # Poor man's background job - spawn a thread to deliver
      # Non-blocking for the request thread in Puma.
      #
      # Note: Works with Thin/EventMachine too (creates real OS thread outside
      # the reactor), but no thread pool limits - sustained RabbitMQ outages
      # could cause thread proliferation. For Thin, consider :sync instead.
      #
      # @param email_type [Symbol] :templated or :raw
      def send_via_thread(email_type)
        # Capture state before thread (instance vars won't be accessible)
        template = @pending_template
        data = @pending_data
        raw_email = @pending_raw_email

        clear_pending_state

        Thread.new do
          deliver_email(email_type, template: template, data: data, raw_email: raw_email)
        rescue StandardError => e
          # Log but don't crash - this is fire-and-forget
          OT.le "[Jobs::Publisher] Async thread delivery failed: #{e.message}"
          OT.le e.backtrace.first(5).join("\n") if OT.debug?
        end

        OT.li "[Jobs::Publisher] Spawned thread for #{email_type} email delivery"
      end

      # Blocking synchronous delivery
      # @param email_type [Symbol] :templated or :raw
      def send_synchronously(email_type)
        template = @pending_template
        data = @pending_data
        raw_email = @pending_raw_email

        clear_pending_state

        deliver_email(email_type, template: template, data: data, raw_email: raw_email)
        OT.li "[Jobs::Publisher] Sent #{email_type} email synchronously"
      end

      # Actually deliver the email
      # @param email_type [Symbol] :templated or :raw
      # @param template [Symbol, nil] Template name for templated emails
      # @param data [Hash, nil] Template data for templated emails
      # @param raw_email [Hash, nil] Raw email hash for raw emails
      def deliver_email(email_type, template:, data:, raw_email:)
        require_relative '../mail'

        case email_type
        when :templated
          return unless template && data

          Onetime::Mail.deliver(template, data)
        when :raw
          return unless raw_email

          Onetime::Mail.deliver_raw(raw_email)
        end
      end

      # Clear pending state
      def clear_pending_state
        @pending_template = nil
        @pending_data = nil
        @pending_raw_email = nil
      end
    end
  end
end

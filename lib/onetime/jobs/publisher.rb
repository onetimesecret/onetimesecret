# lib/onetime/jobs/publisher.rb
#
# frozen_string_literal: true

require_relative 'queue_config'

module Onetime
  module Jobs
    # Thread-safe RabbitMQ publisher with fallback to synchronous execution
    #
    # Uses connection pool for thread safety in multi-threaded environments
    # like Puma. Falls back to synchronous execution if RabbitMQ is unavailable
    # after retry attempts.
    #
    # Example:
    #   Onetime::Jobs::Publisher.enqueue_email(:secret_link, { secret_id: 'abc123' })
    #
    class Publisher
      MAX_RETRIES = 3
      RETRY_DELAY = 0.5 # seconds

      class << self
        # Enqueue an email for immediate delivery
        # @param template [Symbol] Email template name
        # @param data [Hash] Template data
        # @return [Boolean] true if published, false if fell back to sync
        def enqueue_email(template, data)
          new.enqueue_email(template, data)
        end

        # Schedule an email for delayed delivery
        # @param template [Symbol] Email template name
        # @param data [Hash] Template data
        # @param delay_seconds [Integer] Delay in seconds
        # @return [Boolean] true if published, false if fell back to sync
        def schedule_email(template, data, delay_seconds:)
          new.schedule_email(template, data, delay_seconds: delay_seconds)
        end

        # Enqueue a raw email (non-templated) for immediate delivery
        # Used for Rodauth integration where emails are pre-formatted
        # @param email [Hash] Raw email with :to, :from, :subject, :body keys
        # @return [Boolean] true if published, false if fell back to sync
        def enqueue_email_raw(email)
          new.enqueue_email_raw(email)
        end
      end

      def initialize
        @pending_template = nil
        @pending_data = nil
      end

      # Enqueue email for immediate delivery
      def enqueue_email(template, data)
        @pending_template = template
        @pending_data = data

        # Gracefully fallback if jobs are disabled (no pool initialized)
        unless jobs_enabled?
          OT.ld "[Jobs::Publisher] Jobs disabled, sending synchronously: #{template}"
          send_synchronously
          return false
        end

        with_fallback do
          publish('email.immediate', { template: template, data: data })
          OT.ld "[Jobs::Publisher] Enqueued email: #{template}"
          true
        end
      end

      # Schedule email for delayed delivery
      def schedule_email(template, data, delay_seconds:)
        @pending_template = template
        @pending_data = data

        # Gracefully fallback if jobs are disabled (no pool initialized)
        unless jobs_enabled?
          OT.ld "[Jobs::Publisher] Jobs disabled, sending synchronously: #{template}"
          send_synchronously
          return false
        end

        with_fallback do
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
      def enqueue_email_raw(email)
        @pending_raw_email = email

        # Gracefully fallback if jobs are disabled (no pool initialized)
        unless jobs_enabled?
          OT.ld "[Jobs::Publisher] Jobs disabled, sending raw email synchronously"
          send_raw_synchronously
          return false
        end

        with_fallback_raw do
          publish('email.immediate', { raw: true, email: email })
          OT.ld "[Jobs::Publisher] Enqueued raw email to: #{email[:to]}"
          true
        end
      end

      # Publish generic message to a queue
      # @param queue_name [String] Queue name
      # @param payload [Hash] Message payload
      # @param options [Hash] Additional AMQP options
      def publish(queue_name, payload, **options)
        unless $rmq_channel_pool
          raise Onetime::Problem, 'RabbitMQ channel pool not initialized. Check config[:jobs][:enabled]'
        end

        $rmq_channel_pool.with do |channel|
          channel.default_exchange.publish(
            payload.to_json,
            routing_key: queue_name,
            persistent: true,
            headers: { 'x-schema-version' => QueueConfig::CURRENT_SCHEMA_VERSION },
            **options
          )
        end
      end

      private

      # Check if the job system is enabled and initialized
      # @return [Boolean] true if RabbitMQ channel pool is available
      def jobs_enabled?
        !$rmq_channel_pool.nil?
      end

      # Wrap publish operation with retry and fallback logic
      def with_fallback
        retries = 0
        begin
          yield
        rescue Bunny::ConnectionClosedError, Bunny::NetworkFailure => e
          retries += 1
          if retries <= MAX_RETRIES
            OT.li "[Jobs::Publisher] RabbitMQ connection failed (attempt #{retries}/#{MAX_RETRIES}), retrying in #{RETRY_DELAY * retries}s: #{e.message}"
            sleep(RETRY_DELAY * retries)
            retry
          else
            OT.li "[Jobs::Publisher] RabbitMQ unavailable after #{MAX_RETRIES} retries, falling back to sync: #{e.message}"
            send_synchronously
            false
          end
        rescue StandardError => e
          OT.le "[Jobs::Publisher] Unexpected error publishing message: #{e.message}"
          OT.le e.backtrace.join("\n") if OT.debug?
          send_synchronously
          false
        end
      end

      # Fallback to synchronous email delivery
      def send_synchronously
        return unless @pending_template && @pending_data

        begin
          require_relative '../mail'
          Onetime::Mail.deliver(@pending_template, @pending_data)
          OT.li "[Jobs::Publisher] Sent email synchronously: #{@pending_template}"
        rescue StandardError => e
          OT.le "[Jobs::Publisher] Sync fallback failed: #{e.message}"
          raise
        ensure
          @pending_template = nil
          @pending_data = nil
        end
      end

      # Wrap raw email publish with retry and fallback logic
      def with_fallback_raw
        retries = 0
        begin
          yield
        rescue Bunny::ConnectionClosedError, Bunny::NetworkFailure => e
          retries += 1
          if retries <= MAX_RETRIES
            OT.li "[Jobs::Publisher] RabbitMQ connection failed (attempt #{retries}/#{MAX_RETRIES}), retrying in #{RETRY_DELAY * retries}s: #{e.message}"
            sleep(RETRY_DELAY * retries)
            retry
          else
            OT.li "[Jobs::Publisher] RabbitMQ unavailable after #{MAX_RETRIES} retries, falling back to sync raw: #{e.message}"
            send_raw_synchronously
            false
          end
        rescue StandardError => e
          OT.le "[Jobs::Publisher] Unexpected error publishing raw message: #{e.message}"
          OT.le e.backtrace.join("\n") if OT.debug?
          send_raw_synchronously
          false
        end
      end

      # Fallback to synchronous raw email delivery
      def send_raw_synchronously
        return unless @pending_raw_email

        begin
          require_relative '../mail'
          Onetime::Mail.deliver_raw(@pending_raw_email)
          OT.li "[Jobs::Publisher] Sent raw email synchronously to: #{@pending_raw_email[:to]}"
        rescue StandardError => e
          OT.le "[Jobs::Publisher] Sync raw fallback failed: #{e.message}"
          raise
        ensure
          @pending_raw_email = nil
        end
      end
    end
  end
end

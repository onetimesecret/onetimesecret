# lib/onetime/jobs/publisher.rb
#
# frozen_string_literal: true

require 'securerandom'
require_relative 'queues/config'

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
      # @return [SemanticLogger::Logger] Logger for job publishing operations
      def self.logger
        @logger ||= Onetime.get_logger('Jobs')
      end

      def logger
        self.class.logger
      end
      # Valid fallback strategies
      FALLBACK_STRATEGIES = [:async_thread, :sync, :raise, :none].freeze

      # Default fallback - async thread is non-blocking for Puma
      DEFAULT_FALLBACK = :async_thread

      class << self
        # Enqueue an email for immediate delivery
        # @param template [Symbol] Email template name
        # @param data [Hash] Template data
        # @param fallback [Symbol] Fallback strategy if RabbitMQ unavailable
        # @param domain_id [String, nil] Domain identifier for per-domain sender config
        # @return [Boolean] true if published to queue, false if fallback used
        def enqueue_email(template, data, fallback: DEFAULT_FALLBACK, domain_id: nil)
          new.enqueue_email(template, data, fallback: fallback, domain_id: domain_id)
        end

        # Schedule an email for delayed delivery
        # @param template [Symbol] Email template name
        # @param data [Hash] Template data
        # @param delay_seconds [Integer] Delay in seconds
        # @param fallback [Symbol] Fallback strategy if RabbitMQ unavailable
        # @param domain_id [String, nil] Domain identifier for per-domain sender config
        # @return [Boolean] true if published to queue, false if fallback used
        def schedule_email(template, data, delay_seconds:, fallback: DEFAULT_FALLBACK, domain_id: nil)
          new.schedule_email(template, data, delay_seconds: delay_seconds, fallback: fallback, domain_id: domain_id)
        end

        # Enqueue a raw email (non-templated) for immediate delivery
        # Used for Rodauth integration where emails are pre-formatted
        # @param email [Hash] Raw email with :to, :from, :subject, :body keys
        # @param fallback [Symbol] Fallback strategy if RabbitMQ unavailable
        # @param domain_id [String, nil] Domain identifier for per-domain sender config
        # @return [Boolean] true if published to queue, false if fallback used
        def enqueue_email_raw(email, fallback: DEFAULT_FALLBACK, domain_id: nil)
          new.enqueue_email_raw(email, fallback: fallback, domain_id: domain_id)
        end

        # Enqueue a Stripe webhook event for async processing
        #
        # Falls back to synchronous processing if jobs are disabled.
        # This ensures billing webhooks work without RabbitMQ for dev/testing.
        #
        # @param event [Stripe::Event] The validated Stripe event
        # @param payload [String] The raw JSON payload from Stripe
        # @return [Boolean] true if published to queue or processed synchronously
        # @raise [Onetime::Problem] If RabbitMQ unavailable when jobs ARE enabled
        def enqueue_billing_event(event, payload)
          new.enqueue_billing_event(event, payload)
        end

        # Enqueue a domain DNS validation check for async processing
        #
        # Falls back to synchronous validation if jobs are disabled, ensuring
        # domain validation works without RabbitMQ for dev/testing.
        #
        # @param domain_id [String] CustomDomain identifier (MailerConfig key)
        # @return [Boolean] true if published to queue or processed synchronously
        # @raise [Onetime::Problem] If RabbitMQ unavailable when jobs ARE enabled
        def enqueue_domain_validation(domain_id)
          new.enqueue_domain_validation(domain_id)
        end
      end

      def initialize
        @pending_template  = nil
        @pending_data      = nil
        @pending_raw_email = nil
        @pending_domain_id = nil
      end

      # Enqueue email for immediate delivery
      def enqueue_email(template, data, fallback: DEFAULT_FALLBACK, domain_id: nil)
        validate_fallback!(fallback)
        @pending_template  = template
        @pending_data      = data
        @pending_domain_id = domain_id

        # Gracefully fallback if jobs are disabled (no pool initialized)
        unless jobs_enabled?
          logger.info 'Jobs disabled, using fallback', template: template, fallback: fallback
          return execute_fallback(fallback, :templated)
        end

        with_fallback(fallback, :templated) do
          message_id = publish('email.message.send', { template: template, data: data, domain_id: domain_id })
          logger.info 'Enqueued email', template: template, message_id: message_id, queue: 'email.message.send'
          true
        end
      end

      # Schedule email for delayed delivery
      def schedule_email(template, data, delay_seconds:, fallback: DEFAULT_FALLBACK, domain_id: nil)
        validate_fallback!(fallback)
        @pending_template  = template
        @pending_data      = data
        @pending_domain_id = domain_id

        # Gracefully fallback if jobs are disabled (no pool initialized)
        unless jobs_enabled?
          logger.info 'Jobs disabled, using fallback', template: template, fallback: fallback
          return execute_fallback(fallback, :templated)
        end

        with_fallback(fallback, :templated) do
          message_id = publish(
            'email.message.schedule',
            { template: template, data: data, domain_id: domain_id },
            expiration: (delay_seconds * 1000).to_s, # Convert to milliseconds
          )
          logger.info 'Scheduled email', template: template, message_id: message_id, delay_seconds: delay_seconds
          true
        end
      end

      # Enqueue raw email (non-templated) for immediate delivery
      # Used for Rodauth integration where emails are pre-formatted
      def enqueue_email_raw(email, fallback: DEFAULT_FALLBACK, domain_id: nil)
        validate_fallback!(fallback)
        @pending_raw_email = email
        @pending_domain_id = domain_id

        # Gracefully fallback if jobs are disabled (no pool initialized)
        unless jobs_enabled?
          logger.info 'Jobs disabled, using fallback for raw email', fallback: fallback
          return execute_fallback(fallback, :raw)
        end

        with_fallback(fallback, :raw) do
          message_id = publish('email.message.send', { raw: true, email: email, domain_id: domain_id })
          logger.info 'Enqueued raw email', to: email[:to], message_id: message_id
          true
        end
      end

      # Enqueue a Stripe webhook event for async processing
      #
      # Falls back to synchronous processing if jobs are disabled, enabling
      # development/testing without RabbitMQ. If jobs ARE enabled but RabbitMQ
      # is unavailable, raises so the controller returns 500 and Stripe retries.
      #
      # @param event [Stripe::Event] The validated Stripe event
      # @param payload [String] The raw JSON payload from Stripe
      # @return [Boolean] true if published to queue or processed synchronously
      # @raise [Onetime::Problem] If RabbitMQ unavailable when jobs ARE enabled
      def enqueue_billing_event(event, payload)
        # Fallback to synchronous processing if jobs are disabled
        # This ensures billing webhooks work without RabbitMQ for dev/testing
        unless jobs_enabled?
          logger.info 'Jobs disabled, processing billing event synchronously',
            event_id: event.id,
            event_type: event.type

          require 'apps/web/billing/operations/process_webhook_event'
          result = Billing::Operations::ProcessWebhookEvent.new(
            event: event,
            context: { source: :sync_fallback },
          ).call

          logger.info 'Billing event processed synchronously',
            event_id: event.id,
            event_type: event.type,
            result: result
          return true
        end

        message = {
          event_id: event.id,
          event_type: event.type,
          payload: payload,
          received_at: Time.now.utc.iso8601,
        }

        message_id = publish('billing.event.process', message)
        logger.info 'Enqueued billing event',
          event_id: event.id,
          event_type: event.type,
          message_id: message_id,
          queue: 'billing.event.process'
        true
      end

      # Enqueue a domain DNS validation check for async processing
      #
      # Falls back to synchronous validation if jobs are disabled, enabling
      # development/testing without RabbitMQ. If jobs ARE enabled but RabbitMQ
      # is unavailable, raises so the controller can return an error.
      #
      # @param domain_id [String] CustomDomain identifier (MailerConfig key)
      # @return [Boolean] true if published to queue or processed synchronously
      # @raise [Onetime::Problem] If RabbitMQ unavailable when jobs ARE enabled
      def enqueue_domain_validation(domain_id)
        unless jobs_enabled?
          logger.info 'Jobs disabled, validating domain synchronously',
            domain_id: domain_id

          require 'onetime/operations/validate_sender_domain'
          require 'onetime/models/custom_domain/mailer_config'

          mailer_config = Onetime::CustomDomain::MailerConfig.find_by_domain_id(domain_id)
          if mailer_config
            Onetime::Operations::ValidateSenderDomain.new(
              mailer_config: mailer_config,
              persist: true,
            ).call
          end

          return true
        end

        message = {
          domain_id: domain_id,
          requested_at: Time.now.utc.iso8601,
        }

        message_id = publish('domain.validation.check', message)
        logger.info 'Enqueued domain validation',
          domain_id: domain_id,
          message_id: message_id,
          queue: 'domain.validation.check'
        true
      end

      # Publish generic message to a queue
      # @param queue_name [String] Queue name
      # @param payload [Hash] Message payload
      # @param options [Hash] Additional AMQP options
      # @return [String] The message_id assigned to this message
      def publish(queue_name, payload, **)
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
            **,
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
      rescue Bunny::ConnectionClosedError, Bunny::NetworkFailure => ex
        logger.warn 'RabbitMQ unavailable, using fallback', fallback: fallback, error: ex.message
        execute_fallback(fallback, email_type)
      rescue StandardError => ex
        logger.error 'Unexpected error publishing message', error: ex.message, backtrace: ex.backtrace.first(5)
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
          logger.info 'Fallback disabled, email not sent'
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
        template  = @pending_template
        data      = @pending_data
        raw_email = @pending_raw_email
        domain_id = @pending_domain_id

        clear_pending_state

        # rubocop:disable ThreadSafety/NewThread
        Thread.new do
          deliver_email(email_type, template: template, data: data, raw_email: raw_email, domain_id: domain_id)
        rescue StandardError => ex
          # Log but don't crash - this is fire-and-forget
          logger.error 'Async thread delivery failed', error: ex.message, backtrace: ex.backtrace.first(5)
        end
        # rubocop:enable ThreadSafety/NewThread
        #
        logger.info 'Spawned thread for email delivery', email_type: email_type
      end

      # Blocking synchronous delivery
      # @param email_type [Symbol] :templated or :raw
      def send_synchronously(email_type)
        template  = @pending_template
        data      = @pending_data
        raw_email = @pending_raw_email
        domain_id = @pending_domain_id

        clear_pending_state

        deliver_email(email_type, template: template, data: data, raw_email: raw_email, domain_id: domain_id)
        logger.info 'Sent email synchronously', email_type: email_type
      end

      # Actually deliver the email
      # @param email_type [Symbol] :templated or :raw
      # @param template [Symbol, nil] Template name for templated emails
      # @param data [Hash, nil] Template data for templated emails
      # @param raw_email [Hash, nil] Raw email hash for raw emails
      # @param domain_id [String, nil] Domain identifier for per-domain sender config
      def deliver_email(email_type, template:, data:, raw_email:, domain_id: nil)
        require_relative '../mail'
        require_relative '../models/custom_domain/mailer_config'

        sender_config = Onetime::CustomDomain::MailerConfig.load_for_domain(domain_id) if domain_id

        case email_type
        when :templated
          return unless template && data

          Onetime::Mail.deliver(template, data, sender_config: sender_config)
        when :raw
          return unless raw_email

          Onetime::Mail.deliver_raw(raw_email, sender_config: sender_config)
        end
      end

      # Clear pending state
      def clear_pending_state
        @pending_template  = nil
        @pending_data      = nil
        @pending_raw_email = nil
        @pending_domain_id = nil
      end
    end
  end
end

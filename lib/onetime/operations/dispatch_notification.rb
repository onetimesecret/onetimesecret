# lib/onetime/operations/dispatch_notification.rb
#
# frozen_string_literal: true

require 'net/http'
require 'uri'
require 'securerandom'

module Onetime
  module Operations
    #
    # Dispatches notifications to multiple channels based on configuration.
    # Extracted from NotificationWorker for reuse in CLI tools and testing.
    #
    # Supported channels:
    # - in_app: Stores notification in Redis for web UI display
    # - email: Queues to email.message.send for delivery
    # - webhook: Makes HTTP POST callback to user-defined URL
    #
    # Message payload schema:
    # {
    #   type: 'secret.viewed',         # Event type
    #   addressee: {                   # Who receives the notification
    #     custid: 'cust:abc123',
    #     email: 'user@example.com',
    #     webhook_url: 'https://...',  # Optional
    #   },
    #   template: 'secret_viewed',     # Template name for rendering
    #   locale: 'en',                  # Localization
    #   channels: ['in_app', 'email'], # Which delivery methods to use
    #   data: { ... }                  # Template-specific variables
    # }
    #
    class DispatchNotification
      include Onetime::LoggerMethods

      # Supported notification channels
      SUPPORTED_CHANNELS = %w[in_app email webhook].freeze

      # Redis TTL for stored notifications (30 days)
      NOTIFICATION_TTL = 30 * 24 * 60 * 60

      # Maximum notifications to keep per customer
      MAX_NOTIFICATIONS = 100

      # Webhook HTTP timeouts
      WEBHOOK_OPEN_TIMEOUT = 5
      WEBHOOK_READ_TIMEOUT = 10

      # @param data [Hash] Parsed notification data
      # @param context [Hash] Optional context (e.g., { source_message_id: 'abc' })
      def initialize(data:, context: {})
        @data = data
        @context = context
        @results = {}
      end

      # Executes the notification dispatch
      #
      # @return [Hash] Results per channel { in_app: :success, email: :skipped, webhook: :error }
      def call
        channels = resolve_channels

        channels.each do |channel|
          @results[channel.to_sym] = dispatch_to_channel(channel)
        end

        @results
      end

      # @return [Hash] Results from the last call
      attr_reader :results

      private

      # Resolve which channels to dispatch to
      # @return [Array<String>] List of valid channel names
      def resolve_channels
        requested = Array(@data[:channels]).map(&:to_s)
        valid = requested & SUPPORTED_CHANNELS

        if valid.empty?
          logger.info 'No valid channels specified, defaulting to in_app'
          ['in_app']
        else
          valid
        end
      end

      # Dispatch to a single channel
      # @param channel [String] Channel name
      # @return [Symbol] :success, :skipped, or :error
      def dispatch_to_channel(channel)
        case channel
        when 'in_app'
          deliver_in_app
        when 'email'
          deliver_email
        when 'webhook'
          deliver_webhook
        end
      rescue StandardError => ex
        logger.error "Failed to deliver to #{channel}",
          error: ex.message,
          error_class: ex.class.name
        :error
      end

      # Store notification in Redis for in-app display
      # @return [Symbol] :success or :skipped
      def deliver_in_app
        addressee = @data[:addressee] || {}
        custid = addressee[:custid]

        unless custid
          logger.debug 'No custid for in_app notification, skipping'
          return :skipped
        end

        notification = build_in_app_notification
        key = "notifications:#{custid}"

        Familia.dbclient.lpush(key, notification.to_json)
        Familia.dbclient.ltrim(key, 0, MAX_NOTIFICATIONS - 1)
        Familia.dbclient.expire(key, NOTIFICATION_TTL)

        logger.debug 'In-app notification stored', custid: custid, type: @data[:type]
        :success
      end

      # Build the in-app notification structure
      # @return [Hash] Notification hash for Redis storage
      def build_in_app_notification
        {
          id: SecureRandom.uuid,
          type: @data[:type],
          template: @data[:template],
          data: @data[:data] || {},
          read: false,
          created_at: Time.now.utc.iso8601,
        }
      end

      # Queue email notification via email.message.send
      # @return [Symbol] :success or :skipped
      def deliver_email
        addressee = @data[:addressee] || {}
        email = addressee[:email]

        unless email
          logger.debug 'No email address for email notification, skipping'
          return :skipped
        end

        email_payload = build_email_payload(email)

        Onetime::Jobs::Publisher.new.publish(
          'email.message.send',
          email_payload
        )

        logger.debug 'Email notification queued', email: email, template: @data[:template]
        :success
      end

      # Build the email payload for the email worker
      # @param email [String] Recipient email address
      # @return [Hash] Email payload
      def build_email_payload(email)
        {
          template: @data[:template],
          data: (@data[:data] || {}).merge(
            locale: @data[:locale] || 'en',
            to: email
          ),
        }
      end

      # Make HTTP POST callback to user's webhook URL
      # @return [Symbol] :success or :skipped
      def deliver_webhook
        addressee = @data[:addressee] || {}
        webhook_url = addressee[:webhook_url]

        unless webhook_url
          logger.debug 'No webhook_url for webhook notification, skipping'
          return :skipped
        end

        payload = build_webhook_payload
        response = send_webhook_request(webhook_url, payload)

        unless response.is_a?(Net::HTTPSuccess)
          raise "Webhook returned #{response.code}: #{response.body&.slice(0, 200)}"
        end

        logger.debug 'Webhook delivered', url: webhook_url, status: response.code
        :success
      end

      # Build the webhook payload
      # @return [Hash] Webhook payload
      def build_webhook_payload
        {
          event: @data[:type],
          template: @data[:template],
          data: @data[:data] || {},
          timestamp: Time.now.utc.iso8601,
        }
      end

      # Send HTTP POST request to webhook URL
      # @param url [String] Webhook URL
      # @param payload [Hash] Request payload
      # @return [Net::HTTPResponse] HTTP response
      def send_webhook_request(url, payload)
        uri = URI.parse(url)
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = (uri.scheme == 'https')
        http.open_timeout = WEBHOOK_OPEN_TIMEOUT
        http.read_timeout = WEBHOOK_READ_TIMEOUT

        request = Net::HTTP::Post.new(uri.request_uri)
        request['Content-Type'] = 'application/json'
        request['User-Agent'] = 'OneTimeSecret-Webhook/1.0'
        request.body = payload.to_json

        http.request(request)
      end

      # @return [SemanticLogger::Logger] Logger instance
      def logger
        @logger ||= Onetime.get_logger('Operations')
      end
    end
  end
end

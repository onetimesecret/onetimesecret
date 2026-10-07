# lib/onetime/operations/dispatch_notification.rb
#
# frozen_string_literal: true

require 'net/http'
require 'uri'
require 'securerandom'
require_relative '../http/guard'
require_relative '../models/delivery_event'

module Onetime
  module Operations
    #
    # Dispatches notifications to multiple channels based on configuration.
    # Extracted from NotificationWorker for reuse in CLI tools and testing.
    #
    # Supported channels:
    # - via_bell: Stores notification in Redis for bell/notification UI display
    # - via_email: Queues to email.message.send for delivery
    # - via_webhook: Makes HTTP POST callback to user-defined URL
    #
    # Message payload schema:
    # {
    #   type: 'secret.viewed',         # Event type
    #   addressee: {                   # Who receives the notification
    #     custid: 'cust:abc123',
    #     customer_extid: 'ur...',     # Optional, public customer id for delivery events
    #     email: 'user@example.com',
    #     webhook_url: 'https://...',  # Optional
    #   },
    #   template: 'secret_viewed',     # Template name for rendering
    #   locale: 'en',                  # Localization
    #   channels: ['via_bell', 'via_email'], # Which delivery methods to use
    #   data: { ... }                  # Template-specific variables
    # }
    #
    # Delivery events (Onetime::DeliveryEvent) are recorded for the email
    # and webhook channels: email at stage `queue` (the hand-off to
    # email.message.send), webhook at stage `delivery` (around the HTTP
    # request). The context's source_message_id is the correlation id; it is
    # copied into the email payload so EmailWorker's terminal event shares
    # it. Recording is best-effort and never changes the channel result.
    #
    class DispatchNotification
      include Onetime::LoggerMethods

      # Supported notification channels
      SUPPORTED_CHANNELS = %w[via_bell via_email via_webhook].freeze

      # Redis TTL for stored notifications (30 days)
      NOTIFICATION_TTL = 30 * 24 * 60 * 60

      # Maximum notifications to keep per customer
      MAX_NOTIFICATIONS = 100

      # Webhook HTTP timeouts
      WEBHOOK_OPEN_TIMEOUT = 5
      WEBHOOK_READ_TIMEOUT = 10

      # Raised for a non-2xx webhook response. Carries the status so the
      # delivery event can record it without the response body.
      class WebhookResponseError < StandardError
        attr_reader :status

        def initialize(message, status:)
          super(message)
          @status = status
        end
      end

      # @param data [Hash] Parsed notification data
      # @param context [Hash] Optional context (e.g., { source_message_id: 'abc' })
      def initialize(data:, context: {})
        @data    = data
        @context = context
        @results = {}
      end

      # Correlation id shared by every delivery event this dispatch writes.
      # The source queue message id when there is one (NotificationWorker);
      # a generated id otherwise (CLI, tests), so the chain still links.
      # @return [String]
      def correlation_id
        @correlation_id ||= (@context[:source_message_id] || "gen-#{SecureRandom.uuid}").to_s
      end

      # Executes the notification dispatch
      #
      # @return [Hash] Results per channel { via_bell: :success, via_email: :skipped, via_webhook: :error }
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
        valid     = requested & SUPPORTED_CHANNELS
        invalid   = requested - valid

        if invalid.any?
          logger.warn 'Unsupported channels requested and ignored', unsupported: invalid
        end

        if valid.empty?
          logger.info 'No valid channels specified, defaulting to via_bell'
          ['via_bell']
        else
          valid
        end
      end

      # Dispatch to a single channel
      # @param channel [String] Channel name
      # @return [Symbol] :success, :skipped, or :error
      def dispatch_to_channel(channel)
        case channel
        when 'via_bell'
          deliver_via_bell
        when 'via_email'
          deliver_via_email
        when 'via_webhook'
          deliver_via_webhook
        end
      rescue StandardError => ex
        logger.error "Failed to deliver to #{channel}",
          error: ex.message,
          error_class: ex.class.name
        record_channel_error(channel, ex)
        :error
      end

      # One delivery event for a channel that raised. Email raises before or
      # during publish, so its stage is `queue`; webhook raises around the
      # HTTP request, so its stage is `delivery`.
      def record_channel_error(channel, ex)
        case channel
        when 'via_email'
          record_event(
            channel: 'email',
            stage: 'queue',
            outcome: 'failed',
            reason: 'publish_failed',
            error: ex,
          )
        when 'via_webhook'
          # A non-2xx response is recorded as its status only: the exception
          # message quotes the response body, which is the remote side's
          # text and is not stored.
          http_error = ex.is_a?(WebhookResponseError)
          record_event(
            channel: 'webhook',
            stage: 'delivery',
            outcome: 'failed',
            reason: webhook_failure_reason(ex),
            error: (ex unless http_error),
            http_status: (ex.status if http_error),
            target_host: webhook_target_host,
            attempt_count: 1,
          )
        end
      rescue StandardError => ex
        logger.error 'Delivery event not recorded', error_class: ex.class.name
        nil
      end

      def webhook_failure_reason(ex)
        case ex
        when WebhookResponseError then 'http_status'
        when Onetime::Http::Guard::Blocked then 'blocked_target'
        when Net::OpenTimeout, Net::ReadTimeout then 'timeout'
        when ArgumentError, URI::Error then 'invalid_url'
        else 'error'
        end
      end

      # Fields every event from this dispatch carries. Best-effort: a
      # failure here is logged and never changes the channel result.
      def record_event(**fields)
        Onetime::DeliveryEvent.record(
          correlation_id: correlation_id,
          event_type: @data[:type],
          template: @data[:template],
          customer_id: (@data[:addressee] || {})[:customer_extid],
          **fields,
        )
      rescue StandardError => ex
        logger.error 'Delivery event not recorded', error_class: ex.class.name
        nil
      end

      # Host of the addressee's webhook URL, for the event record only.
      # @return [String, nil]
      def webhook_target_host
        url = (@data[:addressee] || {})[:webhook_url]
        return nil unless url

        URI.parse(url.to_s).host
      rescue URI::Error
        nil
      end

      # Store notification in Redis for bell notification display
      # @return [Symbol] :success or :skipped
      def deliver_via_bell
        addressee = @data[:addressee] || {}
        custid    = addressee[:custid]

        unless custid
          logger.debug 'No custid for bell notification, skipping'
          return :skipped
        end

        notification = build_bell_notification
        key          = "notifications:#{custid}"

        # Use MULTI/EXEC for atomic Redis operations. Keep the
        # Familia.dbclient resolve inline with .multi — splitting the
        # resolve from the .multi call can land the two on different pool
        # connections under the escaped-checkout provider.
        Familia.dbclient.multi do |multi|
          multi.lpush(key, notification.to_json)
          multi.ltrim(key, 0, MAX_NOTIFICATIONS - 1)
          multi.expire(key, NOTIFICATION_TTL)
        end

        logger.debug 'Bell notification stored', custid: custid, type: @data[:type]
        :success
      end

      # Build the bell notification structure
      # @return [Hash] Notification hash for Redis storage
      def build_bell_notification
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
      def deliver_via_email
        addressee = @data[:addressee] || {}
        email     = addressee[:email]

        unless email
          logger.debug 'No email address for email notification, skipping'
          record_event(channel: 'email', stage: 'queue', outcome: 'skipped', reason: 'no_recipient')
          return :skipped
        end

        email_payload = build_email_payload(email)

        message_id = Onetime::Jobs::Publisher.new.publish(
          'email.message.send',
          email_payload,
        )

        logger.debug 'Email notification queued', email: email, template: @data[:template]
        record_event(channel: 'email', stage: 'queue', outcome: 'queued', message_id: message_id)
        :success
      end

      # Build the email payload for the email worker. The top-level
      # correlation_id, event_type and customer_extid are read by EmailWorker
      # for its delivery event; only `data` reaches the template.
      # @param email [String] Recipient email address
      # @return [Hash] Email payload
      def build_email_payload(email)
        {
          template: @data[:template],
          data: (@data[:data] || {}).merge(
            locale: @data[:locale] || 'en',
            to: email,
          ),
          correlation_id: correlation_id,
          event_type: @data[:type],
          customer_extid: (@data[:addressee] || {})[:customer_extid],
        }
      end

      # Make HTTP POST callback to user's webhook URL
      # @return [Symbol] :success or :skipped
      def deliver_via_webhook
        addressee   = @data[:addressee] || {}
        webhook_url = addressee[:webhook_url]

        unless webhook_url
          logger.debug 'No webhook_url for webhook notification, skipping'
          record_event(channel: 'webhook', stage: 'delivery', outcome: 'skipped', reason: 'no_target')
          return :skipped
        end

        payload    = build_webhook_payload
        started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        response   = send_webhook_request(webhook_url, payload)

        unless response.is_a?(Net::HTTPSuccess)
          raise WebhookResponseError.new(
            "Webhook returned #{response.code}: #{response.body&.slice(0, 200)}",
            status: response.code,
          )
        end

        logger.debug 'Webhook delivered', url: webhook_url, status: response.code
        record_event(
          channel: 'webhook',
          stage: 'delivery',
          outcome: 'sent',
          http_status: response.code,
          target_host: webhook_target_host,
          duration_ms: elapsed_ms(started_at),
          attempt_count: 1,
        )
        :success
      end

      def elapsed_ms(started_at)
        ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at) * 1000).round
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
        # ALPHA: Webhook delivery needs further security review before wide use.
        # Current mitigations: SSRF protection with DNS pinning (each dial
        # pinned to one validated IP, with reachability fallback across the
        # remaining validated addresses), TLS verification, timeouts.
        # Missing: request signing, URL allowlisting, rate limiting, payload size limits.
        logger.warn 'Webhook delivery is alpha functionality', url: url

        uri = URI.parse(url)

        # Validate scheme before doing any resolution work
        scheme = (uri.scheme || '').downcase
        unless %w[http https].include?(scheme)
          raise ArgumentError, "Unsupported webhook scheme: #{uri.scheme.inspect}"
        end

        request                 = Net::HTTP::Post.new(uri.request_uri)
        request['Content-Type'] = 'application/json'
        request['User-Agent']   = Onetime::VERSION.user_agent
        request.body            = payload.to_json

        # SSRF Protection with DNS pinning: resolve + validate the hostname
        # once, then dial each validated IP via Net::HTTP#ipaddr= while the
        # Host header, SNI, and certificate verification keep using the
        # hostname. This closes the validate-then-reresolve DNS-rebinding
        # window the previous Addrinfo check left open; the fallback walk
        # only spans already-validated addresses (reachability, not target
        # widening). Raises Guard::Blocked (an Onetime::Problem) for
        # forbidden targets; dispatch_to_channel's StandardError rescue
        # classifies that as a permanent :error — the worker never retries
        # per-channel failures.
        Onetime::Http::Guard.try_each_address!(uri.host) do |pinned_ip|
          # The explicit nil p_addr disables environment-proxy pickup
          # (http_proxy env var), which would otherwise route the request
          # through a proxy and silently bypass the IP pinning below.
          http        = Net::HTTP.new(uri.host, uri.port, nil)
          http.ipaddr = pinned_ip

          http.use_ssl = (scheme == 'https')

          # Explicit TLS verification settings
          if http.use_ssl?
            http.verify_mode     = OpenSSL::SSL::VERIFY_PEER
            http.verify_hostname = true
          end

          http.open_timeout = WEBHOOK_OPEN_TIMEOUT
          http.read_timeout = WEBHOOK_READ_TIMEOUT

          http.request(request)
        end
      end

      # @return [SemanticLogger::Logger] Logger instance
      def logger
        @logger ||= Onetime.get_logger('Operations')
      end
    end
  end
end

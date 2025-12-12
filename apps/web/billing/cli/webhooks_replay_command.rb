# apps/web/billing/cli/webhooks_replay_command.rb
#
# frozen_string_literal: true

require_relative 'helpers'
require_relative 'safety_helpers'
require_relative '../models/stripe_webhook_event'
require_relative '../controllers/webhooks'

module Onetime
  module CLI
    # Replay stored webhook events with filtering
    #
    # Supports post-release debugging by replaying failed webhooks after
    # deploying fixes. Uses list-based filtering - all operations produce
    # a list of matching events (even single event_id).
    #
    # ## Examples
    #
    #   # Single event (most common)
    #   ots billing webhooks replay evt_xxx
    #
    #   # By event type (all checkout failures in last 24h)
    #   ots billing webhooks replay --type checkout.session.completed --status failed
    #
    #   # By customer (reprocess all events for affected customer)
    #   ots billing webhooks replay --customer cust123abc
    #
    #   # Time-scoped
    #   ots billing webhooks replay --since 2h
    #
    #   # Combined filters
    #   ots billing webhooks replay --type customer.subscription.updated --customer cust123 --since 1d
    #
    #   # Dry run (preview what would be replayed)
    #   ots billing webhooks replay --status failed --dry-run
    #
    class BillingWebhooksReplayCommand < Command
      include BillingHelpers
      include SafetyHelpers

      desc 'Replay stored webhook events with filtering'

      argument :event_id, required: false, desc: 'Specific event ID to replay (evt_xxx)'

      option :type, type: :string, desc: 'Filter by event type (e.g., customer.subscription.updated)'
      option :since, type: :string, default: '24h', desc: 'Time window (2h, 3d, ISO8601). Default: 24h'
      option :customer, type: :string, desc: 'Customer ID (objid, extid, or cus_xxx)'
      option :status, type: :string, default: 'failed', desc: 'Filter by status (pending|failed|retrying)'
      option :limit, type: :integer, default: 10, desc: 'Max events to replay. Default: 10'
      option :dry_run, type: :boolean, default: false, desc: 'Preview without executing'
      option :force, type: :boolean, default: false, desc: 'Replay even if already successful'
      option :skip_notifications, type: :boolean, default: false, desc: 'Skip email side effects'
      option :yes, type: :boolean, default: false, desc: 'Skip confirmation prompt'

      def call(event_id: nil, type: nil, since: '24h', customer: nil, status: 'failed',
               limit: 10, dry_run: false, force: false, skip_notifications: false, yes: false, **)
        boot_application!

        return unless stripe_configured?

        # Collect events matching filters (list-based approach)
        events = collect_replay_candidates(
          event_id: event_id,
          type: type,
          since: since,
          customer: customer,
          status: status,
          limit: limit,
          force: force
        )

        if events.empty?
          puts 'No events found matching filters.'
          puts ''
          puts 'Hints:'
          puts '  - Default time window is 24h. Use --since 3d for longer.'
          puts '  - Default status is "failed". Use --status pending for other statuses.'
          puts '  - Use --force to include already successful events.'
          return
        end

        # Display preview
        display_replay_preview(events, dry_run: dry_run)

        # Return early if dry run
        return if dry_run

        # Confirm before execution
        unless yes
          return unless confirm_operation("Replay #{events.size} event(s)?")
        end

        # Execute replay
        execute_replay(events, skip_notifications: skip_notifications)
      end

      private

      # Collect events matching all filters
      #
      # Uses streaming approach: scan Redis keys, load and filter events
      # incrementally, stop when limit reached.
      #
      # Note: Currently uses N+1 Redis calls (one per event). For large-scale
      # replay, consider:
      # 1. RabbitMQ-based replay (publish event IDs to worker queue)
      # 2. Familia load_multi method for batch HGETALL
      # 3. Redis pipeline with proper Horreum deserialization
      #
      # @return [Array<Billing::StripeWebhookEvent>] Matching events
      def collect_replay_candidates(event_id:, type:, since:, customer:, status:, limit:, force:)
        # If specific event_id provided, just wrap in list
        if event_id
          event = Billing::StripeWebhookEvent.find_by_identifier(event_id)
          if event.nil?
            puts "Event not found: #{event_id}"
            return []
          end
          # Skip success check for single event (user explicitly asked for it)
          return [event]
        end

        cutoff = parse_since_option(since)
        customer_pattern = resolve_customer_filter(customer)

        events = []

        # Scan and filter with early termination
        # Over-fetch slightly to allow for filtering, but cap memory usage
        max_scan = limit * 5
        scanned = 0

        scan_webhook_events do |event|
          scanned += 1
          break if scanned > max_scan

          next unless matches_filters?(event, type: type, cutoff: cutoff,
                                       customer_pattern: customer_pattern, status: status, force: force)
          events << event
          break if events.size >= limit
        end

        # Sort chronologically for dependency chains
        events.sort_by { |e| e.created.to_i }
      end

      # Scan all webhook events from Redis
      #
      # @yield [Billing::StripeWebhookEvent] Each event found
      def scan_webhook_events
        cursor = '0'
        prefix_match = format('%s:*:object', Billing::StripeWebhookEvent.prefix)

        loop do
          cursor, batch = Familia.dbclient.scan(cursor, match: prefix_match, count: 100)

          batch.each do |key|
            event_id = key.split(':')[-2]
            event = Billing::StripeWebhookEvent.find_by_identifier(event_id)
            yield event if event
          end

          break if cursor == '0'
        end
      end

      # Check if event matches all filters
      def matches_filters?(event, type:, cutoff:, customer_pattern:, status:, force:)
        # Skip already successful unless forced
        return false if event.success? && !force

        # Type filter
        return false if type && event.event_type != type

        # Status filter
        return false if status && event.processing_status != status

        # Time filter (based on first_seen_at)
        return false if cutoff && event.first_seen_at.to_i < cutoff.to_i

        # Customer filter
        return false if customer_pattern && !matches_customer?(event, customer_pattern)

        true
      end

      # Resolve customer input to Stripe customer ID
      #
      # @param customer_input [String, nil] objid, extid, or cus_xxx
      # @return [String, nil] Stripe customer ID or nil
      def resolve_customer_filter(customer_input)
        return nil unless customer_input

        # Already a Stripe customer ID
        return customer_input if customer_input.start_with?('cus_')

        # Try as OneTime customer objid
        ot_customer = Onetime::Customer.load(customer_input)

        # Try as extid if not found
        ot_customer ||= Onetime::Customer.find_by_extid(customer_input) if Onetime::Customer.respond_to?(:find_by_extid)

        return nil unless ot_customer&.respond_to?(:stripe_customer_id)
        return nil if ot_customer.stripe_customer_id.to_s.empty?

        ot_customer.stripe_customer_id
      end

      # Check if event relates to a specific customer
      def matches_customer?(event, customer_id)
        # Direct match on data_object_id
        return true if event.data_object_id == customer_id

        # Check payload for customer reference
        payload = event.deserialize_payload
        return false unless payload

        data_obj = payload.dig('data', 'object') || {}
        data_obj['customer'] == customer_id ||
          data_obj['id'] == customer_id ||
          data_obj.dig('metadata', 'custid') == customer_id
      end

      # Parse time string to cutoff timestamp
      #
      # @param since_str [String] Time string (2h, 3d, ISO8601)
      # @return [Integer] Unix timestamp cutoff
      def parse_since_option(since_str)
        return (Time.now - 86_400).to_i if since_str.nil? # Default 24h

        case since_str
        when /^(\d+)h$/i
          (Time.now - (::Regexp.last_match(1).to_i * 3600)).to_i
        when /^(\d+)d$/i
          (Time.now - (::Regexp.last_match(1).to_i * 86_400)).to_i
        when /^(\d+)m$/i
          (Time.now - (::Regexp.last_match(1).to_i * 60)).to_i
        else
          Time.parse(since_str).to_i
        end
      end

      # Display replay preview
      def display_replay_preview(events, dry_run:)
        prefix = dry_run ? '[DRY RUN] ' : ''
        puts ''
        puts "#{prefix}Replay Preview"
        puts '=' * 60
        puts ''
        puts "Found #{events.size} event(s) matching filters:"
        puts ''

        puts format('%-28s %-35s %-10s %s',
          'EVENT ID', 'TYPE', 'STATUS', 'AGE'
        )
        puts '-' * 90

        events.each do |event|
          age = format_age(event.first_seen_at)
          puts format('%-28s %-35s %-10s %s',
            event.stripe_event_id,
            event.event_type.to_s[0...35],
            event.processing_status,
            age
          )
        end

        puts ''

        if dry_run
          puts 'Run without --dry-run to execute replay.'
          puts ''
        end
      end

      # Execute replay for all events
      def execute_replay(events, skip_notifications:)
        puts ''
        puts "Replaying #{events.size} event(s)..."
        puts ''

        results = { success: 0, failed: 0, skipped: 0 }

        events.each do |event|
          result = replay_single_event(event, skip_notifications: skip_notifications)
          results[result] += 1
        end

        puts ''
        puts "Results: #{results[:success]} success, #{results[:failed]} failed, #{results[:skipped]} skipped"
        puts ''
      end

      # Replay a single event
      #
      # @param event [Billing::StripeWebhookEvent] Event to replay
      # @param skip_notifications [Boolean] Skip notification side effects
      # @return [Symbol] :success, :failed, or :skipped
      def replay_single_event(event, skip_notifications:)
        # Reconstruct Stripe event
        stripe_event = event.stripe_event
        unless stripe_event
          puts "  FAIL #{event.stripe_event_id} (cannot reconstruct from payload)"
          return :failed
        end

        # Reset and reprocess
        event.mark_processing!

        begin
          # Create webhook controller instance and process
          controller = Billing::Controllers::Webhooks.new
          controller.send(:process_webhook_event, stripe_event)

          event.mark_success!
          puts "  OK   #{event.stripe_event_id} (#{event.event_type})"
          :success
        rescue StandardError => ex
          event.mark_failed!(ex)
          puts "  FAIL #{event.stripe_event_id}: #{ex.message}"
          :failed
        end
      end

      # Format age from timestamp
      def format_age(timestamp)
        return 'N/A' if timestamp.nil? || timestamp.to_s.empty?

        seconds = Time.now.to_i - timestamp.to_i
        return 'just now' if seconds < 60

        if seconds < 3600
          "#{seconds / 60}m ago"
        elsif seconds < 86_400
          "#{seconds / 3600}h ago"
        else
          "#{seconds / 86_400}d ago"
        end
      end
    end
  end
end

Onetime::CLI.register 'billing webhooks replay', Onetime::CLI::BillingWebhooksReplayCommand

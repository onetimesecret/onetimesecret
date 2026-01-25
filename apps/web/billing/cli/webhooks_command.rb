# apps/web/billing/cli/webhooks_command.rb
#
# frozen_string_literal: true

require_relative 'helpers'
require_relative '../models/stripe_webhook_event'

module Onetime
  module CLI
    # Inspect webhook event processing status
    class BillingWebhooksCommand < Command
      include BillingHelpers

      desc 'Inspect webhook event processing status'

      argument :event_id, required: false, desc: 'Stripe event ID (evt_xxx) to inspect'
      option :status, type: :string, desc: 'Filter by status (pending|success|failed|retrying)'
      option :failed, type: :boolean, desc: 'Show only failed events'
      option :stats, type: :boolean, desc: 'Show webhook processing statistics'
      option :migrate, type: :boolean, desc: 'Migrate legacy events to new format'

      def call(event_id: nil, status: nil, failed: false, stats: false, migrate: false, **)
        boot_application!

        return unless stripe_configured?

        if migrate
          migrate_legacy_events
        elsif stats
          show_statistics
        elsif event_id
          inspect_event(event_id)
        elsif failed || status
          list_events_by_status(status || 'failed')
        else
          show_help
        end
      end

      private

      def show_help
        puts 'Usage:'
        puts '  ots billing webhooks EVENT_ID         # Inspect specific event'
        puts '  ots billing webhooks --failed         # List failed events'
        puts '  ots billing webhooks --status pending # List pending events'
        puts '  ots billing webhooks --stats          # Show statistics'
        puts '  ots billing webhooks --migrate        # Migrate legacy events to new format'
        puts ''
        puts 'Note: This command inspects locally tracked events only.'
        puts 'Use "ots billing events" to fetch events from Stripe API.'
      end

      def migrate_legacy_events
        puts 'Scanning for legacy webhook events...'
        puts ''

        keys         = []
        cursor       = '0'
        prefix_match = format('%s:*:object', Billing::StripeWebhookEvent.prefix)
        loop do
          cursor, batch = Familia.dbclient.scan(cursor, match: prefix_match, count: 100)
          keys.concat(batch)
          break if cursor == '0'
        end

        migrated = 0
        skipped  = 0

        keys.each do |key|
          event_id = key.split(':')[-2]  # Extract event ID from prefix:event_id:object
          event    = Billing::StripeWebhookEvent.find_by_identifier(event_id)
          next unless event

          # Skip if already has processing_status
          if event.processing_status
            skipped += 1
            next
          end

          # Migrate: assume old events were successfully processed
          event.processing_status = 'success'
          event.first_seen_at   ||= event.processed_at || Time.now.to_i.to_s
          event.last_attempt_at ||= event.processed_at || Time.now.to_i.to_s
          event.attempt_count   ||= '0'
          event.save

          migrated += 1
        end

        puts 'Migration complete:'
        puts "  Migrated: #{migrated} event(s)"
        puts "  Skipped:  #{skipped} event(s) (already migrated)"
        puts "  Total:    #{keys.size} event(s)"
        puts ''
      end

      def inspect_event(event_id)
        event = Billing::StripeWebhookEvent.find_by_identifier(event_id)

        unless event&.first_seen_at
          puts "Event not found: #{event_id}"
          puts ''
          puts 'Note: Only events processed by this system are tracked.'
          puts 'Use "ots billing events" to fetch from Stripe API.'
          return
        end

        puts ''
        puts "=== Webhook Event: #{event_id} ==="
        puts ''
        puts "Event Type:       #{event.event_type}"
        puts "Status:           #{format_status(event.processing_status)}"
        puts "API Version:      #{event.api_version}"
        puts "Livemode:         #{event.livemode == 'true' ? 'Yes' : 'No (Test Mode)'}"
        puts ''
        puts "First Seen:       #{format_timestamp(event.first_seen_at)}"
        puts "Last Attempt:     #{format_timestamp(event.last_attempt_at)}"
        puts "Processed At:     #{format_timestamp(event.processed_at)}"
        puts ''
        puts "Attempt Count:    #{event.attempt_count || 0}"
        puts "Can Retry:        #{event.retryable? ? 'Yes' : 'No'}"
        puts "Max Attempts:     #{event.max_attempts_reached? ? 'Yes' : 'No'}"
        puts ''

        if event.error_message
          puts 'Error Message:'
          puts "  #{event.error_message}"
          puts ''
        end

        if event.data_object_id
          puts "Affected Object:  #{event.data_object_id}"
        end

        if event.request_id
          puts "Stripe Request:   #{event.request_id}"
        end

        if event.pending_webhooks
          puts "Pending Webhooks: #{event.pending_webhooks}"
        end

        puts ''

        if event.event_payload
          puts 'Payload Preview:'
          preview_payload(event.event_payload)
        end

        puts ''
      end

      def list_events_by_status(target_status)
        puts 'Note: This is a simple implementation that scans Redis keys.'
        puts 'For production use, consider adding a secondary index.'
        puts ''

        # This is a basic implementation - in production you'd want a secondary index
        puts "Scanning for #{target_status} events..."

        # Scan for stripe_webhook_event keys
        keys         = []
        cursor       = '0'
        prefix_match = format('%s:*:object', Billing::StripeWebhookEvent.prefix)
        loop do
          cursor, batch = Familia.dbclient.scan(cursor, match: prefix_match, count: 100)
          keys.concat(batch)
          break if cursor == '0'
        end

        matching_events = []
        keys.each do |key|
          event_id = key.split(':')[-2]  # Extract event ID from prefix:event_id:object
          event    = Billing::StripeWebhookEvent.find_by_identifier(event_id)
          next unless event

          matching_events << event if event.processing_status == target_status
        end

        if matching_events.empty?
          puts "No #{target_status} events found"
          return
        end

        puts format(
          '%-25s %-35s %-12s %-6s %s',
          'EVENT ID',
          'TYPE',
          'STATUS',
          'RETRIES',
          'LAST ATTEMPT',
        )
        puts '-' * 110

        matching_events.sort_by { |e| -(e.last_attempt_at.to_i) }.each do |event|
          puts format(
            '%-25s %-35s %-12s %-6s %s',
            event.stripe_event_id,
            event.event_type.to_s[0...35],
            format_status(event.processing_status),
            event.attempt_count || 0,
            format_timestamp(event.last_attempt_at),
          )

          if event.error_message
            puts "  Error: #{event.error_message.to_s[0...100]}"
          end
        end

        puts ''
        puts "Total: #{matching_events.size} #{target_status} event(s)"
      end

      def show_statistics
        puts 'Scanning webhook events...'
        puts ''

        keys         = []
        cursor       = '0'
        prefix_match = format('%s:*:object', Billing::StripeWebhookEvent.prefix)
        loop do
          cursor, batch = Familia.dbclient.scan(cursor, match: prefix_match, count: 100)
          keys.concat(batch)
          break if cursor == '0'
        end

        stats          = Hash.new(0)
        events_by_type = Hash.new(0)

        keys.each do |key|
          event_id = key.split(':')[-2]  # Extract event ID from prefix:event_id:object
          event    = Billing::StripeWebhookEvent.find_by_identifier(event_id)
          next unless event

          status                                 = event.processing_status || 'unknown'
          stats[status]                         += 1
          events_by_type[event.event_type.to_s] += 1 if event.event_type
        end

        puts '=== Webhook Processing Statistics ==='
        puts ''
        puts "Total Events:     #{keys.size}"
        puts ''
        puts 'By Status:'
        stats.sort_by { |_k, v| -v }.each do |status, count|
          puts "  #{format_status(status).ljust(12)} #{count}"
        end

        puts ''
        puts 'By Event Type:'
        events_by_type.sort_by { |_k, v| -v }.first(10).each do |type, count|
          puts "  #{type.ljust(40)} #{count}"
        end

        puts ''
      end

      def format_status(status)
        case status
        when 'success'
          "\e[32m#{status}\e[0m"  # Green
        when 'failed'
          "\e[31m#{status}\e[0m"  # Red
        when 'retrying'
          "\e[33m#{status}\e[0m"  # Yellow
        when 'pending'
          "\e[36m#{status}\e[0m"  # Cyan
        else
          status.to_s
        end
      end

      def format_timestamp(timestamp)
        return 'N/A' if timestamp.nil? || timestamp.to_s.empty?

        Time.at(timestamp.to_i).strftime('%Y-%m-%d %H:%M:%S')
      rescue ArgumentError
        'Invalid'
      end

      def preview_payload(payload)
          data = JSON.parse(payload)
          puts "  Event ID:   #{data['id']}"
          puts "  Object:     #{data['object']}"
          puts "  Created:    #{format_timestamp(data['created'])}"

          if data['data'] && data['data']['object']
            obj = data['data']['object']
            puts "  Data Type:  #{obj['object']}"
            puts "  Data ID:    #{obj['id']}"
          end
      rescue JSON::ParserError
          puts '  (Invalid JSON - cannot parse)'
      end
    end
  end
end

Onetime::CLI.register 'billing webhooks', Onetime::CLI::BillingWebhooksCommand

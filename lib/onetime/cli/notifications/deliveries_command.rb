# lib/onetime/cli/notifications/deliveries_command.rb
#
# frozen_string_literal: true

# CLI adapter over the delivery-event feed (Onetime::DeliveryEvent, #4479):
# what the application queued, sent, skipped or failed for outbound email and
# webhook notifications, and what the email worker observed.
#
# Usage:
#   ots notifications deliveries
#   ots notifications deliveries --channel email --outcome failed
#   ots notifications deliveries --correlation <id>     # one notification's chain
#   ots notifications deliveries --counts 7             # per-day totals
#   ots notifications deliveries --format json
#
# This is the application's own record. Bounces, complaints, suppressions
# and provider message history are on the colonel email deliverability page
# and `ots email sync-feedback`.

require 'json'
require 'time'
require 'onetime/models/delivery_event'
require 'onetime/operations/notifications/list_delivery_events'

module Onetime
  module CLI
    module Notifications
      class DeliveriesCommand < Command
        desc 'List delivery events for outbound email and webhook notifications'

        option :channel, type: :string, desc: 'email or webhook'
        option :stage, type: :string, desc: 'queue or delivery'
        option :outcome, type: :string, desc: 'queued, sent, failed or skipped'
        option :correlation, type: :string, desc: 'Correlation id of one notification'
        option :template, type: :string, desc: 'Template name'
        option :limit, type: :integer, default: 50, aliases: ['n'], desc: 'Max events to show'
        option :offset, type: :integer, default: 0, desc: 'Matching events to skip'
        option :counts, type: :integer, desc: 'Show unfiltered per-day totals for the last N days (no event filters)'
        option :format, type: :string, default: 'text', aliases: ['f'], desc: 'Output format: text or json'

        def call(channel: nil, stage: nil, outcome: nil, correlation: nil, template: nil,
                 limit: 50, offset: 0, counts: nil, format: 'text', **)
          boot_application!

          raise ArgumentError, '--format must be one of: text, json' unless %w[text json].include?(format)
          raise ArgumentError, '--limit must be a positive integer' if limit.to_i < 1

          if counts
            raise ArgumentError, '--counts must be a positive integer' if counts.to_i < 1

            max_days = Onetime::DeliveryEvent::COUNTS_TTL / 86_400
            raise ArgumentError, "--counts must be at most #{max_days} days" if counts.to_i > max_days

            filters   = { channel: channel, stage: stage, outcome: outcome, correlation: correlation, template: template }
            requested = filters.reject { |_name, value| value.nil? }.keys
            unless requested.empty?
              flags = requested.map { |name| "--#{name}" }.join(', ')
              raise ArgumentError, "--counts cannot be combined with event filters: #{flags}"
            end

            return output_counts(counts.to_i, format)
          end

          result = Onetime::Operations::Notifications::ListDeliveryEvents.new(
            limit: limit,
            offset: offset,
            channel: channel,
            stage: stage,
            outcome: outcome,
            correlation_id: correlation,
            template: template,
          ).call

          format == 'json' ? output_json(result) : output_text(result)
        rescue StandardError => ex
          warn "Error: #{ex.message}"
          exit 1
        end

        private

        def output_json(result)
          puts JSON.pretty_generate(
            events: result.events,
            limit: result.limit,
            offset: result.offset,
            more: result.more,
            retained: result.retained,
            filters: result.filters,
          )
        end

        def output_text(result)
          if result.events.empty?
            puts 'No delivery events match.'
            puts format('Retained events: %d', result.retained)
            return
          end

          puts format(
            '%-20s %-8s %-9s %-8s %-24s %-22s %s',
            'Occurred (UTC)',
            'Channel',
            'Stage',
            'Outcome',
            'Template',
            'Correlation',
            'Detail',
          )
          puts '-' * 110

          result.events.each do |event|
            puts format(
              '%-20s %-8s %-9s %-8s %-24s %-22s %s',
              Time.at(event[:occurred_at].to_f).utc.strftime('%Y-%m-%d %H:%M:%S'),
              event[:channel],
              event[:stage],
              event[:outcome],
              event[:template].to_s[0, 24],
              event[:correlation_id].to_s,
              detail_for(event),
            )
          end

          puts '-' * 110
          puts format(
            'Shown: %d  Retained: %d%s',
            result.events.size,
            result.retained,
            result.more ? '  (more; use --offset)' : '',
          )
        end

        def detail_for(event)
          parts = []
          parts << event[:reason] if event[:reason]
          parts << "http=#{event[:http_status]}" if event[:http_status]
          parts << "host=#{event[:target_host]}" if event[:target_host]
          parts << "provider=#{event[:provider]}" if event[:provider]
          parts << "attempts=#{event[:attempt_count]}" if event[:attempt_count]
          parts << "#{event[:duration_ms]}ms" if event[:duration_ms]
          parts << event[:error_class] if event[:error_class]
          parts.join(' ')
        end

        def output_counts(days, format)
          rows = Onetime::DeliveryEvent.daily_counts(days)

          if format == 'json'
            puts JSON.pretty_generate(rows)
            return
          end

          puts format('%-10s %s', 'Day (UTC)', 'channel:stage:outcome = count')
          puts '-' * 60
          rows.each do |row|
            counts = row[:counts].sort.map { |field, count| "#{field}=#{count}" }.join('  ')
            puts format('%-10s %s', row[:date], counts.empty? ? '-' : counts)
          end
        end
      end
    end

    register 'notifications deliveries', Notifications::DeliveriesCommand
  end
end

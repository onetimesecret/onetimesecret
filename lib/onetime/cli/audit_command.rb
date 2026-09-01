# lib/onetime/cli/audit_command.rb
#
# frozen_string_literal: true

# CLI reader for the operator audit trail (#4334).
#
# Usage:
#   ots audit                                       # usage
#   ots audit list                                  # newest 50, human-readable
#   ots audit list --limit 500 --format ndjson      # machine-readable
#   ots audit list --verb customer --format csv     # one category, spreadsheet
#   ots audit list --actor colonel@example.com
#
# READ-ONLY, like the console screen and the export endpoint it shares code
# with: reading the log never records an audit event (CONTRACT 4).
#
# Everything but the terminal table comes from Onetime::ColonelAuditReader —
# the same merge, the same filters and the same FIELD ALLOWLIST the HTTP
# surfaces use. That is the reason this command is thin: an operator reading
# the trail from a shell must see the same record, with the same fields, as one
# reading it in the console, and there must be exactly one place that decides
# what those fields are.
#
# Loaded explicitly (not via an app autoloader) because CLI runs never load the
# colonel app.
require 'json'

require 'onetime/colonel_audit_reader'

module Onetime
  module CLI
    # Namespace for the audit reader subcommands.
    module Audit
      # Default page size for the human-readable listing. Small on purpose: the
      # terminal view is for "what just happened", and an operator who wants the
      # whole trail is asking for --format csv/ndjson and a redirect.
      DEFAULT_LIMIT = 50

      # Terminal-only formats plus the two export serialisations
      # (Onetime::ColonelAuditReader::FORMATS). `text` is the default because a
      # bare `ots audit list` is a human reading a screen.
      FORMATS = (%w[text json] + Onetime::ColonelAuditReader::FORMATS).freeze

      # List recent audit events, newest first.
      class ListCommand < Command
        desc 'List recent operator audit events (newest first)'

        option :limit,
          type: :integer,
          default: DEFAULT_LIMIT,
          aliases: ['n'],
          desc: "Maximum events to show (default: #{DEFAULT_LIMIT})"
        option :actor,
          type: :string,
          desc: 'Filter by actor (case-insensitive substring of extid/email)'
        option :verb,
          type: :string,
          desc: 'Filter by verb: exact (customer.purge) or category (customer)'
        option :format,
          type: :string,
          default: 'text',
          aliases: ['f'],
          desc: "Output format: #{FORMATS.join(', ')}"

        def call(limit: DEFAULT_LIMIT, actor: nil, verb: nil, format: 'text', **)
          boot_application!

          unless FORMATS.include?(format)
            warn "Unknown format '#{format}'. Use one of: #{FORMATS.join(', ')}"
            exit 1
          end

          events = Onetime::ColonelAuditReader.recent(
            limit: limit.to_i,
            actor: actor,
            verb: verb,
          )

          case format
          when 'text' then print_table(events)
          when 'json' then puts JSON.pretty_generate(events.map { |e| Onetime::ColonelAuditReader.format_event(e) })
          else print Onetime::ColonelAuditReader.serialize(events, format: format)
          end
        end

        private

        # Human-readable listing. Deliberately NOT the export format: it drops
        # the event id and truncates detail to fit a terminal, so a caller who
        # needs the record uses --format json/csv/ndjson instead. Diagnostics go
        # to stderr under the CLI, so this stdout stream stays parseable-ish.
        def print_table(events)
          if events.empty?
            puts 'No audit events recorded.'
            return
          end

          puts format('%-20s %-26s %-24s %-22s %s', 'When (UTC)', 'Actor', 'Verb', 'Target', 'Result')
          puts '-' * 110

          events.each do |event|
            row = Onetime::ColonelAuditReader.format_event(event)
            puts format(
              '%-20s %-26s %-24s %-22s %s',
              timestamp(row[:created]),
              clip(row[:actor], 26),
              clip(row[:verb], 24),
              clip(row[:target], 22),
              row[:result],
            )

            detail = detail_line(row[:detail])
            puts "    #{detail}" unless detail.nil?
          end
        end

        def timestamp(created)
          Time.at(created.to_f).utc.strftime('%Y-%m-%d %H:%M:%S')
        rescue StandardError
          'unknown'
        end

        def clip(value, width)
          str = value.to_s
          str.length <= width ? str : "#{str[0, width - 1]}…"
        end

        # Detail is free-form and already redacted by the model; render it as
        # compact JSON and clip it so one long event cannot swamp the listing.
        def detail_line(detail)
          return nil if detail.nil?

          text = detail.is_a?(String) ? detail : JSON.generate(detail)
          return nil if text.empty? || text == '{}'

          clip(text, 100)
        end
      end
    end

    # Default audit command (shows usage)
    class AuditCommand < Command
      desc 'Read the operator audit trail'

      def call(**)
        boot_application!

        puts 'Operator audit trail'
        puts '-' * 70
        puts "Retained events: #{Onetime::ColonelAuditEvent.count} operator, " \
             "#{Onetime::ColonelAuditEvent.security_count} security telemetry"
        puts
        puts 'Usage: ots audit <subcommand> [options]'
        puts
        puts 'Available subcommands:'
        puts '  list [--limit N] [--actor X] [--verb Y] [--format F]'
        puts
        puts 'Formats: text (default), json, csv, ndjson.'
        puts 'Redirect csv/ndjson to a file for an export:'
        puts '  ots audit list --limit 10000 --format ndjson > audit.ndjson'
        puts
        puts 'The retained trail is a bounded cache, not the archive: every event'
        puts 'is also emitted to the ColonelAudit log sink at write time, which is'
        puts 'where longer retention lives.'
      end
    end

    register 'audit', AuditCommand
    register 'audit list', Audit::ListCommand
  end
end

# lib/onetime/colonel_audit_reader.rb
#
# frozen_string_literal: true

require 'csv'
require 'json'

require_relative 'models/colonel_audit_event'

module Onetime
  # ColonelAuditReader — the single READ projection of the operator audit trail.
  #
  # {Onetime::ColonelAuditEvent} owns storage; this owns what a reader is
  # allowed to see and how a reader serialises it. It exists because there are
  # now THREE readers of the same trail and they must not drift:
  #
  #   1. GET /api/colonel/audit    — ColonelAPI::Logic::Colonel::ListColonelAuditEvents
  #   2. GET /api/colonel/audit/export — …::ExportColonelAuditEvents (CSV / NDJSON)
  #   3. `bin/ots audit list`      — Onetime::CLI::Audit::ListCommand
  #
  # The field ALLOWLIST is the reason this is shared rather than copied. The
  # stored member is an internal shape; every reader emits {FIELDS} explicitly,
  # so a field added to the model for internal use cannot leak into a wire
  # payload, a download, or a terminal by being forgotten in one of three
  # places. It lives in lib/ (not in the colonel app) because the CLI reaches
  # it without any app autoloader.
  #
  # Read-only by construction: nothing here writes, and per CONTRACT 4 reading
  # the log never records an audit event.
  module ColonelAuditReader
    # Ceiling on how many events one read may load into Ruby: the two trails'
    # caps summed, i.e. the entire store. Both are trimmed on every write, so
    # this is a fixed bound, not a function of traffic.
    MAX_COMBINED = ColonelAuditEvent::MAX_EVENTS + ColonelAuditEvent::MAX_SECURITY_EVENTS

    # The allowlist, in a fixed column order (the CSV header depends on the
    # order; the JSON surfaces do not, but keeping one order keeps the three
    # readers describing the same record the same way).
    FIELDS = [:id, :actor, :verb, :target, :result, :detail, :created].freeze

    # Export serialisations. Deliberately not JSON-array: an audit export is
    # append-shaped and consumed line-at-a-time by log tooling, so NDJSON is
    # the structured option and CSV the spreadsheet one.
    FORMATS = %w[csv ndjson].freeze

    DEFAULT_FORMAT = 'csv'

    CONTENT_TYPES = {
      'csv' => 'text/csv; charset=utf-8',
      'ndjson' => 'application/x-ndjson; charset=utf-8',
    }.freeze

    class << self
      # Newest-first view over BOTH audit trails.
      #
      # The model stores operator activity and unauthenticated security
      # telemetry in two separately-capped sorted sets so a flood of anonymous
      # events cannot evict privileged records (the WRITE-FREQUENCY INVARIANT
      # on {Onetime::ColonelAuditEvent}). That split is a storage concern; every
      # reader wants one chronological feed, so the merge happens here.
      #
      # Both trails are already newest-first, so this is a merge by `created`
      # (descending) truncated to `limit`, and bounded by {MAX_COMBINED}: an
      # arbitrarily deep page can never read more than the whole store.
      #
      # @param limit [Integer] max events to return.
      # @return [Array<Hash>] raw stored events (string keys), newest first.
      def merged(limit)
        limit = [limit.to_i, MAX_COMBINED].min
        return [] if limit <= 0

        (ColonelAuditEvent.recent(limit) + ColonelAuditEvent.recent_security(limit))
          .sort_by { |event| -event['created'].to_f }
          .first(limit)
      end

      # Newest-first, filtered. The filtered path always reads the whole store
      # because the events are opaque JSON members — matching happens in Ruby.
      # Bounded by design (see {merged}).
      #
      # @param limit [Integer] max events to return AFTER filtering.
      # @param actor [String, nil] case-insensitive substring over the actor.
      # @param verb [String, nil] exact verb, or a dotted category prefix.
      # @return [Array<Hash>] raw stored events, newest first.
      def recent(limit: MAX_COMBINED, actor: nil, verb: nil)
        limit  = [limit.to_i, MAX_COMBINED].min
        return [] if limit <= 0

        return merged(limit) unless filters?(actor, verb)

        merged(MAX_COMBINED)
          .select { |event| matches?(event, actor: actor, verb: verb) }
          .first(limit)
      end

      # @return [Boolean] whether either filter is active.
      def filters?(actor, verb)
        !actor.to_s.empty? || !verb.to_s.empty?
      end

      # `actor` matches as a case-insensitive substring (the sessions-search
      # idiom); `verb` matches exactly OR as a dotted category prefix, so
      # `customer` reaches every `customer.*` verb.
      def matches?(event, actor: nil, verb: nil)
        actor = actor.to_s
        if !actor.empty? && !event['actor'].to_s.downcase.include?(actor.downcase)
          return false
        end

        verb = verb.to_s
        return true if verb.empty?

        stored = event['verb'].to_s
        stored == verb || stored.start_with?("#{verb}.")
      end

      # Project one stored event onto the allowlist. Emitted field by field —
      # never the raw stored hash — so the readable surface stays a deliberate
      # decision even if the model grows internal fields later.
      #
      # @return [Hash] symbol-keyed, exactly {FIELDS}.
      def format_event(event)
        {
          id: event['id'].to_s,
          actor: event['actor'].to_s,
          verb: event['verb'].to_s,
          target: event['target'].to_s,
          result: event['result'].to_s,
          detail: event['detail'],
          created: event['created'].to_f,
        }
      end

      # @param value [String, Symbol, nil]
      # @return [String, nil] a member of {FORMATS}, or nil when unrecognised
      #   (callers decide whether that is a default or an error).
      def normalize_format(value)
        candidate = value.to_s.strip.downcase
        return DEFAULT_FORMAT if candidate.empty?

        FORMATS.include?(candidate) ? candidate : nil
      end

      # @return [String] MIME type for a normalised format.
      def content_type(format)
        CONTENT_TYPES.fetch(format)
      end

      # Serialise events for download.
      #
      # Built in memory rather than streamed: the input is hard-bounded by
      # {MAX_COMBINED} (the whole store), so the size is fixed and small, and a
      # streaming body would buy nothing while complicating the Rack contract.
      #
      # @param events [Array<Hash>] raw stored events.
      # @param format [String] a member of {FORMATS}.
      # @return [String]
      def serialize(events, format:)
        case format
        when 'ndjson' then to_ndjson(events)
        when 'csv' then to_csv(events)
        else raise ArgumentError, "unsupported audit export format: #{format}"
        end
      end

      # One JSON object per line, allowlisted. `detail` keeps its native JSON
      # type here (hash / string / null) — this is the lossless serialisation.
      def to_ndjson(events)
        return '' if events.empty?

        events.map { |event| "#{JSON.generate(format_event(event))}\n" }.join
      end

      # Header row + one row per event, allowlisted, in {FIELDS} order.
      #
      # `detail` is free-form (hash / string / null) and a CSV cell is text, so
      # it is JSON-encoded: a consumer parses that one cell as JSON and gets
      # exactly what the JSON surfaces return. `created` stays the stored epoch
      # float — the same value {format_event} emits — rather than becoming a second,
      # drift-prone timestamp representation.
      def to_csv(events)
        CSV.generate do |csv|
          csv << FIELDS
          events.each do |event|
            row = format_event(event)
            csv << FIELDS.map { |field| csv_cell(row[field]) }
          end
        end
      end

      # Suggested download filename for a format. Timestamped so repeated
      # exports do not overwrite each other in a downloads folder.
      def filename(format, now: Time.now.utc)
        "colonel-audit-#{now.strftime('%Y%m%dT%H%M%SZ')}.#{format}"
      end

      private

      def csv_cell(value)
        case value
        when nil then ''
        when String, Numeric, TrueClass, FalseClass then value
        else JSON.generate(value)
        end
      end
    end
  end
end

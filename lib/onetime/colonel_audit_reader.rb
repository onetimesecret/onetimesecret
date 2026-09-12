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
  # READ-ONLY BY CONSTRUCTION, and it stays that way after #4335: nothing in
  # this module writes. Reading the trail IS now recorded — as an observation on
  # the `access_events` trail, never on the operator trail — but each of the
  # three READERS emits its own event around its call into here, using the verb
  # constants below. Keeping the write out of this module is what makes the
  # recursion question trivial: `merged` can read the access trail without any
  # chance of appending to it mid-read, and a reader that calls this module
  # twice still records once.
  module ColonelAuditReader
    # Ceiling on how many events one read may load into Ruby: the three trails'
    # caps summed, i.e. the entire store. All three are trimmed on every write,
    # so this is a fixed bound, not a function of traffic.
    MAX_COMBINED = ColonelAuditEvent::MAX_EVENTS +
                   ColonelAuditEvent::MAX_SECURITY_EVENTS +
                   ColonelAuditEvent::MAX_ACCESS_EVENTS

    # The audit-READ verbs (#4335). Single-sourced here rather than on each
    # emitter because they have THREE emitters that already share this module —
    # see the multi-emitter note on {Onetime::ColonelAuditEvent::VERB_COLONEL_SIGNIN}.
    # Reading the flight recorder is itself an operator action worth recording:
    # "who has been reading the audit log" is one of the first questions asked
    # after an incident, and it was the one question the log could not answer.
    #
    # A page view and a bulk download are separate verbs on purpose. Exporting
    # takes the whole retained trail out of the system as a file; listing shows
    # one page in a console. An operator scanning for exfiltration wants those
    # distinguishable without parsing `detail`.
    AUDIT_VERB_LIST   = 'audit.list'
    AUDIT_VERB_EXPORT = 'audit.export'

    # Fixed audit target for the read verbs: the trail has no per-resource
    # public id, and the thing being read IS the trail.
    AUDIT_TARGET = 'colonel_audit'

    # Wire values for the `trail` discriminator, matching the names the SINK
    # already tags its lines with ({ColonelAuditEvent.emit_to_sink}) so a line
    # in the log stream and a row in the console remain the same record.
    TRAIL_OPERATOR = 'events'
    TRAIL_SECURITY = 'security_events'
    TRAIL_ACCESS   = 'access_events'

    # The allowlist, in a fixed column order (the CSV header depends on the
    # order; the JSON surfaces do not, but keeping one order keeps the three
    # readers describing the same record the same way).
    #
    # `trail` is APPENDED rather than slotted next to `result`, so every
    # incumbent CSV column keeps its index for consumers reading positionally.
    #
    # WHY IT IS ON THE WIRE AT ALL (#4335). Two trails merged invisibly was
    # defensible; three is not. Retention now differs per trail — the operator
    # trail is count-capped only, the security trail expires at 7 days, the
    # observation trail at 30 — so "nothing before date X" means something
    # different depending on which trail a row came from, and a reader with no
    # discriminator cannot tell whether an absence is an eviction, an
    # expiry, or a thing that never happened. It also closes a real drift: the
    # sink has tagged every line with `trail` since #4334, so until now the
    # console and the log stream described the same event differently.
    FIELDS = [:id, :actor, :verb, :target, :result, :detail, :created, :trail].freeze

    # Export serialisations. Deliberately not JSON-array: an audit export is
    # append-shaped and consumed line-at-a-time by log tooling, so NDJSON is
    # the structured option and CSV the spreadsheet one.
    FORMATS = %w[csv ndjson].freeze

    DEFAULT_FORMAT = 'csv'

    CONTENT_TYPES = {
      'csv' => 'text/csv; charset=utf-8',
      'ndjson' => 'application/x-ndjson; charset=utf-8',
    }.freeze

    # Leading characters that make a spreadsheet treat a CSV cell as a FORMULA
    # rather than text (Excel, LibreOffice, Google Sheets). `=` and `+` open a
    # formula outright, `-` opens one as a negation, `@` is Excel's legacy
    # function-call sigil, and a leading TAB or CR is stripped by the importer
    # before it looks at the first character — so `\t=cmd|'/c calc'!A1` slips
    # past a check that only looked for `=`.
    #
    # This matters here because the trail now carries OPERATOR FREE TEXT: the
    # #4338 `reason` and the session-console search term both land in `detail`,
    # and an unresolved identifier lands in `target`. An export is a file
    # someone opens in a spreadsheet, so a cell like `=HYPERLINK(...)` is a
    # payload with a reader, planted by whoever could reach an audited surface.
    CSV_FORMULA_PREFIXES = ['=', '+', '-', '@', "\t", "\r"].freeze

    # The prefix that neutralises them: a leading apostrophe is the standard
    # "this cell is text" marker every major spreadsheet honours (and strips
    # from the displayed value). It is added at SERIALISATION time only —
    # nothing stored, and nothing on the JSON/NDJSON surfaces, changes.
    CSV_FORMULA_GUARD = "'"

    class << self
      # Newest-first view over ALL THREE audit trails.
      #
      # The model stores operator activity, unauthenticated security telemetry
      # and authenticated observations in three separately-capped sorted sets so
      # that neither anonymous floods nor chatty console reading can evict
      # privileged records (the WRITE-FREQUENCY INVARIANT on
      # {Onetime::ColonelAuditEvent}). Those splits are a storage concern; every
      # reader wants one chronological feed, so the merge happens here.
      #
      # Each trail is already newest-first, so this is a merge by `created`
      # (descending) truncated to `limit`, and bounded by {MAX_COMBINED}: an
      # arbitrarily deep page can never read more than the whole store.
      #
      # Rows are TAGGED with their source trail on the way through, without
      # mutating what the model returns. The tag is derived from which
      # collection a row came from rather than stored on the member, so no
      # historical event needs backfilling and the stored shape is unchanged.
      #
      # @param limit [Integer] max events to return.
      # @return [Array<Hash>] stored events (string keys) plus `trail`, newest
      #   first.
      def merged(limit)
        limit = [limit.to_i, MAX_COMBINED].min
        return [] if limit <= 0

        (tagged(ColonelAuditEvent.recent(limit), TRAIL_OPERATOR) +
          tagged(ColonelAuditEvent.recent_security(limit), TRAIL_SECURITY) +
          tagged(ColonelAuditEvent.recent_access(limit), TRAIL_ACCESS))
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
          # Stamped by {merged}, not stored on the member. An event reaching
          # here untagged (a caller formatting a raw model read) falls back to
          # the operator trail, which is where an untagged event came from
          # before there was anything else.
          trail: event.fetch('trail', TRAIL_OPERATOR).to_s,
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
      #
      # Every cell is then run through the formula guard (see
      # {CSV_FORMULA_PREFIXES}). CSV ONLY: NDJSON has no formula problem, and
      # adding a character to a JSON string would corrupt the lossless
      # serialisation for the tooling that consumes it.
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

      # Stamp one trail's rows with where they came from, non-destructively —
      # `merge` rather than `[]=`, so nothing a caller handed us (or a model
      # collection returned) is modified in place.
      def tagged(events, trail)
        events.map { |event| event.merge('trail' => trail) }
      end

      # One CSV cell: the value's text form, guarded against formula injection.
      #
      # The guard is applied LAST, to the finished cell string, so it covers the
      # JSON-encoded `detail` as well as the plain string fields — a caller
      # cannot slip a payload past it by choosing a different serialisation. The
      # text form is what CSV would have written anyway (`CSV#<<` calls #to_s on
      # every field), so numbers and booleans still export unquoted and
      # unchanged; only a cell that would OPEN A FORMULA gains a character.
      def csv_cell(value)
        cell = case value
               when nil then ''
               when String, Numeric, TrueClass, FalseClass then value.to_s
               else JSON.generate(value)
               end

        guard_csv_formula(cell)
      end

      # Prefix a cell that a spreadsheet would evaluate rather than display.
      # See {CSV_FORMULA_PREFIXES} for why each character is on the list.
      def guard_csv_formula(cell)
        return cell if cell.empty?
        return cell unless CSV_FORMULA_PREFIXES.include?(cell[0])

        "#{CSV_FORMULA_GUARD}#{cell}"
      end
    end
  end
end

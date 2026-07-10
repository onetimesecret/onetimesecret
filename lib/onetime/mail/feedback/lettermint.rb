# lib/onetime/mail/feedback/lettermint.rb
#
# frozen_string_literal: true

require_relative 'base'

module Onetime
  module Mail
    module Feedback
      # Lettermint deliverability feedback fetcher.
      #
      # Reads the Lettermint *suppression list* via the Team API
      # (`GET /suppressions`), the addresses Lettermint stopped sending to for
      # hard bounces, spam complaints, and unsubscribes. This is a team-level
      # resource, so it authenticates with the team token (`lm_team_*`), NOT the
      # project sending token used by the delivery backend. We import the list as
      # suppressions, mapping Lettermint's reason vocabulary onto ours.
      #
      # Configuration (from Mailer.provider_credentials('lettermint')):
      #   team_token  — required (the Team API bearer token)
      #   base_url    — optional API base URL override
      #   timeout     — optional request timeout (seconds)
      class Lettermint < Base
        # Lettermint suppression reasons -> our suppression reasons. Unsubscribe
        # is a legitimate stop-mailing signal but not a bounce/complaint, so it
        # imports as 'manual'.
        REASON_MAP = {
          'hard_bounce' => 'bounce',
          'spam_complaint' => 'complaint',
          'unsubscribe' => 'manual',
          'manual' => 'manual',
        }.freeze

        # Lettermint page size (its default is 30; 100 cuts round-trips).
        PAGE_SIZE = 100

        def fetch(limit: MAX_FETCH)
          limit   = clamp_limit(limit)
          records = []
          cursor  = nil
          rounds  = 0

          loop do
            response = team_api.suppressions.list(page_size: PAGE_SIZE, page_cursor: cursor)

            each_entry(response) do |entry|
              value = fetch_field(entry, 'value')
              # Suppressions can be scoped to a domain or extension too; we only
              # import address-level entries into the per-address suppression list.
              next unless value.to_s.include?('@')

              records << suppression_record(
                email: value,
                reason: REASON_MAP[fetch_field(entry, 'reason').to_s] || 'manual',
                source: 'lettermint',
              )
              break if records.size >= limit
            end

            cursor  = next_cursor(response)
            rounds += 1
            break if records.size >= limit
            break if cursor.nil? || cursor.to_s.empty?
            break if rounds >= MAX_ROUNDS
          end

          records.first(limit)
        end

        # Deliverability stats over a date range for the status panel (Track B).
        # Returns the provider totals normalized to our metric names. The exact
        # /stats envelope field names are provider-versioned and unconfirmed at
        # build time, so extraction is tolerant (data/totals wrapper + a few
        # metric aliases); an unexpected shape yields zeroed metrics rather than
        # raising. The op computes bounce/complaint RATES from these in Ruby.
        def stats(from:, to:)
          response = team_api.stats.get(from: from, to: to)
          totals   = extract_totals(response)

          {
            sent: metric(totals, 'sent', 'total', 'total_sent', 'messages'),
            delivered: metric(totals, 'delivered', 'delivery'),
            hard_bounced: metric(totals, 'hard_bounced', 'bounced', 'hard_bounces', 'bounces'),
            # nil (NOT 0) when absent: Lettermint's /stats totals expose
            # sent/delivered/bounced but NO complaint field (confirmed against
            # the gem's own stats_spec fixtures). A 0 here would render a
            # misleading 0.00% complaint rate — "healthy" — to an operator whose
            # actual problem is a poor rating. nil surfaces as "not reported".
            spam_complaints: metric_or_nil(totals, 'spam_complaints', 'complained', 'complaints', 'complaint', 'spam'),
            opened: metric(totals, 'opened', 'opens'),
            clicked: metric(totals, 'clicked', 'clicks'),
          }
        end

        # Recent outbound message log (Track B, item 9) — SES has no equivalent
        # (fire-and-forget), so this is the ONLY live send log. Maps each row to
        # the wire shape. Recipient addresses + subjects are returned in
        # plaintext: this is a live, colonel-only admin read that is never
        # persisted, so it is exempt from the at-rest address-hashing posture.
        def messages(page_size:, page_cursor: nil)
          response = team_api.messages.list(page_size: page_size, page_cursor: page_cursor)
          rows     = envelope_rows(response)

          {
            messages: rows.map { |row| message_record(row) },
            cursor: next_cursor(response),
          }
        end

        # Live per-address suppression lookup (Track B, item 10). The gem sends
        # filter params flat and the API may IGNORE filter[value], returning
        # substring matches, so we KEEP only the exact `value == address` row
        # (contract §4 rule 9 — never trust the provider filter for a lookup).
        # Returns the RAW Lettermint reason (not REASON_MAP'd). Errors propagate
        # to the op's fail-soft rescue.
        def lookup(address)
          response = team_api.suppressions.list(value: address)
          rows     = envelope_rows(response)
          match    = rows.find { |row| fetch_field(row, 'value').to_s == address }

          if match
            { suppressed: true, reason: fetch_field(match, 'reason')&.to_s, last_update_time: nil }
          else
            { suppressed: false, reason: nil, last_update_time: nil }
          end
        end

        private

        # Rows array from Lettermint's paginated envelope ('data'), tolerating a
        # bare array. Mirrors #each_entry but returns the array for map/find.
        def envelope_rows(response)
          if response.is_a?(Hash)
            response['data'] || response[:data] || []
          else
            Array(response)
          end
        end

        # The /stats totals block, tolerating {totals:}, {data:{totals:}},
        # {data:{...}}, or a flat totals hash.
        def extract_totals(response)
          return {} unless response.is_a?(Hash)

          totals = response['totals'] || response[:totals]
          return totals if totals.is_a?(Hash)

          data = response['data'] || response[:data]
          if data.is_a?(Hash)
            return data['totals'] || data[:totals] || data
          end

          response
        end

        # First present metric under any alias, coerced to Integer; 0 when absent.
        def metric(totals, *names)
          return 0 unless totals.is_a?(Hash)

          names.each do |name|
            value = totals[name] || totals[name.to_sym]
            return value.to_i unless value.nil?
          end
          0
        end

        # Like {#metric} but returns nil (NOT 0) when no alias is present, so a
        # caller can tell "the provider reported zero" from "the provider does
        # not report this metric at all". Used for complaints (see {#stats}).
        def metric_or_nil(totals, *names)
          return nil unless totals.is_a?(Hash)

          names.each do |name|
            value = totals[name] || totals[name.to_sym]
            return value.to_i unless value.nil?
          end
          nil
        end

        def message_record(row)
          {
            id: fetch_field(row, 'id').to_s,
            status: fetch_field(row, 'status').to_s,
            subject: fetch_field(row, 'subject').to_s,
            to: recipients(row),
            from_email: (fetch_field(row, 'from_email') || fetch_field(row, 'from')).to_s,
            created_at: parse_time(fetch_field(row, 'created_at')),
          }
        end

        def recipients(row)
          raw = fetch_field(row, 'to') || fetch_field(row, 'recipients')
          Array(raw).map(&:to_s)
        end

        # Lettermint timestamps arrive as ISO8601 strings; normalize to Unix
        # seconds (the wire contract). Tolerate an already-numeric value and
        # never raise on an unparseable one.
        def parse_time(value)
          return nil if value.nil?
          return value.to_i if value.is_a?(Numeric)

          require 'time'
          Time.parse(value.to_s).to_i
        rescue StandardError
          nil
        end

        def team_api
          @team_api ||= begin
            require 'lettermint'

            token = config['team_token']
            if token.nil? || token.to_s.strip.empty?
              raise ArgumentError,
                'Lettermint team token required to read the suppression list ' \
                '(set emailer.lettermint_team_token / LETTERMINT_TEAM_TOKEN)'
            end

            ::Lettermint::TeamAPI.new(
              team_token: token,
              base_url: config['base_url'],
              timeout: config['timeout'],
            )
          end
        end

        # The suppressions list payload wraps its rows under 'data' (Lettermint's
        # paginated envelope); tolerate a bare array too.
        def each_entry(response, &)
          rows = if response.is_a?(Hash)
            response['data'] || response[:data] || []
          else
            Array(response)
          end
          Array(rows).each(&)
        end

        # Extract the next-page cursor from Lettermint's pagination envelope,
        # tolerating the shapes it may return; nil ends pagination.
        def next_cursor(response)
          return nil unless response.is_a?(Hash)

          pagination = response['pagination'] || response[:pagination] ||
                       response['meta'] || response[:meta] || {}
          fetch_field(pagination, 'next_cursor') ||
            fetch_field(pagination, 'next_page_cursor') ||
            fetch_field(response, 'next_cursor')
        end

        def fetch_field(hash, name)
          return nil unless hash.is_a?(Hash)

          hash[name] || hash[name.to_sym]
        end
      end
    end
  end
end

# lib/onetime/mail/feedback/smtp2go.rb
#
# frozen_string_literal: true

require_relative 'base'
require_relative '../smtp2go_client'

module Onetime
  module Mail
    module Feedback
      # SMTP2GO deliverability feedback fetcher.
      #
      # Reads the SMTP2GO *suppression list* via `POST /suppression/view` — the
      # addresses (and domains) SMTP2GO stopped sending to for hard bounces,
      # spam complaints, unsubscribes, and manual blocks. We import the list as
      # suppressions, mapping SMTP2GO's reason vocabulary onto ours.
      #
      # API shape (confirmed against the SMTP2GO API v3 reference,
      # https://smtp2go.github.io/smtp2go.apidocs/ — "View Suppressions"):
      # the endpoint takes optional email_address/wildcard filters, has NO
      # pagination (it returns the whole list in one response), and each row is
      #   { "email_address": ..., "complain": ..., "block_description": ...,
      #     "reason": "manual" | "spam" | "bounce" | "unsubscribe",
      #     "timestamp": "2021-04-30T00:00:00" }
      # wrapped in the standard { request_id, data: { suppressions: [...] } }
      # envelope, which {Onetime::Mail::Smtp2goClient#post} unwraps to the
      # `data` hash.
      #
      # Configuration (from Mailer.provider_credentials('smtp2go')):
      #   api_key   — required (same key the delivery backend uses)
      #   base_url  — optional API base URL override
      #   timeout   — optional read timeout (seconds)
      class Smtp2go < Base
        # SMTP2GO suppression reasons -> our suppression reasons. Unsubscribe
        # is a legitimate stop-mailing signal but not a bounce/complaint, so it
        # imports as 'manual' (same convention as the Lettermint fetcher).
        REASON_MAP = {
          'bounce' => 'bounce',
          'spam' => 'complaint',
          'unsubscribe' => 'manual',
          'manual' => 'manual',
        }.freeze

        def fetch(limit: MAX_FETCH)
          limit   = clamp_limit(limit)
          records = []

          # No pagination: /suppression/view returns the full suppression list
          # in a single response (the API exposes no cursor/page parameter for
          # it), so one POST and a client-side clamp is the whole walk.
          response = client.post('/suppression/view', {})

          each_entry(response) do |entry|
            value = fetch_field(entry, 'email_address')
            # Suppressions can be domain-scoped too (e.g. "@example.com"); we
            # only import address-level entries into the per-address list.
            next unless address_level?(value)

            records << suppression_record(
              email: value,
              reason: REASON_MAP[fetch_field(entry, 'reason').to_s] || 'manual',
              source: 'smtp2go',
            )
            break if records.size >= limit
          end

          records.first(limit)
        end

        # Live per-address suppression lookup (Track B, item 10). The
        # email_address filter accepts wildcards, so we KEEP only the exact
        # `email_address == address` row (contract §4 rule 9 — never trust
        # the provider filter for a lookup). Returns the RAW SMTP2GO reason
        # (manual|spam|bounce|unsubscribe), NOT the REASON_MAP'd form —
        # REASON_MAP is for the local ingest path; the lookup surfaces the
        # provider's own vocabulary. Errors propagate to the op's fail-soft
        # rescue.
        def lookup(address)
          address  = address.to_s
          response = client.post('/suppression/view', { 'email_address' => address })
          match    = nil
          each_entry(response) do |entry|
            next unless fetch_field(entry, 'email_address').to_s == address

            match = entry
            break
          end

          if match
            {
              suppressed: true,
              reason: fetch_field(match, 'reason')&.to_s,
              last_update_time: parse_time(fetch_field(match, 'timestamp')),
            }
          else
            { suppressed: false, reason: nil, last_update_time: nil }
          end
        end

        # Current-cycle account summary via POST /stats/email_summary: quota
        # usage plus bounce/spam/unsubscribe counts and percentages. The
        # numbers are provider-computed over the CURRENT BILLING CYCLE — the
        # endpoint takes no date-range parameter, so there is no fixed-window
        # variant. `*_percent` fields preserve nil (not reported) vs 0.0
        # (reported zero) so the op can render "not reported" honestly.
        # Errors propagate to the op's fail-soft rescue.
        def stats
          data = client.post('/stats/email_summary', {})
          {
            cycle_start: fetch_field(data, 'cycle_start')&.to_s,
            cycle_end: fetch_field(data, 'cycle_end')&.to_s,
            cycle_used: fetch_field(data, 'cycle_used').to_i,
            cycle_remaining: fetch_field(data, 'cycle_remaining').to_i,
            cycle_max: fetch_field(data, 'cycle_max').to_i,
            email_count: fetch_field(data, 'email_count').to_i,
            bounce_rejects: fetch_field(data, 'bounce_rejects').to_i,
            softbounces: fetch_field(data, 'softbounces').to_i,
            hardbounces: fetch_field(data, 'hardbounces').to_i,
            spam_rejects: fetch_field(data, 'spam_rejects').to_i,
            unsubscribes: fetch_field(data, 'unsubscribes').to_i,
            bounce_percent: float_or_nil(fetch_field(data, 'bounce_percent')),
            spam_percent: float_or_nil(fetch_field(data, 'spam_percent')),
          }
        end

        private

        # Row timestamps are ISO8601 strings ("2021-04-30T00:00:00"); the
        # wire wants Unix seconds (the colonel lookup schema transforms from
        # number). nil on missing/unparseable — never a raise (mirrors the
        # Lettermint fetcher's parse_time).
        def parse_time(value)
          return nil if value.nil?
          return value.to_i if value.is_a?(Numeric)

          require 'time'
          Time.parse(value.to_s).to_i
        rescue StandardError
          nil
        end

        # nil when the provider omitted the metric, Float otherwise — the
        # distinction feeds the "not reported" rendering (same convention as
        # the Lettermint fetcher's metric_or_nil).
        def float_or_nil(value)
          value.nil? ? nil : value.to_f
        end

        # True only for entries that look like a concrete address
        # (local-part@domain). Domain suppressions arrive as "@example.com" —
        # an '@' with nothing before it — and are skipped.
        def address_level?(value)
          index = value.to_s.index('@')
          !index.nil? && index.positive?
        end

        # Rows array from the unwrapped response envelope: Smtp2goClient#post
        # returns the `data` hash, whose rows live under 'suppressions'.
        # Tolerates a bare array for defensiveness.
        def each_entry(response, &)
          rows = if response.is_a?(Hash)
            response['suppressions'] || response[:suppressions] || []
          else
            Array(response)
          end
          Array(rows).each(&)
        end

        def fetch_field(hash, name)
          return nil unless hash.is_a?(Hash)

          hash[name] || hash[name.to_sym]
        end

        def client
          @client ||= begin
            api_key = config['api_key']
            if api_key.nil? || api_key.to_s.strip.empty?
              raise ArgumentError,
                'SMTP2GO API key required to read the suppression list ' \
                '(set emailer.smtp2go_api_key / SMTP2GO_API_KEY)'
            end

            Smtp2goClient.new(
              api_key: api_key,
              base_url: config['base_url'],
              read_timeout: config['timeout'] || 30,
            )
          end
        end
      end
    end
  end
end

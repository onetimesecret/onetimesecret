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

        private

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

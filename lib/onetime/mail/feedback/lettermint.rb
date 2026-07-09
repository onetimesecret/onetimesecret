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

            cursor = next_cursor(response)
            rounds += 1
            break if records.size >= limit
            break if cursor.nil? || cursor.to_s.empty?
            break if rounds >= MAX_ROUNDS
          end

          records.first(limit)
        end

        private

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
        def each_entry(response, &block)
          rows = if response.is_a?(Hash)
            response['data'] || response[:data] || []
          else
            Array(response)
          end
          Array(rows).each(&block)
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

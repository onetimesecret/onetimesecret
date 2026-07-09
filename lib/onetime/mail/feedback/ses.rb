# lib/onetime/mail/feedback/ses.rb
#
# frozen_string_literal: true

require_relative 'base'

module Onetime
  module Mail
    module Feedback
      # AWS SES v2 deliverability feedback fetcher.
      #
      # Reads the SES *account-level suppression list* — the addresses SES has
      # itself stopped sending to because they hard-bounced or filed a spam
      # complaint — via `ListSuppressedDestinations`. This is the API-native
      # receiving side of SES: bounce/complaint notifications also flow over SNS,
      # but the suppression list is the durable, pollable record and needs no
      # inbound webhook endpoint (which would be a suppression-injection vector —
      # see IngestFeedback). We import it as suppressions, preserving the
      # BOUNCE/COMPLAINT reason.
      #
      # Configuration (from Mailer.provider_credentials('ses')):
      #   region, access_key_id, secret_access_key
      class SES < Base
        # SES suppression reasons -> our suppression reasons.
        REASON_MAP = { 'BOUNCE' => 'bounce', 'COMPLAINT' => 'complaint' }.freeze

        # Reasons we request from SES (both authoritative "stop mailing" signals).
        REASONS = %w[BOUNCE COMPLAINT].freeze

        # SES caps page_size at 1000; 100 keeps each round-trip small.
        PAGE_SIZE = 100

        DEFAULT_REGION = 'us-east-1'

        def fetch(limit: MAX_FETCH)
          limit     = clamp_limit(limit)
          records   = []
          next_token = nil
          rounds     = 0

          loop do
            response = client.list_suppressed_destinations(
              reasons: REASONS,
              page_size: PAGE_SIZE,
              next_token: next_token,
            )

            Array(response.suppressed_destination_summaries).each do |summary|
              records << suppression_record(
                email: summary.email_address,
                reason: REASON_MAP[summary.reason.to_s] || 'manual',
                source: 'ses',
              )
              break if records.size >= limit
            end

            next_token = response.next_token
            rounds += 1
            break if records.size >= limit
            break if next_token.nil? || next_token.empty?
            break if rounds >= MAX_ROUNDS
          end

          records.first(limit)
        end

        private

        def client
          @client ||= begin
            require 'aws-sdk-sesv2'

            Aws::SESV2::Client.new(
              region: config['region'] || ENV['AWS_REGION'] || DEFAULT_REGION,
              credentials: Aws::Credentials.new(
                config['access_key_id'] || ENV.fetch('AWS_ACCESS_KEY_ID', nil),
                config['secret_access_key'] || ENV.fetch('AWS_SECRET_ACCESS_KEY', nil),
              ),
            )
          end
        end
      end
    end
  end
end

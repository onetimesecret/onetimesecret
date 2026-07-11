# lib/onetime/mail/feedback/base.rb
#
# frozen_string_literal: true

module Onetime
  module Mail
    # Deliverability feedback fetchers — the PULL counterpart of the delivery
    # backends. A delivery backend (Onetime::Mail::Delivery::*) sends mail to a
    # provider; a feedback fetcher reads back what the provider recorded about
    # that mail — the addresses it suppressed for hard bounces and spam
    # complaints.
    #
    # Both AWS SES and Lettermint expose the receiving side as a pollable
    # *suppression list* (not an event stream), so a fetcher walks that list and
    # normalizes each entry into the record shape
    # {Onetime::Operations::Email::IngestFeedback} consumes:
    #
    #   { 'email' => 'a@example.com', 'kind' => 'suppression',
    #     'reason' => 'bounce' | 'complaint' | 'manual', 'source' => 'ses' }
    #
    # Fetchers are read-only and provider-specific; the orchestration (which
    # provider, credentials, feeding the records into IngestFeedback, the one
    # audit event) lives in {Onetime::Operations::Email::SyncProviderFeedback},
    # which a CLI/cron relay drives. Keeping the provider I/O here mirrors the
    # delivery/ layout and keeps the op provider-agnostic.
    module Feedback
      # Abstract base for a provider feedback fetcher.
      class Base
        # Upper bound on records returned by a single fetch, so one sync run can
        # never pull an unbounded provider list into memory. A provider list far
        # past this is a signal to sync more often, not to fetch more per run.
        MAX_FETCH = 5_000

        # Guard against a provider paginator that never terminates (a missing or
        # malformed next-cursor): stop after this many page round-trips.
        MAX_ROUNDS = 200

        # @param config [Hash] provider credentials (string keys), as returned by
        #   Onetime::Mail::Mailer.provider_credentials(<provider>).
        def initialize(config = {})
          @config = config || {}
        end

        # Fetch the provider's suppression list as normalized ingest records.
        # @param limit [Integer] cap on records returned (clamped to MAX_FETCH).
        # @return [Array<Hash>] normalized records (string keys), newest source
        #   order is not guaranteed.
        def fetch(limit: MAX_FETCH)
          raise NotImplementedError, "#{self.class} must implement #fetch"
        end

        protected

        attr_reader :config

        # Build one normalized suppression-import record. `kind` is always
        # 'suppression' (import-only, no feed event); `reason` carries the
        # provider's bounce/complaint distinction so it survives the import.
        def suppression_record(email:, reason:, source:)
          {
            'email' => email.to_s,
            'kind' => 'suppression',
            'reason' => reason.to_s,
            'source' => source.to_s,
          }
        end

        # Clamp a requested limit to a positive value no larger than MAX_FETCH.
        def clamp_limit(limit)
          limit = limit.to_i
          return MAX_FETCH if limit <= 0

          [limit, MAX_FETCH].min
        end
      end
    end
  end
end

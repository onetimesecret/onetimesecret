# lib/onetime/operations/email/sync_provider_feedback.rb
#
# frozen_string_literal: true

# Central (cross-cutting) admin operation — see decision D3 in
# lib/onetime/operations/README.md. Like IngestFeedback and SendTest, provider
# feedback sync is mailer-wide infrastructure, so it lives in the central
# operations home. Dependencies are required at the call site.
require 'onetime/operations/email/ingest_feedback'
require 'onetime/mail/feedback/ses'
require 'onetime/mail/feedback/lettermint'

module Onetime
  module Operations
    module Email
      # Pull a provider's deliverability suppression list and ingest it — the
      # concrete wiring of "get ESP feedback into our suppression list" for the
      # two API-based providers (AWS SES, Lettermint).
      #
      # ## Why this exists
      #
      # {IngestFeedback} is the passive receiver: an operator relay POSTs
      # normalized records to it. This op is the ACTIVE relay for the two
      # providers whose feedback is a pollable API list — it selects the right
      # {Onetime::Mail::Feedback} fetcher, walks the provider's suppression list,
      # and feeds the normalized records straight into IngestFeedback in-process
      # (no HTTP hop, no colonel session — this runs as trusted server code,
      # driven by `bin/ots email sync-feedback` on a cron). IngestFeedback stays
      # the single, audited implementation; this and the colonel HTTP endpoint
      # are both thin adapters over it.
      #
      # ## Idempotence
      #
      # Fetchers emit `kind: 'suppression'` records (import-only, no feed event),
      # so re-syncing an unchanged provider list re-writes the same suppression
      # entries and records nothing new in the bounce/complaint feed — a cron can
      # run it as often as it likes.
      class SyncProviderFeedback
        # Providers with a pollable feedback API (a fetcher under
        # Onetime::Mail::Feedback). Other transports (SMTP, sendgrid, logger,
        # disabled) have no pull API and are rejected.
        PROVIDERS = %w[ses lettermint].freeze

        # Audit actor sentinel for the CLI/cron sync path (matches the send-test
        # CLI convention). The one AdminAuditEvent IngestFeedback records per
        # accepting batch is attributed to this.
        CLI_ACTOR = 'cli'

        # @!attribute provider [r] @return [String] provider synced
        # @!attribute fetched  [r] @return [Integer] records pulled from provider
        # @!attribute accepted [r] @return [Integer] records ingested
        # @!attribute rejected [r] @return [Integer] records refused by ingest
        # @!attribute errors   [r] @return [Array<String>] first ingest errors
        # @!attribute dry_run  [r] @return [Boolean] true when nothing ingested
        Result = Data.define(:provider, :fetched, :accepted, :rejected, :errors, :dry_run)

        # @param provider [String, nil] 'ses' or 'lettermint'. Defaults to the
        #   configured delivery provider (Mailer.determine_provider) so a
        #   single-provider install needs no flag.
        # @param actor [String, #extid, #email] audit actor (default: CLI sentinel).
        # @param limit [Integer, nil] cap on records pulled this run.
        # @param dry_run [Boolean] fetch and count but do not ingest (no writes,
        #   no audit event).
        def initialize(provider: nil, actor: CLI_ACTOR, limit: nil, dry_run: false)
          @provider = (provider || default_provider).to_s.downcase.strip
          @actor    = actor
          @limit    = limit
          @dry_run  = dry_run
        end

        # @return [Result]
        def call
          unless PROVIDERS.include?(@provider)
            raise ArgumentError,
              "no feedback API for provider '#{@provider}' (supported: #{PROVIDERS.join(', ')})"
          end

          records = @limit ? fetcher.fetch(limit: @limit) : fetcher.fetch

          if @dry_run || records.empty?
            return Result.new(
              provider: @provider, fetched: records.size,
              accepted: 0, rejected: 0, errors: [], dry_run: @dry_run
            )
          end

          ingest = IngestFeedback.new(
            records: records, actor: @actor, default_source: @provider
          ).call

          Result.new(
            provider: @provider,
            fetched: records.size,
            accepted: ingest.accepted,
            rejected: ingest.rejected,
            errors: ingest.errors,
            dry_run: false,
          )
        end

        private

        def fetcher
          @fetcher ||= case @provider
                       when 'ses'
                         Onetime::Mail::Feedback::SES.new(provider_credentials('ses'))
                       when 'lettermint'
                         Onetime::Mail::Feedback::Lettermint.new(provider_credentials('lettermint'))
                       end
        end

        def provider_credentials(provider)
          Onetime::Mail::Mailer.provider_credentials(provider)
        end

        def default_provider
          Onetime::Mail::Mailer.determine_provider
        rescue StandardError
          nil
        end
      end
    end
  end
end

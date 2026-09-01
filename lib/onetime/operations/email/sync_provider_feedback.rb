# lib/onetime/operations/email/sync_provider_feedback.rb
#
# frozen_string_literal: true

# Central (cross-cutting) admin operation — see decision D3 in
# lib/onetime/operations/README.md. Like IngestFeedback and SendTest, provider
# feedback sync is mailer-wide infrastructure, so it lives in the central
# operations home. Dependencies are required at the call site.
require 'onetime/operations/email/ingest_feedback'
require 'onetime/models/colonel_audit_event'
require 'onetime/models/email_suppression'
require 'onetime/mail/provider_registry'
require 'onetime/mail/feedback/ses'
require 'onetime/mail/feedback/lettermint'
require 'onetime/mail/feedback/smtp2go'

module Onetime
  module Operations
    module Email
      # Pull a provider's deliverability suppression list and ingest it — the
      # concrete wiring of "get ESP feedback into our suppression list" for the
      # API-based providers (AWS SES, Lettermint, SMTP2GO).
      #
      # ## Why this exists
      #
      # {IngestFeedback} is the passive receiver: an operator relay POSTs
      # normalized records to it. This op is the ACTIVE relay for the
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
      #
      # ## sync_status and the audit events (#4336)
      #
      # Every real (non-dry-run) call — including one where the provider list is
      # empty or unchanged — stamps `EmailSuppression.sync_status[provider]`, so
      # the deliverability summary's "never synced" banner reflects whether a
      # sync ever RAN, not whether it ever imported something.
      #
      # This op used to lean on that stamp alone and audit only TRANSITIVELY,
      # through {IngestFeedback}'s one-event-per-accepting-batch rule, on the
      # reading that CONTRACT 4 audits state changes rather than no-ops. That
      # reading was wrong for THIS op: stamping sync_status IS a state change —
      # it moves the console out of its "never synced" state — and it happens on
      # every real run, including the ones that accept nothing. So a colonel
      # could clear the never-synced banner, or run the pull repeatedly against
      # a third-party provider, with no record that anyone had done anything.
      #
      # There are now TWO events, at different layers and neither redundant:
      #
      #   1. `email.deliverability_sync` (this op, {AUDIT_VERB}) — ONE per real
      #      run, unconditionally, carrying the run's tallies. Answers "who ran
      #      a sync, against which provider, and what did it move."
      #   2. `email.deliverability_ingest` ({IngestFeedback}) — ONE per batch
      #      that accepted at least one record, from every ingest path (this op,
      #      the colonel POST endpoint, the relay). Answers "what entered the
      #      suppression list." That invariant is unchanged: a run that accepts
      #      nothing still writes exactly one event here and none there.
      #
      # `dry_run` continues to skip the sync_status write entirely (it makes no
      # claim about the local suppression list) and ingests nothing, so it
      # writes neither event.
      class SyncProviderFeedback
        # Providers with a pollable feedback API (a fetcher under
        # Onetime::Mail::Feedback). Other transports (SMTP, sendgrid, logger,
        # disabled) have no pull API and are rejected.
        # Derived from Mail::ProviderRegistry (descriptor.feedback).
        PROVIDERS = Onetime::Mail::ProviderRegistry.feedback_providers.freeze

        # Audit actor sentinel for the CLI/cron sync path (matches the send-test
        # CLI convention). Both this op's per-run event and the one
        # IngestFeedback records per accepting batch are attributed to this when
        # no operator drove the run.
        CLI_ACTOR = 'cli'

        # Audit verb recorded once per real (non-dry-run) run. Owned here rather
        # than by the colonel endpoint because BOTH drivers — the endpoint and
        # `bin/ots email sync-feedback` on a cron — reach the provider through
        # this op, and the event must read the same either way.
        AUDIT_VERB = 'email.deliverability_sync'

        # Fixed audit target. A sync has no single public id, and the provider
        # is data about the run rather than the thing acted on — the thing acted
        # on is the suppression list, so this mirrors the sentinel
        # {IngestFeedback} already uses for the same store.
        AUDIT_TARGET = 'email_suppression'

        # @!attribute provider [r] @return [String] provider synced
        # @!attribute fetched  [r] @return [Integer] records pulled from provider
        # @!attribute accepted [r] @return [Integer] records ingested
        # @!attribute rejected [r] @return [Integer] records refused by ingest
        # @!attribute errors   [r] @return [Array<String>] first ingest errors
        # @!attribute dry_run  [r] @return [Boolean] true when nothing ingested
        Result = Data.define(:provider, :fetched, :accepted, :rejected, :errors, :dry_run)

        # @param provider [String, nil] 'ses', 'lettermint' or 'smtp2go'.
        #   Defaults to the configured delivery provider
        #   (Mailer.determine_provider) so a single-provider install needs no
        #   flag.
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
          result = perform
          record_sync_event(result)
          result
        end

        private

        # The pull/ingest work. Split from {#call} so the audit write has ONE
        # place to sit: the three exits below (dry run, empty list, ingested
        # batch) all converge here, which is what makes "exactly one event per
        # run" structural rather than a rule three branches have to remember.
        def perform
          unless PROVIDERS.include?(@provider)
            raise ArgumentError,
              "no feedback API for provider '#{@provider}' (supported: #{PROVIDERS.join(', ')})"
          end

          records = @limit ? fetcher.fetch(limit: @limit) : fetcher.fetch

          if @dry_run
            return Result.new(
              provider: @provider,
              fetched: records.size,
              accepted: 0,
              rejected: 0,
              errors: [],
              dry_run: true,
            )
          end

          if records.empty?
            mark_synced!(imported: 0)
            return Result.new(
              provider: @provider,
              fetched: 0,
              accepted: 0,
              rejected: 0,
              errors: [],
              dry_run: false,
            )
          end

          ingest = IngestFeedback.new(
            records: records, actor: @actor, default_source: @provider,
          ).call

          mark_synced!(imported: ingest.accepted)

          Result.new(
            provider: @provider,
            fetched: records.size,
            accepted: ingest.accepted,
            rejected: ingest.rejected,
            errors: ingest.errors,
            dry_run: false,
          )
        end

        # One audit event per real run (#4336) — see the class docs. Skipped for
        # a dry run, which stamps nothing and ingests nothing.
        #
        # NOT fail-closed: a sync destroys nothing (it only ever ADDS
        # suppressions), so per the model's fail-closed contract this stays in
        # the additive family and must not trade a working sync for a hard
        # failure.
        def record_sync_event(result)
          return if result.dry_run

          Onetime::ColonelAuditEvent.record(
            actor: @actor,
            verb: AUDIT_VERB,
            target: AUDIT_TARGET,
            result: :success,
            detail: sync_detail(result),
          )
        end

        # The run's tallies. `skipped` is the fetched-but-not-ingested
        # remainder (rejected records plus anything the ingest silently
        # dropped), so fetched == accepted + skipped always holds and a reader
        # never has to reconcile three counters by hand.
        def sync_detail(result)
          {
            provider: result.provider,
            fetched: result.fetched,
            accepted: result.accepted,
            rejected: result.rejected,
            skipped: result.fetched - result.accepted,
            sync_status_stamped: !result.dry_run,
          }
        end

        # Stamp the per-provider last-sync marker. Called on every real run
        # (imported may be 0) — never on dry_run. String keys at the Redis
        # boundary.
        def mark_synced!(imported:)
          Onetime::EmailSuppression.sync_status[@provider] = {
            'last_synced_at' => Familia.now,
            'imported' => imported,
            'result' => 'ok',
          }
        end

        def fetcher
          @fetcher ||= case @provider
                       when 'ses'
                         Onetime::Mail::Feedback::SES.new(provider_credentials('ses'))
                       when 'lettermint'
                         Onetime::Mail::Feedback::Lettermint.new(provider_credentials('lettermint'))
                       when 'smtp2go'
                         Onetime::Mail::Feedback::Smtp2go.new(provider_credentials('smtp2go'))
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

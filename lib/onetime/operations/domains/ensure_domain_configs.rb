# lib/onetime/operations/domains/ensure_domain_configs.rb
#
# frozen_string_literal: true

# Domain-owned (app-scoped) operation — see decision D3 in
# lib/onetime/operations/README.md. Loaded at the call site (colonel logic),
# so require the audit model explicitly.
require 'onetime/models/colonel_audit_event'
require 'onetime/audited_failure'
require 'onetime/models/custom_domain/config_registry'

module Onetime
  module Operations
    module Domains
      # Materialize the missing per-domain config records among the five
      # materializable kinds (signin/signup/homepage/api/incoming) with model
      # defaults — everything disabled, so creation is behavior-neutral
      # (resolvers gate on `config&.enabled?`, and absent ==
      # present-but-disabled for these kinds). The single implementation behind
      # `POST /api/colonel/domains/:extid/configs/ensure`, the admin-visible
      # fix for the v0.26.2 outage class (config records absent for
      # pre-existing domains fail closed with no way to see or repair it).
      #
      # sso/mailer are NEVER materialized: their models enforce
      # credentials/from_address on create and their absent state means "fall
      # back to platform" — they are reported in `skipped` with a reason.
      #
      # ## Dry-run + exactly-once audit (CONTRACT 4)
      #
      # `dry_run: true` (the safe default) reports the plan — `created` lists
      # the kinds that WOULD be created — and mutates/audits NOTHING.
      # `dry_run: false` creates the missing records race-safely
      # (HomepageConfig/ApiConfig via find_or_create_for_domain; the rest via
      # exists-check + create! with a duplicate-race rescue) and records
      # EXACTLY ONE {Onetime::ColonelAuditEvent} — none when nothing was created.
      class EnsureDomainConfigs
        include Onetime::AuditedFailure

        # Audit verb recorded when an applied run created at least one record.
        AUDIT_VERB = 'domain.configs_ensure'

        # This op has NO refusal STATUS — `:planned` and `:applied` are the only
        # two, and every failure RAISES (contract drift in `materialize`, or a
        # create! that failed for a reason other than the duplicate race). The
        # loop creates records one kind at a time and the success record runs
        # only at the end, so a raise on the fourth of six leaves three created
        # records and no trail. Records one `result: :failure` and re-raises.
        #
        # `dry_run` is in the detail because it defaults to TRUE and the success
        # event is applied-path-only.
        audit_failures :call,
          verb: AUDIT_VERB,
          target: -> { @domain&.extid },
          detail: -> { { dry_run: @dry_run } }

        # @!attribute status [r] Symbol — :planned (dry-run), :applied
        # @!attribute created [r] Array<String> — kinds created (or planned, on dry-run)
        # @!attribute existing [r] Array<String> — kinds that already had records
        # @!attribute skipped [r] Array<Hash> — [{kind:, reason:}, ...] (sso/mailer)
        Result = Data.define(:status, :dry_run, :created, :existing, :skipped)

        # @param domain [Onetime::CustomDomain] target domain (caller ensures non-nil).
        # @param actor [String, #extid, #email] acting admin's PUBLIC identity.
        # @param dry_run [Boolean] preview only when true (default). Applies when false.
        def initialize(domain:, actor:, dry_run: true)
          @domain  = domain
          @actor   = actor
          @dry_run = dry_run
        end

        # @return [Result]
        def call
          registry  = Onetime::CustomDomain::ConfigRegistry
          domain_id = @domain.identifier
          skipped   = registry.credential_required_skips

          created  = []
          existing = []

          registry.materializable_slugs.each do |slug|
            model = registry.model_for(slug)

            if model.exists_for_domain?(domain_id)
              existing << slug
              next
            end

            if @dry_run
              # Plan only — no mutation, and nothing on the OPERATOR trail.
              # The run's single OBSERVATION is recorded once below, not per
              # slug.
              created << slug
              next
            end

            case (outcome = materialize(model, domain_id))
            when :created then created << slug
            when :existed then existing << slug
            else
              # Contract drift in materialize / find_or_create_for_domain
              # (e.g. a renamed outcome symbol) — fail loudly rather than
              # silently miscounting the kind.
              raise Onetime::Problem, "Unexpected materialize outcome #{outcome.inspect} for #{slug}"
            end
          end

          if @dry_run
            # ONE observation per run (#4337), not one per slug — a preview is
            # a single operator action however many configs it enumerates.
            record_preview_event(created, existing, skipped)
            return Result.new(status: :planned, dry_run: true, created: created, existing: existing, skipped: skipped)
          end

          # Exactly one audit event per applied run that created something;
          # none when every record already existed.
          if created.any?
            Onetime::ColonelAuditEvent.record(
              actor: @actor,
              verb: AUDIT_VERB,
              target: @domain.extid,
              result: :success,
              detail: { created: created },
            )
          end

          Result.new(status: :applied, dry_run: false, created: created, existing: existing, skipped: skipped)
        end

        private

        # One OBSERVATION per dry run (#4337), on the budgeted access trail.
        # Same verb and target as the applied event; `result: 'preview'` and
        # `dry_run: true` distinguish them. Counts rather than the applied
        # event's `created` list, because on a preview that list is what WOULD
        # be created — a projection, not a fact.
        def record_preview_event(created, existing, skipped)
          Onetime::ColonelAuditEvent.record_access(
            actor: @actor,
            verb: AUDIT_VERB,
            target: @domain.extid,
            result: 'preview',
            detail: {
              dry_run: true,
              would_create: created.size,
              existing: existing.size,
              skipped: skipped.size,
            },
          )
        end

        # Race-safe creation with model defaults (everything disabled).
        # HomepageConfig/ApiConfig provide WATCH-backed find_or_create_for_domain;
        # the others use create! with a duplicate-race rescue → re-check.
        #
        # @return [Symbol] :created | :existed
        def materialize(model, domain_id)
          if model.respond_to?(:find_or_create_for_domain)
            _config, outcome = model.find_or_create_for_domain(domain_id: domain_id, enabled: false)
            outcome
          else
            begin
              model.create!(domain_id: domain_id)
              :created
            rescue Onetime::Problem
              # Duplicate-create race — a concurrent writer won. Anything else
              # (record still absent) is a real failure: re-raise.
              raise unless model.exists_for_domain?(domain_id)

              :existed
            end
          end
        end
      end
    end
  end
end

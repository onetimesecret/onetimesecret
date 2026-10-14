# lib/onetime/operations/domains/upsert_domain_config.rb
#
# frozen_string_literal: true

# Domain-owned (app-scoped) operation — see decision D3 in
# lib/onetime/operations/README.md. Lives alongside the incumbent domain ops in
# lib/onetime/operations, under the Domains:: namespace. Loaded at the call site
# (colonel logic), so require the audit model explicitly.
require 'onetime/models/colonel_audit_event'
require 'onetime/audited_failure'
require 'onetime/models/custom_domain/config_registry'

module Onetime
  module Operations
    module Domains
      # Upsert (create-if-missing, else partial-update) ONE editable per-domain
      # config record — the single implementation behind
      # `PUT /api/colonel/domains/:extid/configs/:kind` (v0.26.2 outage class:
      # absent config records fail closed with no admin-visible fix).
      #
      # The caller (colonel logic adapter) is responsible for kind validation
      # (editable kinds only — never sso/mailer) and for coercing `attrs` via
      # {Onetime::CustomDomain::ConfigRegistry.coerce_field!}; this op applies
      # them with the correct storage encoding and records EXACTLY ONE
      # {Onetime::ColonelAuditEvent} per successful mutation (CONTRACT 4). The
      # audit detail carries field NAMES only, never values (recipients /
      # allowlists are semi-sensitive).
      #
      # Create path: model defaults + provided fields (`Model.create!`). A
      # duplicate-create race falls back to the update path. Update path:
      # only the provided fields are applied; `updated` is bumped.
      #
      # Both paths refuse a write that adds a validation error the record did
      # not already have (the model's #validation_errors, e.g. SignupConfig's
      # allowlist requirement), raising {InvalidConfig} before anything is
      # saved. Errors the record already had do not count, so a record that is
      # already invalid can still be disabled or repaired one field at a time.
      class UpsertDomainConfig
        include Onetime::AuditedFailure

        # A write that would add a validation error. The message lists the
        # added errors (model text, no values beyond what the model prints).
        class InvalidConfig < Onetime::Problem
          attr_reader :added_errors

          def initialize(added_errors)
            @added_errors = Array(added_errors)
            super("This change would leave the config invalid: #{@added_errors.join('; ')}")
          end
        end

        # Audit verb recorded for every applied upsert.
        AUDIT_VERB = 'domain.config_upsert'

        # This op has NO refusal STATUS — every non-success outcome RAISES
        # (model validation, a lost race whose record then vanished, a datastore
        # failure), and every one of those raises happens after `apply_update`
        # may already have written setters, so the success record never runs.
        # Records one `result: :failure` and re-raises.
        #
        # Field NAMES only in the detail, never values — same rule as the
        # success event (recipients / allowlists are semi-sensitive).
        audit_failures :call,
          verb: AUDIT_VERB,
          target: -> { @domain&.extid },
          detail: -> { { config: @kind, changed: @attrs.keys } }

        # The config models' create! signals a lost duplicate-create race by
        # raising Onetime::Problem from its exists-guard — the FIRST check,
        # before any attribute validation — with this message shape
        # ('<Kind> config already exists for this domain'). No distinct error
        # class exists, and model VALIDATION failures raise the same class
        # (e.g. allowed_signup_domains PublicSuffix rejection), so the race
        # rescue matches the guard message: a validation failure must never
        # be re-applied to a raced record it did not come from.
        ALREADY_EXISTS_MESSAGE = /already exists for this domain\z/

        # @!attribute status [r] Symbol — :created | :updated
        # @!attribute config [r] the persisted config record
        # @!attribute changed [r] Array<String> — applied field NAMES
        Result = Data.define(:status, :kind, :config, :changed)

        # @param domain [Onetime::CustomDomain] target domain (caller ensures non-nil).
        # @param kind [String] editable config kind slug (caller validates).
        # @param attrs [Hash{String => Object}] coerced writable fields
        #   (ConfigRegistry.coerce_field! output; may be empty).
        # @param actor [String, #extid, #email] acting admin's PUBLIC identity.
        def initialize(domain:, kind:, attrs:, actor:)
          @domain = domain
          @kind   = kind.to_s
          @attrs  = attrs
          @actor  = actor
        end

        # @return [Result]
        # @raise [Onetime::Problem] on model-level validation failure
        #   (e.g. allowed_signup_domains PublicSuffix rejection)
        # @raise [InvalidConfig] when the attrs would add a validation error
        def call
          model     = registry.model_for(@kind)
          domain_id = @domain.identifier

          existing = model.find_by_domain_id(domain_id)
          if existing
            status = :updated
            config = apply_update(existing)
          else
            # Checked on an unsaved instance first: create! saves as it goes.
            refuse_invalid_create!(model, domain_id)
            begin
              status = :created
              config = model.create!(domain_id: domain_id, **@attrs.transform_keys(&:to_sym))
            rescue Onetime::Problem => ex
              # Duplicate-create race ONLY: a concurrent writer created the
              # record between our read and create!'s exists-guard. Any other
              # Onetime::Problem is a real validation failure and propagates
              # unchanged (422 form error at the logic layer) — taking the
              # race path for it would re-apply invalid input to a concurrent
              # writer's valid record.
              raise unless ex.message.match?(ALREADY_EXISTS_MESSAGE)

              raced = model.find_by_domain_id(domain_id)
              raise unless raced

              status = :updated
              config = apply_update(raced)
            end
          end

          # Exactly one audit event per successful mutation. Field names only.
          Onetime::ColonelAuditEvent.record(
            actor: @actor,
            verb: AUDIT_VERB,
            target: @domain.extid,
            result: :success,
            detail: { config: @kind, outcome: status.to_s, changed: @attrs.keys },
          )

          Result.new(status: status, kind: @kind, config: config, changed: @attrs.keys)
        end

        private

        def registry
          Onetime::CustomDomain::ConfigRegistry
        end

        # Partial update: only provided fields are applied (storage-encoded by
        # the registry), then `updated` is bumped. Setter failures and
        # refuse_added_errors! raise BEFORE save, so no partial state persists.
        def apply_update(config)
          before = config.validation_errors
          apply_attrs(config)
          refuse_added_errors!(config, before)

          config.created ||= Familia.now.to_i # repair missing created from legacy records
          config.updated   = Familia.now.to_i
          config.save
          config
        end

        # The create path's check: apply the attrs to an unsaved instance
        # carrying the model's defaults and refuse any error they add.
        def refuse_invalid_create!(model, domain_id)
          probe  = model.new(domain_id: domain_id)
          before = probe.validation_errors
          apply_attrs(probe)
          refuse_added_errors!(probe, before)
        end

        def apply_attrs(config)
          @attrs.each { |field, value| registry.apply_field(config, @kind, field, value) }
        end

        # @raise [InvalidConfig] when config reports an error not in before
        def refuse_added_errors!(config, before)
          added = config.validation_errors - before
          raise InvalidConfig, added unless added.empty?
        end
      end
    end
  end
end

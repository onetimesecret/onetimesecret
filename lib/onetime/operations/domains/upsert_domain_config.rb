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
      # only the provided fields are applied, on the record re-read under
      # WATCH (GuardedConfigWrites#update_for_domain!), so fields this call
      # does not name keep a concurrent writer's values; `updated` is bumped.
      class UpsertDomainConfig
        include Onetime::AuditedFailure

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
        def call
          model     = registry.model_for(@kind)
          domain_id = @domain.identifier

          if model.exists_for_domain?(domain_id)
            status = :updated
            config = apply_update(model, domain_id)
          else
            begin
              status = :created
              config = model.create!(domain_id: domain_id, **@attrs.transform_keys(&:to_sym))
            rescue Onetime::Models::Features::GuardedConfigWrites::ConfigExistsError
              # Duplicate-create race ONLY: a concurrent writer created the
              # record between our check and create!. A model VALIDATION
              # failure raises the parent class, Onetime::Problem, and
              # propagates unchanged (422 form error at the logic layer):
              # taking the race path for it would re-apply invalid input to
              # a concurrent writer's valid record.
              status = :updated
              config = apply_update(model, domain_id)
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
        # the registry), then `updated` is bumped. Setter failures raise BEFORE
        # the commit, so no partial state persists.
        #
        # @raise [Familia::KeyNotFoundError] deleted concurrently
        # @raise [Familia::OptimisticLockError] still changing after the retries
        def apply_update(model, domain_id)
          config, = model.update_for_domain!(domain_id) do |stored|
            @attrs.each { |field, value| registry.apply_field(stored, @kind, field, value) }
            stored.created ||= Familia.now.to_i # repair missing created from legacy records
            stored.updated   = Familia.now.to_i
          end
          config
        end
      end
    end
  end
end

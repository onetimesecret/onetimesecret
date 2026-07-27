# lib/onetime/operations/domains/upsert_domain_config.rb
#
# frozen_string_literal: true

# Domain-owned (app-scoped) operation — see decision D3 in
# lib/onetime/operations/README.md. Lives alongside the incumbent domain ops in
# lib/onetime/operations, under the Domains:: namespace. Loaded at the call site
# (colonel logic), so require the audit model explicitly.
require 'onetime/models/admin_audit_event'
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
      # {Onetime::AdminAuditEvent} per successful mutation (CONTRACT 4). The
      # audit detail carries field NAMES only, never values (recipients /
      # allowlists are semi-sensitive).
      #
      # Create path: model defaults + provided fields (`Model.create!`). A
      # duplicate-create race falls back to the update path. Update path:
      # only the provided fields are applied; `updated` is bumped.
      class UpsertDomainConfig
        # Audit verb recorded for every applied upsert.
        AUDIT_VERB = 'domain.config_upsert'

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

          existing = model.find_by_domain_id(domain_id)
          if existing
            status = :updated
            config = apply_update(existing)
          else
            begin
              status = :created
              config = model.create!(domain_id: domain_id, **@attrs.transform_keys(&:to_sym))
            rescue Onetime::Problem
              # Duplicate-create race: a concurrent writer created the record
              # between our read and create!. Re-read and apply as an update.
              # A real validation failure leaves no record — re-raise.
              raced = model.find_by_domain_id(domain_id)
              raise unless raced

              status = :updated
              config = apply_update(raced)
            end
          end

          # Exactly one audit event per successful mutation. Field names only.
          Onetime::AdminAuditEvent.record(
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
        # save, so no partial state persists.
        def apply_update(config)
          @attrs.each { |field, value| registry.apply_field(config, @kind, field, value) }
          config.created ||= Familia.now.to_i # repair missing created from legacy records
          config.updated   = Familia.now.to_i
          config.save
          config
        end
      end
    end
  end
end

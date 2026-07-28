# lib/onetime/operations/domains/delete_domain_config.rb
#
# frozen_string_literal: true

# Domain-owned (app-scoped) operation — see decision D3 in
# lib/onetime/operations/README.md. Loaded at the call site (colonel logic),
# so require the audit model explicitly.
require 'onetime/models/admin_audit_event'
require 'onetime/audited_failure'
require 'onetime/models/custom_domain/config_registry'

module Onetime
  module Operations
    module Domains
      # Delete ONE per-domain config record (any of the seven kinds) — the
      # single implementation behind
      # `DELETE /api/colonel/domains/:extid/configs/:kind`.
      #
      # Deleting is always allowed (including sso/mailer, which are otherwise
      # not colonel-editable): the absent state falls back to platform behavior
      # / fails closed, which is the documented recovery posture.
      #
      # Records EXACTLY ONE {Onetime::AdminAuditEvent} per successful delete
      # (CONTRACT 4). A delete of a non-existent record is `:not_found` and
      # records one `result: :failure` event, as does a raise out of
      # `delete_for_domain!` — the delete drops a config whose absence changes
      # runtime behaviour, so a failed attempt belongs in the trail.
      class DeleteDomainConfig
        include Onetime::AuditedFailure

        # Audit verb recorded for every applied delete.
        AUDIT_VERB = 'domain.config_delete'

        # A privileged mutation was asked for and REFUSED.
        REFUSAL_STATUSES = [:not_found].freeze

        # model_for / delete_for_domain! run BEFORE the success record: an
        # unknown kind or a datastore failure would otherwise leave a deletion
        # attempt untraced. Records one `result: :failure` and re-raises.
        audit_failures :call,
          verb: AUDIT_VERB,
          target: -> { @domain&.extid },
          detail: -> { { config: @kind } }

        # @!attribute status [r] Symbol — :deleted | :not_found
        Result = Data.define(:status, :kind)

        # @param domain [Onetime::CustomDomain] target domain (caller ensures non-nil).
        # @param kind [String] config kind slug (caller validates).
        # @param actor [String, #extid, #email] acting admin's PUBLIC identity.
        def initialize(domain:, kind:, actor:)
          @domain = domain
          @kind   = kind.to_s
          @actor  = actor
        end

        # @return [Result]
        def call
          model   = Onetime::CustomDomain::ConfigRegistry.model_for(@kind)
          deleted = model.delete_for_domain!(@domain.identifier)

          unless deleted
            record_refusal(:not_found)
            return Result.new(status: :not_found, kind: @kind)
          end

          # Exactly one audit event per successful delete. Kind only, no values.
          Onetime::AdminAuditEvent.record(
            actor: @actor,
            verb: AUDIT_VERB,
            target: @domain.extid,
            result: :success,
            detail: { config: @kind },
          )

          Result.new(status: :deleted, kind: @kind)
        end

        private

        # Same verb/target/actor as the success event. Best-effort: never break
        # the op.
        def record_refusal(status)
          Onetime::AdminAuditEvent.record(
            actor: @actor,
            verb: AUDIT_VERB,
            target: @domain.extid,
            result: :failure,
            detail: { reason: status.to_s, config: @kind },
          )
        rescue StandardError => ex
          OT.le "[Domains::DeleteDomainConfig] refusal audit failed: #{ex.class}: #{ex.message}"
        end
      end
    end
  end
end

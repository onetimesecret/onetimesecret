# apps/api/colonel/logic/colonel/delete_domain_config.rb
#
# frozen_string_literal: true

require_relative '../base'
require 'onetime/operations/domains/delete_domain_config'

module ColonelAPI
  module Logic
    module Colonel
      # Delete one per-domain config record (Colonel).
      #
      # @api DELETE /api/colonel/domains/:extid/configs/:kind — removes the
      #   record for ANY of the seven kinds (including the otherwise
      #   non-editable sso/mailer: absent falls back to platform behavior /
      #   fails closed, the documented recovery posture). 404 when the domain,
      #   the kind, or the record does not exist.
      #
      # Thin adapter over {Onetime::Operations::Domains::DeleteDomainConfig} —
      # the audited single implementation (CONTRACT 4: exactly one
      # AdminAuditEvent per successful delete, none on :not_found).
      #
      # Security invariant (epic #20): BOTH the router (role=colonel) AND this
      # logic (verify_one_of_roles!(colonel: true)) enforce the colonel role.
      class DeleteDomainConfig < ColonelAPI::Logic::Base
        SCHEMAS = { response: 'colonelDomainConfigDelete' }.freeze

        attr_reader :extid, :kind, :custom_domain, :result

        def process_params
          @extid = sanitize_identifier(params['extid'])
          @kind  = sanitize_identifier(params['kind']).to_s.downcase
        end

        def raise_concerns
          verify_one_of_roles!(colonel: true)

          raise_form_error('Domain ID is required', field: :extid) if extid.to_s.empty?

          @custom_domain = Onetime::CustomDomain.find_by_extid(extid)
          raise_not_found('Domain not found') unless custom_domain

          raise_not_found('Unknown config kind') unless Onetime::CustomDomain::ConfigRegistry.kind?(kind)
        end

        def process
          @result = Onetime::Operations::Domains::DeleteDomainConfig.new(
            domain: custom_domain,
            kind: kind,
            actor: cust.extid, # acting colonel's PUBLIC id (never an objid)
          ).call

          raise_not_found('Config not found') if result.status == :not_found

          OT.info "[DeleteDomainConfig] #{custom_domain.display_domain} kind=#{kind} deleted"

          success_data
        end

        def success_data
          {
            record: {
              domain_id: custom_domain.domainid,
              extid: custom_domain.extid,
              display_domain: custom_domain.display_domain,
            },
            details: {
              kind: kind,
              deleted: true,
            },
          }
        end
      end
    end
  end
end

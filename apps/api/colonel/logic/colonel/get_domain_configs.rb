# apps/api/colonel/logic/colonel/get_domain_configs.rb
#
# frozen_string_literal: true

require_relative '../base'

module ColonelAPI
  module Logic
    module Colonel
      # Get the seven per-domain config records for a custom domain (Colonel).
      #
      # @api Full read-out of the per-domain config surface
      #   (signin/signup/homepage/api/incoming/sso/mailer) for one domain,
      #   resolved globally by its PUBLIC id (extid). Backs the admin "Domain
      #   configuration" panel — the admin-visible answer to the v0.26.2 outage
      #   class, where absent config records fail closed (signin/signup/
      #   homepage/api/incoming OFF) with no way to see it.
      #
      # Every kind reports `{ exists:, config: }` — `config` is the redacting
      # {Onetime::CustomDomain::ConfigRegistry} serialization (real JSON
      # booleans, credential PRESENCE only — never client_id/client_secret/
      # api_key values) or null when absent.
      #
      # READ-ONLY: emits NO AdminAuditEvent (CONTRACT 4 — audit is for
      # mutations), matching GetCustomDomain / ProbeDomain.
      #
      # Security invariant (epic #20): BOTH the router (role=colonel) AND this
      # logic (verify_one_of_roles!(colonel: true)) enforce the colonel role.
      class GetDomainConfigs < ColonelAPI::Logic::Base
        SCHEMAS = { response: 'colonelDomainConfigs' }.freeze

        attr_reader :extid, :custom_domain

        def process_params
          @extid = sanitize_identifier(params['extid'])
        end

        def raise_concerns
          verify_one_of_roles!(colonel: true)

          raise_form_error('Domain ID is required', field: :extid) if extid.to_s.empty?

          @custom_domain = Onetime::CustomDomain.find_by_extid(extid)
          raise_not_found('Domain not found') unless custom_domain
        end

        def process
          success_data
        end

        def success_data
          { record: domain_record, details: { configs: configs_map } }
        end

        private

        def domain_record
          {
            domain_id: custom_domain.domainid,
            extid: custom_domain.extid,
            display_domain: custom_domain.display_domain,
          }
        end

        def configs_map
          registry = Onetime::CustomDomain::ConfigRegistry
          registry.slugs.each_with_object({}) do |slug, acc|
            config           = registry.model_for(slug).find_by_domain_id(custom_domain.identifier)
            acc[slug.to_sym] = {
              exists: !config.nil?,
              config: registry.serialize(slug, config),
            }
          end
        end
      end
    end
  end
end

# apps/api/colonel/logic/colonel/ensure_domain_configs.rb
#
# frozen_string_literal: true

require_relative '../base'
require 'onetime/operations/domains/ensure_domain_configs'

module ColonelAPI
  module Logic
    module Colonel
      # Ensure the materializable per-domain config records exist (Colonel).
      #
      # @api POST /api/colonel/domains/:extid/configs/ensure — creates any
      #   missing records among the five materializable kinds
      #   (signin/signup/homepage/api/incoming) with model defaults
      #   (everything disabled — behavior-neutral). The one-click repair for
      #   the v0.26.2 outage class. sso/mailer are always `skipped`
      #   (credentials/from_address required; absent = platform fallback).
      #
      # `dry_run` defaults to TRUE (D4 — dry-run default): the screen previews
      # the plan (`created` = kinds that WOULD be created), then re-POSTs with
      # `dry_run: false` behind a confirmation dialog to apply.
      #
      # Thin adapter over {Onetime::Operations::Domains::EnsureDomainConfigs} —
      # the audited single implementation (CONTRACT 4: exactly one
      # AdminAuditEvent per applied run that created something; none on
      # dry-run, none when nothing was missing).
      #
      # Security invariant (epic #20): BOTH the router (role=colonel) AND this
      # logic (verify_one_of_roles!(colonel: true)) enforce the colonel role.
      class EnsureDomainConfigs < ColonelAPI::Logic::Base
        SCHEMAS = { response: 'colonelDomainConfigsEnsure' }.freeze

        attr_reader :extid, :dry_run, :custom_domain, :result

        def process_params
          @extid   = sanitize_identifier(params['extid'])
          @dry_run = params.key?('dry_run') ? truthy?(params['dry_run']) : true
        end

        def raise_concerns
          verify_one_of_roles!(colonel: true)

          raise_form_error('Domain ID is required', field: :extid) if extid.to_s.empty?

          @custom_domain = Onetime::CustomDomain.find_by_extid(extid)
          raise_not_found('Domain not found') unless custom_domain
        end

        def process
          @result = Onetime::Operations::Domains::EnsureDomainConfigs.new(
            domain: custom_domain,
            actor: cust.extid, # acting colonel's PUBLIC id (never an objid)
            dry_run: dry_run,
          ).call

          OT.info "[EnsureDomainConfigs] #{custom_domain.display_domain} " \
                  "status=#{result.status}, dry_run=#{dry_run}, created=#{result.created.join(',')}"

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
              dry_run: result.dry_run,
              created: result.created,
              existing: result.existing,
              skipped: result.skipped,
            },
          }
        end

        private

        def truthy?(value)
          %w[true 1 yes on].include?(value.to_s.strip.downcase)
        end
      end
    end
  end
end

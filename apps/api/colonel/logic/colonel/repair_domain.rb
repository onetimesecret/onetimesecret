# apps/api/colonel/logic/colonel/repair_domain.rb
#
# frozen_string_literal: true

require_relative '../base'
require 'onetime/operations/domains/repair'

module ColonelAPI
  module Logic
    module Colonel
      # Repair a custom domain's organization relationship (Colonel) — surfaces the
      # CLI-only `bin/ots domains repair` toolbox (epic #43).
      #
      # Thin adapter over {Onetime::Operations::Domains::Repair} — the single,
      # audited implementation of the repair verb. The op owns the plan/apply logic
      # and the AdminAuditEvent (CONTRACT 4); this class resolves the domain + the
      # optional target org and threads the `dry_run` flag.
      #
      # `dry_run` defaults to TRUE (CONTRACT / D4 — dry-run default): the screen
      # previews the issues found, then re-POSTs with `dry_run: false` behind a
      # typed-confirmation dialog to apply. A dry-run preview mutates + audits
      # nothing.
      #
      # Security invariant (epic #20): BOTH the router (role=colonel) AND this
      # logic (verify_one_of_roles!(colonel: true)) enforce the colonel role.
      class RepairDomain < ColonelAPI::Logic::Base
        attr_reader :extid, :org_id, :dry_run, :custom_domain, :target_org, :result

        def process_params
          @extid  = sanitize_identifier(params['extid'])
          raise_form_error('Domain ID is required', field: :extid) if extid.to_s.empty?

          @org_id  = sanitize_identifier(params['org_id'])
          # Default to a safe dry-run unless the caller explicitly opts into applying.
          @dry_run = params.key?('dry_run') ? truthy?(params['dry_run']) : true
        end

        def raise_concerns
          verify_one_of_roles!(colonel: true)

          @custom_domain = Onetime::CustomDomain.find_by_extid(extid)
          raise_not_found('Domain not found') unless custom_domain

          # Resolve the optional target org for the ORPHANED case (by objid or extid).
          # The op ignores it when the domain already has an org_id.
          return if org_id.to_s.empty?

          @target_org = Onetime::Organization.load(org_id) ||
                        Onetime::Organization.find_by_extid(org_id)
          raise_form_error('Organization not found', field: :org_id) unless target_org
        end

        def process
          @result = Onetime::Operations::Domains::Repair.new(
            domain: custom_domain,
            org: target_org,
            actor: cust.extid, # acting colonel's PUBLIC id (never an objid)
            dry_run: dry_run,
          ).call

          OT.info "[RepairDomain] #{custom_domain.display_domain} -> " \
                  "status=#{result.status}, dry_run=#{dry_run}, issues=#{result.issues.size}"

          success_data
        end

        def success_data
          {
            record: {
              domain_id: result.domain_id,
              extid: result.extid,
              display_domain: result.display_domain,
            },
            details: {
              status: result.status.to_s,
              dry_run: result.dry_run,
              issues: result.issues,
              repairs_applied: result.repairs_applied,
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

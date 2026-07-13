# apps/api/colonel/logic/colonel/remove_custom_domain.rb
#
# frozen_string_literal: true

require_relative '../base'
require 'onetime/operations/domains/remove'

module ColonelAPI
  module Logic
    module Colonel
      # Remove (permanently delete) a custom domain (Colonel) — surfaces the
      # CLI-only `bin/ots domains remove` toolbox verb (#3731 P3).
      #
      # Thin adapter over {Onetime::Operations::Domains::Remove} — the single,
      # audited implementation of the remove verb. The op owns the teardown, the
      # display_domain_index re-assertion, and the AdminAuditEvent; this class
      # resolves the domain and threads the `dry_run` flag.
      #
      # `dry_run` defaults to TRUE (dry-run default): the screen previews the
      # domain details, then re-issues with `dry_run: false` behind a
      # typed-confirmation dialog to apply.
      #
      # Security invariant (epic #20): BOTH the router (role=colonel) AND this
      # logic (verify_one_of_roles!(colonel: true)) enforce the colonel role.
      class RemoveCustomDomain < ColonelAPI::Logic::Base
        attr_reader :extid, :dry_run, :custom_domain, :result

        def process_params
          @extid = sanitize_identifier(params['extid'])
          raise_form_error('Domain ID is required', field: :extid) if extid.to_s.empty?

          @dry_run = params.key?('dry_run') ? truthy?(params['dry_run']) : true
        end

        def raise_concerns
          verify_one_of_roles!(colonel: true)

          @custom_domain = Onetime::CustomDomain.find_by_extid(extid)
          raise_not_found('Domain not found') unless custom_domain
        end

        def process
          @result = Onetime::Operations::Domains::Remove.new(
            domain: custom_domain,
            actor: cust.extid, # acting colonel's PUBLIC id (never an objid)
            dry_run: dry_run,
          ).call

          # Log from result (snapshotted pre-destroy!) — on the applied path
          # destroy! nils custom_domain.display_domain in memory.
          OT.info "[RemoveCustomDomain] #{result.display_domain} -> " \
                  "status=#{result.status}, dry_run=#{dry_run}, org=#{result.org_id}"

          # NOTE: no audit here — the op owns the single AdminAuditEvent
          # (exactly-once, applied path only). This adapter never audits.
          success_data
        end

        def success_data
          {
            record: {
              deleted: result.status == :removed,
              domain_id: result.domain_id,
              extid: result.extid,
              display_domain: result.display_domain,
            },
            details: {
              status: result.status.to_s,
              dry_run: result.dry_run,
              org_id: result.org_id.to_s,
              org_name: result.org_name,
              reasserts_survivor: result.reasserts_survivor,
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

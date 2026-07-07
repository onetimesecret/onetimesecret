# apps/api/colonel/logic/colonel/transfer_domain.rb
#
# frozen_string_literal: true

require_relative '../base'
require 'onetime/operations/domains/transfer'

module ColonelAPI
  module Logic
    module Colonel
      # Transfer a custom domain between organizations (Colonel) — surfaces the
      # CLI-only `bin/ots domains transfer` toolbox (epic #43). Highest-blast-radius
      # toolbox verb: it reassigns domain OWNERSHIP.
      #
      # Thin adapter over {Onetime::Operations::Domains::Transfer} — the single,
      # audited implementation of the transfer verb. The op owns the ownership
      # check, the atomic-ish move, and the AdminAuditEvent (CONTRACT 4); this class
      # resolves the domain + orgs and threads the `dry_run` flag.
      #
      # `dry_run` defaults to TRUE (D4 — dry-run default): the screen previews the
      # from/to details, then re-POSTs with `dry_run: false` behind a
      # typed-confirmation dialog (retype the domain) to apply.
      #
      # Security invariant (epic #20): BOTH the router (role=colonel) AND this
      # logic (verify_one_of_roles!(colonel: true)) enforce the colonel role.
      class TransferDomain < ColonelAPI::Logic::Base
        attr_reader :extid, :to_org_id, :from_org_id, :dry_run,
                    :custom_domain, :to_org, :from_org, :result

        def process_params
          @extid = sanitize_identifier(params['extid'])
          raise_form_error('Domain ID is required', field: :extid) if extid.to_s.empty?

          @to_org_id   = sanitize_identifier(params['to_org'])
          @from_org_id = sanitize_identifier(params['from_org'])
          raise_form_error('Destination organization is required', field: :to_org) if to_org_id.to_s.empty?

          @dry_run = params.key?('dry_run') ? truthy?(params['dry_run']) : true
        end

        def raise_concerns
          verify_one_of_roles!(colonel: true)

          @custom_domain = Onetime::CustomDomain.find_by_extid(extid)
          raise_not_found('Domain not found') unless custom_domain

          @to_org = resolve_org(to_org_id)
          raise_form_error('Destination organization not found', field: :to_org) unless to_org

          # Optional explicit source org (ownership assertion).
          return if from_org_id.to_s.empty?

          @from_org = resolve_org(from_org_id)
          raise_form_error('Source organization not found', field: :from_org) unless from_org
        end

        def process
          @result = Onetime::Operations::Domains::Transfer.new(
            domain: custom_domain,
            to_org: to_org,
            from_org: from_org,
            actor: cust.extid, # acting colonel's PUBLIC id (never an objid)
            dry_run: dry_run,
          ).call

          # An explicit source org that doesn't match the current owner is a
          # 4xx form error (the CLI's "does not match --from-org" guard), never a
          # silent success.
          if result.status == :mismatch
            raise_form_error(
              "Domain's current organization does not match the source organization",
              field: :from_org,
            )
          end

          OT.info "[TransferDomain] #{custom_domain.display_domain} -> " \
                  "status=#{result.status}, dry_run=#{dry_run}, to=#{result.to_org_id}"

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
              from_org_id: result.from_org_id.to_s,
              from_org_name: result.from_org_name,
              to_org_id: result.to_org_id.to_s,
              to_org_name: result.to_org_name,
            },
          }
        end

        private

        def resolve_org(identifier)
          Onetime::Organization.load(identifier) ||
            Onetime::Organization.find_by_extid(identifier)
        end

        def truthy?(value)
          %w[true 1 yes on].include?(value.to_s.strip.downcase)
        end
      end
    end
  end
end

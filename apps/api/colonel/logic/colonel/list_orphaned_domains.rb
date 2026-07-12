# apps/api/colonel/logic/colonel/list_orphaned_domains.rb
#
# frozen_string_literal: true

require_relative '../base'
require 'onetime/operations/domains/orphaned_scan'

module ColonelAPI
  module Logic
    module Colonel
      # List orphaned custom domains (Colonel) — domains with no owning
      # organization (`org_id` blank), surfaced from the CLI-only
      # `bin/ots domains orphaned` toolbox (epic #43).
      #
      # Thin adapter over {Onetime::Operations::Domains::OrphanedScan} — the single
      # implementation of the orphaned-scan verb. The op owns the bounded scan
      # (CONTRACT 6) and pagination; this class keeps only the HTTP concerns.
      #
      # READ-ONLY: no AdminAuditEvent (CONTRACT 4 — audit is for mutations).
      #
      # Security invariant (epic #20): BOTH the router (role=colonel) AND this
      # logic (verify_one_of_roles!(colonel: true)) enforce the colonel role.
      class ListOrphanedDomains < ColonelAPI::Logic::Base
        SCHEMAS = { response: 'colonelDomainsOrphaned' }.freeze

        attr_reader :domains, :pagination_meta

        def process_params
          @page     = (params['page'] || 1).to_i
          @per_page = (params['per_page'] || 50).to_i
        end

        def raise_concerns
          verify_one_of_roles!(colonel: true)
        end

        def process
          result = Onetime::Operations::Domains::OrphanedScan.new(
            page: @page,
            per_page: @per_page,
          ).call

          @domains         = result.domains
          @pagination_meta = {
            page: result.page,
            per_page: result.per_page,
            total_count: result.total_count,
            total_pages: result.total_pages,
          }

          success_data
        end

        def success_data
          {
            record: {},
            details: {
              domains: domains,
              pagination: pagination_meta,
            },
          }
        end
      end
    end
  end
end

# apps/api/colonel/logic/colonel/list_jobs.rb
#
# frozen_string_literal: true

require_relative '../base'
require 'onetime/jobs/registry'

module ColonelAPI
  module Logic
    module Colonel
      # Scheduler catalog: every scheduled job with its last run, next due time
      # and last error, plus scheduler liveness (Colonel, #4343).
      #
      # Thin adapter over {Onetime::Jobs::Registry} (which jobs exist) and
      # {Onetime::Jobs::JobRun.catalog} (what they last did) — the same
      # projection `bin/ots scheduler status` prints. This class keeps only the
      # HTTP concerns: param coercion, the role gate and in-memory pagination
      # over a bounded catalog (one row per job class).
      #
      # Read-only and unaudited: run records hold job metadata, and error text
      # is email-obscured before it is stored (JobRun.error_text).
      #
      # Security invariant (epic #20): BOTH the router (role=colonel) AND this
      # logic (verify_one_of_roles!(colonel: true)) enforce the colonel role.
      class ListJobs < ColonelAPI::Logic::Base
        SCHEMAS = { response: 'colonelJobs' }.freeze

        DEFAULT_PER_PAGE = 50
        MAX_PER_PAGE     = 100

        attr_reader :jobs, :scheduler, :pagination_meta

        def process_params
          @page     = (params['page'] || 1).to_i
          @page     = 1 if @page < 1
          @per_page = (params['per_page'] || DEFAULT_PER_PAGE).to_i
          @per_page = DEFAULT_PER_PAGE if @per_page <= 0
          @per_page = MAX_PER_PAGE if @per_page > MAX_PER_PAGE
        end

        def raise_concerns
          verify_one_of_roles!(colonel: true)
        end

        def process
          Onetime::Jobs::Registry.load_all!
          catalog = Onetime::Jobs::JobRun.catalog(Onetime::Jobs::Registry.entries)
          rows    = catalog['jobs']

          total_count = rows.size
          total_pages = (total_count.to_f / @per_page).ceil
          start_idx   = (@page - 1) * @per_page

          @scheduler       = catalog['scheduler']
          @jobs            = rows[start_idx, @per_page] || []
          @pagination_meta = {
            page: @page,
            per_page: @per_page,
            total_count: total_count,
            total_pages: total_pages,
          }

          success_data
        end

        private

        def success_data
          {
            record: { scheduler: scheduler },
            details: {
              jobs: jobs,
              pagination: pagination_meta,
            },
          }
        end
      end
    end
  end
end

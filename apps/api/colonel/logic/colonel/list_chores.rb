# apps/api/colonel/logic/colonel/list_chores.rb
#
# frozen_string_literal: true

require_relative '../base'
require 'onetime/jobs/job_run'
require 'onetime/operations/chores/catalog'

module ColonelAPI
  module Logic
    module Colonel
      # The chores an operator can run from the console, each with its last
      # console run (Colonel, #4343).
      #
      # Thin adapter over {Onetime::Operations::Chores::Catalog} (which chores
      # are runnable right now) and {Onetime::Jobs::JobRun} (what the last
      # console run of each did, read in one pipelined batch under
      # `chore.<id>`). In-memory pagination over a bounded list (one row per
      # allowlisted chore).
      #
      # Read-only and unaudited: rows hold chore metadata and counts; run error
      # text is email-obscured before it is stored (JobRun.error_text).
      #
      # Security invariant (epic #20): BOTH the router (role=colonel) AND this
      # logic (verify_one_of_roles!(colonel: true)) enforce the colonel role.
      class ListChores < ColonelAPI::Logic::Base
        SCHEMAS = { response: 'colonelChores' }.freeze

        DEFAULT_PER_PAGE = 50
        MAX_PER_PAGE     = 100

        # A console run lives inside one web request and is bounded
        # (Onetime::Operations::Chores::Run: a few seconds of records, plus at
        # worst the entitlement run's Stripe pull with its timeouts and
        # retries). A record still 'running' this long after it started was
        # cut off — the web process restarted mid-run, e.g. a deploy — and
        # nothing will ever finish it. There is no web-process boot record to
        # compare against, as the scheduler rows have, so age is the signal.
        STALE_RUNNING_SECONDS = 15 * 60
        INTERRUPTED           = 'interrupted: no finish recorded within 15 minutes'

        attr_reader :chores, :pagination_meta

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
          rows = chore_rows

          total_count = rows.size
          total_pages = (total_count.to_f / @per_page).ceil
          start_idx   = (@page - 1) * @per_page

          @chores          = rows[start_idx, @per_page] || []
          @pagination_meta = {
            page: @page,
            per_page: @per_page,
            total_count: total_count,
            total_pages: total_pages,
          }

          success_data
        end

        private

        def chore_rows
          entries = Onetime::Operations::Chores::Catalog.all
          runs    = Onetime::Jobs::JobRun.read_many(entries.map(&:run_id))
          entries.map { |entry| chore_row(entry, runs[entry.run_id] || {}) }
        end

        # Same last-run vocabulary as ListJobs: 'never' and nulls until the
        # first console run.
        def chore_row(entry, run)
          last_status, last_error = if interrupted?(run)
                                      ['error', INTERRUPTED]
                                    else
                                      [run['last_status'] || Onetime::Jobs::JobRun::NEVER, run['last_error']]
                                    end
          {
            'id' => entry.id,
            'kind' => entry.kind,
            'model' => entry.model,
            'chores' => entry.chores,
            'supports_dry_run' => entry.supports_dry_run,
            'cli' => entry.cli,
            'last_status' => last_status,
            'last_started_at' => run['last_started_at'],
            'last_finished_at' => run['last_finished_at'],
            'last_duration_ms' => run['last_duration_ms'],
            'last_error' => last_error,
            'run_count' => run['run_count'].to_i,
          }
        end

        # Read-time only; the stored record is left for the next run.
        def interrupted?(run)
          Onetime::Jobs::JobRun.interrupted?(run, since: Onetime::Jobs::JobRun.now - STALE_RUNNING_SECONDS)
        end

        def success_data
          {
            record: {},
            details: {
              chores: chores,
              pagination: pagination_meta,
            },
          }
        end
      end
    end
  end
end

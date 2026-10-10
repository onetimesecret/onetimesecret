# apps/api/colonel/logic/colonel/run_chore.rb
#
# frozen_string_literal: true

require_relative '../base'
require 'onetime/operations/chores/catalog'
require 'onetime/operations/chores/run'

module ColonelAPI
  module Logic
    module Colonel
      # Run ONE allowlisted chore now (Colonel, #4343).
      #
      # Thin adapter over {Onetime::Operations::Chores::Run}, which owns the
      # record limit, the wall-clock budget, the dry-run rules, the run record
      # and the ColonelAuditEvent. The run is synchronous and bounded, so the
      # response can report partial counts (`capped`, `budget_exhausted`);
      # `details.cli` is the full-fleet command.
      #
      # Request: `POST /api/colonel/chores/:chore/run` with
      # `{ dry_run: bool, limit: int, reason?: string }`.
      #
      # TIER 2: a chore rewrites records toward their current shape and is
      # idempotent, but it does write customer data in bulk, so a live run needs
      # the typed confirmation (X-OTS-Confirm = the chore id). No elevation, no
      # tight-bucket charge. `dry_run` previews without the gate: for a
      # housekeeping chore the preview runs nothing at all.
      #
      # An id that is not runnable — unknown, or excluded from the catalog
      # (the vhost cleanup) — is a 404, checked before the gate so a caller
      # learns nothing about the confirmation from a bad id.
      #
      # Security invariant (epic #20): BOTH the router (role=colonel) AND this
      # logic (verify_one_of_roles!(colonel: true)) enforce the colonel role.
      class RunChore < ColonelAPI::Logic::Base
        SCHEMAS = { response: 'colonelChoreRun' }.freeze

        # Allowlisted ids are at most 61 characters; generous headroom.
        MAX_CHORE_LENGTH = 128

        attr_reader :chore, :limit, :result

        def process_params
          # Ids keep dots (sanitize_identifier strips them); the catalog is the
          # real gate.
          @chore   = params['chore'].to_s.downcase.gsub(/[^a-z0-9._-]/, '')[0, MAX_CHORE_LENGTH].to_s
          @dry_run = truthy?(params['dry_run'])
          @limit   = parse_limit(params['limit'])
          # OPTIONAL operator-supplied why (#4338), threaded onto the preview
          # observation too.
          @reason  = operator_reason_param
        end

        def raise_concerns
          verify_one_of_roles!(colonel: true)

          raise_form_error('Chore is required', field: :chore) if @chore.empty?
          raise_not_found('Unknown chore') unless Onetime::Operations::Chores::Catalog.valid?(@chore)
          unless @limit && (1..Onetime::Operations::Chores::Run::MAX_LIMIT).cover?(@limit)
            raise_form_error(
              "limit must be an integer between 1 and #{Onetime::Operations::Chores::Run::MAX_LIMIT}",
              field: :limit,
            )
          end

          # PREVIEW EXEMPTION (#4326): a dry run writes nothing.
          return if @dry_run

          guard_destructive_action!(
            tier: :sensitive,
            confirm_with: @chore,
            confirm_subject: 'the chore id',
            field: :chore,
          )
        end

        def process
          # actor is the acting colonel's PUBLIC id (never an objid).
          @result = Onetime::Operations::Chores::Run.new(
            chore: @chore,
            actor: cust.extid,
            dry_run: @dry_run,
            limit: @limit,
            reason: @reason,
          ).call

          success_data
        end

        private

        # Absent or blank is the default; anything that is not a whole number
        # is nil (a 422), never silently coerced.
        def parse_limit(raw)
          text = raw.to_s.strip
          return Onetime::Operations::Chores::Run::DEFAULT_LIMIT if text.empty?

          Integer(text, 10, exception: false)
        end

        def success_data
          {
            record: {
              chore: result.chore,
              kind: result.kind,
              status: result.status.to_s,
              dry_run: result.dry_run,
              limit: result.limit,
              capped: result.capped,
              budget_exhausted: result.budget_exhausted,
              duration_ms: result.duration_ms,
            },
            details: {
              report: result.report,
              cli: Onetime::Operations::Chores::Catalog.find(result.chore)&.cli.to_s,
            },
          }
        end
      end
    end
  end
end

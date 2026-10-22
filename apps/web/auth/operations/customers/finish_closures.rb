# apps/web/auth/operations/customers/finish_closures.rb
#
# frozen_string_literal: true

# Loaded from the CLI (outside the auth app's autoloader), so every
# dependency is required explicitly.
require 'auth/account_statuses'
require 'auth/database'
require 'auth/lib/logging'
require 'auth/operations/customers/purge'

module Auth
  module Operations
    module Customers
      # Finish the account closures that stopped before the Customer record
      # was deleted (#4830).
      #
      # ## The state
      #
      # Customer#mark_closure_started! runs just before a closure removes the
      # sign-in, and a completed closure deletes the record, marker included.
      # A closure that stopped after the mark (a partial cleanup that still
      # committed, a Redis failure during the record deletion) leaves the
      # record in Redis, marked, with no open auth account. Its owner asked
      # for it to be deleted. `customers diagnose` and `customers doctor`
      # report it as :closure_interrupted; `customers sync-auth-accounts`
      # skips it rather than give it a live auth account again.
      #
      # ## What it does
      #
      # Selects every marked record that Customer.closure_state classifies
      # as :interrupted: the marker is older than
      # Customer::CLOSURE_STALE_AFTER (a younger one can belong to a closure
      # still running), and there is no open accounts row for its extid in
      # full mode. A marked record with an open row is a closure that rolled
      # back: the account is live, so it is never selected here, and
      # `customers doctor --repair` clears its marker instead.
      #
      # The dry run (the default) lists the records and writes nothing. A
      # live run finishes each one through Customers::Purge, the audited
      # lifecycle of `bin/ots customers purge ID`, with the same preflight:
      # a record that now has blockers is refused and left as it is. The SQL
      # step finds no account to remove; the session revocation, the
      # organization cleanup and the record deletion run as in any purge.
      class FinishClosures
        # @!attribute candidates [r]
        #   @return [Array<Hash>] {extid:, email:, closure_started_at:} per
        #     record selected; the email is obscured
        # @!attribute results [r]
        #   @return [Array<Hash>] {extid:, status:, stage:, blockers:} per
        #     record purged; empty on a dry run
        Result = Data.define(:dry_run, :candidates, :results)

        # Records per pipelined marker read.
        SCAN_BATCH = 500

        # @param dry_run [Boolean] list only (default). `false` purges.
        # @param actor [String] recorded on each purge's audit event
        # @param reason [String, nil] operator-supplied, recorded likewise
        # @param now [Integer] epoch seconds the marker age is measured from
        def initialize(actor:, dry_run: true, reason: nil, now: Familia.now.to_i)
          @dry_run = dry_run ? true : false
          @actor   = actor
          @reason  = reason
          @now     = now
        end

        # @return [Result]
        # @raise [Sequel::Error] the auth database did not answer; nothing was
        #   purged, because an open account cannot be ruled out without it
        def call
          customers  = interrupted_closures
          candidates = customers.map { |customer| candidate(customer) }
          results    = @dry_run ? [] : customers.map { |customer| finish(customer) }

          Auth::Logging.log_operation(
            :finish_closures,
            dry_run: @dry_run,
            candidates: candidates.size,
            finished: results.count { |result| result[:status] == :success },
          )

          Result.new(dry_run: @dry_run, candidates: candidates, results: results)
        end

        private

        def interrupted_closures
          marked_customers.select do |customer|
            customer.closure_state(open_auth_account: open_auth_account?(customer), now: @now) == :interrupted
          end
        end

        # One pipelined HGET per SCAN_BATCH records instead of a full load
        # of every customer; only the marked ones are loaded.
        def marked_customers
          Onetime::Customer.instances.all.each_slice(SCAN_BATCH).flat_map do |objids|
            markers = Onetime::Customer.dbclient.pipelined do |pipe|
              objids.each { |objid| pipe.hget(Onetime::Customer.dbkey(objid), 'closure_started_at') }
            end
            Onetime::Customer.load_multi(
              objids.zip(markers).reject { |_objid, marker| marker.to_s.empty? }.map(&:first),
            ).compact
          end
        end

        def open_auth_account?(customer)
          return false unless auth_db

          auth_db[:accounts]
            .where(external_id: customer.extid, status_id: Auth::AccountStatuses::LIVE)
            .any?
        end

        # nil in simple mode, where there is no auth account to rule out.
        def auth_db
          return @auth_db if defined?(@auth_db)

          @auth_db = Onetime.auth_config.full_enabled? ? Auth::Database.connection : nil
        end

        def candidate(customer)
          {
            extid: customer.extid,
            email: customer.obscure_email,
            closure_started_at: customer.closure_started_at.to_i,
          }
        end

        def finish(customer)
          result = Purge.new(customer: customer, actor: @actor, reason: @reason).call
          {
            extid: customer.extid,
            status: result.status,
            stage: result.stage,
            blockers: result.blockers,
          }
        end
      end
    end
  end
end

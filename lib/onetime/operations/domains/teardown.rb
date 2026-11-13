# frozen_string_literal: true

require 'onetime/domain_validation/strategy'
require 'onetime/operations/delete_sender_domain'
require 'onetime/operations/sender_identity_lease'

module Onetime
  module Operations
    module Domains
      # Shared destructive sequence, independent of authorization, audit trails,
      # session state, and toolbox index repair. Callers finalize a returned
      # committed result before surfacing its lease_error.
      #
      # Accepted limitation for this refactor: local deletion can succeed while
      # external resources remain, with no automatic retry or reconciliation.
      # The result reports the sender cleanup outcome so callers can record
      # it; vhost deletion failures are only logged. Even a nil lease_error
      # does not confirm cleanup. This shares teardown sequencing and
      # commitment-aware lease-loss handling; it does not guarantee provider
      # cleanup or recoverable deletion.
      class Teardown
        class Busy < StandardError; end

        # Only returned after destroy! completes. Earlier failures propagate;
        # they do not imply that preceding provider calls had no side effects.
        # Commitment describes local destruction, not successful remote cleanup.
        # sender_cleanup is :kept when keep_sender_identity skipped the remote
        # deletion, otherwise the DeleteSenderDomain outcome (:deleted,
        # :absent, :skipped, or :failed).
        Result = Data.define(:removal_committed, :lease_error, :sender_cleanup)

        # @param domain [Onetime::CustomDomain]
        # @param keep_vhost [Boolean] leave the provider vhost in place. The
        #   vhost is keyed by the domain's name, not by the record, so a
        #   caller removing one of several records that share a name passes
        #   true to keep it for the record that stays
        #   (Domains::CollisionResolution). The default deletes it.
        # @param keep_sender_identity [Boolean] skip remote sender deletion only;
        #   destroy! still removes the local domain and its mailer config.
        def initialize(domain:, keep_vhost: false, keep_sender_identity: false)
          @domain               = domain
          @keep_vhost           = keep_vhost
          @keep_sender_identity = keep_sender_identity
        end

        def call
          lock  = Onetime::CustomDomain::MailerConfig.sender_identity_lock(@domain.identifier)
          lease = Onetime::Operations::SenderIdentityLease.new(lock)
          unless lease.acquire
            raise Busy,
              "Another change to the sender configuration of #{@domain.display_domain} is in progress. Try again."
          end

          removal_committed = false
          lease_error       = nil
          sender_cleanup    = :kept
          begin
            lease.protect do
              if @keep_vhost
                OT.info "[Domains::Teardown] #{@domain.display_domain} vhost kept for the record that shares the name"
              else
                delete_vhost
              end
              lease.check!
              unless @keep_sender_identity
                sender_cleanup = Onetime::Operations::DeleteSenderDomain.new(mailer_config: @domain.mailer_config).call.outcome
              end
              lease.check!
              @domain.destroy!
              removal_committed = true
            end
          rescue Onetime::Operations::SenderIdentityLease::Lost => ex
            raise unless removal_committed

            # A final ownership check cannot undo destruction or bypass the
            # caller's audit/session/index finalization.
            lease_error = ex
          end

          Result.new(removal_committed: removal_committed, lease_error: lease_error, sender_cleanup: sender_cleanup)
        end

        private

        def delete_vhost
          strategy = Onetime::DomainValidation::Strategy.for_config(OT.conf)
          result   = strategy.delete_vhost(@domain)
          OT.info "[Domains::Teardown.delete_vhost] #{@domain.display_domain} -> #{result && result[:message]}"
        rescue HTTParty::ResponseError, Timeout::Error, Errno::ECONNREFUSED => ex
          OT.le "[Domains::Teardown.delete_vhost error] #{@domain.display_domain} #{ex}"
        end
      end
    end
  end
end

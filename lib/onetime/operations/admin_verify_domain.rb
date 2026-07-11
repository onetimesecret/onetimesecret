# lib/onetime/operations/admin_verify_domain.rb
#
# frozen_string_literal: true

# Reuses (does not rewrite) the incumbent domain-verify operation. Loaded at the
# call site (the colonel logic class), so require the dependencies explicitly —
# the same convention the CLI + domain API logic follow.
require 'onetime/operations/verify_domain'
require 'onetime/models/admin_audit_event'

module Onetime
  module Operations
    # ADMIN domain-verify wrapper: run DNS/SSL verification for a single custom
    # domain as a colonel / operator action, and record it in the admin audit
    # trail (epic #31 / CONTRACT 4).
    #
    # This deliberately does NOT re-implement verification — it delegates to the
    # incumbent {Onetime::Operations::VerifyDomain} (the shared DNS/SSL verifier
    # with atomic persistence semantics, issue #3080) and adds exactly one
    # {Onetime::AdminAuditEvent} per call.
    #
    # ## Why a wrapper instead of auditing inside VerifyDomain
    #
    # The bare `VerifyDomain` op is also driven by NON-admin callers — the
    # `bin/ots domains verify` CLI, the `DomainsAPI::Logic::Domains::VerifyDomain`
    # customer endpoint, and the scheduled `domain_refresh_job`. None of those are
    # admin actions and must not land in the admin audit trail; auditing inside the
    # bare op would mislabel every scheduled/self-service verification as operator
    # activity AND perturb the CLI's golden-master output. So the audit lives in
    # this admin-only wrapper (mirrors the customer-verify precedent
    # {Auth::Operations::Customers::SetVerification}); the incumbent op is untouched.
    #
    # A verify always potentially mutates state (it persists the refreshed
    # verified/resolving flags + `updated`), so — unlike the customer wrapper, which
    # only audits an actual change — this records EXACTLY ONE event per call
    # regardless of the DNS outcome, with `result:` reflecting success/failure. That
    # is the mutating-op audit contract (CONTRACT 4): one event per mutating action.
    #
    # The underlying {Onetime::Operations::VerifyDomain::Result} is returned
    # unchanged so the caller can surface the honest verification outcome
    # (verified / resolving / pending / unverified, or an error) to the operator.
    class AdminVerifyDomain
      # Audit verb recorded for every admin domain verification.
      AUDIT_VERB = 'domain.verify'

      # @param domain [Onetime::CustomDomain] target domain (caller ensures non-nil)
      # @param actor [String, #extid, #email] acting admin's PUBLIC identity
      #   (colonel extid/email). Never an internal objid.
      # @param persist [Boolean] whether to save verification changes (default true;
      #   pass false for a read-only health check — still audited as an attempt).
      def initialize(domain:, actor:, persist: true)
        @domain  = domain
        @actor   = actor
        @persist = persist
      end

      # @return [Onetime::Operations::VerifyDomain::Result] the verification result
      #   (passthrough from the incumbent op).
      def call
        result = Onetime::Operations::VerifyDomain.new(
          domain: @domain,
          persist: @persist,
        ).call

        Onetime::AdminAuditEvent.record(
          actor: @actor,
          verb: AUDIT_VERB,
          target: @domain.extid,
          result: result.success? ? :success : :failure,
          detail: {
            previous_state: result.previous_state.to_s,
            current_state: result.current_state.to_s,
            dns_validated: result.dns_validated,
            is_resolving: result.is_resolving,
            ssl_ready: result.ssl_ready,
            persisted: result.persisted,
          },
        )

        result
      end
    end
  end
end

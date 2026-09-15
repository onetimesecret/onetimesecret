# apps/web/auth/operations/authorize_tenant_connect.rb
#
# frozen_string_literal: true

require 'auth/lib/logging'

module Auth
  module Operations
    # Pre-bind authorization gate for tenant identity Connect (#4413, epic #4408).
    #
    # Decides whether the SESSION account may attach an identity returned by a
    # custom domain's tenant IdP. The tenant callback pipeline (#3849) runs this
    # after the intent, session and surface gates and BEFORE any
    # account_identities row is inserted or updated. It answers exactly one
    # question:
    #
    #   Does the session account hold an ACTIVE OrganizationMembership in the
    #   organization owning the validated custom domain, and does that
    #   membership authorize THIS EXACT domain?
    #
    # The authorization primitive is OrganizationMembership#can_access_domain?:
    # an organization-scoped membership (domain_scope_id blank — every
    # invitation-created row) passes for every domain the organization owns; a
    # domain-scoped membership passes only for the domain whose objid it names.
    # A member scoped to a SIBLING domain of the same organization is refused,
    # which is the case `organization.member?` cannot express and the reason
    # Auth::Operations::JoinDomainOrganization's `already_member` short-circuit
    # is never a substitute for this gate (docs/authentication/per-domain-sso.md,
    # "Why the domain scope matters").
    #
    # Lookup chain (per-domain-sso.md, tenant connect step 6 — the same lookups
    # hooks/login.rb, JoinDomainOrganization and BackfillTenantIssuer already
    # perform; no parallel lookup keyed on org_id or custid):
    #
    #   CustomDomain.find_by_identifier(domain_id)
    #     -> custom_domain.primary_organization
    #     -> Customer.find_by_extid(account[:external_id])
    #     -> OrganizationMembership.find_by_org_customer(org.objid, customer.objid)
    #
    # Any nil in that chain is a refusal.
    #
    # FAIL-CLOSED, SIDE-EFFECT-FREE. This operation never creates, activates or
    # re-scopes a membership, never touches the auth database, and never falls
    # back to email matching. A raise from any lookup is logged and reported as
    # a refusal (:lookup_error) rather than propagated, so a datastore hiccup
    # mid-callback can only deny a bind, never grant one. The membership must
    # exist before the bind: a successful tenant assertion must not create the
    # membership that then authorizes attaching that assertion as a credential.
    #
    # The gate deliberately does NOT check the session surface, recent
    # re-authentication or the connect intent — those are the caller's earlier
    # steps (#4409, #4410/#4414, #4411). Composing them here would let a caller
    # skip one by accident; keeping this single-purpose keeps the pipeline's
    # ordering explicit at the call site.
    #
    # @example In account_from_omniauth, after the intent and surface gates
    #   gate = Auth::Operations::AuthorizeTenantConnect.call(
    #     account: account,                                  # from _account_from_session
    #     domain_id: session[:validated_omniauth_domain_id], # stamped by before_omniauth_callback_route
    #   )
    #   unless gate.authorized?
    #     # refuse — never email-match, never JoinDomainOrganization
    #   end
    #   # bind (provider, issuer, uid) to account[:id] only
    class AuthorizeTenantConnect
      # Refusal reasons, in lookup order. Every reason is a closed door; the
      # caller's response is the same for all of them (refuse the bind). They
      # differ only for the audit log and for tests.
      #
      #   :no_account            — nil account or blank external_id
      #   :no_domain             — blank or unresolvable domain_id
      #   :no_organization       — domain has no primary organization
      #   :no_customer           — no Customer for the account's external_id
      #   :no_membership         — no OrganizationMembership row for (org, customer)
      #                            (covers "in the members set but no row" — the
      #                            members-set-only state organization.member?
      #                            would admit; an organization-scoped ROW passes)
      #   :membership_inactive   — row exists but status != 'active'
      #   :domain_not_authorized — active row scoped to a different domain
      #   :lookup_error          — a lookup raised; treated as refused
      REFUSAL_REASONS = [
        :no_account,
        :no_domain,
        :no_organization,
        :no_customer,
        :no_membership,
        :membership_inactive,
        :domain_not_authorized,
        :lookup_error,
      ].freeze

      # Outcome of the gate. `authorized?` is the only field a caller may
      # branch on; the loaded records are exposed so the bind step that follows
      # can reuse them instead of repeating the lookups.
      Result = Struct.new(
        :authorized,
        :reason,
        :custom_domain,
        :organization,
        :customer,
        :membership,
        keyword_init: true,
      ) do
        def authorized?
          authorized == true
        end

        def refused?
          !authorized?
        end
      end

      attr_reader :account, :domain_id

      # @param account [Hash, nil] the Rodauth account row loaded from the
      #   SESSION (`_account_from_session`), never from the IdP email claim.
      #   Only `:external_id` is read.
      # @param domain_id [String, nil] the callback's validated custom-domain
      #   identifier (`session[:validated_omniauth_domain_id]`).
      # @return [Result]
      def self.call(account:, domain_id:)
        new(account: account, domain_id: domain_id).call
      end

      def initialize(account:, domain_id:)
        @account   = account
        @domain_id = domain_id
      end

      # @return [Result] frozen
      def call
        external_id = account_external_id
        return refuse(:no_account) if external_id.empty?
        return refuse(:no_domain) if domain_id.to_s.empty?

        custom_domain = load_custom_domain
        return refuse(:no_domain) unless custom_domain

        organization = custom_domain.primary_organization
        return refuse(:no_organization, custom_domain: custom_domain) unless organization

        customer = Onetime::Customer.find_by_extid(external_id)
        return refuse(:no_customer, custom_domain: custom_domain, organization: organization) unless customer

        loaded = { custom_domain: custom_domain, organization: organization, customer: customer }

        membership = Onetime::OrganizationMembership.find_by_org_customer(organization.objid, customer.objid)
        return refuse(:no_membership, **loaded) unless membership

        loaded[:membership] = membership
        return refuse(:membership_inactive, **loaded) unless membership.active?
        return refuse(:domain_not_authorized, **loaded) unless membership.can_access_domain?(custom_domain)

        authorize(**loaded)
      rescue StandardError => ex
        Auth::Logging.log_auth_event(
          :tenant_connect_membership_lookup_error,
          level: :error,
          domain_id: domain_id,
          error_class: ex.class.name,
          error: ex.message,
        )
        refuse(:lookup_error, log: false)
      end

      private

      # Tolerates both the symbol-keyed Sequel row Rodauth hands the hooks and
      # a string-keyed copy; anything else (nil, non-hash) reads as absent.
      def account_external_id
        return '' unless account.is_a?(Hash)

        (account[:external_id] || account['external_id']).to_s
      end

      # domain_id is the CustomDomain objid (identifier), exactly as
      # JoinDomainOrganization loads it. Familia's by-identifier loader returns
      # nil for a missing key and never raises RecordNotFound (pinned by
      # try/unit/models/custom_domain_load_contract_try.rb); a datastore error
      # propagates to the outer rescue in #call and refuses as :lookup_error.
      def load_custom_domain
        Onetime::CustomDomain.find_by_identifier(domain_id)
      end

      def authorize(custom_domain:, organization:, customer:, membership:)
        Auth::Logging.log_auth_event(
          :tenant_connect_membership_authorized,
          level: :info,
          domain_id: custom_domain.identifier,
          organization_id: organization.objid,
          customer_extid: customer.extid,
          membership_scope: membership.org_scoped? ? 'organization' : 'domain',
        )

        Result.new(
          authorized: true,
          reason: nil,
          custom_domain: custom_domain,
          organization: organization,
          customer: customer,
          membership: membership,
        ).freeze
      end

      def refuse(reason, log: true, custom_domain: nil, organization: nil, customer: nil, membership: nil)
        raise ArgumentError, "unknown refusal reason #{reason.inspect}" unless REFUSAL_REASONS.include?(reason)

        if log
          Auth::Logging.log_auth_event(
            :tenant_connect_membership_refused,
            level: :warn,
            reason: reason,
            domain_id: domain_id,
            organization_id: organization&.objid,
            customer_extid: customer&.extid,
            membership_status: membership&.status,
            membership_domain_scope_id: membership&.domain_scope_id,
          )
        end

        Result.new(
          authorized: false,
          reason: reason,
          custom_domain: custom_domain,
          organization: organization,
          customer: customer,
          membership: membership,
        ).freeze
      end
    end
  end
end

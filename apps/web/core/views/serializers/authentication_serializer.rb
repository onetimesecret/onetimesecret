# apps/web/core/views/serializers/authentication_serializer.rb
#
# frozen_string_literal: true

require 'onetime/utils'
require 'onetime/tenant_sso_resolution'
require 'onetime/session/impersonation'

module Core
  module Views
    # Serializes authentication-related data for the frontend
    #
    # Responsible for transforming customer authentication state and
    # associated customer data into a consistent format for frontend consumption.
    module AuthenticationSerializer
      # Serializes authentication data from view variables
      #
      # @param view_vars [Hash] The view variables containing authentication state
      # @return [Hash] Serialized authentication data including customer information
      def self.serialize(view_vars)
        output = output_template

        output['authenticated'] = view_vars['authenticated']
        output['awaiting_mfa']  = view_vars['awaiting_mfa'] || false
        cust                    = view_vars['cust']

        # For anonymous users (nil cust), return null to match frontend schema.
        # The customerCanonical schema requires non-null objid string, so we
        # cannot return an object with nil fields - must be null or valid object.
        output['cust'] = cust&.safe_dump

        # Check if there was a valid session at the time of this response
        # This is crucial for error pages where authenticated=false but the user
        # had a valid session. The frontend uses this to avoid incorrect logouts.
        # A valid session has 'external_id' present (customer identifier in session)
        sess                        = view_vars['sess']
        output['had_valid_session'] = !!(sess && !sess.empty? && !sess['external_id'].to_s.empty?)

        # When authenticated, provide full customer data
        if output['authenticated']
          output['custid']         = cust.custid
          output['email']          = cust.email
          # customer_since: Formatted date string (e.g., "Mar 21, 2026") - matches Zod schema z.string()
          output['customer_since'] = OT::Utils::TimeUtils.epochdom(cust.created) if cust.created
          output['has_password']   = account_has_password?(sess)

          # Policy axis, independent of credential presence (#3886): whether
          # this account is ALLOWED to hold a local password. Credential
          # presence (has_password) says what exists; this says what policy
          # permits. The frontend combines both: no password + permitted =>
          # "Set password" affordance; no password + not permitted =>
          # SSO-managed empty state.
          output['password_auth_permitted'] = password_auth_permitted?(view_vars)

          # Add entitlement preview state for colonels. The planid comes from
          # the request-scoped context (ADR-020) — the same source the
          # entitlement chokepoints consult — so the banner cannot disagree
          # with the entitlements actually served.
          preview_planid = Onetime::EntitlementPreview.context&.dig(:planid)
          if cust.role?(:colonel) && preview_planid
            test_plan_name = resolve_test_plan_name(preview_planid)

            if test_plan_name
              output['entitlement_preview_planid']    = preview_planid
              output['entitlement_preview_plan_name'] = test_plan_name
            end
          end

          # Colonel impersonation banner state. Read from the request-scoped
          # context published by Middleware::ImpersonationContext — the SAME
          # marker that decided which customer `cust` above is — so the banner
          # can never disagree with the session actually being served. Reading
          # the session again here could show a banner for an overlay the
          # resolver had already invalidated (or hide one that is live).
          #
          # Not gated on cust.role?(:colonel): `cust` is the TARGET during an
          # impersonation, so a role gate here would suppress the banner in
          # exactly the case it exists for.
          output['impersonation'] = Onetime::SessionImpersonation.context

        # When awaiting MFA, provide minimal data from session (no customer access yet)
        elsif output['awaiting_mfa']
          output['email'] = view_vars['session_email']  # From session, not customer
          # Do NOT provide custid or customer object - user doesn't have access yet
        end

        output
      end

      class << self
        # Provides the base template for authentication serializer output
        #
        # @return [Hash] Template with all possible authentication output fields
        def output_template
          {
            'authenticated' => nil,
            'awaiting_mfa' => false,
            'had_valid_session' => false,
            'has_password' => false,
            'password_auth_permitted' => true,
            'custid' => nil,
            'cust' => nil,
            'email' => nil,
            'customer_since' => nil,
            'entitlement_preview_planid' => nil,
            'entitlement_preview_plan_name' => nil,
            # nil unless a colonel impersonation is active on this request.
            # Absence is the safe state: no block, no banner, ordinary session.
            'impersonation' => nil,
          }
        end

        # Checks whether the authenticated account has a password hash set.
        # SSO-only accounts have no row in account_password_hashes.
        #
        # Returns nil (unknown) when the lookup hits a transient database
        # failure rather than a fabricated false — on the wire, false means
        # "SSO-only account" and drives the frontend to hide password/MFA
        # settings. The bootstrap store treats nil as "no information" so a
        # blipped refresh never clobbers a known-good value. Only Sequel
        # errors degrade; programming errors propagate.
        #
        # @param sess [Hash, nil] Session hash containing account_id
        # @return [Boolean, nil] true if account has a password, false if not
        #   (or no session account / auth DB not in this mode), nil when the
        #   lookup failed
        def account_has_password?(sess)
          account_id = sess&.[]('account_id')
          return false unless account_id
          return false unless defined?(Auth::Database)

          db = Auth::Database.connection
          return false unless db

          db[:account_password_hashes].where(id: account_id).any?
        rescue Sequel::DatabaseError, Sequel::PoolTimeout => ex
          OT.le "[AuthenticationSerializer] account_has_password? query failed: #{ex.class} account_id=#{account_id}"
          nil
        end

        # Whether policy permits this account to hold a local password (#3886).
        #
        # Password auth is permitted when the install runs full auth mode
        # (Rodauth; simple mode has no password management surface) AND
        # nothing enforces SSO for this request context — neither the
        # app-level restrict_to='sso' mode nor a per-domain enforce_sso_only
        # flag. Consumer accounts on the canonical domain therefore default
        # to true. A domain with SSO configured but NOT enforced also yields
        # true: enforcement is the opt-in, per the issue's decision.
        #
        # Never keyed on "is SSO" — an account may hold a password AND SSO
        # identities (hybrid), and the two axes stay independent.
        #
        # @param view_vars [Hash] View variables with request context
        # @return [Boolean] true if the account may set/keep a local password
        def password_auth_permitted?(view_vars)
          auth_config = Onetime.auth_config
          return false unless auth_config&.full_enabled?
          return false if auth_config.restrict_to == 'sso'

          !tenant_sso_enforced?(view_vars)
        end

        # Per-domain SSO enforcement, mirroring the tenant resolution in
        # ConfigSerializer#build_sso_config (which emits the same signal to
        # the frontend as features.sso.enforce_sso_only). Enforcement only
        # counts when the tenant SSO config is actually available — a
        # disabled or unavailable config cannot lock accounts to an IdP.
        #
        # Fails CLOSED on resolution errors: a custom-domain request whose
        # policy cannot be read reports "enforced", so the affordance is not
        # advertised where it may be forbidden (Greptile review, PR #3938).
        # Operator hosts are NOT exempt from the lookup — DomainStrategy
        # publishes display_domain unconditionally (canonical fallback), so a
        # canonical request walks the same ladder, and a record keyed on the
        # operator's own host must still narrow (ADR-024). What they are
        # exempt from is the SENTINEL: TenantSsoResolution answers nil, not
        # DOMAIN_READ_FAILED, when the read fails on :canonical/:subdomain,
        # so a storage blip cannot hide the password form from consumer
        # accounts on the canonical /signin. Note this flag
        # only gates UI affordances — actual sign-in enforcement lives in the
        # signin routes (restrict_to resolution / Base#signin_enabled?).
        #
        # @param view_vars [Hash] View variables with request context
        # @return [Boolean] true if this request's domain enforces SSO-only
        # Resolution is the request-scoped Onetime::TenantSsoResolution — the
        # SAME object ConfigSerializer#resolve_tenant_sso_config answers from,
        # so the password affordance and the SSO button cannot be computed
        # from two different reads of the tenant's SsoConfig.
        def tenant_sso_enforced?(view_vars)
          resolution = Onetime::TenantSsoResolution.from_view_vars(view_vars)
          # Tri-state handling (#4157): failed domain read → enforce (below).
          return true if resolution.domain_read_failed?

          config = resolution.sso_config
          return false unless config

          config.enforce_sso_only?
        rescue Redis::BaseError
          # Tri-state handling (#4157): failed read → enforce SSO (narrowest
          # surface for password_auth_permitted?). This hides the password
          # form during a blip rather than showing it on a tenant that may
          # have disabled local passwords.
          true
        end

        # Resolve test plan name from Billing::Plan cache or config
        #
        # Uses centralized fallback loader to try Stripe cache first,
        # then billing.yaml config for development/standalone environments.
        #
        # @param test_planid [String] Plan ID to resolve
        # @return [String, nil] Plan name or nil if not found
        def resolve_test_plan_name(test_planid)
          result = ::Billing::Plan.load_with_fallback(test_planid)
          result[:plan]&.name || result[:config]&.dig(:name)
        end
      end

      SerializerRegistry.register(self)
    end
  end
end

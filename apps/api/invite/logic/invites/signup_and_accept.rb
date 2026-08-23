# apps/api/invite/logic/invites/signup_and_accept.rb
#
# frozen_string_literal: true

require 'auth/restrict_to'
require 'onetime/security/invite_token_rate_limiter'

module InviteAPI::Logic
  module Invites
    # Signup for org invite (consent step happens separately via /accept)
    #
    # POST /api/invite/:token/signup
    #
    # Auth: noauth (token validates access)
    #
    # This endpoint handles the case where a user receives an org invite but
    # either:
    # - Has no account at all (fresh invite signup)
    # - Has partial data that would block standard Rodauth flows
    #
    # The standard Rodauth create-account flow would block due to before_create_account
    # checks detecting partial state. This endpoint bypasses those checks after
    # validating that no complete account exists.
    #
    # Flow:
    # 1. Validates the invite token (pending, not expired)
    # 2. Derives email from token (NOT user-provided - security)
    # 3. Validates password meets requirements
    # 4. Checks if email exists in EITHER database -> generic error that does
    #    not confirm account existence (see SIGNUP_UNAVAILABLE_MESSAGE)
    # 5. Creates account in authdb via Rodauth internal_request
    #    (the after_create_account hook creates the Customer, auto-verifies
    #    the SQL account, and skips default-workspace creation)
    # 6. Auto-logs in the user
    #
    # The invitation is NOT accepted here — the token survives, and the
    # frontend completes the join by POSTing to /api/invite/:token/accept
    # against the session this endpoint just established. This keeps a single
    # acceptance code path regardless of whether the user signed up fresh
    # or already had an account.
    #
    # ## `restrict_to` (ADR-034#invite-signup-is-gated, #4139)
    #
    # This is a PRE-AUTH PASSWORD SURFACE: it accepts a password from an
    # unauthenticated caller, creates a password account, and mints a session
    # for it. That is create-account + autologin with a different URL, so it
    # goes dark on any host that restricts `password` away — see
    # enforce_restrict_to! below for why the Rodauth-side gate cannot reach it
    # and why "create the account but skip the autologin" is the wrong shape.
    #
    class SignupAndAccept < InviteAPI::Logic::Base
      include Onetime::LoggerMethods

      # Anti-enumeration (#3856): this message is returned whenever signup
      # cannot proceed for an email that already has an account, but it is
      # phrased conditionally and carries a generic error_type so the response
      # never *asserts* account existence. See raise_signup_unavailable.
      SIGNUP_UNAVAILABLE_MESSAGE = 'Unable to complete signup for this ' \
                                   'invitation. If you already have an account, sign in and then open ' \
                                   'your invitation link again.'

      attr_reader :invitation, :customer

      def process_params
        @token    = sanitize_identifier(params['token'])
        @password = params['password'].to_s
      end

      def raise_concerns
        # A restricted-away method presents no surface at all
        # (ADR-034#reject-as-not-found-not-forbidden), so this
        # runs FIRST — before the rate limiter, before the token is even read.
        # A dark endpoint must not consume the invitee's rate-limit budget or
        # touch invitation state.
        enforce_restrict_to!

        # Rate limiting for noauth endpoint - prevents token enumeration
        client_ip    = @strategy_result&.metadata&.dig(:ip) || @strategy_result&.metadata&.dig('ip') || '0.0.0.0'
        rate_limiter = Onetime::Security::InviteTokenRateLimiter.new(client_ip)
        rate_limiter.check!
        rate_limiter.record_attempt

        raise_form_error('Token is required', field: :token) if @token.nil? || @token.empty?
        raise_form_error('Password is required', field: :password) if @password.empty?

        @invitation = load_invitation(@token)

        # Email is derived from the invitation — not user-provided
        # This prevents email mismatch attacks where a user could try to claim
        # an account with a different email than the one they were invited with
        @email = normalize_email(@invitation.invited_email)

        # Check if organization still exists
        unless @invitation.organization
          raise_form_error('Organization no longer exists', field: :token)
        end

        # Check if invitation is still pending
        raise_already_processed(@invitation) unless @invitation.pending?

        # Check if invitation has expired
        if @invitation.expired?
          raise_form_error('Invitation has expired', field: :token)
        end

        # Validate password BEFORE the account-existence checks (#3856).
        # With this ordering, a request with an invalid password gets the
        # identical password_too_short error whether or not the invited email
        # already has an account — closing the cheap, non-destructive
        # enumeration probe (junk password in, read the error_type out).
        validate_password_requirements!(@password)

        # Check if email already exists in EITHER database (authdb + Redis).
        #
        # Anti-enumeration posture (#3856, aligns with the AZ7 hardening on
        # ShowInvite): the error below is generic — same message and
        # error_type regardless of which store matched — and never carries an
        # account_exists signal. Residual: with a valid password, "exists"
        # (this error) is still distinguishable from "does not exist" (signup
        # succeeds); that is inherent to any signup endpoint and probing it is
        # destructive and noisy — it creates the account and emails the
        # invitee. Compensating control: InviteTokenRateLimiter above.
        if email_exists_in_authdb?(@email) || Onetime::Customer.email_exists?(@email)
          raise_signup_unavailable
        end
      end

      def process
        auth_logger.debug 'Creating account and accepting invitation',
          email: OT::Utils.obscure_email(@email)

        # Create account in authdb via Rodauth internal_request.
        # The after_create_account hook (apps/web/auth/config/hooks/account.rb)
        # handles Customer creation, default workspace, invitation acceptance,
        # and auto-verification at the SQL level — all gated on the
        # invite_token we pass through.
        account_id = create_rodauth_account

        # Refetch the account; external_id is populated by the hook's
        # CreateCustomer linking step.
        account   = Auth::Database.connection[:accounts].where(id: account_id).first
        @customer = Onetime::Customer.find_by_extid(account[:external_id]) if account[:external_id]

        unless @customer
          auth_logger.error 'Customer missing after create_account',
            account_id: account_id
          raise_form_error('Account created but customer record missing', field: :email)
        end

        # Reload the invitation via the still-valid token. The after_create_account
        # hook does not accept the invitation — that's the explicit /accept call
        # the frontend makes next. The invitation must still be pending here.
        org_objid   = @invitation.organization_objid
        @invitation = Onetime::OrganizationMembership.find_by_token(@token)
        if @invitation.nil? || !@invitation.pending?
          auth_logger.error 'Invitation missing or not pending after signup',
            token_prefix: @token[0..7],
            org_objid: org_objid,
            customer_objid: @customer.objid,
            invitation_status: @invitation&.status
          raise_form_error('Invitation no longer available', field: :token)
        end

        setup_session(account_id, account)

        auth_logger.info 'User signed up; invitation pending explicit accept',
          event: 'invite.signup_pending_accept',
          invitation_id: @invitation.objid,
          organization_id: @invitation.organization.extid,
          user: @customer.obscure_email,
          role: @invitation.role,
          result: :success

        success_data
      end

      def success_data
        {
          record: {
            user_id: @customer.extid,
            organization: {
              id: @invitation.organization.extid,
              display_name: @invitation.organization.display_name,
            },
            role: @invitation.role,
            invitation_status: @invitation.status,
            auto_login: true,
          },
        }
      end

      private

      # ADR-034#invite-signup-is-gated (#4139) — the `restrict_to` gate for this endpoint.
      #
      # WHY THIS EXISTS AT ALL. Every other pre-auth password surface is gated
      # by Auth::RestrictTo (Rodauth routes via before_rodauth, simple mode's
      # POST /auth/login via Core::Controllers::Base). This one is reachable by
      # neither: the account is created through Rodauth's internal_request,
      # whose synthesized env carries no Host, and Auth::RestrictTo.
      # enforce_method! deliberately exempts internal requests for exactly that
      # reason (ADR-034#reject-as-not-found-not-forbidden). The exemption is correct — an internal request has
      # no request host to key a host policy on — but it leaves this endpoint,
      # which DOES know the request host, as the one unguarded way to mint a
      # password credential and a session on a host that offers neither.
      #
      # WHY 404 AND NOT "CREATE THE ACCOUNT, SKIP THE AUTOLOGIN". Suppressing
      # only the session looks more forgiving and is strictly worse:
      #
      #   1. It does not preserve the invitation. This endpoint never accepts
      #      the invite (see the class doc — the frontend POSTs /accept next),
      #      and /accept is auth=sessionauth. Without the session the very next
      #      call 401s, so the invite stays pending EITHER WAY. "Account without
      #      session" is not a degraded success; it is this same failure plus an
      #      account nobody asked for.
      #   2. That account actively strands the invitee on an sso-restricted
      #      host. An unauthenticated tenant-SSO callback whose email matches an
      #      existing unlinked account hits the H-3 refusal in
      #      apps/web/auth/config/hooks/omniauth.rb (the password-challenge
      #      interstitial is minted on the PLATFORM surface only) — so the
      #      account we just created is precisely what blocks SSO from creating
      #      a clean one. With no account, SSO signs them in and /accept works.
      #   3. It mints a password credential the install has restricted away —
      #      "configuration presenting as availability", the shape
      #      ADR-034#restrict-to-is-an-access-control-not-a-display-preference
      #      exists to kill.
      #
      # WHERE THE INVITEE GOES INSTEAD. The invitation is untouched and still
      # pending: they authenticate by the method the host does offer (SSO on an
      # sso-restricted host; the canonical host, which is what the invitation
      # email links to, when the restriction is per-domain) and then POST
      # /accept. GET /:token (ShowInvite) and POST /:token/accept are NOT gated
      # and must not be: the first is a display surface, the second is
      # account-scoped and reachable only with a session already established by
      # a permitted method (ADR-034#reject-as-not-found-not-forbidden, scope
      # note).
      #
      # Resolution is NOT re-derived here
      # (ADR-034#resolution-is-model-owned): Auth::RestrictTo owns input
      # gathering (including the custom-domain 'sso' pin and the runtime
      # availability half of ADR-034#degradation-is-fail-closed) and
      # SigninConfig.resolve_restrict_to owns the
      # rule. This asks the same question the sign-in page on this host answers.
      def enforce_restrict_to!
        return if Auth::RestrictTo.allows?(restrict_to_env, 'password')

        Auth::Logging.log_auth_event(
          :restrict_to_route_rejected,
          level: :info,
          route: :invite_signup,
          auth_method: 'password',
          host: display_domain,
        )

        # 404, not 403 (ADR-034#reject-as-not-found-not-forbidden): the reject
        # shape for a restricted-away method is
        # not-found, matching Rodauth's behavior for a feature that was never
        # loaded. No error_key — an undefined route has no bespoke i18n string,
        # and reusing the invite API's "not found or expired" key would assert
        # something false about a token that is perfectly valid.
        raise_not_found('Not found')
      end

      def normalize_email(email)
        OT::Utils.normalize_email(email)
      end

      # Single chokepoint for the "email already has an account" outcome so
      # every path (authdb pre-check, Redis pre-check, Rodauth create race)
      # returns a byte-identical response. Deliberately: no field (the email
      # is token-derived, not a submitted field), a conditional message, and
      # a generic error_type — the frontend keys its sign-in fallback off
      # error_type 'signup_unavailable' without the server confirming that an
      # account exists (#3856).
      def raise_signup_unavailable
        raise_form_error(
          SIGNUP_UNAVAILABLE_MESSAGE,
          error_type: 'signup_unavailable',
        )
      end

      # Check if email exists in authdb (SQLite/PostgreSQL)
      def email_exists_in_authdb?(email)
        normalized = normalize_email(email)
        Auth::Database.connection[:accounts]
          .where(email: normalized)
          .where(Sequel.lit('status_id IN (1, 2)')) # Unverified or Verified (not Closed)
          .any?
      end

      # Validate password meets Rodauth requirements
      def validate_password_requirements!(password)
        # Minimum length check (matches auth config)
        min_length = 8
        return unless password.length < min_length

        raise_form_error(
          "Password must be at least #{min_length} characters",
          field: :password,
          error_type: 'password_too_short',
        )

        # Additional requirements can be added here if login_password_requirements_base
        # is enabled and has specific rules. For now, we match the basic Rodauth config.
      end

      # Create account via Rodauth internal_request
      def create_rodauth_account
        # Use Rodauth's internal_request feature to create the account
        # This ensures password hashing is done correctly (Argon2 in this project)
        #
        # Pass invite_token via params: so send_verify_account_email's suppression
        # branch fires (see apps/web/auth/config/features/account_management.rb).
        # Without this, Rodauth tries to build a verify-account URL and fails on
        # the missing `domain` (internal_request has no HTTP host).
        #
        # Rodauth's internal_request create_account returns nil on success by
        # contract (see rodauth_spec.rb assertions of `must_be_nil`); errors are
        # signalled via Rodauth::InternalRequestError. Look up the account row
        # by email after the call to obtain the account_id.
        Auth::Config.create_account(
          login: normalize_email(@email),
          password: @password,
          params: { 'invite_token' => @token },
        )

        account = Auth::Database.connection[:accounts]
          .where(email: normalize_email(@email)).first

        unless account
          auth_logger.error 'Account row missing after create_account',
            email: OT::Utils.obscure_email(@email)
          raise_form_error('Failed to create account', field: :email)
        end

        account[:id]
      rescue Rodauth::InternalRequestError => ex
        auth_logger.error 'Rodauth internal_request error',
          exception: ex,
          email: OT::Utils.obscure_email(@email),
          token_prefix: @token[0..7]

        # Parse field errors from Rodauth
        if ex.field_errors&.any?
          field, message = ex.field_errors.first
          # An account created between our pre-check and Rodauth's insert
          # surfaces here as "already an account with this login". Map it to
          # the same generic response as the pre-check so the race window
          # doesn't reopen the account-existence oracle (#3856).
          raise_signup_unavailable if message.to_s.match?(/already an account/i)

          # Sentinel error_type so clients keying on it never see it absent
          # from this endpoint. Rodauth doesn't supply machine-readable codes
          # for its validation rules, so a generic sentinel is the best we
          # can forward without message-sniffing.
          raise_form_error(message, field: field.to_sym, error_type: 'validation_error')
        else
          raise_form_error(
            ex.flash || 'Failed to create account',
            field: :email,
            error_type: 'validation_error',
          )
        end
      end

      # Set up session for auto-login
      #
      # Manually populates session fields since we don't have direct access to the
      # Rack request object from the logic layer. This mirrors what SyncSession does.
      #
      def setup_session(account_id, _account)
        # Populate session with authentication state
        sess['authenticated']    = true
        sess['authenticated_at'] = Familia.now.to_i
        sess['account_id']       = account_id
        sess['external_id']      = @customer.extid
        sess['email']            = @customer.email
        sess['role']             = @customer.role
        sess['locale']           = @customer.locale || 'en'

        # Track request metadata from strategy_result
        client_ip          = @strategy_result&.metadata&.dig(:ip) ||
                             @strategy_result&.metadata&.dig('ip') ||
                             '0.0.0.0'
        sess['ip_address'] = client_ip

        # Clear any MFA waiting flags
        sess.delete(:awaiting_mfa)
        sess.delete('awaiting_mfa')

        # Clear rate limiting for this account
        rate_limit_key = "login_attempts:#{@customer.email.to_s.downcase}"
        Familia.dbclient.del(rate_limit_key)

        Auth::Logging.log_auth_event(
          :invite_signup_autologin,
          level: :info,
          email: @customer.email,
          account_id: account_id,
          organization_id: @invitation.organization.extid,
        )
      end
    end
  end
end

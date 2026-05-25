# apps/api/invite/logic/invites/signup_and_accept.rb
#
# frozen_string_literal: true

require 'onetime/security/invite_token_rate_limiter'

module InviteAPI::Logic
  module Invites
    # Atomic signup + invitation acceptance for org invites
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
    # 3. Checks if email exists in EITHER database -> error with signin hint
    # 4. Validates password meets requirements
    # 5. Creates account in authdb via Rodauth internal_request
    # 6. Creates Customer in Redis
    # 7. Creates default workspace
    # 8. Accepts the invitation (adds user to org)
    # 9. Auto-logs in the user
    #
    class SignupAndAccept < InviteAPI::Logic::Base
      include Onetime::LoggerMethods

      attr_reader :invitation, :customer

      def process_params
        @token    = sanitize_identifier(params['token'])
        @password = params['password'].to_s
      end

      def raise_concerns
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
        unless @invitation.pending?
          raise_form_error(
            "Invitation has already been #{@invitation.status}",
            field: :token,
          )
        end

        # Check if invitation has expired
        if @invitation.expired?
          raise_form_error('Invitation has expired', field: :token)
        end

        # Check if email already exists in authdb (SQLite/PostgreSQL)
        if email_exists_in_authdb?(@email)
          raise_form_error(
            'An account with this email already exists. Please sign in instead.',
            field: :email,
            error_type: 'account_exists',
          )
        end

        # Check if email already exists in Redis (Customer)
        if Onetime::Customer.email_exists?(@email)
          raise_form_error(
            'An account with this email already exists. Please sign in instead.',
            field: :email,
            error_type: 'account_exists',
          )
        end

        # Validate password meets requirements
        validate_password_requirements!(@password)
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

        # Reload the invitation to pick up the acceptance state written by the hook.
        # NOTE: cannot use find_by_token here — accept! removes the token from
        # token_lookup (pending-only index, cleared for security). Look up the
        # now-active membership via org_customer_lookup, which accept! populates.
        org_objid   = @invitation.organization_objid
        @invitation = Onetime::OrganizationMembership.find_by_org_customer(
          org_objid,
          @customer.objid,
        )
        if @invitation.nil? || @invitation.pending?
          auth_logger.error 'Invitation not accepted by hook',
            token_prefix: @token[0..7],
            org_objid: org_objid,
            customer_objid: @customer.objid
          raise_form_error('Failed to accept invitation', field: :token)
        end

        setup_session(account_id, account)

        auth_logger.info 'User signed up and joined organization',
          event: 'invite.signup_accepted',
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
            joined_at: @invitation.joined_at,
            auto_login: true,
          },
        }
      end

      private

      def normalize_email(email)
        OT::Utils.normalize_email(email)
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
          raise_form_error(message, field: field.to_sym)
        else
          raise_form_error(ex.flash || 'Failed to create account', field: :email)
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

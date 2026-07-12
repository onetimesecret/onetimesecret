# apps/api/account/logic/account/create_account.rb
#
# frozen_string_literal: true

require 'onetime/logic/signup_config_resolution'

module AccountAPI::Logic
  module Account
    # Create Account
    #
    # @api Creates a new user account with the provided email and password.
    #   Returns a success response regardless of whether the account already
    #   exists to prevent email enumeration. Sends a verification email to
    #   new and unverified accounts.
    class CreateAccount < AccountAPI::Logic::Base
      include Onetime::Logic::SignupConfigResolution

      SCHEMAS = { response: 'createAccount' }.freeze

      using Familia::Refinements::TimeLiterals

      attr_reader :cust, :autoverify, :customer_role, :email, :password, :skill
      attr_accessor :token

      def process_params
        OT.ld "[CreateAccount#process_params] param keys: #{params.keys.sort}"

        # NOTE: The parameter names should match what rodauth uses.
        @email    = sanitize_email(params['login'])
        @password = self.class.normalize_password(params['password'])

        @autoverify = resolve_autoverify

        # This is a hidden field, so it should be empty. If it has a value, it's
        # a simple bot trying to submit the form or similar chicanery. We just
        # quietly redirect to the home page to mimic a successful response.
        @skill = sanitize_plain_text(params['skill'], max_length: 60)
      end

      def raise_concerns
        raise OT::FormError, "You're already signed up" if @strategy_result.authenticated?

        # Security: Email enumeration prevention - don't check if email_exists? in the
        # validation layer. Do it in the  process() method where we can handle both new
        # account creation and existing account scenarios uniformly, returning the same
        # success response in both cases. This prevents attackers from discovering which
        # emails are registered in the system by observing different validation error messages.
        unless valid_email?(email)
          raise_form_error 'Is that a valid email address?',
            error_key: 'api.account.errors.invalid_email',
            field: 'login',
            error_type: 'invalid'
        end
        # Security: reuse `api.account.errors.invalid_email` — identical user-visible
        # text prevents enumeration of which domains are on the signup allowlist.
        # Do not split into a domain-specific key without re-reviewing this threat.
        unless allowed_signup_domain?(email)
          raise_form_error 'Is that a valid email address?',
            error_key: 'api.account.errors.invalid_email',
            field: 'login',
            error_type: 'invalid'
        end
        return if password.size >= 6

        raise_form_error 'Password is too short',
          error_key: 'api.account.errors.password_too_short',
          field: 'password',
          error_type: 'too_short'
      end

      def process
        # Security: Timing-safe account creation to prevent email enumeration
        # Always return the same success message regardless of account existence
        existing_customer = Onetime::Customer.find_by_email(email)

        if existing_customer
          # Account already exists - handle silently without revealing this fact
          @cust = existing_customer

          # If the account is not verified, resend the verification email
          # If verified, we do nothing but still return success
          if @cust.verified
            OT.info "[account-exists-verified] Silent success for #{@cust.obscure_email}"
          else
            OT.info "[account-exists-unverified] Resending verification for #{@cust.obscure_email}"
            # TODO: Re-enable when email verification is active
            send_verification_email
          end

          # Use existing customer attributes
          @customer_role = @cust.role || 'customer'
        else
          # New account creation proceeds normally
          @cust = Onetime::Customer.create!(email: email)

          cust.update_passphrase password

          # New accounts default to 'customer' role. Colonel promotion
          # is handled exclusively via CLI: bin/ots customers role promote user@example.com
          @customer_role = 'customer'

          cust.verified    = @autoverify
          cust.verified_by = 'autoverify' if @autoverify  # Track verification method
          cust.role        = @customer_role

          # Capture the signup domain for re-verification and background jobs,
          # and record the provisioning origin as lifecycle/audit metadata.
          # Origin is metadata only — capabilities are governed by org role.
          custom_domain            = if display_domain
                            Onetime::CustomDomain.load_by_display_domain(display_domain)
                          end
          cust.signup_domain_id    = custom_domain.identifier if custom_domain
          cust.provisioning_origin = if params['invite_token'].to_s.strip != ''
                                       'invite'
                                     elsif custom_domain
                                       'domain_signup'
                                     else
                                       'canonical_signup'
                                     end

          cust.save

          session_id = @strategy_result.session['id']
          ip_address = @strategy_result.metadata['ip']
          OT.info "[new-customer] #{cust.objid} #{cust.role} #{ip_address} #{session_id}"

          # Send verification email for new accounts (unless autoverify is enabled)
          unless @autoverify
            # TODO: Disable mail verification temporarily on feature/1787-dual-auth-modes branch
            delivered = send_verification_email
            unless delivered
              OT.lw "[signup] Verification email failed for #{cust.obscure_email} — account is unverified and cannot sign in. " \
                    'Fix emailer config (EMAILER_MODE/SMTP_HOST), set AUTH_AUTOVERIFY=true, or run: bin/ots customers verify EMAIL'
            end
          end
        end

        success_message = if autoverify
                            I18n.t('web.COMMON.autoverified_success', locale: @locale)
                          else
                            # Security: Return generic success message that doesn't reveal account existence
                            # This message is identical for: new accounts, existing verified, and existing unverified
                            # Note: Even though we say "verification email", we don't reveal if account already exists
                            I18n.t('web.COMMON.signup_success_generic', locale: @locale)
                          end

        @sess['success_message'] = success_message

        success_data
      end

      def success_data
        # Security: Use obscured email to prevent email enumeration.
        # Returning the exact email would confirm account existence.
        { user_id: cust.extid, email: cust.obscure_email, role: customer_role }
      end

      private

      def form_fields
        { email: email }
      end

      # Validates if the email domain is allowed for account creation.
      #
      # Resolution order:
      #   1. Per-domain SignupConfig (if display_domain available and config enabled)
      #   2. Global allowed_signup_domains config (fallback)
      #
      # @param email [String] The email address to validate
      # @return [Boolean] true if domain is allowed or no restrictions configured
      #
      # @note This method is security-sensitive:
      #   - Does not reveal which domains are allowed in error messages
      #   - Uses case-insensitive domain matching
      def allowed_signup_domain?(email)
        Onetime::SignupValidation.valid_signup_email?(email, display_domain: display_domain)
      end

      def signup_config_display_domain
        display_domain
      end

      def signup_config_auth_setting(key)
        site.dig('authentication', key)
      end
    end
  end
end

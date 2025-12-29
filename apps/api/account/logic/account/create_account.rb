# apps/api/account/logic/account/create_account.rb
#
# frozen_string_literal: true

module AccountAPI::Logic
  module Account
    class CreateAccount < AccountAPI::Logic::Base
      using Familia::Refinements::TimeLiterals

      attr_reader :cust, :autoverify, :customer_role, :email, :password, :skill
      attr_accessor :token

      def process_params
        OT.ld "[CreateAccount#process_params] param keys: #{params.keys.sort}"

        # NOTE: The parameter names should match what rodauth uses.
        @email    = params['login'].to_s.downcase.strip
        @password = self.class.normalize_password(params['password'])

        autoverify_setting = site.dig('authentication', 'autoverify')
        @autoverify        = autoverify_setting.to_s.eql?('true') || false

        # This is a hidden field, so it should be empty. If it has a value, it's
        # a simple bot trying to submit the form or similar chicanery. We just
        # quietly redirect to the home page to mimic a successful response.
        @skill = params['skill'].to_s.strip.slice(0, 60)
      end

      def raise_concerns
        raise OT::FormError, "You're already signed up" if @strategy_result.authenticated?

        # Security: Email enumeration prevention - don't check if email_exists? in the
        # validation layer. Do it in the  process() method where we can handle both new
        # account creation and existing account scenarios uniformly, returning the same
        # success response in both cases. This prevents attackers from discovering which
        # emails are registered in the system by observing different validation error messages.
        raise_form_error 'Is that a valid email address?', field: 'login', error_type: 'invalid' unless valid_email?(email)
        # Security: Use generic error message to prevent domain enumeration
        raise_form_error 'Is that a valid email address?', field: 'login', error_type: 'invalid' unless allowed_signup_domain?(email)
        raise_form_error 'Password is too short', field: 'password', error_type: 'too_short' unless password.size >= 6
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

          colonels       = OT.conf.dig('site', 'authentication', 'colonels')
          @customer_role = if colonels&.member?(cust.custid)
                             'colonel'
                           else
                             'customer'
                           end

          cust.verified    = @autoverify
          cust.verified_by = 'autoverify' if @autoverify  # Track verification method
          cust.role        = @customer_role
          cust.save

          session_id = @strategy_result.session[:id]
          ip_address = @strategy_result.metadata[:ip]
          OT.info "[new-customer] #{cust.objid} #{cust.role} #{ip_address} #{session_id}"

          # Send verification email for new accounts (unless autoverify is enabled)
          unless @autoverify
            # TODO: Disable mail verification temporarily on feature/1787-dual-auth-modes branch
            send_verification_email
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
        { user_id: cust.objid, email: cust.email, role: customer_role }
      end

      private

      def form_fields
        { email: email }
      end

      # Validates if the email domain is allowed for account creation
      #
      # @param email [String] The email address to validate
      # @return [Boolean] true if domain is allowed or no restrictions configured
      #
      # @note This method is security-sensitive:
      #   - Returns true when no restrictions are configured (default behavior)
      #   - Returns false for malformed emails (no @ or empty domain)
      #   - Uses case-insensitive domain matching
      #   - Does not reveal which domains are allowed in error messages
      def allowed_signup_domain?(email)
        allowed_domains = OT.conf.dig('site', 'authentication', 'allowed_signup_domains')

        # No restrictions configured - allow all domains
        return true if allowed_domains.nil? || allowed_domains.empty?

        # Extract domain from email, handling edge cases
        email_parts = email.to_s.strip.downcase.split('@')

        # Reject malformed emails (no @ symbol or multiple @ symbols)
        return false if email_parts.length != 2

        email_domain = email_parts.last

        # Reject emails with empty domain (e.g., "user@")
        return false if email_domain.nil? || email_domain.empty?

        # Case-insensitive domain matching
        normalized_domains = allowed_domains.compact.map(&:downcase)
        normalized_domains.include?(email_domain)
      end
    end
  end
end

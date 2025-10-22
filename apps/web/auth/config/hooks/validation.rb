# frozen_string_literal: true

#
# apps/web/auth/config/hooks/validation.rb
#
# This file defines Rodauth hooks for input validation, primarily focusing
# on email validation during the account creation process.
#

module Auth
  module Config
    module Hooks
      module Validation
        #
        # Configuration
        #
        # This method returns a proc that Rodauth will execute to configure
        # the validation hooks.
        #
        def self.configure
          proc do
            #
            # Hook: Before Account Creation
            #
            # This hook is triggered before a new account is created. It performs
            # several validation checks on the provided email address.
            #
            before_create_account do
              email = param('login') || param('email')

              # 1. Presence Check
              # Ensure an email address was actually provided.
              unless email && !email.to_s.strip.empty?
                throw_error_status(422, 'login', 'Email is required')
              end

              # 2. Email Format and Deliverability Validation (Truemail)
              # Use the Truemail gem to perform deep validation on the email address.
              begin
                validator = Truemail.validate(email)
                unless validator.result.valid?
                  OT.info "[auth] Invalid email rejected: #{OT::Utils.obscure_email(email)}"
                  throw_error_status(422, 'login', 'Please enter a valid email address')
                end
              rescue StandardError => ex
                OT.le "Email validation error",
                  email: OT::Utils.obscure_email(email),
                  exception: ex,
                  context: "auth",
                  note: "Failing open on validation errors - consider hard failure for higher security"
                # Fail open on validation errors, but notify for investigation.
                # For higher security, this could be changed to a hard failure.
                throw_error_status(422, 'login', 'There was a problem validating your email. Please try again.')
              end

              # 3. Uniqueness Check
              # Rodauth handles the final uniqueness check, but we log here to
              # provide visibility into attempts to create accounts with duplicate emails.
              if db[:accounts].where(email: email, status_id: [1, 2]).first # 1=Unverified, 2=Verified
                OT.info "[auth] Account creation blocked for duplicate email: #{OT::Utils.obscure_email(email)}"
              end
            end
          end
        end
      end
    end
  end
end

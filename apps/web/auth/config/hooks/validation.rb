# apps/web/auth/config/hooks/validation.rb

module Auth
  module Config
    module Hooks
      module Validation
        def self.configure
          proc do
            # Email validation using Truemail before account creation
            before_create_account do
              email = param('login') || param('email')

              unless email && !email.to_s.strip.empty?
                throw_error_status(422, 'login', 'Email is required')
              end

              begin
                validator = Truemail.validate(email)
                unless validator.result.valid?
                  OT.info "[auth] Invalid email rejected: #{OT::Utils.obscure_email(email)}"
                  throw_error_status(422, 'login', 'Please enter a valid email address')
                end
              rescue StandardError => ex
                OT.le "[auth] Email validation error: #{ex.message}"
                throw_error_status(422, 'login', 'Email validation failed')
              end
            end
          end
        end
      end
    end
  end
end

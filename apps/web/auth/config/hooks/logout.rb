# apps/web/auth/config/hooks/login.rb

module Auth
  module Config
    module Hooks
      module Logout
        def self.configure(auth)

          #
          # Hook: Before Logout
          #
          # This hook is triggered just before the session is destroyed on logout.
          #
          auth.before_logout do
            OT.info "[auth] User logging out: #{session['email'] || 'unknown'}"
          end

          #
          # Hook: After Logout
          #
          # This hook is triggered after the user has been logged out.
          #
          auth.after_logout do
            OT.info '[auth] Logout complete'
          end

        end
      end
    end
  end
end

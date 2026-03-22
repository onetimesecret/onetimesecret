# lib/onetime/logic/sso_only_gating.rb
#
# frozen_string_literal: true

module Onetime
  module Logic
    # Concern for enforcing SSO-only mode restrictions in API logic classes.
    #
    # When SSO-only mode is active (AUTH_SSO_ONLY=true and AUTH_SSO_ENABLED=true),
    # password-based account management operations are disabled. Users must
    # manage their credentials through the SSO identity provider instead.
    #
    # Blocked operations:
    # - Account destruction (POST /destroy)
    # - Password changes (POST /change-password)
    # - Email changes (POST /change-email)
    # - Email change confirmation (POST /confirm-email-change)
    # - Resend email change confirmation (POST /resend-email-change-confirmation)
    #
    # Usage in raise_concerns:
    #
    #   def raise_concerns
    #     require_non_sso_only!
    #     super
    #   end
    #
    module SsoOnlyGating
      # Raise Forbidden if SSO-only mode is active.
      #
      # @raise [Onetime::Forbidden] If sso_only_enabled? is true
      # @return [true] If check passes (SSO-only not active)
      def require_non_sso_only!
        return true unless Onetime.auth_config.sso_only_enabled?

        raise Onetime::Forbidden, 'This action is not available in SSO-only mode'
      end
    end
  end
end

# lib/onetime/logic/sso_only_gating.rb
#
# frozen_string_literal: true

module Onetime
  module Logic
    # Concern for enforcing SSO-only mode restrictions in API logic classes.
    #
    # Keys off AuthConfig#sso_only_enabled? — the global restriction, i.e.
    # `full.restrict_to == 'sso'` (rendered from AUTH_SSO_ONLY=true, or set
    # directly). A global restriction naming an unavailable method is a fatal
    # boot error, so by the time this concern runs the restriction is honorable;
    # the predicate is a bare comparison with no availability guard of its own
    # (ADR-034#degradation-is-fail-closed).
    #
    # When it is active, password-based account management operations are
    # disabled. Users must manage their credentials through the SSO identity
    # provider instead.
    #
    # These endpoints are account-scoped, not host-scoped, so they are
    # explicitly EXEMPT from host-scoped restrict_to route enforcement
    # (ADR-034#reject-as-not-found-not-forbidden) and are governed by this
    # concern instead — hence 403 here rather than the 404 the route gate
    # returns. A per-domain restrict_to never reaches this check.
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

        raise Onetime::Forbidden.new(
          'This action is not available in SSO-only mode',
          error_key: 'api.errors.sso_only_action_blocked',
        )
      end
    end
  end
end

# apps/web/auth/config/overrides/public_base_url.rb
#
# frozen_string_literal: true

require_relative '../../lib/public_host'

module Auth::Config::Overrides
  # Rodauth credential links and their branding use the recipient account's
  # authorized tenant origin, or a configured canonical origin. A verified
  # custom domain is insufficient without active membership authorizing that
  # exact domain. SSO and WebAuthn keep their browser-origin resolvers.
  #
  # Nonmember tenant requests receive canonical links, including ordinary
  # password signups: their personal workspace is not membership in the tenant
  # organization. This resolver does not check destination route availability
  # or widen its policy. Global sign-in flags gate tenants too; disabling them
  # does not create a tenant-only password/email deployment.
  module PublicBaseUrl
    module ResetPasswordOrigin
      # Also protect direct/internal key creation, before INSERT or updating an
      # existing key's email_last_sent; an email-time failure alone is too late.
      #
      # On the public request route the refusal depends on the recipient
      # (membership), so it answers with the generic response used for missing,
      # unopen and throttled accounts (ResetPasswordEnumeration). A 500 here
      # would tell an unauthenticated caller the login names an open account.
      # Halts before the key write; direct/internal callers still get the raise.
      def create_reset_password_key
        begin
          base_url
        rescue Auth::PublicHost::MissingAllowlistedOrigin
          raise unless current_route == :reset_password_request

          Auth::Logging.log_auth_event(
            :reset_password_request_no_credential_origin,
            level: :error,
            account_id: account_id,
          )
          reset_password_email_sent_response
        end
        super
      end
    end

    def self.configure(auth)
      auth.base_url do
        Auth::PublicHost.required_credential_base_url!(request.env, account)
      end

      auth_class = auth.instance_variable_get(:@auth)
      if auth_class&.features&.include?(:reset_password)
        auth.auth_class_eval { prepend Auth::Config::Overrides::PublicBaseUrl::ResetPasswordOrigin }
      end

      # rubocop:disable-next Lint/NestedMethodDefinition -- Rodauth's auth_class_eval pattern
      auth.auth_class_eval do
        # Brand credential emails with the same recipient-bound origin.
        def public_display_domain
          Auth::PublicHost.credential_display_host(request.env, account)
        end
      end
    end
  end
end

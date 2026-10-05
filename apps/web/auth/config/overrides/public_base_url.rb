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
  # Public nonmember tenant requests therefore receive canonical links. On
  # tenant-only password/email deployments, canonical redemption must already
  # be enabled; this override does not widen any sign-in route policy.
  module PublicBaseUrl
    module ResetPasswordOrigin
      # Also protect direct/internal key creation, before INSERT or updating an
      # existing key's email_last_sent; an email-time failure alone is too late.
      def create_reset_password_key
        base_url
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

# apps/web/auth/config/json_mode.rb
#
# frozen_string_literal: true

#
# Single owner of the `only_json?` Rodauth setter.
#
# Background: rodauth defines `only_json?` via `def_auth_value_method`, which
# calls `define_method` on the Auth::Config class. Each `auth.only_json? do ... end`
# call therefore REPLACES the previous definition — there is no super chain
# to compose multiple blocks. Before this module existed, the OAuth hook's
# `only_json?` block silently overwrote OmniAuth's, causing SSO callbacks
# to be rejected with a 400 when both `AUTH_SSO_ENABLED` and
# `AUTH_OAUTH_ENABLED` were true.
#
# This module is the single place that defines `only_json?`. It consults
# OAUTH_EXEMPT_PATHS (from Hooks::OAuth) and `omniauth_prefix` (from the
# omniauth feature, when loaded) to compute the exempt set. It is invoked
# from apps/web/auth/config.rb AFTER all hooks have run so the
# constants/methods it queries are in scope.
#
# This module lives under `Auth::JsonMode` (not `Auth::Config::JsonMode`) so
# it doesn't need to reopen the Auth::Config class — keeps test isolation
# simpler since some specs stub `Auth::Config` as a module.
#
# Adding a new exemption source:
#   1. Add a path-source constant on the relevant hook module.
#   2. Add the lookup to `exempt?` below.
#

module Auth
  module JsonMode
    def self.configure(auth)
      auth.only_json? do
        !Auth::JsonMode.exempt?(self)
      end
    end

    # Called per-request from the `only_json?` block above.
    # `rodauth_instance` is the Rodauth::Auth instance handling the request.
    def self.exempt?(rodauth_instance)
      path   = rodauth_instance.request.path
      prefix = Auth::Application.uri_prefix

      return true if oauth_exempt?(path, prefix)
      return true if sso_exempt?(rodauth_instance, path, prefix)

      false
    end

    def self.oauth_exempt?(path, prefix)
      return false unless defined?(Auth::Config::Hooks::OAuth::OAUTH_EXEMPT_PATHS)

      Auth::Config::Hooks::OAuth::OAUTH_EXEMPT_PATHS.any? do |p|
        full = "#{prefix}#{p}"
        path == full || path.start_with?("#{full}/")
      end
    end

    def self.sso_exempt?(rodauth_instance, path, prefix)
      return false unless rodauth_instance.respond_to?(:omniauth_prefix)

      full_sso_prefix = "#{prefix}#{rodauth_instance.omniauth_prefix}"
      # Trailing slash check prevents matching unrelated paths like /auth/sso-admin.
      path == full_sso_prefix || path.start_with?("#{full_sso_prefix}/")
    end
  end
end

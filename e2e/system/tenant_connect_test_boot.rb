# frozen_string_literal: true

# Test-process-only boot shim for the Playwright tenant Connect acceptance
# project. Load with RUBYOPT=-r./e2e/system/tenant_connect_test_boot.rb.
#
# It does exactly one thing: put OmniAuth into test mode with a mock auth hash
# for the E2E_TENANT_CONNECT_{PROVIDER,UID,IDP_EMAIL,ISSUER} tuple, so the
# tenant OIDC route (registered by the application itself under
# ORGS_SSO_ENABLED=true) completes its callback without a live IdP.
#
# It does NOT touch the tenant Connect kill switch
# (Auth::Config::Hooks::OmniAuthConnect.tenant_connect_enabled?). That returns
# true in the application since #4427; the journey runs against the real
# value. If the switch is ever closed for incident response, this lane fails
# with tenant_connect_prerequisites_incomplete, which is the correct signal.
#
# No production configuration surface: refuses to load unless both the test
# environment and the explicit arming flag are present.

unless ENV['RACK_ENV'] == 'test' && ENV['E2E_TENANT_CONNECT_ARMED'] == '1'
  abort 'tenant Connect E2E boot shim requires RACK_ENV=test and E2E_TENANT_CONNECT_ARMED=1'
end

require 'omniauth'

provider = ENV.fetch('E2E_TENANT_CONNECT_PROVIDER', 'oidc')
uid      = ENV.fetch('E2E_TENANT_CONNECT_UID')
email    = ENV.fetch('E2E_TENANT_CONNECT_IDP_EMAIL')
issuer   = ENV.fetch('E2E_TENANT_CONNECT_ISSUER')

OmniAuth.config.test_mode                  = true
OmniAuth.config.allowed_request_methods    = [:get, :post]
OmniAuth.config.mock_auth[provider.to_sym] = OmniAuth::AuthHash.new(
  provider: provider,
  uid: uid,
  info: { email: email, name: 'Tenant Connect E2E', email_verified: true },
  extra: { raw_info: { sub: uid, email: email, email_verified: true, iss: issuer } },
)

# Marker the CI workflow greps for in the server log to prove this shim loaded
# into the server process (a server booted without it would try to reach the
# fictional issuer at callback time and fail one step from the end).
warn "[tenant_connect_test_boot] OmniAuth test mode armed for provider '#{provider}' (issuer #{issuer})"

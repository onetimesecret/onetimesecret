# frozen_string_literal: true

# Test-process-only boot shim for the Playwright tenant Connect acceptance
# project. Load with RUBYOPT=-r./e2e/system/tenant_connect_test_boot.rb.
# It has no production configuration surface and refuses to load unless both
# the test environment and the explicit arming flag are present.

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

# The production method remains hard-coded false. Trace the definition of its
# containing module and replace it only in this explicitly armed Ruby process.
gate_override = nil
gate_override = TracePoint.new(:end) do
  next unless defined?(Auth::Config::Hooks::OmniAuthConnect)

  Auth::Config::Hooks::OmniAuthConnect.define_singleton_method(:tenant_connect_enabled?) { true }
  gate_override.disable
end
gate_override.enable

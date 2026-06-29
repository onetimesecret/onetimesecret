# apps/web/auth/spec/integration/full/resend_verify_account_internal_request_spec.rb
#
# frozen_string_literal: true

# Mechanism guard for the "resend verification email" recovery flow.
#
# The backend logic (AccountAPI::Logic::Account::ResendVerifyAccount) delegates
# to Rodauth's verify_account feature via internal_request:
#
#     Auth::Config.verify_account_resend(login: <email>)
#
# This spec isolates the internal-request MECHANISM from the HTTP layer. It is
# the FIRST place a method-name regression surfaces: if rodauth (or a gem bump)
# renames the internal-request method, `Auth::Config.respond_to?(...)` flips and
# this fails before any route spec does.
#
# -----------------------------------------------------------------------------
# Setup mirrors the sibling internal_request specs in this directory (e.g.
# internal_request_trace_spec.rb): an explicit before(:all) force-boot plus
# Registry.prepare_application_registry, referencing Auth::Config directly.
#
# Boot-time reality: the verify_account feature — and therefore the
# verify_account_resend internal-request method — is only enabled when
# Onetime.auth_config.verify_account_enabled? is true. Under RACK_ENV=test the
# defaults YAML forces that false, so the method is typically absent here. We
# detect that and skip the "method exists" assertion rather than fail in a
# feature-disabled boot; the assertion runs (and guards the contract) in any
# environment where verify_account is enabled at boot.
# -----------------------------------------------------------------------------

require_relative '../../spec_helper'

RSpec.describe 'Auth::Config.verify_account_resend internal_request', type: :integration do
  before(:all) do
    require 'onetime'
    require 'onetime/application/registry'
    require 'onetime/auth_config'

    Onetime.boot!(:test, force: true)
    Onetime::Application::Registry.prepare_application_registry
  end

  def verify_account_enabled_at_boot?
    Onetime.auth_config.respond_to?(:verify_account_enabled?) &&
      Onetime.auth_config.verify_account_enabled?
  end

  it 'exposes verify_account_resend as a callable internal_request method when verify_account is enabled' do
    unless verify_account_enabled_at_boot?
      skip 'verify_account feature disabled at boot (RACK_ENV=test); ' \
           'internal_request method only registered when the feature is enabled'
    end

    # The single, load-bearing mechanism assertion: the method the backend logic
    # calls must exist on the Auth::Config class. internal_request exposes each
    # rodauth route method (here verify_account_resend) as a class method.
    expect(Auth::Config).to respond_to(:verify_account_resend)
  end

  it 'keeps the InternalRequest namespace available for the verify_account flow' do
    # internal_request is enabled unconditionally (base.rb: auth.enable
    # :internal_request), independent of verify_account. This guards that the
    # mechanism the backend relies on is present regardless of feature flags.
    expect(defined?(Auth::Config)).to be_truthy
    expect(Auth::Config.const_defined?(:InternalRequest)).to be(true)
  end
end

# apps/web/auth/spec/integration/full/omniauth_callback_wrapper_order_spec.rb
#
# frozen_string_literal: true

# =============================================================================
# TEST TYPE: Runtime configuration guard (#4432)
# =============================================================================
#
# WHAT THIS TESTS:
#   The wrapper half of the hook-ownership invariant in
#   apps/web/auth/config/hooks.rb, on the CONFIGURED auth class:
#
#     1. exactly one application module wraps before_omniauth_callback_route,
#        and it is Auth::Config::Hooks::OmniAuthConnect::Callback;
#     2. it is prepended, so it runs AHEAD of the registered hook — the gem's
#        hook method reaches the registered block through
#        _before_omniauth_callback_route, which only happens once the wrapper
#        calls `super`;
#     3. the registered block is the one in hooks/omniauth_tenant.rb.
#
# WHY IT IS NOT ONLY STATIC:
#   spec/config/hook_ownership_spec.rb scans apps/web/auth/config/** and pins
#   which modules may define the method. It cannot see a module defined
#   outside that tree, one built with define_method, or the ORDER in which
#   modules end up in the ancestor chain. The ancestor chain can.
#
# REQUIREMENTS:
#   A full lane with ORGS_SSO_ENABLED=true (tests/lanes/run full-sqlite), so
#   the :omniauth feature — and with it the prepend — is configured.
#
# =============================================================================

require_relative '../../spec_helper'

RSpec.describe 'OmniAuth callback hook wrapper order (#4432)', type: :integration do
  hook       = :before_omniauth_callback_route
  registered = :_before_omniauth_callback_route

  before(:all) { boot_onetime_app }

  before do
    skip 'the :omniauth feature is not configured in this lane' unless Auth::Config.features.include?(:omniauth)
  end

  # Every ancestor that itself defines `name`, in method-resolution order.
  def definers_of(name, klass = Auth::Config)
    klass.ancestors.select do |ancestor|
      ancestor.private_instance_methods(false).include?(name) ||
        ancestor.public_instance_methods(false).include?(name) ||
        ancestor.protected_instance_methods(false).include?(name)
    end
  end

  def application_code?(mod)
    locations = mod.instance_methods(false).concat(mod.private_instance_methods(false))
      .filter_map { |name| mod.instance_method(name).source_location&.first }
    locations.any? { |path| !path.include?('/gems/') }
  end

  it 'configures the omniauth feature in the SSO-enabled lanes (the guard is not skipped there)' do
    skip 'ORGS_SSO_ENABLED is not set in this lane' unless ENV['ORGS_SSO_ENABLED'] == 'true'

    expect(Auth::Config.features).to include(:omniauth)
  end

  it 'has exactly one application wrapper around the hook, the Connect callback' do
    wrappers = definers_of(hook).select { |mod| application_code?(mod) }

    expect(wrappers).to eq([Auth::Config::Hooks::OmniAuthConnect::Callback]),
      "before_omniauth_callback_route is wrapped by #{wrappers.inspect}. Wrappers chain through " \
      '`super` in this order; adding one is an ownership decision — see apps/web/auth/config/hooks.rb.'
  end

  it 'runs the Connect wrapper first: prepended ahead of the auth class and of the gem hook method' do
    ancestors = Auth::Config.ancestors
    callback  = Auth::Config::Hooks::OmniAuthConnect::Callback

    expect(definers_of(hook).first).to eq(callback)
    expect(ancestors.index(callback)).to be < ancestors.index(Auth::Config)
    expect(Auth::Config.instance_method(hook).owner).to eq(callback)
    # `super` from the wrapper lands in the gem's hook method, which is what
    # calls the registered block.
    expect(Auth::Config.instance_method(hook).super_method.source_location.first).to include('/gems/')
  end

  it 'keeps omniauth_tenant.rb the registered owner the wrapper hands over to' do
    expect(definers_of(registered).first).to eq(Auth::Config)
    expect(Auth::Config.instance_method(registered).source_location.first)
      .to end_with('apps/web/auth/config/hooks/omniauth_tenant.rb')
  end

  it 'detects a second prepended wrapper (the check is not vacuous)' do
    intruder = Module.new do
      # A wrapper that only calls super IS the fixture: its presence in the
      # ancestor chain is what the check must see.
      def before_omniauth_callback_route = super # rubocop:disable Lint/UselessMethodDefinition
    end
    subclass = Class.new(Auth::Config) { prepend intruder }

    wrappers = definers_of(hook, subclass).select { |mod| application_code?(mod) }

    expect(wrappers).to eq([intruder, Auth::Config::Hooks::OmniAuthConnect::Callback])
  end
end

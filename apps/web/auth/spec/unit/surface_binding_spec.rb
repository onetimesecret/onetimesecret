# apps/web/auth/spec/unit/surface_binding_spec.rb
#
# frozen_string_literal: true

# Unit tests for the update_session surface stamp (#4409).
#
# Rodauth's `login_session` runs `update_session` on EVERY path that mints an
# authenticated session — the login route family AND the autologins
# (create_account / verify_account / reset_password, remember's load_memory)
# that never fire after_login. The override prepends a module ahead of the
# auth class so it chains with the active-sessions `def update_session`
# rather than replacing it. These examples pin the module's contract against
# a stand-in class shaped like the Rodauth instance: `session`, `request.env`,
# a private `internal_request?`, and a base `update_session` to reach via
# `super`.
#
# Run:
#   pnpm run test:rspec apps/web/auth/spec/unit/surface_binding_spec.rb

require_relative '../spec_helper'

require 'onetime/session/surface'

module Auth; end
Auth.const_set(:Config, Class.new(Rodauth::Auth)) unless defined?(Auth::Config)
Auth::Config.const_set(:Overrides, Module.new) unless Auth::Config.const_defined?(:Overrides, false)

require_relative '../../config/overrides/surface_binding'

RSpec.describe Auth::Config::Overrides::SurfaceBinding::UpdateSession do
  # The base class stands in for the auth class WITH the active-sessions
  # override already applied: its update_session is the one `super` reaches.
  let(:base_class) do
    Class.new do
      attr_reader :session, :request, :calls

      def initialize(env, internal: false)
        @session  = {}
        @request  = Struct.new(:env).new(env)
        @calls    = []
        @internal = internal
      end

      def update_session
        calls << :base_update_session
        session['account_id'] = 42
      end

      private

      def internal_request?
        @internal
      end
    end
  end

  let(:klass) do
    mod = described_class
    Class.new(base_class) { prepend mod }
  end

  it 'runs the base update_session first, then stamps the request surface' do
    auth = klass.new({ 'onetime.domain_strategy' => :canonical })
    auth.update_session

    expect(auth.calls).to eq([:base_update_session])
    expect(auth.session['account_id']).to eq(42)
    expect(auth.session[Onetime::SessionSurface::KEY]).to eq(Onetime::SessionSurface::CANONICAL)
  end

  it 'stamps a custom surface keyed by CustomDomain#identifier' do
    auth = klass.new(
      {
        'onetime.domain_strategy' => :custom,
        'onetime.display_domain' => 'secrets.tenant.example',
        'onetime.custom_domain_id' => 'cd_abc123',
      },
    )
    auth.update_session

    expect(auth.session[Onetime::SessionSurface::KEY]).to eq({ 'kind' => 'custom', 'id' => 'cd_abc123' })
  end

  it 'stamps nil (fail closed) when the request surface is unresolved' do
    auth = klass.new({ 'onetime.domain_strategy' => :invalid })
    auth.update_session

    expect(auth.session).to have_key(Onetime::SessionSurface::KEY)
    expect(auth.session[Onetime::SessionSurface::KEY]).to be_nil
  end

  it 'leaves an internal request session unstamped (no marker key at all)' do
    auth = klass.new({ 'onetime.domain_strategy' => :canonical }, internal: true)
    auth.update_session

    expect(auth.calls).to eq([:base_update_session])
    expect(auth.session).not_to have_key(Onetime::SessionSurface::KEY)
  end

  it 'uses string keys so the marker survives the JSON session codec' do
    auth = klass.new({ 'onetime.domain_strategy' => :canonical })
    auth.update_session

    round_tripped = JSON.parse(JSON.generate(auth.session))
    expect(round_tripped[Onetime::SessionSurface::KEY]).to eq(Onetime::SessionSurface::CANONICAL)
  end

  describe '.configure' do
    it 'prepends the module so it chains ahead of a class-level update_session' do
      auth_class   = Class.new(base_class)
      configurator = Class.new do
        def initialize(auth_class)
          @auth_class = auth_class
        end

        def auth_class_eval(&)
          @auth_class.class_eval(&)
        end
      end

      Auth::Config::Overrides::SurfaceBinding.configure(configurator.new(auth_class))

      expect(auth_class.ancestors.index(described_class)).to be < auth_class.ancestors.index(auth_class)
      expect(auth_class.instance_method(:update_session).owner).to eq(described_class)
    end
  end
end

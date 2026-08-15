# spec/unit/onetime/application/middleware_manifest_spec.rb
#
# frozen_string_literal: true

require 'spec_helper'

# Middleware Manifest — characterization spec (refactor step 4)
#
# Snapshots the resolved Rack middleware for every Onetime Application
# subclass so that ANY drift in a middleware stack shows up as a reviewed
# spec diff instead of a silent runtime change. It characterizes TODAY'S
# behavior; it does not assert that today's behavior is correct.
#
# Two sections, mirroring how Base#build_rack_app assembles a stack
# (lib/onetime/application/base.rb):
#
#   1. The universal MiddlewareStack (MiddlewareStack.configure) — identical
#      for every app, captured once with a recorder in place of Rack::Builder.
#   2. Each application class's class-level middleware (registered via `use`
#      in the class body, read back via `.resolved_middleware`, which walks
#      the ancestor chain), plus each class's declared middleware profile.
#
# ============================================================================
# PROMINENT BLIND-SPOT WARNING (issue #4170)
# ============================================================================
# Some apps register middleware inside `Onetime.production? do ... use ... end`
# (and `Onetime.development? do ... end`) blocks — e.g.
# apps/web/auth/application.rb wraps Rack::Deflater and five
# Rack::Protection::* middlewares in a production-only block, and
# apps/web/core/application.rb wraps ViteProxy/SchemaValidator in a
# development-only block. Those blocks execute at CLASS-LOAD time, so under
# RACK_ENV=test they simply never run and the middleware is ABSENT from
# `.middleware`. This spec therefore CANNOT see production-only middleware:
# the snapshots below are the test-environment view, and the production /auth
# stack differs from what is recorded here. That environment-dependent,
# load-time-conditional registration is exactly the bug class the later
# registry/profile refactor removes. Step 3 of that refactor is EXPECTED to
# change these snapshots deliberately — update them in the same reviewed diff.
#
# A second blind spot this spec previously made visible is now FIXED (#4170
# step 2): `middleware` is a plain class-ivar reader and does not inherit, so
# BaseJSONAPI's `use Rack::JSONBodyParser` was dead code for its subclasses.
# `build_rack_app` now reads `resolved_middleware` (ancestor-chain walk,
# superclass entries first), and BaseJSONAPI's dead `use` line was removed in
# the same change so today's resolved stacks stay EXACTLY the same. This spec
# snapshots `resolved_middleware` — the list build_rack_app actually mounts.
#
# NOTE on Auth::Application: apps/web/auth/application.rb requires
# apps/web/auth/config.rb, whose header explicitly forbids requiring it from
# tests (it triggers the full boot chain: database.rb, production config,
# database connections). The Auth app is therefore NOT loaded or manifested
# here; its test-env class-level list would in any case show only
# Rack::JSONBodyParser, with the entire production security block invisible
# (see the blind-spot warning above).
RSpec.describe 'Middleware manifest (characterization)' do
  # Minimal stand-in for Rack::Builder: records what MiddlewareStack.configure
  # would mount without instantiating any middleware or booting an app.
  class MiddlewareRecorder
    attr_reader :used, :ran, :mapped, :warmups

    def initialize
      @used    = []
      @ran     = []
      @mapped  = []
      @warmups = []
    end

    def use(klass, *args, &blk)
      @used << klass
    end

    def run(app)
      @ran << app
    end

    def map(path, &blk)
      @mapped << path
    end

    def warmup(&blk)
      @warmups << blk
    end
  end

  describe 'universal MiddlewareStack (MiddlewareStack.configure)' do
    subject(:recorded_names) do
      recorder = MiddlewareRecorder.new
      Onetime::Application::MiddlewareStack.configure(
        recorder,
        application_context: { name: 'ManifestSpec', prefix: '/manifest-spec' },
      )
      recorder.used.map(&:name)
    end

    it 'mounts exactly the known universal middleware, in order' do
      # Conditional mounts, as resolved under the test config
      # (spec/config.test.yaml + spec/logging.test.yaml):
      #   - Onetime::Application::RequestLogger: absent (logging http.enabled: false)
      #   - Sentry::Rack::CaptureExceptions: absent (diagnostics not initialized
      #     in unit tests; Onetime.with_diagnostics yields only after boot
      #     enables d9s)
      expect(recorded_names).to eq [
        'Onetime::Middleware::AssumeHttps',
        'Otto::Security::Middleware::IPPrivacyMiddleware',
        'Onetime::Middleware::IPBan',
        'Onetime::Middleware::HealthAccessControl',
        'Rack::ContentLength',
        'Onetime::Middleware::StartupReadiness',
        'Rack::DetectHost',
        'Onetime::Middleware::AdminNetworkIsolation',
        'Rack::RequestId',
        'Onetime::Middleware::NormalizeContentType',
        'Rack::Parser',
        'Onetime::Session',
        'Onetime::Middleware::SessionSkip',
        'Onetime::Middleware::IdentityResolution',
        'Onetime::Middleware::EntitlementPreviewContext',
        'Otto::Locale::Middleware',
        'Middleware::I18nLocale',
        'Onetime::Middleware::DomainStrategy',
        'Onetime::Middleware::RetryAfterHeader',
        'Onetime::Middleware::CsrfResponseHeader',
        'Onetime::Middleware::Security',
      ]
    end

    it 'only records `use` calls (no run/map/warmup at the universal layer)' do
      recorder = MiddlewareRecorder.new
      Onetime::Application::MiddlewareStack.configure(
        recorder,
        application_context: { name: 'ManifestSpec', prefix: '/manifest-spec' },
      )
      expect(recorder.ran).to be_empty
      expect(recorder.mapped).to be_empty
      expect(recorder.warmups).to be_empty
    end
  end

  describe 'class-level middleware per application' do
    # Load every Application subclass that is safe to require under test
    # config (no Redis/network/database needed at require time).
    # spec_helper already puts apps/api and apps/web on the load path and
    # requires core/application + account/application itself.
    before(:all) do
      %w[
        core/application
        billing/application
        v1/application
        v2/application
        v3/application
        account/application
        colonel/application
        domains/application
        incoming/application
        invite/application
        organizations/application
      ].each { |f| require f }
      require File.join(Onetime::HOME, 'apps', 'internal', 'acme', 'application')
    end

    # Expected manifest: app class name => class-level middleware class names,
    # in registration order, as resolved under RACK_ENV=test. Entries wrapped
    # in environment-conditional blocks in the class bodies are absent here —
    # see the blind-spot warning at the top of this file.
    EXPECTED_CLASS_LEVEL_MIDDLEWARE = {
      # Onetime.development? block (ViteProxy, SessionDebugger,
      # SchemaValidator) absent under test.
      'Core::Application' => [
        'Core::Middleware::RequestSetup',
        'Core::Middleware::ErrorHandling',
        'Onetime::Middleware::StaticFiles',
      ],
      'Billing::Application' => [],
      'V1::Application' => ['Rack::JSONBodyParser'],
      'V2::Application' => ['Rack::JSONBodyParser'],
      # BaseJSONAPI's former `use Rack::JSONBodyParser` was dead (it never
      # inherited and the class is abstract); now that resolution DOES inherit,
      # the line was removed so subclasses still resolve to [] (header note).
      'BaseJSONAPI' => [],
      'V3::Application' => [],
      'AccountAPI::Application' => [],
      'ColonelAPI::Application' => [],
      'DomainsAPI::Application' => [],
      'Incoming::Application' => [],
      'InviteAPI::Application' => [],
      'OrganizationAPI::Application' => [],
      'Internal::ACME::Application' => ['Internal::ACME::LocalhostOnly'],
    }.freeze

    EXPECTED_CLASS_LEVEL_MIDDLEWARE.each do |class_name, expected|
      it "#{class_name} resolves exactly #{expected.inspect}" do
        klass  = Object.const_get(class_name)
        actual = klass.resolved_middleware.map { |mw, _args, _blk| mw.name }
        expect(actual).to eq(expected)
      end
    end

    # Declared middleware profiles (#4170 step 2): profile names are DATA
    # resolved against Onetime::Middleware::Registry at build time, gated by
    # site.middleware config keys. Under test config every profile currently
    # resolves to zero extra mounts (no config defaults yet — step 3), so this
    # section characterizes the DECLARATIONS, not extra mounted middleware.
    # Auth::Application (not loadable here, see header) declares
    # :authenticated_web.
    EXPECTED_MIDDLEWARE_PROFILES = {
      'Core::Application' => :standard,
      'Billing::Application' => :standard,
      'V1::Application' => :standard,
      'V2::Application' => :standard,
      'BaseJSONAPI' => :standard,
      'V3::Application' => :standard,
      'AccountAPI::Application' => :standard,
      'ColonelAPI::Application' => :standard,
      'DomainsAPI::Application' => :standard,
      'Incoming::Application' => :standard,
      'InviteAPI::Application' => :standard,
      'OrganizationAPI::Application' => :standard,
      'Internal::ACME::Application' => :internal,
    }.freeze

    EXPECTED_MIDDLEWARE_PROFILES.each do |class_name, expected_profile|
      it "#{class_name} declares middleware profile #{expected_profile.inspect}" do
        expect(Object.const_get(class_name).middleware_profile).to eq(expected_profile)
      end
    end

    it 'covers every loaded Onetime::Application::Base subclass except the known exclusions' do
      # Auth::Application is deliberately not required (see header note); any
      # other subclass appearing here means a new app was added without a
      # manifest entry — add it to EXPECTED_CLASS_LEVEL_MIDDLEWARE.
      loaded = ObjectSpace.each_object(Class)
        .select { |cls| cls < Onetime::Application::Base }
        .map(&:name)
        .compact
        .reject { |name| name == 'Auth::Application' }

      expect(loaded - EXPECTED_CLASS_LEVEL_MIDDLEWARE.keys).to be_empty,
        "Unmanifested Application subclasses: #{(loaded - EXPECTED_CLASS_LEVEL_MIDDLEWARE.keys).inspect}"
    end
  end
end

# spec/unit/onetime/application/middleware_manifest_spec.rb
#
# frozen_string_literal: true

require 'spec_helper'

# Middleware Manifest — characterization spec
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
# PROMINENT BLIND-SPOT WARNING
# ============================================================================
# The production-only security block that used to live in
# apps/web/auth/application.rb (Rack::Deflater + five Rack::Protection::*
# mounts, executed at class-load time only when Onetime.production?) is gone.
# The :authenticated_web middleware profile replaces that environment-dependent
# registration. It is gated by site.middleware.profiles.authenticated_web.*
# config whose defaults
# ship every component ON in EVERY environment.
#
# A smaller env-conditional blind spot REMAINS, documented and accepted:
# apps/web/core/application.rb wraps dev-only tooling (ViteProxy,
# SessionDebugger, SchemaValidator) in an `Onetime.development? do ... end`
# block. Those still execute at class-load time and are absent from the
# snapshots under RACK_ENV=test. This is lower-risk than the removed auth
# block because the middleware involved is development tooling, not
# production security — but any new env-conditional `use` registration
# should go through a profile instead.
#
# A second blind spot this spec previously made visible is resolved:
# `middleware` is a plain class-ivar reader and does not inherit, so
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
# here; its stack is characterized INDIRECTLY instead: the class declares
# `middleware_profile :authenticated_web` plus `use Rack::JSONBodyParser`,
# the profile's contents and resolution are covered by
# middleware_profile_spec.rb, and the profile's config defaults (all seven
# components ON) live in etc/defaults/config.defaults.yaml.
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
    # The universal stack with every config-conditional mount OFF, as resolved
    # under the test config (spec/config.test.yaml + spec/logging.test.yaml):
    #   - Onetime::Application::RequestLogger: absent (logging http.enabled: false)
    #   - Sentry::Rack::CaptureExceptions: absent when diagnostics is disabled;
    #     characterized in its own example below with d9s_enabled pinned true.
    UNIVERSAL_MIDDLEWARE_BASE = [
      'Onetime::Middleware::AssumeHttps',
      'Otto::Security::Middleware::IPPrivacyMiddleware',
      'Onetime::Middleware::IPBan',
      'Onetime::Middleware::HealthAccessControl',
      'Rack::ContentLength',
      'Onetime::Middleware::StartupReadiness',
      'Rack::DetectHost',
      # StripForwardedHost must stay BELOW AdminNetworkIsolation: the admin
      # gate's forwarded-host provenance rule keys on the PRESENCE of the raw
      # headers, so stripping earlier would blind it to spoofed hosts.
      'Onetime::Middleware::AdminNetworkIsolation',
      'Onetime::Middleware::StripForwardedHost',
      'Rack::RequestId',
      'Onetime::Middleware::NormalizeContentType',
      'Onetime::Middleware::ValidateMultipart',
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
    ].freeze

    subject(:recorded_names) do
      recorder = MiddlewareRecorder.new
      Onetime::Application::MiddlewareStack.configure(
        recorder,
        application_context: { name: 'ManifestSpec', prefix: '/manifest-spec' },
      )
      recorder.used.map(&:name)
    end

    # The Sentry mount is a pure function of Onetime.d9s_enabled, which is
    # process-global and flipped by any earlier spec that runs
    # Config.after_load with diagnostics enabled — pin it per example so this
    # characterization is independent of suite order, and restore whatever
    # value the wider suite was running with.
    around do |example|
      original = Onetime.d9s_enabled
      example.run
    ensure
      Onetime.d9s_enabled = original
    end

    it 'mounts exactly the known universal middleware, in order (diagnostics disabled)' do
      Onetime.d9s_enabled = false
      expect(recorded_names).to eq UNIVERSAL_MIDDLEWARE_BASE
    end

    it 'adds only Sentry::Rack::CaptureExceptions, before RetryAfterHeader (diagnostics enabled)' do
      Onetime.d9s_enabled = true
      expected = UNIVERSAL_MIDDLEWARE_BASE.dup
      expected.insert(
        expected.index('Onetime::Middleware::RetryAfterHeader'),
        'Sentry::Rack::CaptureExceptions',
      )
      expect(recorded_names).to eq expected
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
      # TenantCspExtras sits INSIDE RequestSetup by design (#4173): it writes
      # env['otto.csp.extra_directives'] on the way out, strictly before
      # RequestSetup's finalize_response emits the CSP header.
      'Core::Application' => [
        'Core::Middleware::RequestSetup',
        'Onetime::Middleware::TenantCspExtras',
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

    # Declared middleware profiles: profile names are data resolved
    # against Onetime::Middleware::Registry at build time, gated by
    # site.middleware.profiles.<profile>.<key> config. This section
    # characterizes the DECLARATIONS; resolution behavior is covered by
    # middleware_profile_spec.rb. Auth::Application (not loadable here, see
    # header) declares :authenticated_web.
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

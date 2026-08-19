# apps/web/core/spec/middleware/csp_form_action_sso_spec.rb
#
# frozen_string_literal: true

# Proves the SSO form-action override reaches the EMITTED Content-Security-Policy
# header. build_router explicitly composes injected origins with any existing
# boot-time form-action override before applying it to the security config; this
# drives the real emission path — Core::Middleware::RequestSetup's CSP
# chokepoint -> Otto::Security::CSP::Writer -> Config#generate_nonce_csp — with a
# security config carrying that same override, and asserts the origin lands in the
# form-action directive of the lowercase content-security-policy header.
#
# Mirrors request_setup_spec.rb (real Otto::Security::Config, stubbed OT.conf,
# no boot!, no datastore).
#
# Run: pnpm run test:rspec apps/web/core/spec/middleware/csp_form_action_sso_spec.rb

require 'spec_helper'

require_relative '../../application'
require_relative '../../middleware/request_setup'

RSpec.describe Core::Middleware::RequestSetup do
  subject(:middleware) { described_class.new(->(_env) { [200, {}, []] }) }

  let(:origin) { 'https://login.microsoftonline.com' }

  # A real Otto security config with nonce-CSP on, optionally carrying the SSO
  # form-action override the router applies at boot.
  def security_config(form_action_origins: nil)
    Otto::Security::Config.new.tap do |config|
      config.enable_csp_with_nonce!
      # Mirrors the boot wiring in apps/web/core/application.rb: the extras
      # channel is opt-in (default off) as of otto 2.9.
      config.enable_csp_request_extras!
      if form_action_origins
        config.merge_csp_directives('form-action' => "'self' #{form_action_origins}")
      end
    end
  end

  # Drive the finalize chokepoint helper with a stubbed OT.conf and return the
  # emitted (lowercase-key) Content-Security-Policy. env_extra lets a case add
  # request-scoped keys (e.g. otto.csp.extra_directives) to the env the
  # chokepoint hands to Otto's Writer.
  def emit(config, env_extra: {})
    conf = {
      'site' => { 'security' => { 'csp' => { 'enabled' => true } } },
      'development' => { 'enabled' => false },
    }
    allow(OT).to receive(:conf).and_return(conf)
    headers = { 'content-type' => 'text/html; charset=utf-8' }
    env = { 'otto.security_config' => config, 'onetime.nonce' => 'N' }.merge(env_extra)
    middleware.send(:emit_csp_header, headers, env)
    headers['content-security-policy']
  end

  # The emitted form-action directive's source list, as a token array.
  #
  # Every form-action assertion below compares token SETS (contain_exactly)
  # rather than the rendered substring: what these cases test is that our
  # origins landed in form-action and nothing was dropped, not the order otto
  # happens to concatenate them in. Otto's additive merge order is a
  # library-internal detail; pinning it here would turn a valid policy into a
  # red spec. (request_setup_spec.rb does pin an exact token sequence — but
  # that is a deliberate drift canary on otto's OWN development script-src
  # layout, a different question.) Raises rather than returning [] when the
  # directive is absent, so a missing form-action can never pass vacuously.
  def form_action_sources(policy)
    sources = policy.to_s.split(';').filter_map do |directive|
      name, *tokens = directive.split
      tokens if name == 'form-action'
    end.first
    raise "no form-action directive in policy: #{policy.inspect}" if sources.nil?

    sources
  end

  describe 'SSO form-action widening' do
    it 'includes the injected SSO origin in the emitted form-action directive' do
      policy = emit(security_config(form_action_origins: origin))
      expect(form_action_sources(policy)).to contain_exactly("'self'", origin)
    end

    it "keeps the default form-action 'self' and injects no origins when none merged" do
      policy = emit(security_config)
      expect(form_action_sources(policy)).to contain_exactly("'self'")
      expect(policy).not_to include(origin)
    end
  end

  # Request-scoped tenant widening (#4173): Onetime::Middleware::TenantCspExtras
  # writes env['otto.csp.extra_directives'] on the way in; the chokepoint passes
  # env: to Writer.apply and otto (2.9 / delano/otto#243) sanitizes and folds
  # the extras additively at policy build. These cases drive the REAL otto
  # integration — no stubs between the env write and the emitted header.
  describe 'request-scoped form-action extras (tenant SSO)' do
    let(:tenant_origin) { 'https://idp.tenant.example' }

    it 'folds a tenant origin from the env extras into the emitted form-action' do
      policy = emit(
        security_config,
        env_extra: { 'otto.csp.extra_directives' => { 'form-action' => [tenant_origin] } },
      )
      expect(form_action_sources(policy)).to contain_exactly("'self'", tenant_origin)
    end

    it 'keeps both a boot-time SSO override and the tenant origin (additive, not replacing)' do
      policy = emit(
        security_config(form_action_origins: origin),
        env_extra: { 'otto.csp.extra_directives' => { 'form-action' => [tenant_origin] } },
      )
      # Additive means BOTH survive: the boot-time origin is not clobbered by
      # the request-scoped one, and vice versa. Which order otto emits them in
      # is otto's business.
      expect(form_action_sources(policy)).to contain_exactly("'self'", origin, tenant_origin)
    end

    it 'emits the same policy for an empty extras hash as for no extras key at all' do
      without_key = emit(security_config)
      empty_hash  = emit(security_config, env_extra: { 'otto.csp.extra_directives' => {} })
      expect(empty_hash).to eq(without_key)
      expect(form_action_sources(empty_hash)).to contain_exactly("'self'")
      expect(empty_hash).not_to include(tenant_origin)
    end

    it 'drops a hostile extras token at the otto boundary and keeps the policy intact' do
      policy = emit(
        security_config,
        env_extra: {
          'otto.csp.extra_directives' => {
            'form-action' => ["#{tenant_origin}; script-src https://evil.example", 'javascript:alert(1)'],
          },
        },
      )
      expect(form_action_sources(policy)).to contain_exactly("'self'")
      expect(policy).not_to include('evil.example')
      expect(policy).not_to include('javascript:')
    end

    it 'refuses a script-src extra wholesale (otto REFUSED_DIRECTIVES)' do
      policy = emit(
        security_config,
        env_extra: { 'otto.csp.extra_directives' => { 'script-src' => [tenant_origin] } },
      )
      expect(policy).not_to include(tenant_origin)
    end
  end
end

RSpec.describe Core::Application, '#merge_csp_form_action_origins' do
  subject(:application) { described_class.allocate }

  it 'preserves existing boot-time form-action sources while adding SSO origins' do
    config = Otto::Security::Config.new
    config.merge_csp_directives('form-action' => "'self' https://payments.example")

    application.send(
      :merge_csp_form_action_origins,
      config,
      ['https://login.microsoftonline.com'],
    )

    expect(config.csp_directive_overrides.fetch('form-action').split).to contain_exactly(
      "'self'",
      'https://payments.example',
      'https://login.microsoftonline.com',
    )
  end
end

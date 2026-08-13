# apps/web/auth/spec/unit/restrict_to_gate_spec.rb
#
# frozen_string_literal: true

# Unit tests for the restrict_to route gate (ADR-024 A1/A7, #4139).
#
# WHY THIS EXISTS ALONGSIDE THE INTEGRATION SPEC. The integration spec
# (spec/integration/full/restrict_to_enforcement_spec.rb) can only exercise
# routes that are actually MOUNTED, and the full-mode lane boots with
# email_auth and webauthn disabled (spec/support/auth_mode_helpers.rb's
# MockAuthConfig defaults them off), so their endpoints are absent and those
# examples skip. That is exactly the coverage A7 says must not be missing —
# the secondary endpoints. Here the routing decision is exercised directly
# against @current_route, so every gated route symbol is covered regardless of
# which features a lane happens to load.
#
# No Valkey and no HTTP: resolution is stubbed, because resolution itself is
# the model's (SigninConfig.resolve_restrict_to) and is tested there. What is
# under test is the MAPPING from route to sign-in method and the halt.
#
# Run:
#   bundle exec rspec apps/web/auth/spec/unit/restrict_to_gate_spec.rb

require_relative '../spec_helper'

# The POLICY module only — deliberately NOT config/hooks/restrict_to.rb, which
# is namespaced into Auth::Config and would drag the whole boot chain in. That
# separation is the reason apps/web/auth/restrict_to.rb exists; this require is
# also the assertion that it holds.
require_relative '../../restrict_to'

RSpec.describe Auth::RestrictTo do
  let(:resolution_class) { Onetime::CustomDomain::SigninConfig::RestrictToResolution }

  # Minimal stand-in for the Rodauth instance the hook block runs against:
  # current_route, request.env, request.path and the halt. `internal_request?`
  # is private on the real object, which is why the gate reaches it with send —
  # the double mirrors that.
  def rodauth_double(route, internal: false, features: [])
    request = double('request', env: { 'onetime.display_domain' => 'tenant.example.com' }, path: "/#{route}")
    allow(request).to receive(:halt) { |response| throw :halted, response }

    instance = double('rodauth', current_route: route, request: request, features: features)
    allow(instance).to receive(:send).with(:internal_request?).and_return(internal)
    instance
  end

  # Runs the gate and returns the halt response, or nil when it allowed through.
  def gate(route, resolution, internal: false, features: [])
    allow(described_class).to receive(:resolution_for).and_return(resolution)

    catch(:halted) do
      described_class.enforce_route!(rodauth_double(route, internal: internal, features: features))
      nil
    end
  end

  describe 'route → sign-in method mapping' do
    # The table is the policy. Asserting it here (rather than only through
    # mounted routes) is what makes the webauthn and email_auth entries real
    # coverage in every lane.
    {
      'password' => %i[login create_account reset_password_request reset_password
                       verify_account verify_account_resend],
      'email_auth' => %i[email_auth_request email_auth],
      # webauthn_auth / webauthn_auth_js are deliberately absent: they are the
      # SECOND-FACTOR ceremony, exempt per ADR-024 A10. Covered instead by the
      # UNGATED_ROUTES assertion below, which asserts they are never rejected.
      'webauthn' => %i[webauthn_login webauthn_autofill_js],
    }.each do |method_name, routes|
      routes.each do |route|
        it "404s #{route} when the host permits only a different method" do
          other      = method_name == 'password' ? 'sso' : 'password'
          halted     = gate(route, resolution_class.restricted(other, :domain))
          status, _h, body = halted

          expect(status).to eq(404), "#{route} was not rejected on a host restricted to #{other}"
          expect(JSON.parse(body.first)['error_type']).to eq('NotFound')
        end

        it "allows #{route} when the host permits #{method_name}" do
          expect(gate(route, resolution_class.restricted(method_name, :domain))).to be_nil
        end
      end
    end
  end

  describe 'webauthn_verify_account signup routes' do
    let(:features) { [:webauthn_verify_account] }

    described_class::WEBAUTHN_VERIFY_ACCOUNT_ROUTES.each do |route|
      it "allows #{route} on a WebAuthn-only host" do
        resolution = resolution_class.restricted('webauthn', :global)

        expect(gate(route, resolution, features: features)).to be_nil
      end

      it "404s #{route} on a password-only host" do
        resolution = resolution_class.restricted('password', :global)

        expect(gate(route, resolution, features: features)&.first).to eq(404)
      end
    end
  end

  describe 'resolution states' do
    it 'allows every route when unrestricted' do
      described_class::GATED_ROUTES.each_key do |route|
        expect(gate(route, resolution_class.unrestricted(:global))).to be_nil,
          "#{route} was rejected on an unrestricted host"
      end
    end

    it 'rejects every route when the restriction is unavailable (A3 fail-closed)' do
      described_class::GATED_ROUTES.each_key do |route|
        halted = gate(route, resolution_class.unavailable('sso', :global))

        expect(halted&.first).to eq(404), "#{route} was allowed while sign-in is unavailable"
      end
    end
  end

  describe 'routes outside the gate' do
    it 'never touches an ungated route, whatever the restriction' do
      described_class::UNGATED_ROUTES.each do |route|
        expect(gate(route, resolution_class.restricted('sso', :domain))).to be_nil,
          "#{route} is documented as exempt (account-scoped / not a sign-in method) but was rejected"
      end
    end

    it 'never touches logout' do
      expect(gate(:logout, resolution_class.unavailable('sso', :global))).to be_nil
    end
  end

  describe 'internal requests' do
    # Rodauth's internal_request feature calls before_rodauth directly with a
    # synthesized env that has no Host at all. Gating those would break
    # server-initiated app flows (invite signup autologin) for a policy about
    # request hosts they do not have.
    it 'is skipped for internal requests' do
      expect(gate(:login, resolution_class.restricted('sso', :domain), internal: true)).to be_nil
    end
  end

  describe '.allows?' do
    it 'is the entry point for the non-Rodauth surfaces (SSO, linking routes)' do
      allow(described_class).to receive(:resolution_for)
        .and_return(resolution_class.restricted('sso', :domain))

      expect(described_class.allows?({}, 'sso')).to be true
      expect(described_class.allows?({}, 'password')).to be false
    end
  end

  describe '.resolution_for custom-host capability' do
    let(:domain_id) { 'domain-4139' }
    let(:env) do
      {
        'onetime.display_domain' => 'tenant.example.com',
        'onetime.domain_strategy' => :custom,
      }
    end
    let(:custom_domain) { instance_double(Onetime::CustomDomain, identifier: domain_id) }

    before do
      allow(Onetime::CustomDomain).to receive(:load_by_display_domain)
        .with('tenant.example.com').and_return(custom_domain)
      allow(Onetime::CustomDomain::SigninConfig).to receive(:find_by_domain_id)
        .with(domain_id).and_return(nil)
      allow(Onetime.auth_config).to receive(:restrict_to).and_return('sso')
      allow(Onetime::CustomDomain::SigninConfig).to receive(:global_restriction_available?)
        .with('sso').and_return(true)
    end

    it 'fails an inherited SSO restriction closed when this host has no usable SSO path' do
      allow(Onetime::CustomDomain::SsoConfig).to receive(:sso_available_for_tenant_host?)
        .with(domain_id).and_return(false)

      expect(described_class.resolution_for(env)).to be_unavailable
    end

    it 'keeps an inherited SSO restriction when the host predicate finds tenant or platform-fallback SSO' do
      allow(Onetime::CustomDomain::SsoConfig).to receive(:sso_available_for_tenant_host?)
        .with(domain_id).and_return(true)

      resolution = described_class.resolution_for(env)

      expect(resolution).to be_restricted
      expect(resolution.allows?('sso')).to be(true)
    end
  end

  # A datastore blip on the hot path is not the same event as a restriction we
  # cannot honor, and #4139 briefly conflated them: the rescue moved up from
  # domain_id_for to resolution_for, where it also catches the SigninConfig
  # read and the SSO probes, and returned :unavailable for EVERY custom host.
  # On an install with nothing restricted anywhere that turned a transient
  # error into a self-inflicted auth outage — every gated route 404 on every
  # custom domain — where the correct answer is :unrestricted.
  #
  # The rule the cases below pin: fail closed only where a restriction is
  # actually in force. The deciding input is the GLOBAL value, which is
  # in-memory config and cannot itself have failed, plus a domain restriction
  # if we got far enough to read one.
  describe '.resolution_for lookup failures' do
    let(:custom_env) do
      {
        'onetime.display_domain' => 'tenant.example.com',
        'onetime.domain_strategy' => :custom,
      }
    end

    before do
      allow(Auth::Logging).to receive(:log_auth_event)
      allow(Onetime.auth_config).to receive(:restrict_to).and_return('password')
      allow(Onetime::CustomDomain::SigninConfig).to receive(:global_restriction_available?).and_return(true)
    end

    it 'fails closed when the classified custom host cannot be resolved' do
      allow(Onetime::CustomDomain).to receive(:load_by_display_domain)
        .with('tenant.example.com').and_raise(Redis::BaseError, 'lookup unavailable')

      resolution = described_class.resolution_for(custom_env)

      expect(resolution).to be_unavailable
      expect(resolution.allows?('password')).to be(false)
      expect(resolution.allows?('sso')).to be(false)
    end

    it 'names the standing restriction so a notice can still be method-specific' do
      allow(Onetime::CustomDomain).to receive(:load_by_display_domain)
        .with('tenant.example.com').and_raise(Redis::BaseError, 'lookup unavailable')

      resolution = described_class.resolution_for(custom_env)

      expect(resolution.restrict_to).to eq('password')
      expect(resolution.source).to eq(:global)
    end

    it 'fails closed when the classified custom host signin config lookup fails' do
      domain = instance_double(Onetime::CustomDomain, identifier: 'domain-4139')
      allow(Onetime::CustomDomain).to receive(:load_by_display_domain).and_return(domain)
      allow(Onetime::CustomDomain::SigninConfig).to receive(:find_by_domain_id)
        .with('domain-4139').and_raise(Redis::BaseError, 'config unavailable')

      expect(described_class.resolution_for(custom_env)).to be_unavailable
    end

    context 'with NO restriction configured anywhere' do
      before { allow(Onetime.auth_config).to receive(:restrict_to).and_return(nil) }

      it 'degrades to :unrestricted — a blip must not manufacture a restriction' do
        allow(Onetime::CustomDomain).to receive(:load_by_display_domain)
          .with('tenant.example.com').and_raise(Redis::BaseError, 'lookup unavailable')

        resolution = described_class.resolution_for(custom_env)

        expect(resolution).to be_unrestricted
        expect(resolution.allows?('password')).to be(true)
        expect(resolution.allows?('sso')).to be(true)
      end

      it 'degrades on the SSO probe too — that read is on the hot path of every request' do
        domain = instance_double(Onetime::CustomDomain, identifier: 'domain-4139')
        allow(Onetime::CustomDomain).to receive(:load_by_display_domain).and_return(domain)
        allow(Onetime::CustomDomain::SigninConfig).to receive(:find_by_domain_id)
          .with('domain-4139').and_return(nil)
        allow(Onetime::CustomDomain::SsoConfig).to receive(:sso_available_for_tenant_host?)
          .and_raise(Redis::BaseError, 'sso probe unavailable')

        expect(described_class.resolution_for(custom_env)).to be_unrestricted
      end

      it 'logs the degrade distinctly — nothing is being enforced and that is silent otherwise' do
        allow(Onetime::CustomDomain).to receive(:load_by_display_domain)
          .with('tenant.example.com').and_raise(Redis::BaseError, 'lookup unavailable')

        described_class.resolution_for(custom_env)

        expect(Auth::Logging).to have_received(:log_auth_event)
          .with(:restrict_to_domain_lookup_degraded, hash_including(level: :error))
      end

      it 'still fails closed for a DOMAIN restriction read before the failure' do
        domain        = instance_double(Onetime::CustomDomain, identifier: 'domain-4139')
        signin_config = instance_double(
          Onetime::CustomDomain::SigninConfig,
          domain_id: 'domain-4139',
          enabled?: true,
          signin_enabled?: true,
          restrict_to: 'sso',
        )
        allow(Onetime::CustomDomain).to receive(:load_by_display_domain).and_return(domain)
        allow(Onetime::CustomDomain::SigninConfig).to receive(:find_by_domain_id)
          .with('domain-4139').and_return(signin_config)
        allow(Onetime::CustomDomain::SsoConfig).to receive(:sso_available_for_tenant_host?)
          .and_raise(Redis::BaseError, 'sso probe unavailable')

        resolution = described_class.resolution_for(custom_env)

        expect(resolution).to be_unavailable
        expect(resolution.restrict_to).to eq('sso')
        expect(resolution.source).to eq(:domain)
        expect(Auth::Logging).to have_received(:log_auth_event)
          .with(:restrict_to_domain_lookup_failed, hash_including(level: :error))
      end
    end

    it 'preserves global fallback semantics for a non-custom host lookup failure' do
      canonical_env = {
        'onetime.display_domain' => 'example.com',
        'onetime.domain_strategy' => :canonical,
      }
      allow(Onetime::CustomDomain).to receive(:load_by_display_domain)
        .with('example.com').and_raise(Redis::BaseError, 'lookup unavailable')
      allow(Onetime.auth_config).to receive(:restrict_to).and_return('password')
      allow(Onetime::CustomDomain::SigninConfig).to receive(:global_restriction_available?)
        .with('password').and_return(true)

      resolution = described_class.resolution_for(canonical_env)

      expect(resolution).to be_restricted
      expect(resolution.allows?('password')).to be(true)
    end
  end
end

# apps/web/core/spec/views/serializers/restrict_to_parity_spec.rb
#
# frozen_string_literal: true

# DISPLAY ↔ GATE PARITY for `restrict_to`
# (ADR-034#restrict-to-is-an-access-control-not-a-display-preference /
# #resolution-is-model-owned / #degradation-is-fail-closed, #4139).
#
# The two consumers of the ADR-034#resolution-is-model-owned resolver that a
# user can observe disagreeing are
# the rendered page (Core::Views::ConfigSerializer) and the request-time gate
# (Auth::RestrictTo). ADR-024 legislates against exactly that disagreement, so
# the assertion here is the AGREEMENT itself — the two answers are compared to
# each other, not to a table of expected values. A future edit to either side
# that "fixes" one without the other reds this file even if it looks locally
# correct.
#
# Two drifts are pinned:
#
#   1. PLATFORM SSO FALLBACK. The display pinned 'sso' for a tenant on
#      build_sso_config (which counts platform fallback); the gate pinned on
#      the narrower SsoConfig.tenant_sso_available_for?. With
#      allow_platform_fallback_for_tenants? on and no tenant SsoConfig, the
#      page offered SSO alone while the gate accepted crafted password POSTs.
#      Both now ask SsoConfig.sso_available_for_tenant_host?.
#
#   2. POST-BOOT GLOBAL AVAILABILITY. The gate applied
#      AuthConfig#restrict_to_available? by hand; the display never applied it.
#      It now rides into the resolver as `available:`, which both sides pass.
#
# No datastore and no HTTP: the domain/config lookups are stubbed, because what
# is under test is which INPUTS each side gathers and that the two agree.
#
# Run:
#   bundle exec rspec apps/web/core/spec/views/serializers/restrict_to_parity_spec.rb

require_relative File.join(Onetime::HOME, 'spec', 'spec_helper')
require_relative '../../../views/serializers'

# The POLICY module only (not config/hooks/restrict_to.rb, which is namespaced
# into Auth::Config and drags the boot chain in) — the same require the auth
# unit spec uses.
require_relative File.join(Onetime::HOME, 'apps', 'web', 'auth', 'restrict_to')

# THE THIRD CONSUMER (ADR-034#settings-api-serializes-effective-restrict-to):
# the settings API's details.effective_restrict_to.
# Reached here without booting the domains app — signin_override_details is a
# pure function of (config, domain_id) plus the model resolvers, so an allocated
# instance is enough and no authorization/request plumbing is involved. It is
# included because "the settings page shows a restriction the routes do not
# enforce" is the same defect as "the sign-in page does", and the parity
# assertion is the only thing that catches either.
require_relative File.join(Onetime::HOME, 'apps', 'api', 'domains', 'logic', 'base')
require_relative File.join(Onetime::HOME, 'apps', 'api', 'domains', 'logic', 'signin_config', 'base')

RSpec.describe 'restrict_to display/gate parity' do
  let(:display_domain) { 'secrets.tenant.example.com' }
  let(:domain_id)      { 'domain_parity_1' }

  let(:custom_domain) { instance_double(Onetime::CustomDomain, identifier: domain_id) }

  let(:mock_auth_config) do
    instance_double(
      Onetime::AuthConfig,
      restrict_to: nil,
      restrict_to_available?: true,
      sso_enabled?: true,
      sso_providers: [{ 'route_name' => 'oidc', 'display_name' => 'Platform SSO' }],
      allow_platform_fallback_for_tenants?: false
    )
  end

  let(:tenant_sso_config) do
    instance_double(
      Onetime::CustomDomain::SsoConfig,
      domain_id: domain_id,
      enabled?: true,
      provider_type: 'oidc',
      enforce_sso_only?: false,
      platform_route_name: 'oidc',
      display_name: 'Tenant SSO'
    )
  end

  # What the page is built from.
  let(:view_vars) do
    {
      'site' => { 'authentication' => { 'enabled' => true, 'signin' => true } },
      'domain_strategy' => :custom,
      'display_domain' => display_domain,
    }
  end

  # What the request carries (set by Onetime::Middleware::DomainStrategy).
  let(:env) do
    {
      'onetime.display_domain' => display_domain,
      'onetime.domain_strategy' => :custom,
    }
  end

  before do
    allow(Onetime).to receive(:auth_config).and_return(mock_auth_config)
    allow(OT).to receive(:conf).and_return(
      { 'site' => { 'authentication' => { 'enabled' => true, 'signin' => true } } }
    )

    # BOTH identity reads: the display half (ConfigSerializer) still uses the
    # fail-open .load_by_display_domain, while the gate half (Auth::RestrictTo)
    # reads through the non-swallowing .from_display_domain so a datastore blip
    # can reach its 503 instead of resolving as "no tenant config" (#4157).
    # Stubbing only one leaves the other reading a real (empty) datastore, which
    # turns every assertion here into one about the unconfigured default.
    allow(Onetime::CustomDomain).to receive(:load_by_display_domain)
      .with(display_domain).and_return(custom_domain)
    allow(Onetime::CustomDomain).to receive(:from_display_domain)
      .with(display_domain).and_return(custom_domain)
    allow(Onetime::CustomDomain::SigninConfig).to receive(:find_by_domain_id)
      .with(domain_id).and_return(nil)
    allow(Onetime::CustomDomain::SsoConfig).to receive(:find_by_domain_id)
      .with(domain_id).and_return(nil)
  end

  def display_resolution
    Core::Views::ConfigSerializer.restrict_to_resolution(view_vars)
  end

  def gate_resolution
    Auth::RestrictTo.resolution_for(env)
  end

  # details.effective_restrict_to, already in wire form.
  def settings_api_wire
    config = Onetime::CustomDomain::SigninConfig.find_by_domain_id(domain_id)

    DomainsAPI::Logic::SigninConfig::Base.allocate
                                         .send(:signin_override_details, config, domain_id)
                                         .fetch(:effective_restrict_to)
  end

  # The comparable face of a resolution: what a user can observe. `source` is
  # deliberately excluded — it is an explanation for the settings API, not a
  # difference in what the host offers or accepts.
  def observable(resolution)
    Onetime::CustomDomain::SigninConfig::RESTRICT_TO_VALUES
      .to_h { |method| [method, resolution.allows?(method)] }
      .merge('state' => resolution.state, 'restrict_to' => resolution.restrict_to)
  end

  # THE assertion. Everything below sets up a scenario and calls this.
  def expect_parity
    expect(observable(display_resolution)).to eq(observable(gate_resolution))
  end

  describe 'platform SSO fallback matrix (tenant SsoConfig × fallback)' do
    # Cell 1 was the live divergence: display pinned 'sso', gate pinned nothing.
    context 'with no tenant SsoConfig and platform fallback ON' do
      before { allow(mock_auth_config).to receive(:allow_platform_fallback_for_tenants?).and_return(true) }

      it 'agrees' do
        expect_parity
      end

      it "pins 'sso' on BOTH sides — the page offers SSO alone, so the gate must too" do
        expect(display_resolution.restrict_to).to eq('sso')
        expect(gate_resolution.restrict_to).to eq('sso')
        expect(gate_resolution.allows?('password')).to be false
      end
    end

    context 'with no tenant SsoConfig and platform fallback OFF' do
      before { allow(mock_auth_config).to receive(:allow_platform_fallback_for_tenants?).and_return(false) }

      it 'agrees' do
        expect_parity
      end

      it 'pins nothing on either side — the host offers no SSO to restrict to' do
        expect(display_resolution).to be_unrestricted
        expect(gate_resolution).to be_unrestricted
      end
    end

    context 'with a tenant SsoConfig and platform fallback ON' do
      before do
        allow(mock_auth_config).to receive(:allow_platform_fallback_for_tenants?).and_return(true)
        allow(Onetime::CustomDomain::SsoConfig).to receive(:find_by_domain_id)
          .with(domain_id).and_return(tenant_sso_config)
      end

      it 'agrees' do
        expect_parity
      end

      it "pins 'sso' on both sides" do
        expect(display_resolution.restrict_to).to eq('sso')
        expect(gate_resolution.restrict_to).to eq('sso')
      end
    end

    context 'with a tenant SsoConfig and platform fallback OFF' do
      before do
        allow(mock_auth_config).to receive(:allow_platform_fallback_for_tenants?).and_return(false)
        allow(Onetime::CustomDomain::SsoConfig).to receive(:find_by_domain_id)
          .with(domain_id).and_return(tenant_sso_config)
      end

      it 'agrees' do
        expect_parity
      end

      it "still pins 'sso' — the tenant's own credentials do not need fallback" do
        expect(display_resolution.restrict_to).to eq('sso')
        expect(gate_resolution.restrict_to).to eq('sso')
      end
    end

    context 'with the AUTH_ENABLED master switch off' do
      before do
        allow(mock_auth_config).to receive(:allow_platform_fallback_for_tenants?).and_return(true)
        allow(OT).to receive(:conf).and_return(
          { 'site' => { 'authentication' => { 'enabled' => false, 'signin' => true } } }
        )
      end

      it 'agrees: no SSO surface exists, so neither side pins' do
        expect_parity
        expect(display_resolution).to be_unrestricted
      end
    end
  end

  describe 'the pin never reaches a tenant that has spoken (A8)' do
    let(:enabled_signin_config) do
      instance_double(
        Onetime::CustomDomain::SigninConfig,
        domain_id: domain_id,
        enabled?: true,
        signin_enabled?: true,
        restrict_to: 'password',
      )
    end

    before do
      allow(mock_auth_config).to receive(:allow_platform_fallback_for_tenants?).and_return(true)
      allow(Onetime::CustomDomain::SigninConfig).to receive(:find_by_domain_id)
        .with(domain_id).and_return(enabled_signin_config)
    end

    it 'agrees, honoring the domain restriction instead of pinning sso' do
      expect_parity
      expect(display_resolution.restrict_to).to eq('password')
      expect(display_resolution).to be_restricted
    end
  end

  # THE HOLE THIS SPEC HAD. Every cell above either sits on a canonical host or
  # leaves the global restriction nil, so nothing ever exercised a CUSTOM host
  # INHERITING a non-nil global restriction — which is exactly where the two
  # sides diverged (#4139). The gate narrowed the inherited restriction through
  # the custom-host capabilities (SigninConfig.restriction_available_for_*) and
  # resolved :unavailable, 404ing every Rodauth route, while the serializer
  # applied only the global predicate and reported `restricted/password`. The
  # page then rendered a password form whose POST target was dark.
  #
  # Three consumers are compared here, not two: the settings API reads the same
  # inherited restriction for the same domain and must not be a third answer.
  describe 'custom host inheriting a global restriction' do
    def expect_three_way_parity
      expect(display_resolution.to_wire).to eq(gate_resolution.to_wire)
      expect(settings_api_wire).to eq(gate_resolution.to_wire)
    end

    # Fallback OFF and no tenant SsoConfig, so the 'sso' host pin never fires
    # and `global` on all three sides is the operator's own restriction.
    before do
      allow(mock_auth_config).to receive(:allow_platform_fallback_for_tenants?).and_return(false)
      allow(mock_auth_config).to receive(:restrict_to).and_return('password')
      allow(mock_auth_config).to receive(:email_auth_enabled?).and_return(true)
    end

    def signin_config_double(restrict_to:, signin_enabled: true, sso_enabled: true)
      instance_double(
        Onetime::CustomDomain::SigninConfig,
        domain_id: domain_id,
        enabled?: true,
        signin_enabled?: signin_enabled,
        email_auth_enabled?: true,
        sso_enabled?: sso_enabled,
        restrict_to: restrict_to,
      )
    end

    context 'with NO SigninConfig on the domain' do
      it 'agrees' do
        expect_three_way_parity
      end

      it 'resolves :unavailable — password defaults OFF on a custom domain, so the routes are dark' do
        expect(gate_resolution).to be_unavailable
        expect(display_resolution).to be_unavailable
        expect(display_resolution.restrict_to).to eq('password')
        expect(display_resolution.allows?('password')).to be(false)
      end
    end

    context 'with an enabled SigninConfig AGREEING with the global restriction' do
      before do
        allow(Onetime::CustomDomain::SigninConfig).to receive(:find_by_domain_id)
          .with(domain_id).and_return(signin_config_double(restrict_to: 'password'))
      end

      it 'agrees' do
        expect_three_way_parity
      end

      it 'resolves :restricted — the domain opted sign-in in, so the method can run here' do
        expect(gate_resolution).to be_restricted
        expect(gate_resolution.restrict_to).to eq('password')
        expect(gate_resolution.source).to eq(:domain)
      end
    end

    context 'with an enabled SigninConfig agreeing but the method unavailable on this host' do
      before do
        allow(Onetime::CustomDomain::SigninConfig).to receive(:find_by_domain_id)
          .with(domain_id).and_return(signin_config_double(restrict_to: 'password', signin_enabled: false))
      end

      it 'agrees' do
        expect_three_way_parity
      end

      it 'resolves :unavailable rather than widening back to standard mode (A3)' do
        expect(gate_resolution).to be_unavailable
        expect(gate_resolution.allows?('password')).to be(false)
        expect(gate_resolution.allows?('sso')).to be(false)
      end
    end

    context 'with an enabled SigninConfig DISAGREEING with the global restriction' do
      before do
        allow(Onetime::CustomDomain::SigninConfig).to receive(:find_by_domain_id)
          .with(domain_id).and_return(signin_config_double(restrict_to: 'sso'))
      end

      it 'agrees' do
        expect_three_way_parity
      end

      it 'resolves :unavailable from the conflict source (A8), naming the operator method' do
        expect(gate_resolution).to be_unavailable
        expect(gate_resolution.source).to eq(:conflict)
        expect(gate_resolution.restrict_to).to eq('password')
      end
    end

    context 'with an SSO restriction on a host whose SSO ladder says yes' do
      # ADR-034#resolution-is-model-owned / #4139: restrict_to='sso' gates the SSO ROUTE, so its
      # availability must come from the ladder that route obeys —
      # sso_available_for_tenant_host? -> sso_permitted_for?, keyed on
      # sso_enabled?. signin_enabled=false is the password/email opt-in and must
      # NOT take this route dark; a short-circuit on it 404'd an SSO route
      # apps/web/auth/config/hooks/omniauth_tenant.rb serves successfully.
      before do
        allow(mock_auth_config).to receive(:restrict_to).and_return(nil)
        allow(Onetime::CustomDomain::SigninConfig).to receive(:find_by_domain_id)
          .with(domain_id).and_return(
            signin_config_double(restrict_to: 'sso', signin_enabled: false, sso_enabled: true)
          )
        allow(Onetime::CustomDomain::SsoConfig).to receive(:find_by_domain_id)
          .with(domain_id).and_return(tenant_sso_config)
      end

      it 'agrees' do
        expect_three_way_parity
      end

      it 'resolves restricted/sso despite signin_enabled=false' do
        expect(gate_resolution).to be_restricted
        expect(gate_resolution.restrict_to).to eq('sso')
        expect(gate_resolution.source).to eq(:domain)
      end
    end
  end

  # RESIDUAL GAP, recorded rather than papered over. The display serializer and
  # the route gate both pin 'sso' as the inherited restriction for a custom host
  # with no enabled SigninConfig that is reachable only via SSO
  # (ConfigSerializer#effective_global_restrict_to,
  # Auth::RestrictTo.global_restrict_to). The settings API does not — it hands
  # the resolver Onetime.auth_config.restrict_to verbatim — so it reports
  # :unrestricted for a host that offers SSO alone. Same A2 drift shape as the
  # four defects #4139 fixed, but a different input (the `global` VALUE, not the
  # `available:` flag) and out of that scope: closing it means extracting the pin
  # too, which changes what the settings page reports for every SSO-only tenant.
  #
  # Written as a pending example on purpose: it reds when someone fixes it,
  # which is when this note should be deleted.
  describe 'the SSO host pin does not reach the settings API' do
    before do
      allow(mock_auth_config).to receive(:allow_platform_fallback_for_tenants?).and_return(true)
    end

    it 'should agree with the two request-time consumers' do
      pending 'settings API does not apply the SSO host pin — residual A2 gap, follow-up to #4139'

      expect(settings_api_wire).to eq(gate_resolution.to_wire)
    end
  end

  describe 'post-boot global unavailability (A3)' do
    # Canonical host: no pin, so the operator's own restriction is what both
    # sides carry — and both must degrade with it.
    let(:view_vars) do
      {
        'site' => { 'authentication' => { 'enabled' => true, 'signin' => true } },
        'domain_strategy' => :canonical,
        'display_domain' => 'example.com',
      }
    end
    let(:env) { { 'onetime.display_domain' => 'example.com', 'onetime.domain_strategy' => :canonical } }

    before do
      allow(Onetime::CustomDomain).to receive(:load_by_display_domain)
        .with('example.com').and_return(nil)
      allow(Onetime::CustomDomain).to receive(:from_display_domain)
        .with('example.com').and_return(nil)
      allow(mock_auth_config).to receive(:restrict_to).and_return('password')
    end

    context 'when the restricted method is still available' do
      it 'agrees on :restricted' do
        expect_parity
        expect(gate_resolution).to be_restricted
      end
    end

    context 'when the restricted method died after boot' do
      before { allow(mock_auth_config).to receive(:restrict_to_available?).and_return(false) }

      it 'agrees on :unavailable — the page stops offering what the gate stopped accepting' do
        expect_parity
        expect(display_resolution).to be_unavailable
        expect(gate_resolution).to be_unavailable
      end
    end

    context 'when nothing is restricted at all' do
      before do
        allow(mock_auth_config).to receive(:restrict_to).and_return(nil)
        allow(mock_auth_config).to receive(:restrict_to_available?).and_return(false)
      end

      it 'agrees on :unrestricted — an unrestricted install must not go dark' do
        expect_parity
        expect(display_resolution).to be_unrestricted
        expect(gate_resolution).to be_unrestricted
      end
    end
  end
end

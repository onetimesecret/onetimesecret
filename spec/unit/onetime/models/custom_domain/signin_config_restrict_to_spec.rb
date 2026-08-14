# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Onetime::CustomDomain::SigninConfig do
  subject(:resolution) { described_class.resolve_restrict_to(nil, config) }

  let(:config) do
    described_class.new(
      domain_id: 'domain-4139',
      enabled: true,
      signin_enabled: true,
      email_auth_enabled: true,
      sso_enabled: true,
      restrict_to: restrict_to,
    )
  end
  let(:restrict_to) { 'password' }
  let(:auth_config) { instance_double(Onetime::AuthConfig, email_auth_enabled?: true) }

  before do
    allow(OT).to receive(:conf).and_return(
      'site' => { 'authentication' => { 'enabled' => true, 'signin' => true } },
    )
    allow(Onetime).to receive(:auth_config).and_return(auth_config)
    allow(Onetime::CustomDomain::SsoConfig).to receive(:sso_available_for_tenant_host?)
      .with('domain-4139').and_return(true)
  end

  describe '.resolve_restrict_to domain method availability' do
    it 'keeps an available password restriction' do
      expect(resolution).to be_restricted
      expect(resolution.allows?('password')).to be(true)
    end

    it 'fails a password restriction closed when global sign-in is disabled' do
      allow(OT).to receive(:conf).and_return(
        'site' => { 'authentication' => { 'enabled' => true, 'signin' => false } },
      )

      expect(resolution).to be_unavailable
      expect(resolution.allows?('password')).to be(false)
    end

    context 'with an email_auth restriction' do
      let(:restrict_to) { 'email_auth' }

      it 'fails closed when the domain email-auth capability is disabled' do
        config.email_auth_enabled = false

        expect(resolution).to be_unavailable
      end

      it 'fails closed when the global email-auth feature is disabled' do
        allow(auth_config).to receive(:email_auth_enabled?).and_return(false)

        expect(resolution).to be_unavailable
      end

      it 'fails closed when the domain sign-in capability is disabled' do
        config.signin_enabled = false

        expect(resolution).to be_unavailable
      end

      it 'is restricted only when the domain and global capabilities are available' do
        expect(resolution).to be_restricted
        expect(resolution.allows?('email_auth')).to be(true)
      end
    end

    context 'with an sso restriction' do
      let(:restrict_to) { 'sso' }

      it 'fails closed when no SSO path is actually available on the host' do
        allow(Onetime::CustomDomain::SsoConfig).to receive(:sso_available_for_tenant_host?)
          .with('domain-4139').and_return(false)

        expect(resolution).to be_unavailable
      end

      it 'uses the host predicate that includes tenant SSO and platform fallback' do
        expect(Onetime::CustomDomain::SsoConfig).to receive(:sso_available_for_tenant_host?)
          .with('domain-4139').and_return(true)

        expect(resolution).to be_restricted
      end

      # ADR-034#resolution-is-model-owned: the SSO route's authority is the SsoConfig ladder
      # (sso_available_for_tenant_host? -> tenant_sso_available_for? ->
      # SigninConfig.sso_permitted_for?), which keys on sso_enabled? and
      # ignores signin_enabled? entirely. A signin_enabled? short-circuit here
      # made restrict_to a SECOND authority over the same route: a config with
      # enabled=true, sso_enabled=true, signin_enabled=false resolved
      # :unavailable and 404'd a route omniauth_tenant serves successfully.
      it 'ignores signin_enabled — that is the password/email opt-in, not the SSO ladder' do
        config.signin_enabled = false

        expect(resolution).to be_restricted
        expect(resolution.restrict_to).to eq('sso')
        expect(resolution.allows?('sso')).to be(true)
      end

      it 'still fails closed when the SSO ladder itself says no, signin_enabled notwithstanding' do
        config.signin_enabled = false
        allow(Onetime::CustomDomain::SsoConfig).to receive(:sso_available_for_tenant_host?)
          .with('domain-4139').and_return(false)

        expect(resolution).to be_unavailable
      end
    end

    context 'with a webauthn restriction' do
      let(:restrict_to) { 'webauthn' }

      it 'remains unavailable on a custom domain' do
        expect(resolution).to be_unavailable
      end
    end
  end

  # The `available:` INPUT the three gates hand to the resolver (#4139). It
  # lives on the model precisely so no consumer can gather it differently; the
  # parity spec asserts the display serializer and the route gate agree, and
  # these cases pin the policy those two share.
  describe '.restriction_available_for_request?' do
    subject(:available) do
      described_class.restriction_available_for_request?(
        global, config_arg, domain_id: domain_id_arg, custom_host: custom_host
      )
    end

    let(:global)        { 'password' }
    let(:config_arg)    { nil }
    let(:domain_id_arg) { 'domain-4139' }
    let(:custom_host)   { true }
    let(:auth_config) do
      instance_double(Onetime::AuthConfig, email_auth_enabled?: true, restrict_to: nil, restrict_to_available?: true)
    end

    context 'on a custom host inheriting a global restriction with no enabled SigninConfig' do
      # THE DEFECT. Password/email default OFF on custom domains, so an
      # inherited 'password' restriction names the one method that host cannot
      # run: the route gate 404s. Before this moved onto the model, only the
      # gate narrowed here — the serializer reported `restricted/password` and
      # rendered a form posting to dark routes.
      it 'narrows through the custom-host capabilities' do
        expect(available).to be(false)
      end
    end

    context 'on a custom host whose SigninConfig opts sign-in in' do
      let(:config_arg) do
        described_class.new(
          domain_id: 'domain-4139', enabled: true, signin_enabled: true, restrict_to: nil
        )
      end

      it 'keeps the inherited restriction available' do
        expect(available).to be(true)
      end
    end

    context 'on a canonical host' do
      let(:custom_host) { false }

      it 'has no custom-domain capabilities to intersect' do
        expect(available).to be(true)
      end
    end

    context 'when nothing is restricted at all' do
      let(:global) { nil }

      it 'never manufactures unavailability — an unrestricted install must not go dark' do
        expect(available).to be(true)
      end
    end

    context 'when the custom host could not be classified' do
      let(:domain_id_arg) { nil }

      it 'keeps the global verdict; there is no domain to narrow it' do
        expect(available).to be(true)
      end
    end

    context 'when the operator restriction itself died after boot' do
      let(:global)      { 'sso' }
      let(:custom_host) { false }
      let(:auth_config) do
        instance_double(
          Onetime::AuthConfig, email_auth_enabled?: true, restrict_to: 'sso', restrict_to_available?: false
        )
      end

      it 'reports unavailable from the global half (ADR-034#degradation-is-fail-closed)' do
        expect(available).to be(false)
      end
    end
  end

  # The `global` VALUE the three consumers hand to the resolver (#4140). Same
  # rule as restriction_available_for_request? above and for the same reason:
  # the SSO HOST PIN used to be written twice (display serializer, route gate)
  # and omitted entirely by the settings API, which therefore reported
  # `unrestricted` for a host whose routes the gate restricted to SSO.
  describe '.inherited_restrict_to' do
    subject(:inherited) do
      described_class.inherited_restrict_to(
        config_arg, domain_id: domain_id_arg, custom_host: custom_host
      )
    end

    let(:config_arg)    { nil }
    let(:domain_id_arg) { 'domain-4139' }
    let(:custom_host)   { true }
    let(:auth_config) do
      instance_double(Onetime::AuthConfig, email_auth_enabled?: true, restrict_to: nil)
    end

    context 'on an SSO-only custom host with no SigninConfig' do
      it "pins 'sso' — password and email default OFF there" do
        expect(inherited).to eq('sso')
      end
    end

    context 'on a custom host with no SSO available' do
      before do
        allow(Onetime::CustomDomain::SsoConfig).to receive(:sso_available_for_tenant_host?)
          .with('domain-4139').and_return(false)
      end

      it 'inherits the operator restriction (here: none)' do
        expect(inherited).to be_nil
      end
    end

    context 'on a canonical host' do
      let(:custom_host) { false }

      it 'never pins — the pin is a custom-host property' do
        expect(inherited).to be_nil
      end
    end

    context 'when the custom host could not be classified' do
      let(:domain_id_arg) { nil }

      it 'never pins — there is no domain whose SSO could be probed' do
        expect(inherited).to be_nil
      end
    end

    context 'when an enabled SigninConfig speaks' do
      let(:config_arg) do
        described_class.new(
          domain_id: 'domain-4139', enabled: true, signin_enabled: true, restrict_to: 'password'
        )
      end
      let(:auth_config) do
        instance_double(Onetime::AuthConfig, email_auth_enabled?: true, restrict_to: 'password')
      end

      it 'declines the pin — intersecting it would resolve :conflict and lock the host out' do
        expect(inherited).to eq('password')
      end
    end

    context 'when a DISABLED SigninConfig exists on an SSO-only host' do
      let(:config_arg) do
        described_class.new(
          domain_id: 'domain-4139', enabled: false, signin_enabled: true, restrict_to: 'password'
        )
      end

      it "still pins 'sso' — a disabled config has not spoken" do
        expect(inherited).to eq('sso')
      end
    end
  end
end

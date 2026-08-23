# apps/web/core/spec/views/serializers/authentication_serializer_spec.rb
#
# frozen_string_literal: true

# Coverage for AuthenticationSerializer.password_auth_permitted? (#3886).
#
# The flag is the POLICY axis of password management, independent of the
# credential-presence axis (has_password): it answers "may this account hold
# a local password?" and is false only when auth mode is not 'full', when the
# app-level restrict_to='sso' mode is active, or when the request's custom
# domain enforces SSO-only. The frontend combines both axes: no password +
# permitted => Set-password affordance; no password + not permitted =>
# SSO-managed empty state.
#
# All collaborators are stubbed — no Redis or SQL required.
#
# Run with:
#   bundle exec rspec apps/web/core/spec/views/serializers/authentication_serializer_spec.rb

require_relative File.join(Onetime::HOME, 'spec', 'spec_helper')
require_relative '../../../views/serializers'

RSpec.describe Core::Views::AuthenticationSerializer do
  let(:display_domain) { 'secrets.acme.com' }
  let(:domain_id) { 'cd_test_domain_123' }

  let(:full_auth_config) do
    instance_double(Onetime::AuthConfig, full_enabled?: true, restrict_to: nil)
  end

  before do
    allow(Onetime).to receive(:auth_config).and_return(full_auth_config)
  end

  describe '.password_auth_permitted?' do
    subject(:permitted) { described_class.send(:password_auth_permitted?, view_vars) }

    context 'canonical domain (no display_domain), full auth mode' do
      let(:view_vars) { {} }

      it 'defaults to true for consumer accounts' do
        expect(permitted).to be(true)
      end
    end

    context 'auth mode is not full' do
      let(:view_vars) { {} }
      let(:full_auth_config) do
        instance_double(Onetime::AuthConfig, full_enabled?: false)
      end

      it 'returns false (no password management surface in simple mode)' do
        expect(permitted).to be(false)
      end
    end

    context 'app-level SSO-only mode (restrict_to=sso)' do
      let(:view_vars) { {} }
      let(:full_auth_config) do
        instance_double(Onetime::AuthConfig, full_enabled?: true, restrict_to: 'sso')
      end

      it 'returns false' do
        expect(permitted).to be(false)
      end
    end

    context 'app-level restrict_to=password' do
      let(:view_vars) { {} }
      let(:full_auth_config) do
        instance_double(Onetime::AuthConfig, full_enabled?: true, restrict_to: 'password')
      end

      it 'returns true (only sso restriction forbids passwords)' do
        expect(permitted).to be(true)
      end
    end

    context 'custom domain with tenant SSO' do
      let(:view_vars) { { 'display_domain' => display_domain } }
      let(:custom_domain) { instance_double(Onetime::CustomDomain, identifier: domain_id) }
      let(:sso_config) do
        instance_double(Onetime::CustomDomain::SsoConfig, enforce_sso_only?: enforce)
      end

      before do
        allow(Onetime::CustomDomain).to receive(:from_display_domain)
          .with(display_domain).and_return(custom_domain)
        allow(Onetime::CustomDomain::SsoConfig).to receive(:find_by_domain_id)
          .with(domain_id).and_return(sso_config)
        allow(Onetime::CustomDomain::SsoConfig).to receive(:tenant_sso_available_for?)
          .with(domain_id, sso_config: sso_config).and_return(sso_available)
      end

      context 'SSO configured, available, and ENFORCED' do
        let(:enforce) { true }
        let(:sso_available) { true }

        it 'returns false (per-domain enforcement wins)' do
          expect(permitted).to be(false)
        end
      end

      context 'SSO configured and available but NOT enforced' do
        let(:enforce) { false }
        let(:sso_available) { true }

        it 'returns true (enforcement is the opt-in, per the #3886 decision)' do
          expect(permitted).to be(true)
        end
      end

      context 'SSO config present but unavailable (e.g. disabled)' do
        let(:enforce) { true }
        let(:sso_available) { false }

        it 'returns true (an unavailable config cannot lock accounts to an IdP)' do
          expect(permitted).to be(true)
        end
      end
    end

    context 'custom domain without an SSO config' do
      let(:view_vars) { { 'display_domain' => display_domain } }
      let(:custom_domain) { instance_double(Onetime::CustomDomain, identifier: domain_id) }

      before do
        allow(Onetime::CustomDomain).to receive(:from_display_domain)
          .with(display_domain).and_return(custom_domain)
        allow(Onetime::CustomDomain::SsoConfig).to receive(:find_by_domain_id)
          .with(domain_id).and_return(nil)
      end

      it 'returns true' do
        expect(permitted).to be(true)
      end
    end

    # The resolver reads through the RAISING finder (#4157), so this failure
    # is the one production actually produces — its fail-open sibling
    # load_by_display_domain would have swallowed it into "no tenant config"
    # and quietly advertised the affordance.
    context 'domain resolution raises (e.g. Redis unavailable)' do
      let(:view_vars) { { 'display_domain' => display_domain, 'domain_strategy' => :custom } }

      before do
        allow(OT).to receive(:le)
        allow(Onetime::CustomDomain).to receive(:from_display_domain)
          .and_raise(Redis::ConnectionError, 'redis down')
      end

      it 'fails closed: an unresolvable domain policy does not advertise the affordance' do
        expect(permitted).to be(false)
      end
    end

    # DomainStrategy publishes display_domain UNCONDITIONALLY (canonical
    # fallback), so a canonical request does reach the lookup — but no
    # per-domain policy can be lost there, and failing it closed would hide
    # the password form from every consumer account during a blip.
    context 'canonical host whose lookup fails' do
      let(:view_vars) do
        { 'display_domain' => 'example.com', 'domain_strategy' => :canonical }
      end

      before do
        allow(OT).to receive(:le)
        allow(Onetime::CustomDomain).to receive(:from_display_domain)
          .and_raise(Redis::ConnectionError, 'redis down')
      end

      it 'stays permissive: an operator host has no tenant policy to fail closed on' do
        expect(permitted).to be(true)
      end
    end

    context 'canonical domain when storage is down' do
      let(:view_vars) { {} }

      before do
        # Would raise if reached — the empty display_domain early return must
        # keep canonical-domain requests off the fallible lookup path.
        allow(Onetime::CustomDomain).to receive(:from_display_domain)
          .and_raise(StandardError, 'redis down')
      end

      it 'stays permissive: no tenant policy to resolve, no lookup attempted' do
        expect(permitted).to be(true)
      end
    end
  end

  describe 'output template' do
    it 'defaults password_auth_permitted to true' do
      expect(described_class.output_template['password_auth_permitted']).to be(true)
    end
  end
end

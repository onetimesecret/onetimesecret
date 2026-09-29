# frozen_string_literal: true

require 'spec_helper'
require 'climate_control'

RSpec.describe Onetime::CustomDomain::SsoConfig do
  describe '.sso_available_for_tenant_host?' do
    let(:domain_id) { 'tenant-saml-availability' }
    let(:providers) { [{ 'route_name' => 'saml' }] }
    let(:custom_domain) { instance_double(Onetime::CustomDomain, verified: true) }
    let(:auth_config) do
      instance_double(Onetime::AuthConfig,
        allow_platform_fallback_for_tenants?: true,
        sso_enabled?: true,
        sso_providers: providers)
    end

    # The install-wide switch (#4604) is on for every example except the
    # ones about the switch itself.
    around do |example|
      ClimateControl.modify(SAML_ENABLED: 'true') { example.run }
    end

    before do
      allow(Onetime).to receive(:auth_config).and_return(auth_config)
      allow(Onetime::CustomDomain::SigninConfig).to receive(:global_auth_enabled).and_return(true)
      allow(Onetime::CustomDomain::SigninConfig).to receive(:sso_permitted_for?).with(domain_id).and_return(true)
      allow(described_class).to receive(:find_by_domain_id).with(domain_id).and_return(nil)
    end

    it 'does not advertise native tenant SAML while SAML_ENABLED is off, on an otherwise available record' do
      allow(described_class).to receive(:find_by_domain_id).with(domain_id)
        .and_return(instance_double(
          described_class,
          enabled?: true,
          provider_type: 'saml',
          custom_domain: custom_domain,
        ))
      allow(auth_config).to receive(:allow_platform_fallback_for_tenants?).and_return(false)
      ClimateControl.modify(SAML_ENABLED: nil) do
        expect(described_class.sso_available_for_tenant_host?(domain_id)).to be false
      end
      ClimateControl.modify(SAML_ENABLED: 'true') do
        expect(described_class.sso_available_for_tenant_host?(domain_id)).to be true
      end
    end

    it 'does not advertise SAML-only platform fallback on a tenant host' do
      expect(described_class.sso_available_for_tenant_host?(domain_id)).to be false
    end

    it 'does not advertise SAML fallback when the tenant config is disabled' do
      allow(described_class).to receive(:find_by_domain_id).with(domain_id)
        .and_return(instance_double(described_class, enabled?: false, provider_type: 'saml'))
      expect(described_class.sso_available_for_tenant_host?(domain_id)).to be false
    end

    it 'follows the operator-renamed SAML route' do
      ClimateControl.modify(SAML_ROUTE_NAME: 'corporate') do
        allow(auth_config).to receive(:sso_providers).and_return([{ 'route_name' => 'corporate' }])
        expect(described_class.sso_available_for_tenant_host?(domain_id)).to be false
      end
    end

    it 'retains mixed OAuth and SAML fallback through the OAuth provider' do
      allow(auth_config).to receive(:sso_providers).and_return(providers + [{ 'route_name' => 'oidc' }])
      expect(described_class.sso_available_for_tenant_host?(domain_id)).to be true
    end

    it 'retains OAuth-only fallback' do
      allow(auth_config).to receive(:sso_providers).and_return([{ 'route_name' => 'google' }])
      expect(described_class.sso_available_for_tenant_host?(domain_id)).to be true
    end

    it 'requires a routable provider even when SSO is globally enabled' do
      [[], [{ 'route_name' => '' }]].each do |list|
        allow(auth_config).to receive(:sso_providers).and_return(list)
        expect(described_class.sso_available_for_tenant_host?(domain_id)).to be false
      end
    end

    it 'preserves native tenant SAML independently of platform fallback and providers' do
      allow(described_class).to receive(:find_by_domain_id).with(domain_id)
        .and_return(instance_double(
          described_class,
          enabled?: true,
          provider_type: 'saml',
          custom_domain: custom_domain,
        ))
      allow(auth_config).to receive(:allow_platform_fallback_for_tenants?).and_return(false)
      allow(auth_config).to receive(:sso_enabled?).and_return(false)
      expect(described_class.sso_available_for_tenant_host?(domain_id)).to be true
      expect(auth_config).not_to have_received(:sso_providers)
    end

    it 'retains the platform fallback opt-in and global kill switches' do
      allow(auth_config).to receive(:sso_providers).and_return([{ 'route_name' => 'oidc' }])
      allow(auth_config).to receive(:allow_platform_fallback_for_tenants?).and_return(false)
      expect(described_class.sso_available_for_tenant_host?(domain_id)).to be false
      allow(auth_config).to receive(:allow_platform_fallback_for_tenants?).and_return(true)
      allow(Onetime::CustomDomain::SigninConfig).to receive(:global_auth_enabled).and_return(false)
      expect(described_class.sso_available_for_tenant_host?(domain_id)).to be false
    end
  end
end

# apps/api/organizations/spec/logic/sso_config/patch_sso_config_spec.rb
#
# frozen_string_literal: true

require_relative File.join(Onetime::HOME, 'spec', 'spec_helper')
require 'organizations/logic'

RSpec.describe OrganizationAPI::Logic::SsoConfig::PatchSsoConfig do
  # Configure Familia encryption for testing
  before(:all) do
    key_v1 = 'test_encryption_key_32bytes_ok!!'
    key_v2 = 'another_test_key_for_testing_!!'

    Familia.configure do |config|
      config.encryption_keys = {
        v1: Base64.strict_encode64(key_v1),
        v2: Base64.strict_encode64(key_v2),
      }
      config.current_key_version = :v1
      config.encryption_personalization = 'SsoConfigTest'
    end
  end

  let(:customer) do
    instance_double(
      Onetime::Customer,
      objid: 'cust-123',
      custid: 'cust-123',
      extid: 'ext-cust-123',
      email: 'owner@example.com',
      anonymous?: false,
      role: 'customer',
    )
  end

  let(:organization) do
    instance_double(
      Onetime::Organization,
      objid: 'org-123',
      extid: 'ext-org-123',
      display_name: 'Test Organization',
    )
  end

  let(:session) { { 'csrf' => 'test-csrf-token' } }

  let(:strategy_result) do
    double('StrategyResult',
      session: session,
      user: customer,
      authenticated?: true,
      metadata: {},
    )
  end

  let(:valid_entra_params) do
    {
      'extid' => 'ext-org-123',
      'provider_type' => 'entra_id',
      'display_name' => 'Contoso SSO',
      'client_id' => 'client-id-123',
      'client_secret' => 'client-secret-456',
      'tenant_id' => 'tenant-uuid-789',
      'allowed_domains' => ['contoso.com', 'contoso.onmicrosoft.com'],
      'enabled' => true,
    }
  end

  let(:valid_oidc_params) do
    {
      'extid' => 'ext-org-123',
      'provider_type' => 'oidc',
      'display_name' => 'Generic OIDC',
      'client_id' => 'oidc-client-id',
      'client_secret' => 'oidc-client-secret',
      'issuer' => 'https://auth.example.com',
      'allowed_domains' => ['example.com'],
      'enabled' => true,
    }
  end

  subject(:logic) { described_class.new(strategy_result, valid_entra_params) }

  before do
    allow(OT).to receive(:info)
    allow(OT).to receive(:ld)
    allow(OT).to receive(:li)
  end

  describe '#process_params' do
    it 'extracts provider_type from params' do
      expect(logic.instance_variable_get(:@provider_type)).to eq('entra_id')
    end

    it 'extracts client_id from params' do
      expect(logic.instance_variable_get(:@client_id)).to eq('client-id-123')
    end

    it 'extracts tenant_id from params' do
      expect(logic.instance_variable_get(:@tenant_id)).to eq('tenant-uuid-789')
    end

    it 'parses allowed_domains array' do
      expect(logic.instance_variable_get(:@allowed_domains)).to eq(['contoso.com', 'contoso.onmicrosoft.com'])
    end

    it 'parses enabled as boolean' do
      expect(logic.instance_variable_get(:@enabled)).to be true
    end

    context 'with comma-separated allowed_domains string' do
      let(:params) do
        valid_entra_params.merge('allowed_domains' => 'foo.com, bar.com, BAZ.COM')
      end

      subject(:logic) { described_class.new(strategy_result, params) }

      it 'parses and normalizes domains' do
        domains = logic.instance_variable_get(:@allowed_domains)
        expect(domains).to eq(['foo.com', 'bar.com', 'baz.com'])
      end
    end
  end

  describe '#raise_concerns' do
    context 'when customer is anonymous' do
      let(:customer) do
        instance_double(
          Onetime::Customer,
          objid: 'anon-123',
          anonymous?: true,
        )
      end

      it 'raises unauthorized error' do
        expect { logic.raise_concerns }.to raise_error(
          OT::FormError,
          'Authentication required',
        )
      end
    end

    context 'when provider_type is missing' do
      let(:params) { valid_entra_params.merge('provider_type' => '') }
      subject(:logic) { described_class.new(strategy_result, params) }

      before do
        allow(Onetime::Organization).to receive(:find_by_extid).and_return(organization)
        allow(organization).to receive(:owner?).and_return(true)
        allow(Onetime::OrgSsoConfig).to receive(:find_by_org_id).and_return(nil)
      end

      it 'raises missing error' do
        expect { logic.raise_concerns }.to raise_error(
          OT::FormError,
          'Provider type is required',
        )
      end
    end

    context 'when provider_type is invalid' do
      let(:params) { valid_entra_params.merge('provider_type' => 'unsupported') }
      subject(:logic) { described_class.new(strategy_result, params) }

      before do
        allow(Onetime::Organization).to receive(:find_by_extid).and_return(organization)
        allow(organization).to receive(:owner?).and_return(true)
        allow(Onetime::OrgSsoConfig).to receive(:find_by_org_id).and_return(nil)
      end

      it 'raises invalid error' do
        expect { logic.raise_concerns }.to raise_error(
          OT::FormError,
          /Invalid provider type/,
        )
      end
    end

    context 'when client_id is missing' do
      let(:params) { valid_entra_params.merge('client_id' => '') }
      subject(:logic) { described_class.new(strategy_result, params) }

      before do
        allow(Onetime::Organization).to receive(:find_by_extid).and_return(organization)
        allow(organization).to receive(:owner?).and_return(true)
        allow(Onetime::OrgSsoConfig).to receive(:find_by_org_id).and_return(nil)
      end

      it 'raises missing error' do
        expect { logic.raise_concerns }.to raise_error(
          OT::FormError,
          'Client ID is required',
        )
      end
    end

    context 'when creating new config without client_secret' do
      let(:params) { valid_entra_params.merge('client_secret' => '') }
      subject(:logic) { described_class.new(strategy_result, params) }

      before do
        allow(Onetime::Organization).to receive(:find_by_extid).and_return(organization)
        allow(organization).to receive(:owner?).and_return(true)
        allow(Onetime::OrgSsoConfig).to receive(:find_by_org_id).and_return(nil)
      end

      it 'raises missing error' do
        expect { logic.raise_concerns }.to raise_error(
          OT::FormError,
          'Client secret is required',
        )
      end
    end

    context 'when OIDC provider without issuer' do
      let(:params) { valid_oidc_params.merge('issuer' => '') }
      subject(:logic) { described_class.new(strategy_result, params) }

      before do
        allow(Onetime::Organization).to receive(:find_by_extid).and_return(organization)
        allow(organization).to receive(:owner?).and_return(true)
        allow(Onetime::OrgSsoConfig).to receive(:find_by_org_id).and_return(nil)
      end

      it 'raises missing error' do
        expect { logic.raise_concerns }.to raise_error(
          OT::FormError,
          'Issuer URL is required for OIDC provider',
        )
      end
    end

    context 'when Entra ID provider without tenant_id' do
      let(:params) { valid_entra_params.merge('tenant_id' => '') }
      subject(:logic) { described_class.new(strategy_result, params) }

      before do
        allow(Onetime::Organization).to receive(:find_by_extid).and_return(organization)
        allow(organization).to receive(:owner?).and_return(true)
        allow(Onetime::OrgSsoConfig).to receive(:find_by_org_id).and_return(nil)
      end

      it 'raises missing error' do
        expect { logic.raise_concerns }.to raise_error(
          OT::FormError,
          'Tenant ID is required for Entra ID provider',
        )
      end
    end
  end

  describe '#process' do
    context 'when creating new config' do
      before do
        allow(Onetime::Organization).to receive(:find_by_extid).with('ext-org-123').and_return(organization)
        allow(organization).to receive(:owner?).with(customer).and_return(true)
        allow(Onetime::OrgSsoConfig).to receive(:find_by_org_id).with('org-123').and_return(nil)
        # Call raise_concerns to set up instance variables before process
        logic.raise_concerns
      end

      it 'creates a new SSO config' do
        # Use a real OrgSsoConfig instance instead of mocks to avoid reveal block issues
        new_config = Onetime::OrgSsoConfig.new(
          org_id: 'org-123',
          provider_type: 'entra_id',
          display_name: 'Contoso SSO',
          tenant_id: 'tenant-uuid-789',
          enabled: 'true',
        )
        new_config.client_id = 'client-id-123'
        new_config.client_secret = 'client-secret-456'
        new_config.allowed_domains = ['contoso.com', 'contoso.onmicrosoft.com']
        new_config.define_singleton_method(:save) { true }

        expect(Onetime::OrgSsoConfig).to receive(:create!).with(
          hash_including(
            org_id: 'org-123',
            provider_type: 'entra_id',
            client_id: 'client-id-123',
            client_secret: 'client-secret-456',
          ),
        ).and_return(new_config)

        result = logic.process
        expect(result[:record][:provider_type]).to eq('entra_id')
      end
    end

    context 'when updating existing config' do
      let(:existing_config) do
        config = Onetime::OrgSsoConfig.new(
          org_id: 'org-123',
          provider_type: 'entra_id',
          display_name: 'Old Name',
          tenant_id: 'old-tenant',
          enabled: 'false',
        )
        config.client_id = 'old-client-id'
        config.client_secret = 'old-secret'
        config.define_singleton_method(:save) { true }
        config
      end

      before do
        allow(Onetime::Organization).to receive(:find_by_extid).with('ext-org-123').and_return(organization)
        allow(organization).to receive(:owner?).with(customer).and_return(true)
        allow(Onetime::OrgSsoConfig).to receive(:find_by_org_id).with('org-123').and_return(existing_config)
        # Call raise_concerns to set up instance variables before process
        logic.raise_concerns
      end

      it 'updates the existing config' do
        result = logic.process

        expect(existing_config.provider_type).to eq('entra_id')
        expect(existing_config.display_name).to eq('Contoso SSO')
        expect(existing_config.tenant_id).to eq('tenant-uuid-789')
        expect(existing_config.enabled).to eq('true')
      end

      it 'updates client_id' do
        logic.process
        expect(existing_config.client_id.reveal { it }).to eq('client-id-123')
      end

      it 'updates client_secret when provided' do
        logic.process
        expect(existing_config.client_secret.reveal { it }).to eq('client-secret-456')
      end

      context 'when client_secret is not provided (PATCH semantics)' do
        let(:params) { valid_entra_params.merge('client_secret' => '') }
        subject(:logic) { described_class.new(strategy_result, params) }

        before do
          # Need to re-call raise_concerns after creating new subject
          logic.raise_concerns
        end

        it 'preserves existing client_secret' do
          logic.process
          expect(existing_config.client_secret.reveal { it }).to eq('old-secret')
        end
      end

      context 'when display_name is empty (PATCH semantics)' do
        let(:params) { valid_entra_params.merge('display_name' => '') }
        subject(:logic) { described_class.new(strategy_result, params) }

        before do
          logic.raise_concerns
        end

        it 'preserves existing display_name' do
          logic.process
          expect(existing_config.display_name).to eq('Old Name')
        end
      end

      context 'when tenant_id is empty (PATCH semantics)' do
        let(:params) { valid_entra_params.merge('tenant_id' => '') }
        subject(:logic) { described_class.new(strategy_result, params) }

        before do
          logic.raise_concerns
        end

        it 'preserves existing tenant_id' do
          logic.process
          expect(existing_config.tenant_id).to eq('old-tenant')
        end
      end

      # Provider switching tests document intentional PATCH semantics:
      # When switching providers, provider-specific fields from the old provider
      # are preserved rather than cleared. This is intentional behavior that
      # allows reverting to the old provider without re-entering credentials.
      context 'when switching provider from entra_id to google (PATCH semantics)' do
        let(:params) do
          {
            'extid' => 'ext-org-123',
            'provider_type' => 'google',
            'client_id' => 'new-google-client-id',
            'client_secret' => 'new-google-secret',
            'allowed_domains' => ['google-domain.com'],
            'enabled' => true,
          }
        end
        subject(:logic) { described_class.new(strategy_result, params) }

        before do
          logic.raise_concerns
        end

        it 'preserves tenant_id from previous entra_id config (intentional PATCH semantics)' do
          logic.process
          expect(existing_config.provider_type).to eq('google')
          # tenant_id is preserved even though Google provider does not use it
          # This is intentional: allows reverting to entra_id without re-entering tenant_id
          expect(existing_config.tenant_id).to eq('old-tenant')
        end
      end

      context 'when switching provider from oidc to entra_id (PATCH semantics)' do
        let(:existing_config) do
          config = Onetime::OrgSsoConfig.new(
            org_id: 'org-123',
            provider_type: 'oidc',
            display_name: 'OIDC Provider',
            enabled: 'false',
          )
          config.client_id = 'old-client-id'
          config.client_secret = 'old-secret'
          config.issuer = 'https://auth.example.com'
          config.define_singleton_method(:save) { true }
          config
        end

        let(:params) do
          {
            'extid' => 'ext-org-123',
            'provider_type' => 'entra_id',
            'client_id' => 'entra-client-id',
            'client_secret' => 'entra-secret',
            'tenant_id' => 'new-tenant-id',
            'allowed_domains' => ['contoso.com'],
            'enabled' => true,
          }
        end
        subject(:logic) { described_class.new(strategy_result, params) }

        before do
          logic.raise_concerns
        end

        it 'preserves issuer from previous oidc config (intentional PATCH semantics)' do
          logic.process
          expect(existing_config.provider_type).to eq('entra_id')
          # issuer is preserved even though Entra ID provider does not use it
          # This is intentional: allows reverting to oidc without re-entering issuer URL
          expect(existing_config.issuer).to eq('https://auth.example.com')
        end
      end

      # allowed_domains tests document the PUT-like behavior within PATCH:
      # Unlike other optional fields, allowed_domains always replaces the
      # existing value rather than merging or preserving when empty.
      context 'when allowed_domains is empty array (replaces existing)' do
        let(:existing_config) do
          config = Onetime::OrgSsoConfig.new(
            org_id: 'org-123',
            provider_type: 'entra_id',
            display_name: 'Old Name',
            tenant_id: 'old-tenant',
            enabled: 'false',
          )
          config.client_id = 'old-client-id'
          config.client_secret = 'old-secret'
          config.allowed_domains = ['existing.com', 'old-domain.com']
          config.define_singleton_method(:save) { true }
          config
        end

        let(:params) do
          valid_entra_params.merge('allowed_domains' => [])
        end
        subject(:logic) { described_class.new(strategy_result, params) }

        before do
          logic.raise_concerns
        end

        it 'clears existing allowed_domains (PUT semantics for this field)' do
          logic.process
          # Unlike other optional fields, allowed_domains uses PUT semantics:
          # an empty array explicitly clears the existing domains
          expect(existing_config.allowed_domains).to eq([])
        end
      end

      context 'when allowed_domains is omitted (nil)' do
        let(:existing_config) do
          config = Onetime::OrgSsoConfig.new(
            org_id: 'org-123',
            provider_type: 'entra_id',
            display_name: 'Old Name',
            tenant_id: 'old-tenant',
            enabled: 'false',
          )
          config.client_id = 'old-client-id'
          config.client_secret = 'old-secret'
          config.allowed_domains = ['existing.com', 'old-domain.com']
          config.define_singleton_method(:save) { true }
          config
        end

        let(:params) do
          {
            'extid' => 'ext-org-123',
            'provider_type' => 'entra_id',
            'client_id' => 'client-id-123',
            'client_secret' => 'client-secret-456',
            'tenant_id' => 'tenant-uuid-789',
            # allowed_domains intentionally omitted (nil)
            'enabled' => true,
          }
        end
        subject(:logic) { described_class.new(strategy_result, params) }

        before do
          logic.raise_concerns
        end

        it 'replaces with empty array when omitted (PUT semantics for this field)' do
          logic.process
          # Note: omitting allowed_domains results in empty array, not preservation
          # This is consistent PUT-like behavior for the allowed_domains field
          expect(existing_config.allowed_domains).to eq([])
        end
      end
    end
  end

  describe '#success_data' do
    let(:sso_config) do
      config = Onetime::OrgSsoConfig.new(
        org_id: 'org-123',
        provider_type: 'entra_id',
        display_name: 'Contoso SSO',
        tenant_id: 'tenant-uuid-789',
        enabled: 'true',
      )
      config.client_id = 'client-id-123'
      config.client_secret = 'client-secret-456'
      config.allowed_domains = ['contoso.com']
      config.define_singleton_method(:save) { true }
      config
    end

    before do
      allow(Onetime::Organization).to receive(:find_by_extid).and_return(organization)
      allow(organization).to receive(:owner?).and_return(true)
      allow(Onetime::OrgSsoConfig).to receive(:find_by_org_id).and_return(nil)
      allow(Onetime::OrgSsoConfig).to receive(:create!).and_return(sso_config)
      # Call raise_concerns to set up instance variables before process
      logic.raise_concerns
    end

    it 'includes user_id' do
      result = logic.process
      expect(result[:user_id]).to eq('ext-cust-123')
    end

    it 'includes serialized record' do
      result = logic.process
      expect(result[:record]).to have_key(:org_id)
      expect(result[:record]).to have_key(:provider_type)
      expect(result[:record]).to have_key(:client_secret_masked)
    end

    it 'masks client_secret in response' do
      result = logic.process
      # "client-secret-456" -> last 4 chars are "-456"
      expect(result[:record][:client_secret_masked]).to eq('••••••••-456')
    end

    it 'includes timestamps as Unix integers' do
      result = logic.process
      record = result[:record]

      expect(record[:created_at]).to be_a(Integer)
      expect(record[:updated_at]).to be_a(Integer)
    end
  end

  describe 'URL sanitization' do
    let(:params) { valid_oidc_params.merge('issuer' => 'http://insecure.example.com') }
    subject(:logic) { described_class.new(strategy_result, params) }

    before do
      allow(Onetime::Organization).to receive(:find_by_extid).and_return(organization)
      allow(organization).to receive(:owner?).and_return(true)
      allow(Onetime::OrgSsoConfig).to receive(:find_by_org_id).and_return(nil)
    end

    it 'rejects non-HTTPS issuer URLs' do
      # The sanitize_url method returns empty string for non-HTTPS URLs
      # Which triggers the validation error
      expect { logic.raise_concerns }.to raise_error(
        OT::FormError,
        'Issuer URL is required for OIDC provider',
      )
    end
  end
end

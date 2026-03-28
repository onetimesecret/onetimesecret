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

      it 'updates the updated timestamp' do
        # Set an old timestamp first
        existing_config.updated = 1000000000

        logic.process

        # After update, updated timestamp should be current (greater than old value)
        expect(existing_config.updated.to_i).to be > 1000000000
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

      context 'when provider_type is omitted (PATCH semantics)' do
        let(:params) do
          {
            'extid' => 'ext-org-123',
            # provider_type intentionally omitted - should use existing
            'display_name' => 'Updated Name',
            'client_id' => 'new-client-id',
            'client_secret' => 'new-secret',
          }
        end
        subject(:logic) { described_class.new(strategy_result, params) }

        before do
          logic.raise_concerns
        end

        it 'uses existing provider_type when not provided' do
          logic.process
          expect(existing_config.provider_type).to eq('entra_id')
        end
      end

      context 'when client_id is omitted (PATCH semantics)' do
        let(:params) do
          {
            'extid' => 'ext-org-123',
            'provider_type' => 'entra_id',
            'display_name' => 'Updated Name',
            # client_id intentionally omitted - should use existing
            'client_secret' => 'new-secret',
          }
        end
        subject(:logic) { described_class.new(strategy_result, params) }

        before do
          logic.raise_concerns
        end

        it 'uses existing client_id when not provided' do
          logic.process
          expect(existing_config.client_id.reveal { it }).to eq('old-client-id')
        end
      end

      context 'when enabled is omitted (PATCH semantics)' do
        let(:existing_config) do
          config = Onetime::OrgSsoConfig.new(
            org_id: 'org-123',
            provider_type: 'entra_id',
            display_name: 'Old Name',
            tenant_id: 'old-tenant',
            enabled: 'true', # SSO is currently enabled
          )
          config.client_id = 'old-client-id'
          config.client_secret = 'old-secret'
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
            # 'enabled' intentionally omitted (nil) - should preserve existing
          }
        end
        subject(:logic) { described_class.new(strategy_result, params) }

        before do
          logic.raise_concerns
        end

        it 'preserves existing enabled state when not provided' do
          logic.process
          # enabled was 'true' before and should remain 'true' since we didn't provide it
          expect(existing_config.enabled).to eq('true')
        end
      end

      context 'when enabled is explicitly set to false (PATCH semantics)' do
        let(:existing_config) do
          config = Onetime::OrgSsoConfig.new(
            org_id: 'org-123',
            provider_type: 'entra_id',
            display_name: 'Old Name',
            tenant_id: 'old-tenant',
            enabled: 'true', # SSO is currently enabled
          )
          config.client_id = 'old-client-id'
          config.client_secret = 'old-secret'
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
            'enabled' => false, # Explicitly disable SSO
          }
        end
        subject(:logic) { described_class.new(strategy_result, params) }

        before do
          logic.raise_concerns
        end

        it 'disables SSO when enabled is explicitly false' do
          logic.process
          # Explicit false should override existing 'true' and disable SSO
          expect(existing_config.enabled).to eq('false')
        end

        it 'distinguishes explicit false from omitted field' do
          # This test documents the semantic difference:
          # - omitted (nil): preserve existing state
          # - explicit false: disable SSO
          logic.process
          expect(existing_config.enabled).not_to eq('true')
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

        it 'preserves existing domains when omitted (PATCH semantics)' do
          logic.process
          # PATCH semantics: omitting allowed_domains preserves existing values
          # Use empty array [] to explicitly clear domains
          expect(existing_config.allowed_domains).to eq(['existing.com', 'old-domain.com'])
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

    it 'includes non-zero timestamps' do
      # Set timestamps to simulate create! initialization
      sso_config.created = Familia.now.to_i
      sso_config.updated = Familia.now.to_i

      result = logic.process
      record = result[:record]

      expect(record[:created_at]).to be > 0
      expect(record[:updated_at]).to be > 0
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

  describe 'SSRF protection' do
    before do
      allow(Onetime::Organization).to receive(:find_by_extid).and_return(organization)
      allow(organization).to receive(:owner?).and_return(true)
      allow(Onetime::OrgSsoConfig).to receive(:find_by_org_id).and_return(nil)
    end

    context 'when issuer points to localhost' do
      let(:params) { valid_oidc_params.merge('issuer' => 'https://localhost/auth') }
      subject(:logic) { described_class.new(strategy_result, params) }

      it 'rejects localhost as invalid issuer' do
        expect { logic.raise_concerns }.to raise_error(
          OT::FormError,
          'Issuer URL must be a valid HTTPS URL pointing to a public host',
        )
      end
    end

    context 'when issuer points to 127.0.0.1' do
      let(:params) { valid_oidc_params.merge('issuer' => 'https://127.0.0.1/auth') }
      subject(:logic) { described_class.new(strategy_result, params) }

      it 'rejects loopback IP as invalid issuer' do
        expect { logic.raise_concerns }.to raise_error(
          OT::FormError,
          'Issuer URL must be a valid HTTPS URL pointing to a public host',
        )
      end
    end

    context 'when issuer points to private network (192.168.x.x)' do
      let(:params) { valid_oidc_params.merge('issuer' => 'https://192.168.1.1/auth') }
      subject(:logic) { described_class.new(strategy_result, params) }

      it 'rejects private IP as invalid issuer' do
        expect { logic.raise_concerns }.to raise_error(
          OT::FormError,
          'Issuer URL must be a valid HTTPS URL pointing to a public host',
        )
      end
    end

    context 'when issuer points to private network (10.x.x.x)' do
      let(:params) { valid_oidc_params.merge('issuer' => 'https://10.0.0.1/auth') }
      subject(:logic) { described_class.new(strategy_result, params) }

      it 'rejects private IP as invalid issuer' do
        expect { logic.raise_concerns }.to raise_error(
          OT::FormError,
          'Issuer URL must be a valid HTTPS URL pointing to a public host',
        )
      end
    end

    context 'when issuer points to .local domain' do
      let(:params) { valid_oidc_params.merge('issuer' => 'https://auth.local/auth') }
      subject(:logic) { described_class.new(strategy_result, params) }

      it 'rejects .local domain as invalid issuer' do
        expect { logic.raise_concerns }.to raise_error(
          OT::FormError,
          'Issuer URL must be a valid HTTPS URL pointing to a public host',
        )
      end
    end

    context 'when issuer is a valid public URL' do
      let(:params) { valid_oidc_params.merge('issuer' => 'https://auth.example.com') }
      subject(:logic) { described_class.new(strategy_result, params) }

      it 'accepts valid public issuer URL' do
        # Should not raise SSRF error - would succeed or fail for other reasons
        expect { logic.raise_concerns }.not_to raise_error
      end
    end
  end
end

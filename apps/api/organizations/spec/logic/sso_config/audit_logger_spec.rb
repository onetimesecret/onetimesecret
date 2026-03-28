# apps/api/organizations/spec/logic/sso_config/audit_logger_spec.rb
#
# frozen_string_literal: true

require_relative File.join(Onetime::HOME, 'spec', 'spec_helper')
require 'organizations/logic'

RSpec.describe OrganizationAPI::Logic::SsoConfig::AuditLogger do
  # Test class that includes the module
  let(:test_class) do
    Class.new do
      include OrganizationAPI::Logic::SsoConfig::AuditLogger

      attr_accessor :strategy_result

      def initialize(strategy_result = nil)
        @strategy_result = strategy_result
      end
    end
  end

  let(:organization) do
    instance_double(
      Onetime::Organization,
      objid: 'org-123',
      extid: 'ext-org-123',
    )
  end

  let(:actor) do
    instance_double(
      Onetime::Customer,
      custid: 'cust-123',
      email: 'admin@example.com',
    )
  end

  let(:strategy_result) do
    double('StrategyResult',
      metadata: { ip: '192.168.1.100' },
    )
  end

  subject(:logger) { test_class.new(strategy_result) }

  before do
    allow(OT).to receive(:info)
  end

  describe '#log_sso_audit_event' do
    it 'logs event with structured JSON payload' do
      expect(OT).to receive(:info) do |message, json_payload|
        expect(message).to eq('[SSO_AUDIT] sso_config_created')

        payload = JSON.parse(json_payload)
        expect(payload['event']).to eq('sso_config_created')
        expect(payload['org_id']).to eq('org-123')
        expect(payload['org_extid']).to eq('ext-org-123')
        expect(payload['actor_id']).to eq('cust-123')
        expect(payload['actor_email']).to eq('admin@example.com')
        expect(payload['provider_type']).to eq('entra_id')
        expect(payload['timestamp']).to be_a(Integer)
      end

      logger.log_sso_audit_event(
        event: :sso_config_created,
        org: organization,
        actor: actor,
        provider_type: 'entra_id',
      )
    end

    it 'includes IP address from strategy_result metadata' do
      expect(OT).to receive(:info) do |_message, json_payload|
        payload = JSON.parse(json_payload)
        expect(payload['ip_address']).to eq('192.168.1.100')
      end

      logger.log_sso_audit_event(
        event: :sso_config_created,
        org: organization,
        actor: actor,
        provider_type: 'entra_id',
      )
    end

    it 'includes changes hash when provided' do
      changes = {
        'display_name' => { from: 'Old Name', to: 'New Name' },
        'enabled' => { from: false, to: true },
      }

      expect(OT).to receive(:info) do |_message, json_payload|
        payload = JSON.parse(json_payload)
        expect(payload['changes']).to eq({
          'display_name' => { 'from' => 'Old Name', 'to' => 'New Name' },
          'enabled' => { 'from' => false, 'to' => true },
        })
      end

      logger.log_sso_audit_event(
        event: :sso_config_updated,
        org: organization,
        actor: actor,
        provider_type: 'entra_id',
        changes: changes,
      )
    end

    it 'excludes empty changes hash' do
      expect(OT).to receive(:info) do |_message, json_payload|
        payload = JSON.parse(json_payload)
        expect(payload).not_to have_key('changes')
      end

      logger.log_sso_audit_event(
        event: :sso_config_updated,
        org: organization,
        actor: actor,
        provider_type: 'entra_id',
        changes: {},
      )
    end

    it 'handles nil strategy_result gracefully' do
      logger_without_strategy = test_class.new(nil)

      expect(OT).to receive(:info) do |_message, json_payload|
        payload = JSON.parse(json_payload)
        expect(payload['ip_address']).to be_nil
      end

      logger_without_strategy.log_sso_audit_event(
        event: :sso_config_deleted,
        org: organization,
        actor: actor,
        provider_type: 'oidc',
      )
    end
  end

  describe '#compute_sso_changes' do
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
        config.encryption_personalization = 'AuditLoggerTest'
      end
    end

    let(:existing_config) do
      config = Onetime::OrgSsoConfig.new(
        org_id: 'org-123',
        provider_type: 'entra_id',
        display_name: 'Old Name',
        tenant_id: 'old-tenant',
        enabled: 'false',
      )
      config.client_id = 'old-client-id'
      config.client_secret = 'old-client-secret'
      config.allowed_domains = ['old.com']
      config
    end

    context 'with safe field changes' do
      it 'detects display_name change' do
        new_params = { 'display_name' => 'New Name' }
        changes = logger.compute_sso_changes(existing_config, new_params)

        expect(changes['display_name']).to eq({ from: 'Old Name', to: 'New Name' })
      end

      it 'detects provider_type change' do
        new_params = { 'provider_type' => 'google' }
        changes = logger.compute_sso_changes(existing_config, new_params)

        expect(changes['provider_type']).to eq({ from: 'entra_id', to: 'google' })
      end

      it 'detects enabled state change' do
        new_params = { 'enabled' => true }
        changes = logger.compute_sso_changes(existing_config, new_params)

        expect(changes['enabled']).to eq({ from: false, to: true })
      end

      it 'detects allowed_domains change' do
        new_params = { 'allowed_domains' => ['new.com', 'another.com'] }
        changes = logger.compute_sso_changes(existing_config, new_params)

        expect(changes).to have_key('allowed_domains')
        expect(changes['allowed_domains'][:to]).to contain_exactly('another.com', 'new.com')
      end

      it 'ignores unchanged safe fields' do
        new_params = { 'display_name' => 'Old Name' }
        changes = logger.compute_sso_changes(existing_config, new_params)

        expect(changes).not_to have_key('display_name')
      end
    end

    context 'with sensitive field changes' do
      it 'indicates client_id changed without logging value' do
        new_params = { 'client_id' => 'new-client-id' }
        changes = logger.compute_sso_changes(existing_config, new_params)

        expect(changes['client_id']).to eq({ changed: true })
        expect(changes['client_id']).not_to have_key(:from)
        expect(changes['client_id']).not_to have_key(:to)
      end

      it 'indicates client_secret changed without logging value' do
        new_params = { 'client_secret' => 'new-secret-value' }
        changes = logger.compute_sso_changes(existing_config, new_params)

        expect(changes['client_secret']).to eq({ changed: true })
        expect(changes['client_secret']).not_to have_key(:from)
        expect(changes['client_secret']).not_to have_key(:to)
      end

      it 'does not include sensitive fields when not provided' do
        new_params = { 'display_name' => 'New Name' }
        changes = logger.compute_sso_changes(existing_config, new_params)

        expect(changes).not_to have_key('client_id')
        expect(changes).not_to have_key('client_secret')
      end
    end

    context 'with no changes' do
      it 'returns empty hash when nothing changed' do
        new_params = {
          'provider_type' => 'entra_id',
          'display_name' => 'Old Name',
          'enabled' => false,
        }
        changes = logger.compute_sso_changes(existing_config, new_params)

        # Should only have sensitive field changes if they were provided
        expect(changes.keys).not_to include('provider_type', 'display_name', 'enabled')
      end
    end

    context 'with partial params (PATCH semantics)' do
      it 'does not report changes for unprovided fields' do
        # Only updating display_name, not touching enabled or provider_type
        new_params = { 'display_name' => 'New Name' }
        changes = logger.compute_sso_changes(existing_config, new_params)

        # Should only include display_name change, not enabled (which would be
        # falsely detected as changing from false to false if we didn't check
        # field_provided?)
        expect(changes.keys).to eq(['display_name'])
        expect(changes['display_name']).to eq({ from: 'Old Name', to: 'New Name' })
      end

      it 'ignores enabled field when not provided in params' do
        # Config has enabled: false, sending empty params should not detect
        # any enabled change
        new_params = {}
        changes = logger.compute_sso_changes(existing_config, new_params)

        expect(changes).to be_empty
      end

      it 'detects enabled change when explicitly provided as true' do
        new_params = { 'enabled' => true }
        changes = logger.compute_sso_changes(existing_config, new_params)

        expect(changes['enabled']).to eq({ from: false, to: true })
      end

      it 'detects no change when enabled explicitly set to same value' do
        new_params = { 'enabled' => false }
        changes = logger.compute_sso_changes(existing_config, new_params)

        expect(changes).not_to have_key('enabled')
      end
    end
  end

  describe 'sensitive fields constant' do
    it 'includes client_id' do
      expect(described_class::SENSITIVE_FIELDS).to include('client_id')
    end

    it 'includes client_secret' do
      expect(described_class::SENSITIVE_FIELDS).to include('client_secret')
    end
  end

  describe 'safe fields constant' do
    it 'includes provider_type' do
      expect(described_class::SAFE_FIELDS).to include('provider_type')
    end

    it 'includes display_name' do
      expect(described_class::SAFE_FIELDS).to include('display_name')
    end

    it 'includes enabled' do
      expect(described_class::SAFE_FIELDS).to include('enabled')
    end

    it 'includes tenant_id' do
      expect(described_class::SAFE_FIELDS).to include('tenant_id')
    end

    it 'includes issuer' do
      expect(described_class::SAFE_FIELDS).to include('issuer')
    end

    it 'includes allowed_domains' do
      expect(described_class::SAFE_FIELDS).to include('allowed_domains')
    end

    it 'does not include client_id' do
      expect(described_class::SAFE_FIELDS).not_to include('client_id')
    end

    it 'does not include client_secret' do
      expect(described_class::SAFE_FIELDS).not_to include('client_secret')
    end
  end
end

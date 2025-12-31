# spec/integration/authentication/full_mode/audit_logging_config_spec.rb
#
# frozen_string_literal: true

# Tests for Rodauth audit logging configuration.
# These tests verify that Auth::Config has the correct audit logging
# settings configured. No database or boot required - just config validation.

require 'spec_helper'

RSpec.describe 'Audit Logging Configuration', type: :integration do
  # Auth::Config provides Rodauth configuration. It doesn't need boot,
  # just the class loaded. Using allocate to get config without instantiation.
  let(:config) { Auth::Config.allocate }

  before(:all) do
    require 'auth/config'
  end

  describe 'feature configuration' do
    it 'includes audit_logging feature' do
      expect(config.features).to include(:audit_logging)
    end
  end

  describe 'table configuration' do
    it 'uses account_authentication_audit_logs table' do
      expect(config.audit_logging_table).to eq(:account_authentication_audit_logs)
    end
  end

  describe 'column configuration' do
    it 'uses account_id column for account references' do
      expect(config.audit_logging_account_id_column).to eq(:account_id)
    end

    it 'uses message column for audit messages' do
      expect(config.audit_logging_message_column).to eq(:message)
    end

    it 'uses metadata column for additional data' do
      expect(config.audit_logging_metadata_column).to eq(:metadata)
    end
  end
end

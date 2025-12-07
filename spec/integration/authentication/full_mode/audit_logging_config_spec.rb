# Generated rspec code for /Users/d/Projects/opensource/onetime/onetimesecret/try/integration/authentication/full_mode/audit_logging_config_try.rb
# Updated: 2025-12-06 19:02:12 -0800

require 'spec_helper'

RSpec.describe 'audit_logging_config_try', :full_auth_mode do
  before(:all) do
    require_relative '../../../../apps/web/auth/config'
  end

  it 'Audit logging feature is enabled' do
    result = begin
      Auth::Config.allocate.features.include?(:audit_logging)
    end
    expect(result).to eq(true)
  end

  it 'Audit logging table is configured' do
    result = begin
      Auth::Config.allocate.audit_logging_table
    end
    expect(result).to eq(:account_authentication_audit_logs)
  end

  it 'Audit logging account_id column is configured' do
    result = begin
      Auth::Config.allocate.audit_logging_account_id_column
    end
    expect(result).to eq(:account_id)
  end

  it 'Audit logging message column is configured' do
    result = begin
      Auth::Config.allocate.audit_logging_message_column
    end
    expect(result).to eq(:message)
  end

  it 'Audit logging metadata column is configured' do
    result = begin
      Auth::Config.allocate.audit_logging_metadata_column
    end
    expect(result).to eq(:metadata)
  end

end

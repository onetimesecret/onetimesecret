# frozen_string_literal: true

require 'spec_helper'
require 'yaml'
require 'onetime/authorization/registry'

RSpec.describe Onetime::Authorization::Registry, :aggregate_failures do
  let(:catalog) { YAML.load_file(File.expand_path('../../../../etc/examples/billing.example.yaml', __dir__)) }

  it 'classifies the example catalog and every token carried by legacy plan definitions' do
    expect(catalog.fetch('entitlements').keys - described_class::KINDS.keys).to be_empty
    catalog.fetch('plans').each_value do |plan|
      expect(Array(plan['entitlements']) - described_class::KINDS.keys).to be_empty
    end
  end

  it 'keeps role capabilities, features and account authority disjoint' do
    expect(described_class.features & described_class.capabilities).to be_empty
    expect(described_class.kind('manage_orgs')).to eq('account')
    expect(described_class.kind('manage_teams')).to eq('reserved')
    expect(described_class.kind('unregistered')).to be_nil
    expect(described_class.features).to include('api_access', 'audit_logs')
    expect(described_class.role_capabilities.fetch('admin')).to include('manage_domains')
    expect(described_class.role_capabilities.fetch('admin')).not_to include('manage_billing')
  end
end

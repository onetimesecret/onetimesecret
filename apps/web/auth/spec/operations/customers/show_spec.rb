# apps/web/auth/spec/operations/customers/show_spec.rb
#
# frozen_string_literal: true

# Unit tests for Auth::Operations::Customers::Show.
#
# Covers: not-found result when nothing resolves, and the organizations
# summary for a resolved customer. Read-only op — writes no audit event.
#
# Run: pnpm run test:rspec apps/web/auth/spec/operations/customers/show_spec.rb

require 'spec_helper'
require 'auth/operations/customers/show'

RSpec.describe Auth::Operations::Customers::Show do
  it 'returns found? false and empty organizations when nothing resolves' do
    allow(Onetime::Customer).to receive(:load_by_extid_or_email).and_return(nil)
    allow(Onetime::Customer).to receive(:load).and_return(nil)

    result = described_class.new(identifier: 'nobody@nowhere.example').call

    expect(result.found?).to be(false)
    expect(result.organizations).to eq([])
  end

  it 'resolves by extid/email via load_by_extid_or_email' do
    customer = double('Customer', exists?: true, extid: 'ur_x')
    allow(customer).to receive(:respond_to?).with(:organization_instances).and_return(false)
    allow(Onetime::Customer).to receive(:load_by_extid_or_email).with('ur_x').and_return(customer)

    result = described_class.new(identifier: 'ur_x').call

    expect(result.found?).to be(true)
    expect(result.customer).to eq(customer)
  end

  describe 'rodauth_admin_url (outbound deep link, read-only external_id join)' do
    let(:customer) do
      cust = double('Customer', exists?: true, extid: 'ur_x')
      allow(cust).to receive(:respond_to?).with(:organization_instances).and_return(false)
      cust
    end

    it 'is nil when nothing resolves' do
      allow(Onetime::Customer).to receive(:load_by_extid_or_email).and_return(nil)
      allow(Onetime::Customer).to receive(:load).and_return(nil)

      expect(described_class.new(identifier: 'nobody').call.rodauth_admin_url).to be_nil
    end

    it 'is nil when the admin URL is not configured or auth mode is not full' do
      allow(Onetime::RodauthAdmin).to receive(:account_url).with('ur_x').and_return(nil)

      expect(described_class.new(customer: customer).call.rodauth_admin_url).to be_nil
    end

    it 'carries the account deep link keyed by extid when linkable' do
      allow(Onetime::RodauthAdmin).to receive(:account_url).with('ur_x')
        .and_return('http://127.0.0.1:9292/account?q=ur_x')

      expect(described_class.new(customer: customer).call.rodauth_admin_url)
        .to eq('http://127.0.0.1:9292/account?q=ur_x')
    end
  end

  it 'summarizes organizations for a resolved customer' do
    org = double('org', objid: 'oid', extid: 'or_x', display_name: 'Acme')
    org_set = double('org_set', to_a: [org])
    customer = double('Customer', exists?: true, extid: 'ur_x', organization_instances: org_set)

    result = described_class.new(customer: customer).call

    expect(result.found?).to be(true)
    expect(result.organizations).to eq([{ objid: 'oid', extid: 'or_x', display_name: 'Acme' }])
  end
end

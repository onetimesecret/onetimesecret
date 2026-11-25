# frozen_string_literal: true

require 'spec_helper'
require 'organizations/logic'

# Organization API logic specs mirror the app's logic/organizations directory.
RSpec.describe OrganizationAPI::Logic::Organizations::UpdateSharingPolicy, :aggregate_failures do # rubocop:disable RSpec/SpecFilePathFormat
  let(:customer) { Onetime::Customer.new(email: 'owner@example.com') }
  let(:organization) { Onetime::Organization.new(display_name: 'First') }
  let(:other) { Onetime::Organization.new(display_name: 'Second') }
  let(:membership) do
    instance_double(Onetime::OrganizationMembership, active?: true, has_capability?: true, owner?: true, domain_scoped?: false)
  end
  let(:policy) do
    {
      'recipient_email_mode' => 'restricted',
      'recipient_email_domains' => [' Example.com ', 'BÜCHER.de', 'xn--bcher-kva.de', 'mail.example.com'],
      'passphrase_required' => true,
      'max_ttl' => 604_800,
    }
  end

  def update(org, value)
    actor = Otto::Security::Authentication::StrategyResult.new(
      user: customer, session: {}, auth_method: 'sessionauth', strategy_name: 'sessionauth', metadata: {},
    )
    logic = described_class.new(actor, { 'extid' => org.extid, 'sharing_policy' => value })
    logic.raise_concerns
    logic.process
  end

  before do
    allow(Onetime::Organization).to receive(:find_by_extid).with(organization.extid).and_return(organization)
    allow(Onetime::Organization).to receive(:find_by_extid).with(other.extid).and_return(other)
    allow(Onetime::OrganizationMembership).to receive(:find_by_org_customer).and_return(nil)
    allow(Onetime::OrganizationMembership).to receive(:find_by_org_customer).with(organization.objid, customer.objid).and_return(membership)
    allow(organization).to receive(:safe_dump) { { objid: organization.objid, sharing_policy: organization.sharing_policy } }
  end

  after { organization.sharing_policy_json.delete! }

  it 'writes one organization, returns canonical domains, and leaves legacy organizations unrestricted' do
    expect(organization.sharing_policy).to eq(Onetime::Organization::SharingPolicy::DEFAULT)
    normalized = policy.merge('recipient_email_domains' => %w[example.com xn--bcher-kva.de mail.example.com])
    expect(update(organization, policy).dig(:record, :sharing_policy)).to eq(normalized)
    expect(Onetime::Organization.new(objid: organization.objid).sharing_policy).to eq(normalized)
    expect(other.sharing_policy).to eq(Onetime::Organization::SharingPolicy::DEFAULT)
    expect { update(other, policy) }.to raise_error(Onetime::Forbidden)
  end

  it 'requires ownership even with organization-wide management access' do
    allow(membership).to receive(:owner?).and_return(false)
    expect { update(organization, policy) }.to raise_error(Onetime::Forbidden) do |error|
      expect(error.error_key).to eq('api.organizations.errors.organization_owner_required')
    end
    expect(organization.sharing_policy).to eq(Onetime::Organization::SharingPolicy::DEFAULT)
  end

  {
    'recipient_email_mode' => %w[unknown],
    'passphrase_required' => ['false'],
    'max_ttl' => [59, '60', 60.5, 2**53],
    'recipient_email_domains' => [[], 'example.com', [nil], ['example.com:443'], ['*.example.com'],
                                  ['mail..example.com'], ['-foo.example'], ['ｅｘａｍｐｌｅ.com']],
  }.each do |field, invalid_values|
    invalid_values.each do |value|
      it "rejects #{field}=#{value.inspect} without replacing the saved policy" do
        update(organization, policy)
        saved = organization.sharing_policy
        expect { update(organization, policy.merge(field => value)) }
          .to raise_error(Onetime::FormError)
        expect(organization.sharing_policy).to eq(saved)
      end
    end
  end

  it 'requires a complete policy with known fields' do
    [nil, {}, policy.except('passphrase_required'), policy.merge('pasphrase_required' => false)].each do |invalid|
      expect { update(organization, invalid) }.to raise_error(Onetime::FormError)
    end
  end

  it 'requires an explicit replacement when storage contains invalid policy data' do
    organization.sharing_policy_json = '{}'
    allow(OT).to receive(:le)
    expect(organization.sharing_policy).to eq(Onetime::Organization::SharingPolicy::STRICTEST)
    expect(organization.sharing_policy_invalid?).to be(true)
    update(organization, policy)
    expect(organization.sharing_policy_invalid?).to be(false)
    expect(organization.sharing_policy['max_ttl']).to eq(604_800)
  end
end

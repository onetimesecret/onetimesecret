# apps/api/colonel/spec/logic/colonel/verify_custom_domain_spec.rb
#
# frozen_string_literal: true

require_relative File.join(Onetime::HOME, 'spec', 'spec_helper')
require 'colonel/logic'

RSpec.describe ColonelAPI::Logic::Colonel::VerifyCustomDomain do
  let(:colonel) do
    instance_double(
      Onetime::Customer,
      objid: 'cust_colonel',
      extid: 'ur_colonel',
      role: 'colonel',
      verified?: true,
      anonymous?: false,
    )
  end
  let(:strategy_result) do
    double(
      'StrategyResult',
      session: {},
      user: colonel,
      auth_method: 'sessionauth',
      metadata: {},
    )
  end
  let(:custom_domain) do
    double(
      'CustomDomain',
      domainid: 'cd_internal',
      extid: 'cd_target',
      display_domain: 'secrets.example.com',
      verification_state: :verified,
      verified: true,
      verified_by_override: false,
      resolving: true,
      ready?: true,
      updated: 1_700_003_600,
    )
  end
  let(:result) do
    double(
      'VerifyDomain::Result',
      previous_state: :verified,
      current_state: :verified,
      changed?: false,
      dns_validated: true,
      dns_indeterminate: false,
      dns_message: 'TXT record validated',
      dns_outcome: :validated,
      ssl_ready: nil,
      is_resolving: nil,
      error: nil,
    )
  end

  before do
    allow(OT).to receive(:info)
    allow(Onetime::CustomDomain).to receive(:find_by_extid).and_return(custom_domain)
    allow(Onetime::Operations::AdminVerifyDomain).to receive(:new)
      .and_return(instance_double(Onetime::Operations::AdminVerifyDomain, call: result))
  end

  it 'preserves unknown SSL and resolving values in the response' do
    logic = described_class.new(strategy_result, 'extid' => 'cd_target')
    logic.raise_concerns

    data = logic.process

    expect(data[:details]).to include(ssl_ready: nil, is_resolving: nil)
  end
end

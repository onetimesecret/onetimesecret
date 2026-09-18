# apps/api/colonel/spec/logic/colonel/verify_custom_domain_spec.rb
#
# frozen_string_literal: true

require_relative File.join(Onetime::HOME, 'spec', 'spec_helper')
require 'colonel/logic'

# The verify response carries the status answers of this check in `details`.
# Both have three values: true, false, or nil when the check could not tell
# (provider status UNKNOWN, API or probe failure). nil is sent as JSON null,
# never as false.
RSpec.describe ColonelAPI::Logic::Colonel::VerifyCustomDomain do
  let(:colonel) do
    instance_double(Onetime::Customer,
      objid: 'cust_colonel', extid: 'ur_colonel', role: 'colonel',
      verified?: true, anonymous?: false)
  end

  let(:strategy_result) do
    double('StrategyResult', session: {}, user: colonel, auth_method: 'sessionauth', metadata: {})
  end

  let(:custom_domain) do
    double('CustomDomain',
      domainid: 'cd_internal', extid: 'cd_target', display_domain: 'secrets.example.com',
      verification_state: :verified, verified: true, verified_by_override: false,
      resolving: true, ready?: true, updated: 1)
  end

  def verify_result(is_resolving:, ssl_ready:)
    Onetime::Operations::VerifyDomain::Result.new(
      domain: custom_domain, previous_state: :verified, current_state: :verified,
      dns_validated: true, ssl_ready: ssl_ready, is_resolving: is_resolving,
      persisted: true, error: nil
    )
  end

  def details_for(result)
    allow(Onetime::Operations::AdminVerifyDomain).to receive(:new)
      .and_return(instance_double(Onetime::Operations::AdminVerifyDomain, call: result))

    logic = described_class.new(strategy_result, { 'extid' => 'cd_target' })
    logic.process_params
    logic.raise_concerns
    logic.process[:details]
  end

  before do
    allow(OT).to receive(:info)
    allow(Onetime::CustomDomain).to receive(:find_by_extid).and_return(custom_domain)
  end

  it 'reports a known status as booleans' do
    expect(details_for(verify_result(is_resolving: true, ssl_ready: false)))
      .to include(is_resolving: true, ssl_ready: false)
  end

  it 'reports a status the check could not tell as nil, not false' do
    details = details_for(verify_result(is_resolving: nil, ssl_ready: nil))

    expect(details).to include(is_resolving: nil, ssl_ready: nil)
    expect(JSON.parse(details.to_json)).to include('is_resolving' => nil, 'ssl_ready' => nil)
  end

  it 'keeps the stored resolving flag a boolean: it is the last known answer' do
    allow(Onetime::Operations::AdminVerifyDomain).to receive(:new)
      .and_return(instance_double(Onetime::Operations::AdminVerifyDomain,
        call: verify_result(is_resolving: nil, ssl_ready: nil)))

    logic = described_class.new(strategy_result, { 'extid' => 'cd_target' })
    logic.process_params
    logic.raise_concerns

    expect(logic.process[:record]).to include(resolving: true)
  end
end

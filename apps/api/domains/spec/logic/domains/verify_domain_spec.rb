# apps/api/domains/spec/logic/domains/verify_domain_spec.rb
#
# frozen_string_literal: true

require_relative File.join(Onetime::HOME, 'spec', 'spec_helper')
require_relative '../../../../../../apps/api/domains/application'

RSpec.describe DomainsAPI::Logic::Domains::VerifyDomain do
  let(:customer) do
    instance_double(
      Onetime::Customer,
      custid: 'cust123',
      objid: 'cust123',
      extid: 'ext-cust123',
      anonymous?: false,
    )
  end

  let(:custom_domain) do
    instance_double(
      Onetime::CustomDomain,
      identifier: 'domain123',
      display_domain: 'example.com',
      safe_dump: { 'display_domain' => 'example.com', 'verified' => false },
    )
  end

  let(:strategy_result) do
    double(
      'StrategyResult',
      session: { 'authenticated' => true },
      user: customer,
      authenticated?: true,
      metadata: {},
    )
  end

  let(:logic) { described_class.new(strategy_result, { 'extid' => 'dm123' }) }

  let(:cluster) { { 'type' => 'caddy_on_demand', 'validation_strategy' => 'caddy_on_demand' } }

  # A real Result, so dns_outcome is the operation's own derivation rather
  # than a value restated here.
  def operation_result(**overrides)
    Onetime::Operations::VerifyDomain::Result.new(
      domain: custom_domain,
      previous_state: :pending,
      current_state: :pending,
      dns_validated: false,
      ssl_ready: nil,
      is_resolving: true,
      persisted: true,
      error: nil,
      **overrides,
    )
  end

  def process_with(result)
    allow(Onetime::Operations::VerifyDomain).to receive(:new)
      .with(domain: custom_domain, persist: true)
      .and_return(instance_double(Onetime::Operations::VerifyDomain, call: result))
    logic.process
  end

  before do
    allow(OT).to receive(:info)
    allow(OT).to receive(:ld)
    allow(Onetime::DomainValidation::Features).to receive(:safe_dump).and_return(cluster)
    logic.instance_variable_set(:@custom_domain, custom_domain)
  end

  describe '#process' do
    it 'runs the shared operation with persistence on' do
      process_with(operation_result)

      expect(Onetime::Operations::VerifyDomain).to have_received(:new)
        .with(domain: custom_domain, persist: true)
    end

    it "returns GetDomain's record and cluster" do
      data = process_with(operation_result(dns_validated: true, current_state: :verified))

      expect(data[:record]).to eq(custom_domain.safe_dump)
      expect(data[:details][:cluster]).to eq(cluster)
    end
  end

  # "Could not tell" stays distinguishable from "no" in the payload: the
  # record alone reads the same for both, because an indeterminate check
  # leaves `verified` as it was.
  describe 'TXT outcome in details' do
    {
      'a matching record' => [
        { dns_validated: true, current_state: :verified }, 'validated', false
      ],
      'a missing or wrong record' => [
        { dns_validated: false }, 'failed', false
      ],
      'a check that produced no answer' => [
        { dns_indeterminate: true }, 'indeterminate', true
      ],
      'no answer for longer than the confirmation window' => [
        { dns_indeterminate: true, confirmation_expired: true, previous_state: :verified }, 'confirmation_expired', true
      ],
      'a failed check held by an operator override' => [
        { override_held: true, previous_state: :verified, current_state: :verified }, 'override_held', false
      ],
    }.each do |label, (attrs, outcome, indeterminate)|
      it "reports #{outcome} for #{label}" do
        details = process_with(operation_result(**attrs))[:details]

        expect(details['dns_outcome']).to eq(outcome)
        expect(details['dns_indeterminate']).to be(indeterminate)
      end
    end

    it 'uses string keys, serialised as plain JSON values' do
      details = process_with(operation_result(dns_indeterminate: true))[:details]
      json    = JSON.parse(JSON.generate(details))

      expect(details.keys).to include('dns_outcome', 'dns_indeterminate')
      expect(details).not_to have_key(:dns_outcome)
      expect(json).to include('dns_outcome' => 'indeterminate', 'dns_indeterminate' => true)
    end

    it 'reports an operation error as indeterminate, not as failed' do
      details = process_with(
        operation_result(dns_indeterminate: true, error: 'resolver unavailable', persisted: false),
      )[:details]

      expect(details['dns_outcome']).to eq('indeterminate')
    end

    it 'adds nothing before the operation has run' do
      expect(logic.success_data[:details].keys).to eq([:cluster])
    end
  end
end

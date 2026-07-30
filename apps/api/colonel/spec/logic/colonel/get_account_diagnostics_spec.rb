# apps/api/colonel/spec/logic/colonel/get_account_diagnostics_spec.rb
#
# frozen_string_literal: true

require_relative File.join(Onetime::HOME, 'spec', 'spec_helper')
require 'colonel/logic'
require 'auth/operations/customers/diagnose'

# Adapter-layer coverage only. The diagnosis itself is covered by
# apps/web/auth/spec/operations/customers/diagnose_spec.rb. These examples
# assert what THIS adapter owns: identifier resolution (including the
# email-only arm that must NOT 404), audit_limit parsing, and the
# record/details envelope.
RSpec.describe ColonelAPI::Logic::Colonel::GetAccountDiagnostics do
  let(:op) { instance_double(Auth::Operations::Customers::Diagnose) }

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

  let(:target) do
    instance_double(
      Onetime::Customer,
      objid: 'cust_target',
      extid: 'ur_target',
      email: 'user@example.com',
      exists?: true,
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

  let(:findings) do
    [{ severity: :critical, code: :locked_out, message: 'Lockout active' }]
  end

  def op_result(customer: target)
    Auth::Operations::Customers::Diagnose::Result.new(
      customer: customer,
      sections: { auth_account: { available: true, found: !customer.nil? } },
      findings: findings,
    )
  end

  def logic_for(params = {})
    described_class.new(
      strategy_result,
      { 'user_id' => 'ur_target' }.merge(params),
    )
  end

  before do
    allow(OT).to receive(:info)
    allow(OT).to receive(:ld)
    allow(OT).to receive(:li)
    allow(Onetime::Customer).to receive_messages(load_by_extid_or_email: target, load: nil)
    allow(op).to receive(:call).and_return(op_result)
    allow(Auth::Operations::Customers::Diagnose).to receive(:new).and_return(op)
  end

  it 'diagnoses a resolved customer and emits the record/details envelope' do
    logic = logic_for
    logic.raise_concerns
    data  = logic.process

    expect(Auth::Operations::Customers::Diagnose).to have_received(:new)
      .with(hash_including(customer: target, identifier: 'ur_target'))
    expect(data[:record]).to eq(identifier: 'ur_target', found: true)
    expect(data[:details][:findings]).to eq(findings)
    expect(data[:details][:sections]).to have_key(:auth_account)
  end

  it '404s for an unresolvable non-email identifier' do
    allow(Onetime::Customer).to receive(:load_by_extid_or_email).and_return(nil)

    logic = logic_for('user_id' => 'ur_ghost')

    expect { logic.raise_concerns }.to raise_error(Onetime::RecordNotFound)
  end

  it 'does NOT 404 for an unresolvable email — the diagnosis is the answer' do
    allow(Onetime::Customer).to receive(:load_by_extid_or_email).and_return(nil)
    allow(op).to receive(:call).and_return(op_result(customer: nil))

    logic = logic_for('user_id' => 'ghost@example.com')
    logic.raise_concerns
    data  = logic.process

    expect(data[:record][:found]).to be(false)
    expect(Auth::Operations::Customers::Diagnose).to have_received(:new)
      .with(hash_including(identifier: 'ghost@example.com'))
  end

  describe 'audit_limit parsing' do
    it 'passes a positive integer through' do
      logic = logic_for('audit_limit' => '50')
      logic.raise_concerns
      logic.process

      expect(Auth::Operations::Customers::Diagnose).to have_received(:new)
        .with(hash_including(audit_log_limit: 50))
    end

    it 'falls back to the default when absent or garbage' do
      logic = logic_for('audit_limit' => 'lots')
      logic.raise_concerns
      logic.process

      expect(Auth::Operations::Customers::Diagnose).to have_received(:new)
        .with(hash_including(
                audit_log_limit: Auth::Operations::Customers::Diagnose::DEFAULT_AUDIT_LOG_LIMIT,
              ),
             )
    end
  end
end

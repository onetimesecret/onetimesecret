# apps/api/colonel/spec/logic/colonel/get_account_diagnostics_spec.rb
#
# frozen_string_literal: true

require_relative File.join(Onetime::HOME, 'spec', 'spec_helper')
require 'colonel/logic'
require 'auth/database'
require 'auth/operations/customers/diagnose'

# Adapter-layer coverage only. The diagnosis itself is covered by
# apps/web/auth/spec/operations/customers/diagnose_spec.rb. These examples
# assert what THIS adapter owns: identifier resolution (including the
# unresolvable identifiers that must NOT 404), audit_limit parsing, and the
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

  # `account_found` is separable from `customer` so the orphan shape — an
  # accounts row with no customer record — is expressible.
  def op_result(customer: target, account_found: !customer.nil?)
    Auth::Operations::Customers::Diagnose::Result.new(
      customer: customer,
      sections: { auth_account: { available: true, found: account_found } },
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

  # The case this endpoint exists to name: an accounts row with no customer
  # record, addressed by its extid. Diagnose resolves it straight from the
  # authdb; a 404 here would withhold the diagnosis and diverge from
  # `bin/ots customers diagnose`, which prints it and exits 1.
  it 'delegates an unresolvable extid so orphans are diagnosed, not 404d' do
    allow(Onetime::Customer).to receive(:load_by_extid_or_email).and_return(nil)
    allow(op).to receive(:call).and_return(op_result(customer: nil, account_found: true))

    logic = logic_for('user_id' => 'ur_orphan')
    logic.raise_concerns
    data  = logic.process

    expect(Auth::Operations::Customers::Diagnose).to have_received(:new)
      .with(hash_including(identifier: 'ur_orphan', customer: nil))
    expect(data[:record][:found]).to be(true)
  end

  it 'answers found:false — not 404 — when the identifier names nothing anywhere' do
    allow(Onetime::Customer).to receive(:load_by_extid_or_email).and_return(nil)
    allow(op).to receive(:call).and_return(op_result(customer: nil))

    logic = logic_for('user_id' => '999999')
    logic.raise_concerns

    expect(logic.process[:record][:found]).to be(false)
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

  # This response is JSON-encoded by the API layer, and customer fields come off
  # Valkey as BYTES: a truncated multibyte write leaves a field that is not
  # valid UTF-8, on which JSON.generate raises JSON::GeneratorError. Without a
  # guard, one corrupt field 500s the break-glass endpoint — the one support
  # reaches for when things are already broken.
  #
  # The real op runs here (no double): the guard lives behind it
  # (Diagnose#utf8_safe_deep) so this adapter and the CLI cannot drift, and a
  # stubbed op would assert nothing about that.
  describe 'a section value carrying an invalid byte sequence' do
    let(:corrupt_customer) do
      instance_double(
        Onetime::Customer,
        exists?: true,
        anonymous?: false,
        objid: 'cust_target',
        extid: 'ur_target',
        email: 'user@example.com',
        role: 'customer',
        verified?: true,
        suspended?: true,
        suspended_at: 1_700_000_000.0,
        # Reaches `findings` too: the :suspended message interpolates it. The
        # bad byte sits MID-value on both fields so a scrub that truncated at
        # the first one ('abu', 'e') is distinguishable from one that keeps the
        # surrounding text and marks the bad run.
        suspended_reason: "abu\xFFse",
        created: 1_600_000_000.0,
        last_login: nil,
        # A leaf no finding reads, so `sections` is asserted on its own.
        locale: "e\xFFn",
        planid: 'free_v1',
      )
    end

    let(:limiter) do
      instance_double(Onetime::Operations::RateLimit::Inspect).tap do |double|
        allow(double).to receive(:call).and_return(
          Onetime::Operations::RateLimit::Inspect::Result.new(
            kind: 'login', subject: 'user@example.com', entries: [],
          ),
        )
      end
    end

    let(:sections) { subject_data[:details][:sections] }

    let(:subject_data) do
      logic = logic_for
      logic.raise_concerns
      logic.process
    end

    before do
      allow(Auth::Operations::Customers::Diagnose).to receive(:new).and_call_original
      allow(Onetime::Customer).to receive(:load_by_extid_or_email).and_return(corrupt_customer)
      # Simple mode: the SQL sections degrade by design, leaving the Redis
      # customer record — the source of the bad bytes — as the payload.
      allow(Auth::Database).to receive(:connection).and_return(nil)
      allow(Onetime::Operations::RateLimit::Inspect).to receive(:new).and_return(limiter)
    end

    it 'serializes to JSON instead of raising' do
      expect { JSON.generate(subject_data) }.not_to raise_error
    end

    # Scrubbed, not rescued-away and not blanked: everything around the bad
    # bytes survives, because in a diagnose read-out the mangled field may be
    # the answer. A rescue that dropped the field (or the whole section) would
    # hide it.
    #
    # The bad run is MARKED with U+FFFD, not dropped — asserted exactly, because
    # "no longer raises" would pass either way and this is the whole point of
    # the mode. Dropping used to be required to protect the CLI's mask (a marker
    # inside an address defeats EMAIL_PATTERN); OT::Utils.obscure_email now
    # strips markers itself, so this panel can keep the corruption signal. A
    # corrupt locale that renders as a clean 'en' tells the operator the record
    # is fine when it is not.
    it 'keeps the corruption visible as a marker, with the readable text around it' do
      expect(sections[:customer][:locale]).to eq("e\u{FFFD}n")
    end

    # Findings interpolate section values, so the encoder would raise on this
    # message even with the sections themselves clean.
    it 'scrubs findings derived from the corrupt section too' do
      message = subject_data[:details][:findings]
        .find { |finding| finding[:code] == :suspended }[:message]

      expect(message).to include("suspended (abu\u{FFFD}se)")
      expect(message.valid_encoding?).to be(true)
    end

    # The colonel API is authenticated and deliberately returns FULL addresses —
    # the CLI's obscure-by-default mask belongs to the CLI alone. Guards against
    # importing the whole of the CLI's deep_obscure_emails walk with the
    # encoding fix ('user@example.com' would arrive as 'us***@e***.com').
    it 'still returns the full address un-obscured' do
      expect(sections[:customer][:email]).to eq('user@example.com')
    end
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

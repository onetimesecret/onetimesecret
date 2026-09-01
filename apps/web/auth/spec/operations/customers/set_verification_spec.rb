# apps/web/auth/spec/operations/customers/set_verification_spec.rb
#
# frozen_string_literal: true

# Unit tests for Auth::Operations::Customers::SetVerification.
#
# Covers: it reuses (delegates to) the incumbent SetCustomerVerification op,
# passes through the result symbol + db, audits exactly once on :success,
# does not audit on :no_change, and records one result: :failure (then
# re-raises) when the inner op raises one of its documented error classes.
#
# Plus the #4328 unverify interlocks. They live HERE rather than in the colonel
# adapter so `bin/ots customers unverify` is bound by them too — unverifying a
# colonel is a demotion by another name (has_system_role? refuses every elevated
# role to an unverified account), so unverifying the last one would leave the
# install with no administrator.
#
# Run: pnpm run test:rspec apps/web/auth/spec/operations/customers/set_verification_spec.rb

require 'spec_helper'
require 'onetime/models/colonel_audit_event'
require 'auth/operations/customers/set_verification'

RSpec.describe Auth::Operations::Customers::SetVerification do
  # A plain (non-colonel) target: role/verified? are what the interlocks read,
  # and this one short-circuits both of them.
  let(:customer) do
    double('Customer', extid: 'ur_v', objid: 'cust_v', role: 'customer', verified?: true)
  end
  let(:inner) { instance_double(Auth::Operations::SetCustomerVerification) }

  before do
    allow(OT).to receive(:le)
    allow(Onetime::ColonelAuditEvent).to receive(:record)
    allow(Auth::Operations::SetCustomerVerification).to receive(:new).and_return(inner)
  end

  it 'delegates to SetCustomerVerification and audits once on :success' do
    allow(inner).to receive(:call).and_return(:success)

    result = described_class.new(
      customer: customer, verified: true, actor: 'ur_col', verified_by: 'colonel_admin'
    ).call

    expect(result).to eq(:success)
    expect(Auth::Operations::SetCustomerVerification).to have_received(:new).with(
      customer: customer, verified: true, verified_by: 'colonel_admin', db: nil
    )
    expect(Onetime::ColonelAuditEvent).to have_received(:record).once.with(
      actor: 'ur_col',
      verb: 'customer.set_verification',
      target: 'ur_v',
      result: :success,
      detail: { verified: true },
    )
  end

  it 'does not audit on :no_change' do
    allow(inner).to receive(:call).and_return(:no_change)

    result = described_class.new(
      customer: customer, verified: true, actor: 'x', verified_by: 'colonel_admin'
    ).call

    expect(result).to eq(:no_change)
    expect(Onetime::ColonelAuditEvent).not_to have_received(:record)
  end

  it 'passes an injected db through to the underlying op' do
    allow(inner).to receive(:call).and_return(:no_change)
    db = double('db')

    described_class.new(
      customer: customer, verified: false, actor: 'x', verified_by: nil, db: db
    ).call

    expect(Auth::Operations::SetCustomerVerification).to have_received(:new).with(
      customer: customer, verified: false, verified_by: nil, db: db
    )
  end

  # The Onetime::AuditedFailure mechanism. This wrapper's ENTIRE job is the
  # audit event, and all three documented error classes are raised by the inner
  # op before it — so an operator repeatedly trying to verify a closed or
  # missing account previously left no trace whatsoever. Message expectation,
  # not a store read: ColonelAuditEvent.record swallows its own errors.
  it 'records ONE result: :failure event when the inner op raises, and re-raises' do
    error_class = Auth::Operations::SetCustomerVerification::AccountNotFound
    allow(inner).to receive(:call).and_raise(error_class, 'no auth row for ur_v')

    expect do
      described_class.new(
        customer: customer, verified: true, actor: 'ur_col', verified_by: 'colonel_admin'
      ).call
    end.to raise_error(error_class, /no auth row for ur_v/)

    expect(Onetime::ColonelAuditEvent).to have_received(:record).once.with(
      hash_including(
        actor: 'ur_col',
        verb: 'customer.set_verification',
        target: 'ur_v', # literal: a broken target lambda silently lands as 'unknown'
        result: :failure,
        detail: hash_including(
          error: error_class.name, message: 'no auth row for ur_v', verified: true,
        ),
      ),
    )
  end

  # ---- Unverify interlocks (#4328 / review B-1) ------------------------------
  describe 'unverify interlocks' do
    let(:colonel) do
      double('Customer', extid: 'ur_col_t', objid: 'cust_col_t', role: 'colonel', verified?: true)
    end

    let(:second_colonel) do
      double('Customer', objid: 'cust_other', role: 'colonel', verified?: true, exists?: true)
    end

    def stub_roster(*colonels)
      allow(Onetime::Customer).to receive(:find_all_by_role).with('colonel').and_return(colonels)
    end

    def unverify(target, actor_objid: nil, **extra)
      described_class.new(
        customer: target, verified: false, actor: 'ur_col', verified_by: nil,
        actor_objid: actor_objid, **extra
      ).call
    end

    before do
      allow(inner).to receive(:call).and_return(:success)
      allow(colonel).to receive(:exists?).and_return(true)
    end

    it 'refuses a self-unverify and mutates nothing' do
      expect(unverify(colonel, actor_objid: 'cust_col_t')).to eq(:self_unverify)
      expect(Auth::Operations::SetCustomerVerification).not_to have_received(:new)
    end

    it 'refuses unverifying the last active colonel and mutates nothing' do
      stub_roster(colonel)

      expect(unverify(colonel)).to eq(:last_colonel)
      expect(Auth::Operations::SetCustomerVerification).not_to have_received(:new)
    end

    it 'records exactly one result: :failure event per refusal' do
      stub_roster(colonel)
      unverify(colonel)

      expect(Onetime::ColonelAuditEvent).to have_received(:record).once.with(
        actor: 'ur_col',
        verb: 'customer.set_verification',
        target: 'ur_col_t',
        result: :failure,
        detail: { reason: 'last_colonel', verified: false },
      )
    end

    it 'proceeds once a second active colonel exists' do
      stub_roster(colonel, second_colonel)

      expect(unverify(colonel)).to eq(:success)
    end

    # The roster is authoritative, not the derived index: an index member whose
    # customer hash is gone, whose role field disagrees, or that is unverified
    # must not count as "another colonel" — otherwise the guard fails open.
    it 'ignores drifted index members when counting the remaining colonels' do
      stub_roster(
        colonel,
        double('Customer', objid: 'cust_gone', exists?: false, role: 'colonel', verified?: true),
        double('Customer', objid: 'cust_demoted', exists?: true, role: 'admin', verified?: true),
        double('Customer', objid: 'cust_unver', exists?: true, role: 'colonel', verified?: false),
      )

      expect(unverify(colonel)).to eq(:last_colonel)
    end

    it 'never refuses the VERIFY arm' do
      stub_roster(colonel)

      result = described_class.new(
        customer: colonel, verified: true, actor: 'ur_col',
        verified_by: 'colonel_admin', actor_objid: 'cust_col_t'
      ).call

      expect(result).to eq(:success)
    end

    # A credential-provenance reset (Customers::ChangeEmail) clears verification
    # because the ADDRESS changed and is now unproven. Refusing that would leave
    # a colonel "verified" against an address nobody controls.
    it 'skips the interlocks when the caller opts out (enforce_interlocks: false)' do
      stub_roster(colonel)

      expect(unverify(colonel, enforce_interlocks: false)).to eq(:success)
    end
  end
end

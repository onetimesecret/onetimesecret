# apps/web/auth/spec/operations/customers/set_role_spec.rb
#
# frozen_string_literal: true

# Unit tests for Auth::Operations::Customers::SetRole.
#
# Covers: successful change (+ exactly one audit event), idempotent no_change
# (no save, no audit), invalid-role rejection, and the #4328 interlocks
# (:self_demotion / :last_colonel).
#
# The interlocks live in the OP, not the colonel adapter, so
# `bin/ots customers role demote` is bound by them too — and each refusal
# records exactly one result: :failure event through the single `build` exit
# point, so no early return can skip it (the Memberships::Remove shape).
#
# Run: pnpm run test:rspec apps/web/auth/spec/operations/customers/set_role_spec.rb

require 'spec_helper'
require 'onetime/models/colonel_audit_event'
require 'auth/operations/customers/set_role'

RSpec.describe Auth::Operations::Customers::SetRole do
  let(:customer) do
    double('Customer', role: 'customer', extid: 'ur_test', objid: 'cust_test',
      :role= => nil, save: true)
  end

  before do
    allow(OT).to receive(:le)
    allow(Onetime::ColonelAuditEvent).to receive(:record)
  end

  it 'changes the role, saves, and returns :success with from/to' do
    result = described_class.new(customer: customer, role: 'colonel', actor: 'ur_col').call

    expect(result.status).to eq(:success)
    expect(result.from).to eq('customer')
    expect(result.to).to eq('colonel')
    expect(customer).to have_received(:role=).with('colonel')
    expect(customer).to have_received(:save)
  end

  it 'records exactly one audit event on success (actor = public id, target = extid)' do
    described_class.new(customer: customer, role: 'colonel', actor: 'ur_col').call

    expect(Onetime::ColonelAuditEvent).to have_received(:record).once.with(
      actor: 'ur_col',
      verb: 'customer.set_role',
      target: 'ur_test',
      result: :success,
      detail: { from: 'customer', to: 'colonel' },
    )
  end

  it 'is a no_change (no save, no audit) when already at the target role' do
    allow(customer).to receive(:role).and_return('colonel')

    result = described_class.new(customer: customer, role: 'colonel', actor: 'x').call

    expect(result.status).to eq(:no_change)
    expect(customer).not_to have_received(:save)
    expect(Onetime::ColonelAuditEvent).not_to have_received(:record)
  end

  it 'raises InvalidRole (no save) for an unknown role' do
    expect do
      described_class.new(customer: customer, role: 'wizard', actor: 'x').call
    end.to raise_error(described_class::InvalidRole)

    expect(customer).not_to have_received(:save)
  end

  # Onetime::AuditedFailure: the InvalidRole guard raises before the
  # success-path record call, so a rejected role change would otherwise be
  # invisible. A refused attempt to hand out a role is exactly what the trail
  # is for.
  it 'records one result: :failure event for a rejected role and re-raises' do
    expect do
      described_class.new(customer: customer, role: 'wizard', actor: 'x').call
    end.to raise_error(described_class::InvalidRole)

    expect(Onetime::ColonelAuditEvent).to have_received(:record).once.with(
      hash_including(
        actor: 'x',
        verb: 'customer.set_role',
        result: :failure,
        detail: hash_including(error: 'Auth::Operations::Customers::SetRole::InvalidRole'),
      ),
    )
  end

  # ---- Interlocks (#4328) ----------------------------------------------------
  describe 'interlocks' do
    let(:colonel_target) do
      double('Customer', role: 'colonel', extid: 'ur_col', objid: 'cust_col',
        verified?: true, exists?: true, :role= => nil, save: true)
    end

    let(:second_colonel) do
      double('Customer', role: 'colonel', objid: 'cust_other', verified?: true, exists?: true)
    end

    def stub_roster(*colonels)
      allow(Onetime::Customer).to receive(:find_all_by_role).with('colonel').and_return(colonels)
    end

    def demote(target, **extra)
      described_class.new(customer: target, role: 'customer', actor: 'ur_actor', **extra).call
    end

    it 'refuses a self-demotion and mutates nothing' do
      result = demote(colonel_target, actor_objid: 'cust_col')

      expect(result.status).to eq(:self_demotion)
      expect(colonel_target).not_to have_received(:save)
    end

    it 'refuses demoting the last active colonel and mutates nothing' do
      stub_roster(colonel_target)

      result = demote(colonel_target)

      expect(result.status).to eq(:last_colonel)
      expect(colonel_target).not_to have_received(:save)
    end

    it 'records exactly one result: :failure event per refusal' do
      stub_roster(colonel_target)
      demote(colonel_target)

      expect(Onetime::ColonelAuditEvent).to have_received(:record).once.with(
        actor: 'ur_actor',
        verb: 'customer.set_role',
        target: 'ur_col',
        result: :failure,
        detail: { reason: 'last_colonel', from: 'colonel', to: 'customer' },
      )
    end

    it 'proceeds once a second active colonel exists' do
      stub_roster(colonel_target, second_colonel)

      expect(demote(colonel_target).status).to eq(:success)
      expect(colonel_target).to have_received(:save)
    end

    # The roster is authoritative, not the derived role index: the index drifts
    # UPWARD (add-only partial writes; TTL-expired customer hashes leave members
    # behind), so counting it would make this guard fail OPEN.
    it 'ignores drifted index members when counting the remaining colonels' do
      stub_roster(
        colonel_target,
        double('Customer', objid: 'cust_gone', exists?: false, role: 'colonel', verified?: true),
        double('Customer', objid: 'cust_demoted', exists?: true, role: 'admin', verified?: true),
        double('Customer', objid: 'cust_unver', exists?: true, role: 'colonel', verified?: false),
      )

      expect(demote(colonel_target).status).to eq(:last_colonel)
    end

    # The CLI passes no actor_objid: there is no acting customer in a shell, and
    # nothing to self-demote. It must keep working unchanged.
    it 'never self-refuses when actor_objid is nil (the CLI path)' do
      stub_roster(colonel_target, second_colonel)

      expect(demote(colonel_target).status).to eq(:success)
    end

    it 'does not refuse a PROMOTION to colonel by the actor themselves' do
      result = described_class.new(
        customer: colonel_target, role: 'colonel', actor: 'ur_actor', actor_objid: 'cust_col'
      ).call

      # Already a colonel, so this is the idempotent arm — the point is that it
      # is not :self_demotion.
      expect(result.status).to eq(:no_change)
    end

    it 'does not read the colonel roster when the target is not a colonel' do
      allow(Onetime::Customer).to receive(:find_all_by_role)

      demote(customer)

      expect(Onetime::Customer).not_to have_received(:find_all_by_role)
    end

    # POST-WRITE re-validation (#4328). The pre-check is not atomic: two
    # concurrent demotions of the two distinct last colonels can both pass it
    # and leave zero colonels. Simulate the roster dropping to zero BETWEEN the
    # pre-check and the post-check (find_all_by_role returns two colonels the
    # first time, none the second), and assert the demotion is rolled back and a
    # :last_colonel failure is returned and audited.
    describe 'the check-then-act race (post-write re-validation)' do
      before do
        allow(Onetime::Customer).to receive(:find_all_by_role).with('colonel')
          .and_return([colonel_target, second_colonel], [])
      end

      it 'rolls the role back and refuses with :last_colonel' do
        result = demote(colonel_target)

        expect(result.status).to eq(:last_colonel)
        # demoted to the target role, then restored to the prior colonel role
        expect(colonel_target).to have_received(:role=).with('customer')
        expect(colonel_target).to have_received(:role=).with('colonel')
        expect(colonel_target).to have_received(:save).twice
      end

      it 'records the :last_colonel failure and no success event' do
        demote(colonel_target)

        expect(Onetime::ColonelAuditEvent).to have_received(:record).once.with(
          hash_including(
            verb: 'customer.set_role',
            target: 'ur_col',
            result: :failure,
            detail: hash_including(reason: 'last_colonel'),
          ),
        )
        expect(Onetime::ColonelAuditEvent).not_to have_received(:record).with(
          hash_including(result: :success),
        )
      end
    end
  end
end

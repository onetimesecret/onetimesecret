# spec/unit/onetime/models/organization/rematerialize_all_memberships_spec.rb
#
# frozen_string_literal: true

# Unit tests for Organization#rematerialize_all_memberships! — specifically the
# targeted single-retry behavior (ADR-012 Stage 3).
#
# Strategy: use a real Organization instance (so the method under test runs for
# real) but stub its collaborators — OrganizationMembership.active_for_org and
# the per-membership materialize_for_role! — so no Redis is required.
#
# Run: pnpm run test:rspec spec/unit/onetime/models/organization/rematerialize_all_memberships_spec.rb

require 'spec_helper'

RSpec.describe 'Onetime::Organization#rematerialize_all_memberships!' do
  let(:org) do
    Onetime::Organization.new.tap do |o|
      allow(o).to receive(:extid).and_return('org_test')
    end
  end

  # Build a membership double. `behavior` is a callable invoked on each
  # materialize_for_role! attempt; it returns true or raises.
  def membership(objid, &behavior)
    double(objid).tap do |m|
      allow(m).to receive(:objid).and_return(objid)
      allow(m).to receive(:materialize_for_role!, &behavior)
    end
  end

  def stub_memberships(list)
    allow(Onetime::OrganizationMembership).to receive(:active_for_org)
      .with(org)
      .and_return(list)
  end

  before do
    allow(OT).to receive(:info)
    allow(OT).to receive(:le)
  end

  context 'when every membership succeeds on the first pass' do
    let(:m1) { membership('mem_1') { true } }
    let(:m2) { membership('mem_2') { true } }

    before { stub_memberships([m1, m2]) }

    it 'reports all successful with empty failed_ids' do
      expect(org.rematerialize_all_memberships!).to eq(
        success: 2, failed: 0, total: 2, failed_ids: []
      )
    end

    it 'attempts each membership exactly once (no retry pass)' do
      expect(m1).to receive(:materialize_for_role!).once.and_return(true)
      expect(m2).to receive(:materialize_for_role!).once.and_return(true)

      org.rematerialize_all_memberships!
    end

    it 'does not log any error' do
      expect(OT).not_to receive(:le)
      org.rematerialize_all_memberships!
    end
  end

  context 'when a membership fails the first pass but succeeds on retry' do
    let(:attempts) { { count: 0 } }
    let(:flaky) do
      membership('mem_flaky') do
        attempts[:count] += 1
        raise StandardError, 'transient' if attempts[:count] == 1

        true
      end
    end
    let(:steady) { membership('mem_steady') { true } }

    before { stub_memberships([flaky, steady]) }

    it 'repairs the failure and reports zero failures' do
      expect(org.rematerialize_all_memberships!).to eq(
        success: 2, failed: 0, total: 2, failed_ids: []
      )
    end

    it 'attempts the flaky membership twice and the steady one once' do
      org.rematerialize_all_memberships!

      expect(attempts[:count]).to eq(2)
    end

    it 'logs the first-pass failure (but not a final error)' do
      org.rematerialize_all_memberships!

      expect(OT).to have_received(:le).with(
        '[rematerialize_all_memberships!] failed for membership',
        hash_including(membership_objid: 'mem_flaky', org_extid: 'org_test', retry_attempt: false)
      ).once
    end
  end

  context 'when a membership fails both the first pass and the retry' do
    let(:fail_attempts) { { count: 0 } }
    let(:broken) do
      membership('mem_broken') do
        fail_attempts[:count] += 1
        raise StandardError, 'permanent'
      end
    end
    let(:ok) { membership('mem_ok') { true } }

    before { stub_memberships([broken, ok]) }

    it 'reports the failure and lists it in failed_ids' do
      expect(org.rematerialize_all_memberships!).to eq(
        success: 1, failed: 1, total: 2, failed_ids: ['mem_broken']
      )
    end

    it 'retries only the broken membership (the ok one is attempted once)' do
      expect(ok).to receive(:materialize_for_role!).once.and_return(true)

      org.rematerialize_all_memberships!

      expect(fail_attempts[:count]).to eq(2) # first pass + targeted retry
    end

    it 'logs both the first-pass and the retry failure with retry_attempt flags' do
      org.rematerialize_all_memberships!

      expect(OT).to have_received(:le).with(
        '[rematerialize_all_memberships!] failed for membership',
        hash_including(membership_objid: 'mem_broken', retry_attempt: false)
      ).once
      expect(OT).to have_received(:le).with(
        '[rematerialize_all_memberships!] failed for membership',
        hash_including(membership_objid: 'mem_broken', retry_attempt: true)
      ).once
    end
  end

  context 'when there are no active memberships' do
    before { stub_memberships([]) }

    it 'returns zeroed counts and an empty failed_ids without logging errors' do
      expect(OT).not_to receive(:le)

      expect(org.rematerialize_all_memberships!).to eq(
        success: 0, failed: 0, total: 0, failed_ids: []
      )
    end
  end
end

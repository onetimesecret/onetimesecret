# spec/unit/onetime/models/organization/chores/materialize_standalone_entitlements_spec.rb
#
# frozen_string_literal: true

# Unit tests for the materialize_standalone_entitlements housekeeping chore.
#
# Tests the standalone-mode backfill logic without requiring Redis or actual
# Organization instances. Uses an instance_double that mirrors the interface
# the chore expects, mirroring the shape of standardize_owner_id_spec.rb.
#
# Three branches:
#   1. billing_enabled?                        -> skip with :info log
#   2. entitlements_materialized? already true -> silent no-op
#   3. standalone + unmaterialized             -> call
#                                                 materialize_standalone_entitlements!,
#                                                 log :info with org extid + count
#
# Run: bundle exec rspec spec/unit/onetime/models/organization/chores/materialize_standalone_entitlements_spec.rb

require 'spec_helper'

# Load the chore registration
require_relative '../../../../../../lib/onetime/models/organization/chores/materialize_standalone_entitlements'

RSpec.describe 'Organization chore: materialize_standalone_entitlements' do
  let(:chore) { Onetime::Organization.chores[:materialize_standalone_entitlements] }

  let(:mock_logger) do
    double('SemanticLogger').tap do |logger|
      allow(logger).to receive(:info) { |_msg, _payload = {}| nil }
      allow(logger).to receive(:warn) { |_msg, _payload = {}| nil }
    end
  end

  # Materialized set stub — chore only reads `.size`
  let(:materialized_set) { double('Set', size: 15) }

  # Mock organization object with the interface the chore uses.
  # `materialize_standalone_entitlements!` and `materialized_entitlements`
  # are real methods on Organization (defined in WithPlanEntitlements and
  # WithMaterializedEntitlements respectively), so instance_double with
  # verify_partial_doubles enabled will accept the stubs.
  let(:org) do
    obj = instance_double(
      'Onetime::Organization',
      extid: 'org_test123',
      billing_enabled?: billing_state,
      entitlements_materialized?: materialized_state,
      materialized_entitlements: materialized_set,
    )
    allow(obj).to receive(:materialize_standalone_entitlements!).and_return(true)
    allow(obj).to receive(:rematerialize_all_memberships!)
    obj
  end

  before do
    allow(Onetime).to receive(:get_logger).with('Chores').and_return(mock_logger)
  end

  describe 'chore registration' do
    let(:billing_state) { false }
    let(:materialized_state) { false }

    it 'is registered on Onetime::Organization' do
      expect(Onetime::Organization.chores).to have_key(:materialize_standalone_entitlements)
    end

    it 'is a callable block' do
      expect(chore).to respond_to(:call)
    end
  end

  describe 'Branch 1: billing enabled (skip with :info log)' do
    let(:billing_state) { true }
    let(:materialized_state) { false } # irrelevant; branch 1 short-circuits

    it 'does not call materialize_standalone_entitlements!' do
      expect(org).not_to receive(:materialize_standalone_entitlements!)
      chore.call(org)
    end

    it 'logs the skip at :info with chore name and org extid' do
      expect(mock_logger).to receive(:info).with(
        'Skipping org: billing enabled (webhook owns materialization)',
        hash_including(
          chore: :materialize_standalone_entitlements,
          org_extid: 'org_test123',
        ),
      )
      chore.call(org)
    end

    it 'does not log at :warn' do
      expect(mock_logger).not_to receive(:warn)
      chore.call(org)
    end

    context 'even when org is already materialized' do
      let(:materialized_state) { true }

      it 'still takes the billing branch (skip with :info)' do
        expect(mock_logger).to receive(:info).with(
          'Skipping org: billing enabled (webhook owns materialization)',
          hash_including(chore: :materialize_standalone_entitlements),
        )
        expect(org).not_to receive(:materialize_standalone_entitlements!)
        chore.call(org)
      end
    end
  end

  describe 'Branch 2: already materialized (silent no-op)' do
    let(:billing_state) { false }
    let(:materialized_state) { true }

    it 'returns nil (skips)' do
      expect(chore.call(org)).to be_nil
    end

    it 'does not call materialize_standalone_entitlements!' do
      expect(org).not_to receive(:materialize_standalone_entitlements!)
      chore.call(org)
    end

    it 'does not log at :info' do
      expect(mock_logger).not_to receive(:info)
      chore.call(org)
    end

    it 'does not log at :warn' do
      expect(mock_logger).not_to receive(:warn)
      chore.call(org)
    end
  end

  describe 'Branch 3: standalone + unmaterialized (materialize + log)' do
    let(:billing_state) { false }
    let(:materialized_state) { false }

    it 'calls materialize_standalone_entitlements!' do
      expect(org).to receive(:materialize_standalone_entitlements!).and_return(true)
      chore.call(org)
    end

    it 'calls rematerialize_all_memberships! to cascade to members' do
      expect(org).to receive(:rematerialize_all_memberships!)
      chore.call(org)
    end

    it 'logs the materialization at :info' do
      expect(mock_logger).to receive(:info).with(
        'Materialized standalone entitlements',
        hash_including(
          chore: :materialize_standalone_entitlements,
          org_extid: 'org_test123',
          entitlement_count: 15,
        ),
      )
      chore.call(org)
    end

    it 'returns true' do
      expect(chore.call(org)).to be true
    end

    it 'does not log at :warn' do
      expect(mock_logger).not_to receive(:warn)
      chore.call(org)
    end

  end
end

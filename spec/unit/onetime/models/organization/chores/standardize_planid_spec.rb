# spec/unit/onetime/models/organization/chores/standardize_planid_spec.rb
#
# frozen_string_literal: true

# Unit tests for the standardize_planid housekeeping chore.
#
# Tests the planid normalization logic without requiring Redis or actual
# Organization instances. Uses a mock object that mirrors the interface
# the chore expects.
#
# Run: pnpm run test:rspec spec/unit/onetime/models/organization/chores/standardize_planid_spec.rb

require 'spec_helper'

# Load the chore registration
require_relative '../../../../../../lib/onetime/models/organization/chores/standardize_planid'

RSpec.describe 'Organization chore: standardize_planid' do
  let(:chore) { Onetime::Organization.chores[:standardize_planid] }

  # Create a mock logger that accepts SemanticLogger's (message, hash) signature
  let(:mock_logger) do
    double('SemanticLogger').tap do |logger|
      allow(logger).to receive(:info) { |_msg, _payload = {}| nil }
    end
  end

  # Mock organization object with the interface the chore uses
  let(:org) do
    instance_double(
      'Onetime::Organization',
      extid: 'org_test123',
      planid: current_planid
    )
  end

  before do
    # Stub Onetime.get_logger to return our mock (chore calls this inside the block)
    allow(Onetime).to receive(:get_logger).with('Chores').and_return(mock_logger)
  end

  describe 'chore registration' do
    it 'is registered on Onetime::Organization' do
      expect(Onetime::Organization.chores).to have_key(:standardize_planid)
    end

    it 'is a callable block' do
      expect(chore).to respond_to(:call)
    end
  end

  describe 'canonical planids (silent skip)' do
    %w[free_v1 identity_plus_v1 team_plus_v1 legacy_plan_v1 identity].each do |canonical|
      context "when planid is #{canonical.inspect}" do
        let(:current_planid) { canonical }

        it 'returns nil (skips)' do
          expect(chore.call(org)).to be_nil
        end

        it 'does not call planid!' do
          expect(org).not_to receive(:planid!)
          chore.call(org)
        end

        it 'does not log' do
          expect(mock_logger).not_to receive(:info)
          chore.call(org)
        end
      end
    end
  end

  describe 'free tier mappings' do
    before do
      allow(org).to receive(:planid!)
    end

    context 'when planid is empty string' do
      let(:current_planid) { '' }

      it 'normalizes to free_v1' do
        expect(org).to receive(:planid!).with('free_v1')
        chore.call(org)
      end

      it 'logs the normalization' do
        expect(mock_logger).to receive(:info).with(
          'Normalizing planid',
          hash_including(chore: :standardize_planid, from: '', to: 'free_v1')
        )
        chore.call(org)
      end

      it 'returns true' do
        expect(chore.call(org)).to be true
      end
    end

    context 'when planid is nil (coerced to empty)' do
      let(:current_planid) { nil }

      it 'normalizes to free_v1' do
        expect(org).to receive(:planid!).with('free_v1')
        chore.call(org)
      end
    end

    context 'when planid is "free"' do
      let(:current_planid) { 'free' }

      it 'normalizes to free_v1' do
        expect(org).to receive(:planid!).with('free_v1')
        chore.call(org)
      end

      it 'logs with correct from/to values' do
        expect(mock_logger).to receive(:info).with(
          'Normalizing planid',
          hash_including(from: 'free', to: 'free_v1')
        )
        chore.call(org)
      end
    end

    context 'when planid is "basic"' do
      let(:current_planid) { 'basic' }

      it 'normalizes to free_v1' do
        expect(org).to receive(:planid!).with('free_v1')
        chore.call(org)
      end
    end

    context 'when planid is "free_month" (suffix-stripped)' do
      let(:current_planid) { 'free_month' }

      it 'normalizes to free_v1' do
        expect(org).to receive(:planid!).with('free_v1')
        chore.call(org)
      end
    end
  end

  describe 'identity_plus tier mappings' do
    before do
      allow(org).to receive(:planid!)
    end

    context 'when planid is "identity_plus"' do
      let(:current_planid) { 'identity_plus' }

      it 'normalizes to identity_plus_v1' do
        expect(org).to receive(:planid!).with('identity_plus_v1')
        chore.call(org)
      end

      it 'returns true' do
        expect(chore.call(org)).to be true
      end
    end

    context 'when planid is "identity_plus_monthly"' do
      let(:current_planid) { 'identity_plus_monthly' }

      it 'normalizes to identity_plus_v1' do
        expect(org).to receive(:planid!).with('identity_plus_v1')
        chore.call(org)
      end
    end

    context 'when planid is "identity_plus_yearly"' do
      let(:current_planid) { 'identity_plus_yearly' }

      it 'normalizes to identity_plus_v1' do
        expect(org).to receive(:planid!).with('identity_plus_v1')
        chore.call(org)
      end
    end

    context 'when planid is "identity_plus_v1_monthly"' do
      let(:current_planid) { 'identity_plus_v1_monthly' }

      it 'normalizes to identity_plus_v1' do
        expect(org).to receive(:planid!).with('identity_plus_v1')
        chore.call(org)
      end
    end

    context 'when planid is "identity_plus_v1_yearly"' do
      let(:current_planid) { 'identity_plus_v1_yearly' }

      it 'normalizes to identity_plus_v1' do
        expect(org).to receive(:planid!).with('identity_plus_v1')
        chore.call(org)
      end
    end
  end

  describe 'team_plus tier mappings' do
    before do
      allow(org).to receive(:planid!)
    end

    context 'when planid is "team_plus"' do
      let(:current_planid) { 'team_plus' }

      it 'normalizes to team_plus_v1' do
        expect(org).to receive(:planid!).with('team_plus_v1')
        chore.call(org)
      end
    end

    context 'when planid is "team_plus_monthly"' do
      let(:current_planid) { 'team_plus_monthly' }

      it 'normalizes to team_plus_v1' do
        expect(org).to receive(:planid!).with('team_plus_v1')
        chore.call(org)
      end
    end

    context 'when planid is "team_plus_yearly"' do
      let(:current_planid) { 'team_plus_yearly' }

      it 'normalizes to team_plus_v1' do
        expect(org).to receive(:planid!).with('team_plus_v1')
        chore.call(org)
      end
    end

    context 'when planid is "team_plus_v1_monthly"' do
      let(:current_planid) { 'team_plus_v1_monthly' }

      it 'normalizes to team_plus_v1' do
        expect(org).to receive(:planid!).with('team_plus_v1')
        chore.call(org)
      end
    end

    context 'when planid is "team_plus_v1_yearly"' do
      let(:current_planid) { 'team_plus_v1_yearly' }

      it 'normalizes to team_plus_v1' do
        expect(org).to receive(:planid!).with('team_plus_v1')
        chore.call(org)
      end
    end
  end

  describe 'unknown planid handling' do
    context 'when planid is unrecognized' do
      let(:current_planid) { 'enterprise_custom' }

      it 'returns nil (skips modification)' do
        expect(chore.call(org)).to be_nil
      end

      it 'does not call planid!' do
        expect(org).not_to receive(:planid!)
        chore.call(org)
      end

      it 'logs the skip with org details' do
        expect(mock_logger).to receive(:info).with(
          'Skipping unknown planid',
          hash_including(
            chore: :standardize_planid,
            org_extid: 'org_test123',
            planid: 'enterprise_custom'
          )
        )
        chore.call(org)
      end
    end

    context 'when planid is another unknown value' do
      let(:current_planid) { 'pro_annual_2023' }

      it 'logs and skips' do
        expect(mock_logger).to receive(:info).with(
          'Skipping unknown planid',
          hash_including(planid: 'pro_annual_2023')
        )
        expect(chore.call(org)).to be_nil
      end
    end

  end

  describe 'identity tier mappings' do
    before do
      allow(org).to receive(:planid!)
    end

    # Bare 'identity' is canonical and short-circuits in the canonical-skip
    # block above; these cases cover the interval-suffixed variants that
    # strip to 'identity' and normalize to the bare value.
    context 'when planid is "identity_monthly"' do
      let(:current_planid) { 'identity_monthly' }

      it 'normalizes to identity' do
        expect(org).to receive(:planid!).with('identity')
        chore.call(org)
      end

      it 'logs the normalization' do
        expect(mock_logger).to receive(:info).with(
          'Normalizing planid',
          hash_including(from: 'identity_monthly', to: 'identity')
        )
        chore.call(org)
      end
    end

    context 'when planid is "identity_yearly"' do
      let(:current_planid) { 'identity_yearly' }

      it 'normalizes to identity' do
        expect(org).to receive(:planid!).with('identity')
        chore.call(org)
      end
    end
  end

  describe 'whitespace handling' do
    before do
      allow(org).to receive(:planid!)
    end

    context 'when planid has leading/trailing whitespace' do
      let(:current_planid) { '  free  ' }

      it 'strips whitespace before matching' do
        expect(org).to receive(:planid!).with('free_v1')
        chore.call(org)
      end
    end

    context 'when planid is only whitespace' do
      let(:current_planid) { '   ' }

      it 'treats as empty and normalizes to free_v1' do
        expect(org).to receive(:planid!).with('free_v1')
        chore.call(org)
      end
    end
  end

  describe 'logging details' do
    before do
      allow(org).to receive(:planid!)
    end

    context 'when modification occurs' do
      let(:current_planid) { 'identity_plus' }

      it 'includes org_extid in log' do
        expect(mock_logger).to receive(:info).with(
          'Normalizing planid',
          hash_including(org_extid: 'org_test123')
        )
        chore.call(org)
      end

      it 'includes from and to values' do
        expect(mock_logger).to receive(:info).with(
          'Normalizing planid',
          hash_including(from: 'identity_plus', to: 'identity_plus_v1')
        )
        chore.call(org)
      end

      it 'includes chore name' do
        expect(mock_logger).to receive(:info).with(
          'Normalizing planid',
          hash_including(chore: :standardize_planid)
        )
        chore.call(org)
      end
    end
  end
end

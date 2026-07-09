# spec/unit/onetime/entitlement_preview_spec.rb
#
# frozen_string_literal: true

require 'spec_helper'

# Unit tests for the request-scoped entitlement preview accessor (ADR-020).
#
# The module wraps a Fiber-local holding the session's preview keys. The
# entitlement/limit chokepoints consult it; the middleware populates and
# clears it per request. These tests cover the accessor contract only —
# middleware behavior lives in
# spec/unit/onetime/middleware/entitlement_preview_context_spec.rb.
RSpec.describe Onetime::EntitlementPreview do
  after { described_class.clear }

  describe '.set' do
    it 'stores a frozen context hash with symbol keys' do
      context = described_class.set(
        planid: 'identity_v1',
        grants_key: 'session:abc:entitlement_preview_grants',
        revokes_key: 'session:abc:entitlement_preview_revokes',
      )

      expect(context).to be_frozen
      expect(context).to eq(
        planid: 'identity_v1',
        grants_key: 'session:abc:entitlement_preview_grants',
        revokes_key: 'session:abc:entitlement_preview_revokes',
      )
    end

    it 'normalizes empty strings to nil' do
      context = described_class.set(planid: 'identity_v1', grants_key: '', revokes_key: '')

      expect(context[:planid]).to eq('identity_v1')
      expect(context[:grants_key]).to be_nil
      expect(context[:revokes_key]).to be_nil
    end

    it 'stores a planid-only context (limits preview without reconciliation)' do
      context = described_class.set(planid: 'identity_v1', grants_key: nil, revokes_key: nil)

      expect(context[:planid]).to eq('identity_v1')
      expect(described_class.active?).to be true
    end

    it 'returns nil and stays inactive when all three values are nil' do
      expect(described_class.set(planid: nil, grants_key: nil, revokes_key: nil)).to be_nil
      expect(described_class.active?).to be false
    end

    it 'returns nil and stays inactive when all three values are empty strings' do
      expect(described_class.set(planid: '', grants_key: '', revokes_key: '')).to be_nil
      expect(described_class.active?).to be false
    end

    it 'clears a previously stored context when all values are nil' do
      described_class.set(planid: 'identity_v1', grants_key: nil, revokes_key: nil)

      described_class.set(planid: nil, grants_key: nil, revokes_key: nil)

      expect(described_class.context).to be_nil
      expect(described_class.active?).to be false
    end

    it 'replaces a previously stored context' do
      described_class.set(planid: 'identity_v1', grants_key: nil, revokes_key: nil)
      described_class.set(planid: 'multi_team_v1', grants_key: nil, revokes_key: nil)

      expect(described_class.context[:planid]).to eq('multi_team_v1')
    end
  end

  describe '.context' do
    it 'returns nil when no preview has been set' do
      expect(described_class.context).to be_nil
    end

    it 'returns the stored context' do
      described_class.set(planid: 'identity_v1', grants_key: 'g', revokes_key: 'r')

      expect(described_class.context).to eq(planid: 'identity_v1', grants_key: 'g', revokes_key: 'r')
    end
  end

  describe '.active?' do
    it 'is false with no context' do
      expect(described_class.active?).to be false
    end

    it 'is true once a context is stored' do
      described_class.set(planid: nil, grants_key: 'g', revokes_key: nil)

      expect(described_class.active?).to be true
    end
  end

  describe '.clear' do
    it 'removes the context' do
      described_class.set(planid: 'identity_v1', grants_key: nil, revokes_key: nil)

      described_class.clear

      expect(described_class.context).to be_nil
      expect(described_class.active?).to be false
    end

    it 'is a no-op when nothing is set' do
      expect { described_class.clear }.not_to raise_error
      expect(described_class.context).to be_nil
    end
  end

  describe 'fiber scoping' do
    it 'does not leak a context set inside a child fiber back to the parent' do
      Fiber.new do
        described_class.set(planid: 'identity_v1', grants_key: nil, revokes_key: nil)
      end.resume

      expect(described_class.context).to be_nil
    end
  end
end

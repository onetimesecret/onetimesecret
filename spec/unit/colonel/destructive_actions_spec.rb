# spec/unit/colonel/destructive_actions_spec.rb
#
# frozen_string_literal: true

require_relative File.join(Onetime::HOME, 'spec', 'spec_helper')
require 'colonel/logic'

# The #4326 tier registry, asserted against the source it classifies.
#
# This spec exists so the destructive-action classification is TESTABLE data
# rather than prose in a design doc. Three things it pins, each of which failed
# silently before it existed:
#
#   1. Every listed name resolves to a real logic class (a rename cannot leave a
#      dangling entry behind).
#   2. Every TIER 1 class calls guard_destructive_action! WITH tier: :destructive
#      AND charge_destructive_budget!; every TIER 2 class calls it with
#      tier: :sensitive and does NOT charge the destructive budget. Asserting
#      only that the guard "appears" would let a TIER 1 class typo'd to
#      :sensitive lose step-up (#4327) and the tight bucket (#4329) with every
#      test green.
#   3. Every mutating route in routes.txt maps to a class in exactly one of the
#      three lists. This is what stops the next feature from shipping an
#      un-triaged destructive route.
#
# It reads SOURCE, not behaviour, on purpose: the per-class specs prove the
# guard works; this proves nobody forgot to call it.
RSpec.describe ColonelAPI::DestructiveActions do
  LOGIC_DIR = File.join(Onetime::HOME, 'apps', 'api', 'colonel', 'logic', 'colonel').freeze
  ROUTES_FILE = File.join(Onetime::HOME, 'apps', 'api', 'colonel', 'routes.txt').freeze

  # Several classes share a file (VerifyUser/UnverifyUser, SuspendUser/
  # UnsuspendUser, the two entitlement-override arms), and the gate lives in the
  # shared base class, so the search is per-FILE, not per-class.
  def source_for(class_name)
    klass = ColonelAPI::Logic::Colonel.const_get(class_name)
    path  = Object.const_source_location(klass.name)&.first
    raise "no source location for #{class_name}" unless path

    File.read(path)
  end

  describe 'the lists name real classes' do
    (described_class::TIER1 + described_class::TIER2 +
      described_class::TIER3_REVIEWED.keys).each do |name|
      it "#{name} resolves to a logic class" do
        expect(ColonelAPI::Logic::Colonel.const_get(name)).to be < ColonelAPI::Logic::Base
      end
    end

    it 'lists no class twice across the three tiers' do
      all = described_class::TIER1 + described_class::TIER2 +
            described_class::TIER3_REVIEWED.keys
      expect(all).to eq(all.uniq)
    end

    it 'gives every deliberately un-gated class a stated reason' do
      expect(described_class::TIER3_REVIEWED.values).to all(satisfy { |r| r.to_s.strip.length > 10 })
    end
  end

  describe 'TIER 1 — confirmation + elevation + the tight bucket' do
    described_class::TIER1.each do |name|
      it "#{name} calls guard_destructive_action! with tier: :destructive" do
        expect(source_for(name)).to match(/guard_destructive_action!\([^)]*tier:\s*:destructive/m)
      end

      it "#{name} charges the destructive budget" do
        expect(source_for(name)).to include('charge_destructive_budget!')
      end
    end
  end

  describe 'TIER 2 — confirmation only' do
    described_class::TIER2.each do |name|
      it "#{name} calls guard_destructive_action! with tier: :sensitive" do
        expect(source_for(name)).to match(/guard_destructive_action!\([^)]*tier:\s*:sensitive/m)
      end

      # The tight bucket is the tier-1 ceiling; charging it here would throttle
      # reversible verbs against the wrong budget.
      it "#{name} does NOT charge the destructive budget" do
        expect(source_for(name)).not_to include('charge_destructive_budget!')
      end
    end
  end

  describe 'TIER 3 — reviewed and deliberately un-gated' do
    described_class::TIER3_REVIEWED.each_key do |name|
      it "#{name} calls no destructive guard" do
        # Read the class's OWN file only where it has one to itself; the shared
        # bases (verify/unverify, suspend/unsuspend) do carry a guard, gated on
        # the destructive arm, so their restorative twin is exempt from this.
        next if %w[VerifyUser UnsuspendUser].include?(name)

        expect(source_for(name)).not_to include('guard_destructive_action!')
      end
    end
  end

  describe 'every mutating route is classified' do
    # POST/PUT/PATCH/DELETE lines in routes.txt, mapped to their handler class.
    let(:mutating_handlers) do
      File.readlines(ROUTES_FILE).filter_map do |line|
        next unless line.match?(/\A(POST|PUT|PATCH|DELETE)\s/)

        line.split[2]
      end.uniq
    end

    it 'finds the mutating routes (guards against a parse that silently matches nothing)' do
      expect(mutating_handlers.size).to be >= 40
    end

    it 'classifies every one of them' do
      unclassified = mutating_handlers.reject { |handler| described_class.classified?(handler) }
      expect(unclassified).to be_empty,
        "un-triaged mutating colonel routes: #{unclassified.join(', ')}. Add each to TIER1, " \
        'TIER2, or TIER3_REVIEWED (with a reason) in apps/api/colonel/destructive_actions.rb.'
    end
  end

  describe 'the predicates' do
    it 'accepts a class or a name, qualified or not' do
      expect(described_class.tier1?(ColonelAPI::Logic::Colonel::PurgeUser)).to be true
      expect(described_class.tier1?('ColonelAPI::Logic::Colonel::PurgeUser')).to be true
      expect(described_class.tier1?('PurgeUser')).to be true
    end

    it 'separates the tiers' do
      expect(described_class.tier1?('SuspendUser')).to be false
      expect(described_class.tier2?('SuspendUser')).to be true
      expect(described_class.gated?('SuspendUser')).to be true
      expect(described_class.gated?('SetBanner')).to be false
      expect(described_class.classified?('SetBanner')).to be true
      expect(described_class.classified?('NoSuchThing')).to be false
    end
  end
end

# spec/unit/onetime/models/custom_domain/signup_allowlist_requirement_spec.rb
#
# frozen_string_literal: true

require 'spec_helper'
require 'json'

# The signup allowlist requirement, Ruby half. SignupConfig.allowlist_requirement_error
# is authoritative; allowlistRequirementMet in
# src/schemas/contracts/custom-domain/signup-config.ts mirrors it so the
# workspace form gates Save the same way. Both read
# tests/fixtures/signup_allowlist_requirement_cases.json
# (TypeScript half: src/tests/schemas/contracts/custom-domain/signup-allowlist-requirement.spec.ts).
#
# The unreadable-list case is server-only and stays in
# try/unit/models/custom_domain/signup_config_try.rb.

# Read at file scope so a missing or renamed fixture raises here, naming the
# path, instead of leaving a suite that quietly runs zero examples.
allowlist_fixture_path = File.join(Onetime::HOME, 'tests', 'fixtures', 'signup_allowlist_requirement_cases.json')
allowlist_cases        = JSON.parse(File.read(allowlist_fixture_path)).fetch('cases')

# Cases whose removal OR alteration must turn this suite RED: the two that
# keep an empty effective list from passing, and the one the feature exists
# for. Pinned as full tuples, since editing a pinned case's inputs and
# flipping `met` would otherwise keep both suites green.
pinned_allowlist_cases = {
  'base-domain-only' => ['domain_allowlist', [], true, 'acme.com', true],
  'flag-without-base-domain' => ['domain_allowlist', [], true, nil, false],
  'empty-list-flag-off' => ['domain_allowlist', [], false, 'acme.com', false],
}.freeze

RSpec.describe Onetime::CustomDomain::SignupConfig do
  describe 'the shared allowlist requirement table' do
    it 'carries cases with unique ids' do
      ids = allowlist_cases.map { |c| c['id'] }
      expect(ids).not_to be_empty
      expect(ids.uniq.size).to eq(ids.size)
    end

    it 'still carries the pinned cases, unaltered' do
      by_id = allowlist_cases.to_h { |c| [c['id'], c] }

      pinned_allowlist_cases.each do |id, tuple|
        kase = by_id[id]
        expect(kase).not_to be_nil, "pinned case #{id} is missing from the fixture"
        expect(kase.values_at('strategy', 'domains', 'allow_base_domain', 'base_domain', 'met')).to eq(tuple),
          "pinned case #{id} was altered"
      end
    end

    it 'covers every strategy' do
      expect(allowlist_cases.map { |c| c['strategy'] }.uniq).to match_array(described_class::STRATEGY_TYPES)
    end
  end

  describe '.allowlist_requirement_error' do
    allowlist_cases.each do |kase|
      it "#{kase['met'] ? 'passes' : 'fails'} #{kase['id']}" do
        error = described_class.allowlist_requirement_error(
          strategy: kase['strategy'],
          domains: kase['domains'],
          corrupt: false,
          allow_base_domain: kase['allow_base_domain'],
          base_domain: kase['base_domain'],
        )

        # A readable list can only fail as REQUIRED, never UNREADABLE.
        expect(error).to eq(kase['met'] ? nil : described_class::ALLOWLIST_REQUIRED_ERROR)
      end
    end
  end
end

# spec/unit/onetime/utils/redirect_paths_spec.rb
#
# frozen_string_literal: true

# Unit tests for the server-side internal-redirect validator (#4305).
#
# This is a SECURITY boundary, not a formatting helper: the values it accepts
# are persisted across the signup -> verification-email -> sign-in journey and
# handed back to the SPA as navigation targets. An accepted absolute or
# protocol-relative reference is an open redirect.
#
# The ruleset is duplicated in src/utils/redirect.ts (isValidInternalPath).
# The two are held in lockstep by tests/fixtures/redirect_path_cases.json — a
# single accept/reject table that THIS suite and src/tests/utils/redirect.spec.ts
# both read. A rule relaxed on one side only shows up as a red test here or
# there rather than in production as a phishing vector. Parity is therefore
# enforced, not merely requested in a comment.
#
# What stays hand-written below: the cases that cannot cross the JSON boundary
# (non-String input, a String with invalid encoding) and the examples that
# assert more than a boolean (internal_path_or_nil returning the value
# verbatim, the module's exposure through Onetime::Utils).
#
# Run with:
#   bundle exec rspec spec/unit/onetime/utils/redirect_paths_spec.rb

require 'spec_helper'
require 'json'
require 'onetime/utils/redirect_paths'

# Read at file scope so a missing or renamed fixture raises here, naming the
# path, instead of leaving a suite that quietly runs zero parity examples.
redirect_fixture_path = File.join(Onetime::HOME, 'tests', 'fixtures', 'redirect_path_cases.json')
redirect_fixture      = JSON.parse(File.read(redirect_fixture_path))
redirect_cases        = redirect_fixture.fetch('cases')

# Cases whose removal from the fixture must turn this suite RED. Erosion is the
# one failure mode a fixture-driven suite cannot self-detect: delete every case
# and it passes vacuously. These are the acceptance criteria named in #4305 plus
# the two length boundaries.
pinned_case_ids = %w[
  nested-path
  query-and-fragment
  absolute-https
  protocol-relative
  backslash-authority
  encoded-traversal-lowercase
  length-at-cap
  length-over-cap
].freeze

RSpec.describe Onetime::Utils::RedirectPaths do
  # Exercise through a bare extender rather than Onetime::Utils so the module
  # is tested in isolation from whatever else Utils mixes in.
  let(:validator) do
    Module.new { extend Onetime::Utils::RedirectPaths }
  end

  describe 'the shared parity fixture' do
    it 'carries cases' do
      # Guards against a fixture that loaded from the wrong path, or one that
      # has been emptied: either would make every parity example below vanish
      # and the suite pass for the wrong reason.
      expect(redirect_cases).to be_an(Array)
      expect(redirect_cases.size).to be > 0
    end

    it 'still carries the pinned #4305 cases' do
      expect(redirect_cases.map { |c| c['id'] }).to include(*pinned_case_ids)
    end

    it 'uses unique ids' do
      ids = redirect_cases.map { |c| c['id'] }
      expect(ids.uniq.size).to eq(ids.size)
    end

    it 'gives every case a group' do
      # The group is what turns the generated examples back into a readable
      # taxonomy; a case without one would be silently unfiled.
      ungrouped = redirect_cases.reject { |c| c['group'].is_a?(String) && !c['group'].empty? }
      expect(ungrouped.map { |c| c['id'] }).to be_empty
    end

    it 'pins the length boundaries at MAX_PATH_LENGTH' do
      at_cap   = redirect_cases.find { |c| c['id'] == 'length-at-cap' }
      over_cap = redirect_cases.find { |c| c['id'] == 'length-over-cap' }

      expect(at_cap['input'].length).to eq(Onetime::Utils::RedirectPaths::MAX_PATH_LENGTH)
      expect(over_cap['input'].length).to eq(Onetime::Utils::RedirectPaths::MAX_PATH_LENGTH + 1)
    end
  end

  describe '#safe_internal_path?' do
    # One example per fixture case, named by the case id so a failure names the
    # offending input and the TypeScript half can be checked against the same
    # name. Nested under the case's `group` so the output still reads as a
    # taxonomy of the ruleset — the same reading the hand-written contexts gave,
    # now sourced from the fixture instead of restated in two languages.
    redirect_cases.group_by { |kase| kase['group'] }.each do |group, group_cases|
      context "with #{group}" do
        group_cases.each do |kase|
          verb  = kase['expected'] ? 'accepts' : 'rejects'
          # The length-boundary inputs are ~2KB; summarize rather than paste.
          shown = if kase['input'].length > 64
                    "#{kase['input'].length} characters"
                  else
                    kase['input'].inspect
                  end

          it "#{verb} #{kase['id']} (#{shown})" do
            expect(validator.safe_internal_path?(kase['input'])).to be kase['expected']
          end
        end
      end
    end

    # ------------------------------------------------------------------
    # Ruby-only cases. JSON has no way to express these, so they cannot live
    # in the shared fixture; the TypeScript suite carries its own equivalents
    # (undefined/null/number/object/array).
    # ------------------------------------------------------------------
    context 'with non-String input (not expressible in the shared fixture)' do
      it 'rejects nil' do
        expect(validator.safe_internal_path?(nil)).to be false
      end

      it 'rejects non-String values' do
        expect(validator.safe_internal_path?(123)).to be false
        expect(validator.safe_internal_path?(['/account'])).to be false
        expect(validator.safe_internal_path?({ path: '/account' })).to be false
      end
    end

    context 'with an invalidly-encoded String (not expressible in the shared fixture)' do
      it 'rejects a String tagged UTF-8 that holds an invalid byte' do
        # Distinct from the fixture's "decodes-to-invalid-utf8" case: there the
        # bytes arrive percent-encoded, here the String itself is already
        # broken before any decoding happens.
        expect(validator.safe_internal_path?((+"/acc\xFFount").force_encoding(Encoding::UTF_8))).to be false
      end
    end
  end

  describe '#internal_path_or_nil' do
    # Acceptance criterion from #4305: "/secret/abc?view=raw#content" must
    # survive intact. Query and fragment are simply part of the stored string —
    # there is no parsing/re-serialization step that could lose them.
    it 'returns the value verbatim when valid' do
      expect(validator.internal_path_or_nil('/secret/abc?view=raw#content'))
        .to eq('/secret/abc?view=raw#content')
    end

    it 'returns nil when invalid' do
      expect(validator.internal_path_or_nil('https://attacker.example')).to be_nil
    end

    it 'returns nil for nil' do
      expect(validator.internal_path_or_nil(nil)).to be_nil
    end
  end

  describe 'exposure through Onetime::Utils' do
    it 'is reachable as OT::Utils.safe_internal_path?' do
      expect(Onetime::Utils.safe_internal_path?('/account')).to be true
      expect(Onetime::Utils.safe_internal_path?('//evil.example')).to be false
    end

    it 'does not leak the decoding helper as a public API' do
      expect(Onetime::Utils).not_to respond_to(:percent_decode_once)
    end
  end
end

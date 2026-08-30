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

# Cases whose removal OR alteration must turn this suite RED. Erosion is the
# one failure mode a fixture-driven suite cannot self-detect: delete every case
# and it passes vacuously — and pinning bare ids is not enough, because editing
# a pinned case's input (retargeting `protocol-relative` at some harmless path
# and flipping `expected`) would keep both suites green while removing the
# rejection from coverage. So the acceptance criteria named in #4305 are pinned
# as full (id, input, expected) triples.
pinned_cases = {
  'nested-path' => ['/account/settings/security', true],
  'query-and-fragment' => ['/secret/abc?view=raw#content', true],
  'absolute-https' => ['https://attacker.example', false],
  'protocol-relative' => ['//evil.example', false],
  'backslash-authority' => ['/\evil.example', false],
  'encoded-traversal-lowercase' => ['/%2e%2e/admin', false],
}.freeze

# The length boundaries are pinned too, but their ~2KB inputs are asserted by
# construction (exact length against MAX_PATH_LENGTH, plus expected) in the
# boundary example below rather than pasted here.
pinned_length_case_ids = %w[
  length-at-cap
  length-over-cap
  astral-length-at-cap
  astral-length-over-cap
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

    it 'still carries the pinned #4305 cases, unaltered' do
      by_id = redirect_cases.to_h { |c| [c['id'], c] }

      pinned_cases.each do |id, (input, expected)|
        kase = by_id[id]
        expect(kase).not_to be_nil, "pinned case #{id} is missing from the fixture"
        expect([kase['input'], kase['expected']]).to eq([input, expected]),
          "pinned case #{id} was altered (its input/expected no longer match #4305)"
      end

      expect(by_id.keys).to include(*pinned_length_case_ids)
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
      # String#length counts CODE POINTS — the unit the cap is defined in. The
      # astral cases are the ones where that matters: their UTF-16 length is
      # nearly double, so a validator measuring UTF-16 units (JS String.length)
      # disagrees with this one exactly there. The TS suite measures these same
      # cases in code points via [...input].length.
      boundaries = {
        'length-at-cap' => [0, true],
        'length-over-cap' => [1, false],
        'astral-length-at-cap' => [0, true],
        'astral-length-over-cap' => [1, false],
      }

      boundaries.each do |id, (over_by, expected)|
        kase = redirect_cases.find { |c| c['id'] == id }
        expect(kase['input'].length)
          .to eq(Onetime::Utils::RedirectPaths::MAX_PATH_LENGTH + over_by), "#{id} length drifted"
        expect(kase['expected']).to be(expected), "#{id} expectation flipped"
      end
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

  describe '#loggable_path' do
    # SECURITY: this is what keeps live bearer credentials out of the auth
    # log. `/invite/<token>` and `/secret/<key>` are both ACCEPTED redirect
    # shapes and both grant access to whoever replays them, so the accept-side
    # log lines must not carry the value.
    it 'keeps only the leading path segment of an invite link' do
      expect(validator.loggable_path('/invite/8f3c1d9e2b7a4056')).to eq('/invite')
    end

    it 'keeps only the leading path segment of a secret link' do
      expect(validator.loggable_path('/secret/abc?view=raw#content')).to eq('/secret')
    end

    it 'drops the query and fragment of a single-segment path' do
      expect(validator.loggable_path('/account?tab=security#mfa')).to eq('/account')
    end

    it 'returns the path unchanged when there is nothing to redact' do
      expect(validator.loggable_path('/dashboard')).to eq('/dashboard')
    end

    it 'returns the root path unchanged' do
      expect(validator.loggable_path('/')).to eq('/')
    end

    it 'returns an empty string for a non-String' do
      expect(validator.loggable_path(nil)).to eq('')
      expect(validator.loggable_path(['/invite/tok'])).to eq('')
    end

    it 'slices on the decoded separator, not the raw one' do
      # `/secret%2f<key>` is one RAW segment but two real ones. Slicing the
      # raw string would put the leading characters of the key in the log.
      key = 'a' * 62

      expect(validator.loggable_path("/secret%2f#{key}")).to eq('/secret')
      expect(validator.loggable_path("/invite%2Ftok123")).to eq('/invite')
    end

    it 'returns an empty string when the value does not decode' do
      expect(validator.loggable_path('/invite/%zz')).to eq('')
    end

    it 'truncates an over-long first segment' do
      # No route puts a credential in the first segment today, but if one ever
      # did, the cap keeps it out of the log. Callers log `value_length`
      # separately, so nothing diagnostic is lost.
      token = 'a' * 80

      expect(validator.loggable_path("/#{token}")).to eq("/#{'a' * 31}...")
    end

    it 'returns an empty string for a value that is not an absolute path' do
      # Never reached in practice (callers redact only accepted values), but a
      # regex that anchors on '/' must not silently pass a bare token through.
      expect(validator.loggable_path('invite/8f3c1d9e2b7a4056')).to eq('')
    end
  end

  describe 'exposure through Onetime::Utils' do
    it 'is reachable as OT::Utils.safe_internal_path?' do
      expect(Onetime::Utils.safe_internal_path?('/account')).to be true
      expect(Onetime::Utils.safe_internal_path?('//evil.example')).to be false
    end

    it 'is reachable as OT::Utils.loggable_path' do
      expect(Onetime::Utils.loggable_path('/invite/8f3c1d9e2b7a4056')).to eq('/invite')
    end

    it 'does not leak the decoding helper as a public API' do
      expect(Onetime::Utils).not_to respond_to(:percent_decode_once)
    end
  end
end

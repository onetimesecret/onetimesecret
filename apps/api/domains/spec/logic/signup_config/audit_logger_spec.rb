# apps/api/domains/spec/logic/signup_config/audit_logger_spec.rb
#
# frozen_string_literal: true

# Unit tests for AuditLogger#compute_signup_changes — the normalization seam
# pinned by issue #3245.
#
# The change-detector compares parsed/normalized values: callers (e.g.
# PatchSignupConfig#normalized_change_params) MUST feed Arrays for
# allowed_signup_domains, not raw comma-separated strings, and MUST omit
# blank-valued fields rather than including them with empty/nil values.
# These specs document and pin that contract.
#
# RUN:
#   pnpm run test:rspec apps/api/domains/spec/logic/signup_config/audit_logger_spec.rb

require_relative File.join(Onetime::HOME, 'spec', 'spec_helper')
require_relative '../../../../../../apps/api/domains/application'

RSpec.describe DomainsAPI::Logic::SignupConfig::AuditLogger do
  # Minimal host class — AuditLogger is a mixin and compute_signup_changes
  # doesn't touch instance state, so any include site is sufficient.
  let(:host_class) do
    Class.new { include DomainsAPI::Logic::SignupConfig::AuditLogger }
  end
  let(:host) { host_class.new }

  # compute_signup_changes asks the config for `.enabled?`,
  # `.allowed_signup_domains`, and `.send(:validation_strategy)`.
  def config_double(validation_strategy:, allowed_signup_domains:, enabled:)
    instance_double(
      Onetime::CustomDomain::SignupConfig,
      validation_strategy: validation_strategy,
      allowed_signup_domains: allowed_signup_domains,
      enabled?: enabled,
    )
  end

  describe '#compute_signup_changes' do
    subject(:changes) { host.compute_signup_changes(old_config, new_params) }

    let(:old_config) do
      config_double(
        validation_strategy: 'domain_allowlist',
        allowed_signup_domains: ['a.com', 'b.com'],
        enabled: false,
      )
    end

    context 'with no fields provided' do
      let(:new_params) { {} }

      it 'returns an empty hash' do
        expect(changes).to eq({})
      end
    end

    context 'with a field outside SAFE_FIELDS' do
      let(:new_params) { { 'unknown_field' => 'value' } }

      it 'is ignored' do
        expect(changes).to eq({})
      end
    end

    describe 'field key detection' do
      it 'recognizes string keys' do
        result = host.compute_signup_changes(old_config, { 'enabled' => true })
        expect(result).to have_key('enabled')
      end

      it 'recognizes symbol keys' do
        result = host.compute_signup_changes(old_config, { enabled: true })
        expect(result).to have_key('enabled')
      end

      it 'applies value coercion under symbol keys (closes the params[field.to_sym] branch)' do
        # extract_new_value reads `params[field] || params[field.to_sym]`. The
        # string-key tests cover coercion; this confirms coercion still
        # applies when the key is a symbol — same enabled-coercion logic
        # runs on either lookup path.
        result = host.compute_signup_changes(old_config, { enabled: 'true' })
        expect(result['enabled']).to eq(from: false, to: true)
      end
    end

    describe 'validation_strategy' do
      context 'when not provided' do
        let(:new_params) { {} }

        it 'is omitted from changes' do
          expect(changes).not_to have_key('validation_strategy')
        end
      end

      context 'when provided as the same value' do
        let(:new_params) { { 'validation_strategy' => 'domain_allowlist' } }

        it 'is omitted from changes' do
          expect(changes).not_to have_key('validation_strategy')
        end
      end

      context 'when provided as a new value' do
        let(:new_params) { { 'validation_strategy' => 'passthrough' } }

        it 'is recorded with from/to' do
          expect(changes['validation_strategy']).to eq(from: 'domain_allowlist', to: 'passthrough')
        end
      end

      context 'when provided as an empty string' do
        let(:new_params) { { 'validation_strategy' => '' } }

        # Pins the responsibility split: AuditLogger treats key-presence as
        # "provided" and compares normalized values. '' normalizes to nil and
        # mismatches the existing 'domain_allowlist'. The caller (e.g.
        # PatchSignupConfig#normalized_change_params) is responsible for
        # excluding blank-valued fields from the hash it passes in. If a
        # future refactor moves blank-handling into AuditLogger itself, this
        # test should be revisited.
        it 'is recorded as a change' do
          expect(changes['validation_strategy']).to eq(from: 'domain_allowlist', to: '')
        end
      end

      context 'when existing is nil and provided as empty string' do
        let(:old_config) do
          config_double(
            validation_strategy: nil,
            allowed_signup_domains: [],
            enabled: false,
          )
        end
        let(:new_params) { { 'validation_strategy' => '' } }

        # Pins normalize_value's collapse of nil and '' to the same nil
        # bucket: when both sides normalize to nil, values_equal? returns
        # true and no change is recorded. This is the symmetric counterpart
        # to the previous context.
        it 'is omitted from changes (nil and "" both normalize to nil)' do
          expect(changes).not_to have_key('validation_strategy')
        end
      end
    end

    describe 'enabled' do
      context 'when not provided' do
        let(:new_params) { {} }

        it 'is omitted from changes' do
          expect(changes).not_to have_key('enabled')
        end
      end

      context 'when matching existing state' do
        let(:new_params) { { 'enabled' => false } }

        it 'is omitted from changes' do
          expect(changes).not_to have_key('enabled')
        end
      end

      context 'when toggled true' do
        let(:new_params) { { 'enabled' => true } }

        it 'is recorded as from false to true' do
          expect(changes['enabled']).to eq(from: false, to: true)
        end
      end

      context "with string 'true'" do
        let(:new_params) { { 'enabled' => 'true' } }

        it 'is coerced to true' do
          expect(changes['enabled']).to eq(from: false, to: true)
        end
      end

      context "with string '1'" do
        let(:new_params) { { 'enabled' => '1' } }

        it 'is coerced to true' do
          expect(changes['enabled']).to eq(from: false, to: true)
        end
      end

      context 'with integer 1' do
        let(:new_params) { { 'enabled' => 1 } }

        it 'is coerced to true' do
          expect(changes['enabled']).to eq(from: false, to: true)
        end
      end

      context 'with integer 0' do
        # Pins the asymmetry with `1`: only `true`, 'true', '1', 1 coerce
        # truthy (audit_logger.rb extract_new_value). Everything else,
        # including 0, falls through to false. Matches existing false state
        # so no change recorded.
        let(:new_params) { { 'enabled' => 0 } }

        it 'is coerced to false (matches existing false, no change recorded)' do
          expect(changes).not_to have_key('enabled')
        end
      end

      context 'with a non-truthy value against an enabled existing config' do
        let(:old_config) do
          config_double(
            validation_strategy: 'passthrough',
            allowed_signup_domains: [],
            enabled: true,
          )
        end
        let(:new_params) { { 'enabled' => 'false' } }

        it 'is coerced to false and recorded' do
          expect(changes['enabled']).to eq(from: true, to: false)
        end
      end
    end

    describe 'allowed_signup_domains' do
      # These cover the headline regression vector from #3245.
      # compute_signup_changes does NOT parse raw strings; callers must
      # pre-parse to an Array. The "raw comma-separated string" test below
      # pins the negative behavior the PatchSignupConfig fix guards against.

      context 'when not provided' do
        let(:new_params) { {} }

        it 'is omitted from changes' do
          expect(changes).not_to have_key('allowed_signup_domains')
        end
      end

      context 'when matching existing array' do
        let(:new_params) { { 'allowed_signup_domains' => ['a.com', 'b.com'] } }

        it 'is omitted from changes' do
          expect(changes).not_to have_key('allowed_signup_domains')
        end
      end

      context 'when matching with different sort order' do
        let(:new_params) { { 'allowed_signup_domains' => ['b.com', 'a.com'] } }

        it 'is omitted (normalize sorts)' do
          expect(changes).not_to have_key('allowed_signup_domains')
        end
      end

      context 'when matching with different case' do
        let(:new_params) { { 'allowed_signup_domains' => ['A.COM', 'B.COM'] } }

        it 'is omitted (normalize lowercases)' do
          expect(changes).not_to have_key('allowed_signup_domains')
        end
      end

      context 'when matching with whitespace' do
        let(:new_params) { { 'allowed_signup_domains' => [' a.com ', "\tb.com"] } }

        it 'is omitted (normalize trims)' do
          expect(changes).not_to have_key('allowed_signup_domains')
        end
      end

      context 'when matching with extra empty entries' do
        let(:new_params) { { 'allowed_signup_domains' => ['a.com', '', 'b.com'] } }

        it 'is omitted (normalize rejects empties)' do
          expect(changes).not_to have_key('allowed_signup_domains')
        end
      end

      context 'when domains genuinely differ' do
        let(:new_params) { { 'allowed_signup_domains' => ['c.com'] } }

        it 'records from/to with the raw (un-normalized) input values' do
          expect(changes['allowed_signup_domains']).to eq(
            from: ['a.com', 'b.com'],
            to: ['c.com'],
          )
        end
      end

      # Pins the negative behavior PatchSignupConfig#normalized_change_params
      # guards against (issues #3202 and #3245). compute_signup_changes does
      # not parse strings; a String falls through normalize_value's `else`
      # branch unchanged and mismatches the sorted Array form of the existing
      # value. If a future refactor makes normalize_value parse strings
      # itself, this test should be revisited — but the contract today is
      # "callers must pre-parse."
      context 'when passed as a raw comma-separated string (the bug shape)' do
        let(:new_params) { { 'allowed_signup_domains' => 'a.com, b.com' } }

        it 'reports a false change because the String is not normalized to an Array' do
          expect(changes['allowed_signup_domains']).to eq(
            from: ['a.com', 'b.com'],
            to: 'a.com, b.com',
          )
        end
      end
    end

    describe 'multiple fields at once' do
      let(:new_params) do
        {
          'validation_strategy'    => 'domain_allowlist',  # same — no change
          'enabled'                => true,                # different — change
          'allowed_signup_domains' => ['c.com'],           # different — change
        }
      end

      it 'records only the fields that actually differ' do
        expect(changes.keys).to contain_exactly('enabled', 'allowed_signup_domains')
        expect(changes['enabled']).to eq(from: false, to: true)
        expect(changes['allowed_signup_domains']).to eq(from: ['a.com', 'b.com'], to: ['c.com'])
      end
    end
  end
end

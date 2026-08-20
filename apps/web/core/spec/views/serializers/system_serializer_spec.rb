# apps/web/core/spec/views/serializers/system_serializer_spec.rb
#
# frozen_string_literal: true

# Coverage for SystemSerializer's auth-gated version disclosure.
#
# The app version, long version and Ruby version are withheld from anonymous
# visitors: the exact app/runtime version pairing is the primary input to
# fingerprinting an install and matching it against known CVEs, and the
# bootstrap payload is emitted to every visitor on every page load.
#
# The withheld value is an empty string rather than nil on purpose — the
# frontend contract (src/schemas/contracts/bootstrap.ts) types these fields as
# `z.string().default('')`, and Zod's .default() only fills `undefined`, so a
# JSON null would fail validation and reject the whole payload.
#
# No Redis or SQL required.
#
# Run with:
#   tests/lanes/run unit --only apps/web/core/spec/views/serializers/system_serializer_spec.rb

require_relative File.join(Onetime::HOME, 'spec', 'spec_helper')
require_relative '../../../views/serializers'

RSpec.describe Core::Views::SystemSerializer do
  subject(:output) { described_class.serialize(view_vars) }

  let(:base_vars) { { 'shrimp' => 'token-abc', 'nonce' => 'nonce-xyz' } }

  # Fields that carry version/runtime fingerprinting value.
  let(:version_keys) { %w[ot_version ot_version_long ruby_version] }

  context 'when the visitor is anonymous' do
    let(:view_vars) { base_vars.merge('authenticated' => false) }

    it 'withholds every version field' do
      version_keys.each do |key|
        expect(output[key]).to eq(''), "Expected '#{key}' to be withheld, got #{output[key].inspect}"
      end
    end

    it 'leaks neither the app version nor the Ruby version anywhere in the payload' do
      serialized = output.values.map(&:to_s)

      expect(serialized).not_to include(a_string_including(OT::VERSION.to_s))
      expect(serialized).not_to include(a_string_including(RUBY_VERSION))
    end

    it 'still emits the keys so the frontend Zod contract holds' do
      version_keys.each do |key|
        expect(output).to have_key(key)
        expect(output[key]).to be_a(String)
      end
    end

    it 'still emits the security values, which are not version related' do
      expect(output['shrimp']).to eq('token-abc')
      expect(output['nonce']).to eq('nonce-xyz')
    end
  end

  context 'when the visitor is authenticated' do
    let(:view_vars) { base_vars.merge('authenticated' => true) }

    it 'emits the real app version' do
      expect(output['ot_version']).to eq(OT::VERSION.to_s)
      expect(output['ot_version_long']).to eq(OT::VERSION.details)
    end

    it 'emits the real Ruby version' do
      expect(output['ruby_version']).to eq(RUBY_VERSION.to_s)
    end
  end

  # A missing 'authenticated' key must fail closed. InitializeViewVars always
  # sets it, but the error-recovery path builds view_vars by other means, and
  # an error page is the last place that should start disclosing build info.
  context 'when the authenticated flag is absent' do
    let(:view_vars) { base_vars }

    it 'fails closed and withholds the version' do
      version_keys.each do |key|
        expect(output[key]).to eq('')
      end
    end
  end

  context 'when the authenticated flag is nil' do
    let(:view_vars) { base_vars.merge('authenticated' => nil) }

    it 'fails closed and withholds the version' do
      version_keys.each do |key|
        expect(output[key]).to eq('')
      end
    end
  end
end

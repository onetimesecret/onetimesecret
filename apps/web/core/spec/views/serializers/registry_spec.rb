# apps/web/core/spec/views/serializers/registry_spec.rb
#
# frozen_string_literal: true

# Unit tests for SerializerRegistry output boundary enforcement.
#
# The output_template is each serializer's boundary schema for the bootstrap
# payload: keys a serializer never declared are stripped (not just warned
# about) so accidental additions cannot reach the browser.
#
# Run with:
#   source .env.test && bundle exec rspec apps/web/core/spec/views/serializers/registry_spec.rb

require_relative File.join(Onetime::HOME, 'spec', 'spec_helper')
require_relative '../../../views/serializers'

RSpec.describe Core::Views::SerializerRegistry do
  let(:declared_serializer) do
    Module.new do
      def self.to_s = 'DeclaredSerializer'

      def self.output_template
        { 'declared_key' => nil, 'other_declared' => nil }
      end

      def self.serialize(_vars)
        {
          'declared_key' => 'value',
          'undeclared_key' => 'must-not-ship',
        }
      end
    end
  end

  after do
    described_class.serializers.delete(declared_serializer)
    described_class.dependencies.delete(declared_serializer)
  end

  describe '.run' do
    it 'passes through keys declared in the output_template' do
      described_class.register(declared_serializer)
      result = described_class.run([declared_serializer], {})
      expect(result['declared_key']).to eq('value')
    end

    it 'strips keys the serializer did not declare' do
      described_class.register(declared_serializer)
      result = described_class.run([declared_serializer], {})
      expect(result).not_to have_key('undeclared_key')
    end
  end
end

# spec/unit/onetime/operations/config/validate_spec.rb
#
# frozen_string_literal: true

require 'spec_helper'
require 'onetime/operations/config/validate'

RSpec.describe Onetime::Operations::Config::Validate do
  let(:default_schema_path) do
    File.join(Onetime::HOME, 'generated', 'schemas', 'config', 'static.schema.json')
  end
  let(:default_config_path) do
    File.join(Onetime::HOME, 'etc', 'defaults', 'config.defaults.yaml')
  end

  describe '.call (with mocked filesystem)' do
    let(:config_path) { '/tmp/fake-config.yaml' }
    let(:schema_path) { '/tmp/fake-schema.json' }

    before do
      allow(File).to receive(:exist?).and_call_original
      allow(File).to receive(:exist?).with(config_path).and_return(true)
      allow(File).to receive(:exist?).with(schema_path).and_return(true)

      allow(File).to receive(:read).and_call_original
      allow(File).to receive(:read).with(config_path).and_return(config_yaml)
      allow(File).to receive(:read).with(schema_path).and_return(schema_json.to_json)
    end

    subject(:result) do
      described_class.call(config_path: config_path, schema_path: schema_path)
    end

    context 'with a config matching the schema' do
      let(:config_yaml) { { 'site' => { 'host' => 'example.com', 'ssl' => true } }.to_yaml }
      let(:schema_json) do
        {
          'type'       => 'object',
          'properties' => {
            'site' => {
              'type'       => 'object',
              'properties' => {
                'host' => { 'type' => 'string' },
                'ssl'  => { 'type' => 'boolean' },
              },
              'required'   => ['host'],
            },
          },
          'required'   => ['site'],
        }
      end

      it 'returns success: true and valid: true with no errors' do
        expect(result.success).to be(true)
        expect(result.valid).to be(true)
        expect(result.errors).to be_empty
      end
    end

    context 'with a config violating the schema' do
      let(:config_yaml) { { 'site' => { 'ssl' => 'not-a-bool' } }.to_yaml }
      let(:schema_json) do
        {
          'type'       => 'object',
          'properties' => {
            'site' => {
              'type'       => 'object',
              'properties' => {
                'host' => { 'type' => 'string' },
                'ssl'  => { 'type' => 'boolean' },
              },
              'required'   => ['host'],
            },
          },
        }
      end

      it 'returns success: true and valid: false with descriptive errors' do
        expect(result.success).to be(true)
        expect(result.valid).to be(false)
        expect(result.errors).not_to be_empty
        expect(result.errors.join("\n")).to include('/site/ssl')
      end
    end

    context 'with ERB in the config' do
      let(:config_yaml) do
        <<~YAML
          site:
            host: <%= ENV.fetch('TEST_HOST', 'example.com') %>
        YAML
      end
      let(:schema_json) do
        {
          'type'       => 'object',
          'properties' => {
            'site' => {
              'type'       => 'object',
              'properties' => { 'host' => { 'type' => 'string' } },
            },
          },
        }
      end

      it 'renders ERB before validating' do
        expect(result.success).to be(true)
        expect(result.valid).to be(true)
      end
    end
  end

  describe '.call (with missing files)' do
    it 'reports a clear error when the config file is missing' do
      result = described_class.call(
        config_path: '/nonexistent/config.yaml',
        schema_path: default_schema_path,
      )
      expect(result.success).to be(false)
      expect(result.errors.first).to match(/Config file not found/)
    end

    it 'reports a clear error when the schema file is missing' do
      result = described_class.call(
        config_path: default_config_path,
        schema_path: '/nonexistent/schema.json',
      )
      expect(result.success).to be(false)
      expect(result.errors.first).to match(/Schema file not found.*pnpm run schemas:json:generate/)
    end
  end

  # Drift-detection guard: the real YAML must validate against the real
  # generated schema. This is the spec that catches future schema/YAML
  # divergence — the exact bug class that produced PR #3206 in the first
  # place. Skipped when the schema hasn't been generated yet so local-only
  # runs without `pnpm run schemas:json:generate` don't fail spuriously.
  describe '.call against the real config and generated schema' do
    subject(:result) { described_class.call }

    before do
      skip 'JSON Schema not generated; run `pnpm run schemas:json:generate`' \
        unless File.exist?(default_schema_path)
      skip "Config file missing at #{default_config_path}" \
        unless File.exist?(default_config_path)
    end

    it 'validates etc/defaults/config.defaults.yaml against the generated schema' do
      aggregate_failures do
        expect(result.success).to be(true), result.errors.join("\n")
        expect(result.valid).to be(true), result.errors.join("\n")
        expect(result.errors).to be_empty
      end
    end
  end
end

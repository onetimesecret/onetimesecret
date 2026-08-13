# spec/unit/onetime/mail/frontend_provider_parity_spec.rb
#
# frozen_string_literal: true

# Frontend <-> ProviderRegistry parity guard.
#
# The frontend cannot consume Ruby, so its provider lists are hand-maintained
# copies of Onetime::Mail::ProviderRegistry derivations. This spec reads the
# TS/Vue sources with tolerant regex extraction and fails when they drift.
#
# Parity rules asserted:
#
#   1. zod emailProviderTypeSchema (src/schemas/contracts/email-config.ts)
#      == ProviderRegistry.provisioning_providers + ['inherit'].
#      'smtp' is deliberately absent: per-domain sender configs only surface
#      providers OTS can provision via API (PUT/PATCH never accept a provider;
#      the wire serializer emits the stored provider or 'inherit' when blank —
#      see apps/api/domains/logic/sender_config/serializers.rb).
#      'inherit' is a wire-only sentinel meaning "use installation default".
#
#   2. The providerDisplayName map in DomainEmailConfigForm.vue covers exactly
#      the same set: provisioning_providers + ['inherit'].
#
#   3. The independently-nullable provider blocks in
#      colonelEmailProviderStatusDetailsSchema
#      (src/schemas/api/internal/responses/colonel-deliverability.ts)
#      == ProviderRegistry.feedback_providers (providers with a pollable
#      feedback/status API).
#
#   4. The generated static config schema constrains emailer.mode to registry
#      providers plus Mailer's non-provider transports, constrains
#      sender_provider to registry providers, and models exactly one
#      email_providers block per provisioning provider.
#
#   5. DNS defaults in both the generated schema and rendered shipped YAML
#      agree with each registry descriptor. Provider ENV variables are cleared
#      around the YAML check so ambient deployment config cannot mask drift.
#
# Extraction is designed to fail LOUDLY: if a regex no longer matches (file
# moved or reshaped), the spec fails telling the maintainer to update this
# parity spec — it never silently passes on extraction failure.

require 'json'
require 'spec_helper'
require 'onetime/mail/provider_registry'

RSpec.describe 'Frontend mail provider parity' do # rubocop:disable RSpec/DescribeClass
  let(:project_root) { File.expand_path('../../../..', __dir__) }
  let(:generated_schema_path) do
    File.join(project_root, 'generated', 'schemas', 'config', 'static.schema.json')
  end
  let(:defaults_path) { File.join(project_root, 'etc', 'defaults', 'config.defaults.yaml') }

  def frontend_source(relative_path)
    path = File.join(project_root, relative_path)
    unless File.file?(path)
      raise "Parity spec target #{relative_path} not found. If the file moved, " \
            'update spec/unit/onetime/mail/frontend_provider_parity_spec.rb.'
    end

    File.read(path)
  end

  # Extract with a regex that MUST match; a miss means the file was reshaped
  # and this spec needs updating — never a silent pass.
  def extract!(source, pattern, description, relative_path)
    match = source.match(pattern)
    unless match
      raise "Could not extract #{description} from #{relative_path} " \
            "(pattern #{pattern.inspect} did not match). The file was likely " \
            'reshaped — update the extraction in ' \
            'spec/unit/onetime/mail/frontend_provider_parity_spec.rb.'
    end

    match[1]
  end

  def generated_static_schema
    unless File.file?(generated_schema_path)
      skip 'JSON Schema not generated; run `pnpm run schemas:json:generate`'
    end

    JSON.parse(File.read(generated_schema_path))
  end

  def enum_values(schema)
    direct = schema.fetch('enum', [])
    nested = schema.fetch('anyOf', []).flat_map { |branch| enum_values(branch) }
    direct + nested
  end

  let(:registry) { Onetime::Mail::ProviderRegistry }
  let(:provisioning_plus_inherit) { registry.provisioning_providers + %w[inherit] }

  describe 'zod emailProviderTypeSchema (src/schemas/contracts/email-config.ts)' do
    it 'equals ProviderRegistry.provisioning_providers + inherit' do
      relative = 'src/schemas/contracts/email-config.ts'
      source = frontend_source(relative)
      body = extract!(
        source,
        /emailProviderTypeSchema\s*=\s*z\.enum\(\[([^\]]*)\]/m,
        'emailProviderTypeSchema z.enum values',
        relative,
      )
      values = body.scan(/['"]([^'"]+)['"]/).flatten

      expect(values).to match_array(provisioning_plus_inherit),
        "zod emailProviderTypeSchema #{values.inspect} drifted from " \
        "ProviderRegistry.provisioning_providers + ['inherit'] " \
        "#{provisioning_plus_inherit.inspect} — update #{relative} or the registry."
    end
  end

  describe 'providerDisplayName map (DomainEmailConfigForm.vue)' do
    it 'covers exactly provisioning_providers + inherit' do
      relative = 'src/apps/workspace/components/domains/DomainEmailConfigForm.vue'
      source = frontend_source(relative)
      body = extract!(
        source,
        /const\s+map:\s*Record<string,\s*string>\s*=\s*\{([^}]*)\}/m,
        'providerDisplayName provider->label map',
        relative,
      )
      keys = body.scan(/^\s*(\w+):/).flatten

      expect(keys).to match_array(provisioning_plus_inherit),
        "providerDisplayName map keys #{keys.inspect} drifted from " \
        "ProviderRegistry.provisioning_providers + ['inherit'] " \
        "#{provisioning_plus_inherit.inspect} — update #{relative} or the registry."
    end

    it 'uses the registry labels for each provider' do
      relative = 'src/apps/workspace/components/domains/DomainEmailConfigForm.vue'
      source = frontend_source(relative)
      body = extract!(
        source,
        /const\s+map:\s*Record<string,\s*string>\s*=\s*\{([^}]*)\}/m,
        'providerDisplayName provider->label map',
        relative,
      )
      labels = body.scan(/^\s*(\w+):\s*['"]([^'"]*)['"]/).to_h

      Onetime::Mail::ProviderRegistry.provisioning_providers.each do |name|
        expect(labels[name]).to eq(Onetime::Mail::ProviderRegistry.descriptor!(name).label),
          "Display label for '#{name}' in #{relative} drifted from the registry label."
      end
    end
  end

  describe 'config provider mirrors (src/schemas/.../config/section/mail.ts)' do
    it 'keeps delivery and sender-provider enums aligned with the registry' do
      relative = 'src/schemas/shapes/config/section/mail.ts'
      source   = frontend_source(relative)

      delivery_body = extract!(
        source,
        /emailDeliveryModeSchema\s*=\s*z\.enum\(\[([^\]]*)\]/m,
        'emailDeliveryModeSchema z.enum values',
        relative,
      )
      sender_body = extract!(
        source,
        /emailSenderProviderSchema\s*=\s*z\.enum\(\[([^\]]*)\]/m,
        'emailSenderProviderSchema z.enum values',
        relative,
      )
      delivery_values = delivery_body.scan(/['"]([^'"]+)['"]/).flatten
      sender_values   = sender_body.scan(/['"]([^'"]+)['"]/).flatten

      expect(delivery_values).to match_array(registry.providers + %w[logger disabled none])
      expect(sender_values).to match_array(registry.providers)
    end

    it 'models exactly the provisioning-provider config blocks' do
      relative = 'src/schemas/contracts/config/section/mail.ts'
      source   = frontend_source(relative)
      body     = extract!(
        source,
        /emailProvidersSchema\s*=\s*z\.strictObject\(\{(.*?)\}\);/m,
        'emailProvidersSchema object body',
        relative,
      )
      provider_entries = body.scan(
        /^\s*(\w+):\s*(\w+EmailProviderSchema)\.optional\(\)/,
      )
      provider_keys = provider_entries.map(&:first)

      expect(provider_keys).to match_array(registry.provisioning_providers),
        "emailProvidersSchema blocks #{provider_keys.inspect} drifted from " \
        "ProviderRegistry.provisioning_providers #{registry.provisioning_providers.inspect}."
      provider_entries.each do |name, schema_name|
        expect(source).to match(/const\s+#{Regexp.escape(schema_name)}\s*=\s*z\.strictObject\(/),
          "email_providers.#{name} must use z.strictObject so misspelled keys are rejected."
      end
    end
  end

  describe 'colonel provider-status blocks (colonel-deliverability.ts)' do
    it 'carries exactly the feedback-capable providers as nullable blocks' do
      relative = 'src/schemas/api/internal/responses/colonel-deliverability.ts'
      source = frontend_source(relative)
      body = extract!(
        source,
        /colonelEmailProviderStatusDetailsSchema\s*=\s*z\.object\(\{(.*?)\}\)/m,
        'colonelEmailProviderStatusDetailsSchema object body',
        relative,
      )
      # Provider blocks are the keys whose value is a per-provider status
      # schema; scalar fields (provider/capability/available/error) don't match.
      provider_keys = body.scan(/^\s*(\w+):\s*colonelEmailProviderStatus\w+Schema\.nullable\(\)/).flatten

      expect(provider_keys).to match_array(registry.feedback_providers),
        "colonelEmailProviderStatusDetailsSchema provider blocks #{provider_keys.inspect} " \
        'drifted from ProviderRegistry.feedback_providers ' \
        "#{registry.feedback_providers.inspect} — a new feedback provider needs a status " \
        "block in #{relative} (and vice versa)."
    end
  end

  describe 'generated static config schema provider surfaces' do
    let(:properties) { generated_static_schema.fetch('properties') }
    let(:emailer_properties) { properties.fetch('emailer').fetch('properties') }
    let(:provider_schemas) do
      properties.fetch('email_providers').fetch('properties')
    end

    it 'constrains emailer.mode to registry providers plus non-provider transports' do
      expected = registry.providers + %w[logger disabled none]
      actual   = enum_values(emailer_properties.fetch('mode'))

      expect(actual).to match_array(expected),
        "generated emailer.mode values #{actual.inspect} drifted from registry providers " \
        "plus Mailer transports #{expected.inspect} — update the TypeScript mail shape " \
        'and regenerate schemas.'
    end

    it 'constrains emailer.sender_provider to registry providers while preserving null' do
      schema = emailer_properties.fetch('sender_provider')
      actual = enum_values(schema)

      expect(actual).to match_array(registry.providers),
        "generated emailer.sender_provider values #{actual.inspect} drifted from " \
        "ProviderRegistry.providers #{registry.providers.inspect}."
      expect(schema.fetch('anyOf', []).map { |branch| branch['type'] }).to include('null'),
        'emailer.sender_provider must remain nullable for an unset CUSTOM_MAIL_PROVIDER.'
    end

    it 'strictly models exactly the provisioning-provider blocks' do
      email_providers_schema = properties.fetch('email_providers')

      expect(provider_schemas.keys).to match_array(registry.provisioning_providers),
        "generated email_providers blocks #{provider_schemas.keys.inspect} drifted from " \
        "ProviderRegistry.provisioning_providers #{registry.provisioning_providers.inspect}."
      expect(email_providers_schema['additionalProperties']).to be(false),
        'email_providers must reject misspelled or unregistered provider blocks.'
      provider_schemas.each do |name, schema|
        expect(schema['additionalProperties']).to be(false),
          "email_providers.#{name} must reject unknown provider config keys."
      end
    end

    it 'uses every descriptor config key and DNS default in the generated provider blocks' do
      registry.provisioning_providers.each do |name|
        descriptor = registry.descriptor!(name)
        properties = provider_schemas.fetch(name).fetch('properties')
        expected_keys = (descriptor.dns_defaults.keys + descriptor.config_env_sources.keys)
          .map(&:to_s)
          .uniq
        actual_defaults = properties.filter_map do |key, schema|
          [key, schema.fetch('default')] if schema.key?('default')
        end.to_h
        expected_defaults = descriptor.dns_defaults.transform_keys(&:to_s)

        expect(properties.keys).to match_array(expected_keys),
          "generated email_providers.#{name} keys #{properties.keys.inspect} drifted from " \
          "ProviderRegistry #{expected_keys.inspect}."
        expect(actual_defaults).to eq(expected_defaults),
          "generated email_providers.#{name} defaults #{actual_defaults.inspect} drifted " \
          "from ProviderRegistry #{expected_defaults.inspect}."
      end
    end
  end

  describe 'rendered etc/defaults/config.defaults.yaml provider surfaces' do
    def load_provider_config
      Onetime::Config.load(defaults_path).fetch('email_providers')
    end

    around do |example|
      env_names = registry.descriptors
        .flat_map { |descriptor| descriptor.config_env_sources.values.flatten }
        .uniq
      saved = env_names.to_h { |name| [name, ENV.fetch(name, nil)] }
      env_names.each { |name| ENV.delete(name) }
      example.run
    ensure
      saved&.each do |name, value|
        value.nil? ? ENV.delete(name) : (ENV[name] = value)
      end
    end

    it 'contains exactly one block per provisioning provider' do
      actual = load_provider_config.keys

      expect(actual).to match_array(registry.provisioning_providers),
        "shipped email_providers blocks #{actual.inspect} drifted from " \
        "ProviderRegistry.provisioning_providers #{registry.provisioning_providers.inspect}."
    end

    it 'accounts for every provider config key and uses registry DNS defaults' do
      provider_config = load_provider_config

      registry.provisioning_providers.each do |name|
        descriptor    = registry.descriptor!(name)
        expected_keys = (descriptor.dns_defaults.keys + descriptor.config_env_sources.keys)
          .map(&:to_s)
          .uniq
        actual         = provider_config.fetch(name)
        expected_defaults = descriptor.dns_defaults.transform_keys(&:to_s)

        expect(actual.keys).to match_array(expected_keys),
          "shipped email_providers.#{name} keys #{actual.keys.inspect} drifted from " \
          "ProviderRegistry #{expected_keys.inspect}."
        expect(actual.slice(*expected_defaults.keys)).to eq(expected_defaults),
          "shipped email_providers.#{name} defaults drifted from ProviderRegistry " \
          "#{expected_defaults.inspect}."
      end
    end

    it 'wires every declared ENV source to its provider config key' do
      registry.provisioning_providers.each do |name|
        registry.descriptor!(name).config_env_sources.each do |key, env_names|
          env_names.each do |env_name|
            marker = "parity-#{name}-#{key}-#{env_name.downcase}"
            begin
              ENV[env_name] = marker
              actual        = load_provider_config.fetch(name).fetch(key.to_s)
              expect(actual).to eq(marker),
                "#{env_name} did not populate email_providers.#{name}.#{key}."
            ensure
              ENV.delete(env_name)
            end
          end
        end
      end
    end

    it 'uses the declared ENV source order as fallback precedence' do
      registry.provisioning_providers.each do |name|
        registry.descriptor!(name).config_env_sources.each do |key, env_names|
          next unless env_names.length > 1

          env_names.each_index do |start_index|
            active_sources = env_names.drop(start_index)
            markers        = active_sources.each_with_index.to_h do |env_name, index|
              [env_name, "parity-source-#{start_index}-#{index}"]
            end
            begin
              markers.each { |env_name, marker| ENV[env_name] = marker }
              actual = load_provider_config.fetch(name).fetch(key.to_s)
              expect(actual).to eq(markers.fetch(active_sources.first)),
                "email_providers.#{name}.#{key} did not honor declared ENV precedence " \
                "from #{active_sources.inspect}."
            ensure
              active_sources.each { |env_name| ENV.delete(env_name) }
            end
          end
        end
      end
    end
  end
end

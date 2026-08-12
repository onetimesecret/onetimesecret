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
# Extraction is designed to fail LOUDLY: if a regex no longer matches (file
# moved or reshaped), the spec fails telling the maintainer to update this
# parity spec — it never silently passes on extraction failure.

require 'spec_helper'
require 'onetime/mail/provider_registry'

RSpec.describe 'Frontend mail provider parity' do # rubocop:disable RSpec/DescribeClass
  let(:project_root) { File.expand_path('../../../..', __dir__) }

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

  let(:provisioning_plus_inherit) do
    Onetime::Mail::ProviderRegistry.provisioning_providers + %w[inherit]
  end

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

      expect(provider_keys).to match_array(Onetime::Mail::ProviderRegistry.feedback_providers),
        "colonelEmailProviderStatusDetailsSchema provider blocks #{provider_keys.inspect} " \
        'drifted from ProviderRegistry.feedback_providers ' \
        "#{Onetime::Mail::ProviderRegistry.feedback_providers.inspect} — a new feedback " \
        "provider needs a status block in #{relative} (and vice versa)."
    end
  end
end

# apps/web/billing/spec/operations/catalog/docs_generator_spec.rb
# frozen_string_literal: true

# Pure, boot-free spec for the billing docs generator.
#
# DocsGenerator is a YAML → markdown transform with no Onetime / Redis / auth
# dependency, so this spec requires ONLY the module — not spec_helper — to keep
# it runnable with just Ruby + stdlib (the whole point of the decoupling).
require_relative '../../../operations/catalog/docs_generator'

RSpec.describe Billing::Operations::Catalog::DocsGenerator do
  subject(:generator) { described_class }

  let(:catalog) do
    {
      'schema_version' => '2.0',
      'currency' => 'cad',
      'entitlements' => {
        'custom_domains' => { 'category' => 'feature', 'description' => 'Use custom domains' },
      },
      'plans' => {
        'free_v1' => {
          'name' => 'Free',
          'tier' => 'free',
          'tenancy' => 'shared',
          'region' => 'global',
          'display_order' => 1,
          'show_on_plans_page' => true,
          'legacy' => false,
          'limits' => { 'secret_lifetime' => 604_800, 'teams' => 0 },
          'prices' => [],
        },
        'pro_v1' => {
          'name' => 'Pro',
          'tier' => 'pro',
          'tenancy' => 'shared',
          'region' => 'global',
          'display_order' => 2,
          'show_on_plans_page' => true,
          'legacy' => false,
          'entitlements' => ['custom_domains'],
          'prices' => [{ 'interval' => 'month', 'amount' => 900, 'currency' => 'cad' }],
        },
      },
      'stripe_metadata_schema' => {
        'required' => [{ 'tier' => 'Plan tier' }],
        'optional' => [{ 'legacy' => 'Grandfathered flag' }],
      },
    }
  end

  describe '.generate' do
    subject(:markdown) { generator.generate(catalog) }

    it 'returns a markdown string' do
      expect(markdown).to be_a(String)
    end

    it 'renders the reference header with the schema version' do
      expect(markdown).to include('# Plan Catalog Reference')
      expect(markdown).to include('**Schema Version:** 2.0')
    end

    it 'renders the entitlement definitions section' do
      expect(markdown).to include('## Entitlement Definitions')
      expect(markdown).to include('- **`custom_domains`**: Use custom domains')
    end

    it 'renders the plans overview table' do
      expect(markdown).to include('## Plans Overview')
      expect(markdown).to include('| Plan ID | Name |')
    end

    it 'renders free plans as free and paid plans with pricing' do
      expect(markdown).to include('**Pricing:** Free')
      expect(markdown).to include('- Monthly: $9.0 CAD')
    end

    it 'renders the stripe metadata and validation sections' do
      expect(markdown).to include('## Stripe Product Configuration')
      expect(markdown).to include('### Required Metadata Fields')
      expect(markdown).to include('## Validation and Sync')
    end
  end

  describe '.format_limit_value' do
    it 'renders the unlimited sentinel' do
      expect(generator.format_limit_value(-1)).to eq('∞ (unlimited)')
    end

    it 'renders TBD for nil' do
      expect(generator.format_limit_value(nil)).to eq('TBD')
    end

    it 'stringifies plain values' do
      expect(generator.format_limit_value(604_800)).to eq('604800')
    end
  end

  describe '.limit_notes' do
    it 'formats secret_lifetime as days' do
      expect(generator.limit_notes('secret_lifetime', 604_800)).to eq('7 days')
    end

    it 'flags zero teams as no team access' do
      expect(generator.limit_notes('teams', 0)).to eq('No team access')
    end

    it 'returns an empty note for unknown resources' do
      expect(generator.limit_notes('unknown', 5)).to eq('')
    end
  end

  describe '.load_catalog' do
    it 'returns an empty hash for a nil or missing path' do
      expect(generator.load_catalog(nil)).to eq({})
      expect(generator.load_catalog('/no/such/billing.yaml')).to eq({})
    end
  end

  describe '.entitlements_from' do
    it 'extracts entitlements, defaulting to an empty hash' do
      expect(generator.entitlements_from(catalog)).to have_key('custom_domains')
      expect(generator.entitlements_from({})).to eq({})
    end
  end
end

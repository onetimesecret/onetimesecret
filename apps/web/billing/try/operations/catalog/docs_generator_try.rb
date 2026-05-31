# apps/web/billing/try/operations/catalog/docs_generator_try.rb
#
# frozen_string_literal: true

# Tryouts for the boot-free billing docs generator.
#
# Run with: bundle exec try apps/web/billing/try/operations/catalog/docs_generator_try.rb
#
# Unlike most tryouts, this deliberately requires ONLY the generator module
# (no `require 'onetime'`) to prove it stays boot-free: pure stdlib, no Redis,
# no auth.yaml, no full boot.

require_relative '../../../operations/catalog/docs_generator'

@gen = Billing::Operations::Catalog::DocsGenerator

@catalog = {
  'schema_version' => '2.0',
  'currency' => 'cad',
  'entitlements' => {
    'custom_domains' => { 'category' => 'feature', 'description' => 'Use custom domains' },
  },
  'plans' => {
    'free_v1' => {
      'name' => 'Free', 'tier' => 'free', 'tenancy' => 'shared', 'region' => 'global',
      'limits' => { 'secret_lifetime' => 604_800, 'teams' => 0 }, 'prices' => []
    },
    'pro_v1' => {
      'name' => 'Pro', 'tier' => 'pro', 'tenancy' => 'shared', 'region' => 'global',
      'entitlements' => ['custom_domains'],
      'prices' => [{ 'interval' => 'month', 'amount' => 900, 'currency' => 'cad' }]
    },
  },
  'stripe_metadata_schema' => { 'required' => [{ 'tier' => 'Plan tier' }] },
}

## DocsGenerator.generate returns a markdown String
@gen.generate(@catalog).is_a?(String)
#=> true

## DocsGenerator.generate renders the reference header
@gen.generate(@catalog).include?('# Plan Catalog Reference')
#=> true

## DocsGenerator.generate renders free plans as free
@gen.generate(@catalog).include?('**Pricing:** Free')
#=> true

## DocsGenerator.generate renders paid plan pricing
@gen.generate(@catalog).include?('- Monthly: $9.0 CAD')
#=> true

## DocsGenerator.format_limit_value renders the unlimited sentinel
@gen.format_limit_value(-1)
#=> '∞ (unlimited)'

## DocsGenerator.format_limit_value renders TBD for nil
@gen.format_limit_value(nil)
#=> 'TBD'

## DocsGenerator.limit_notes formats secret_lifetime as days
@gen.limit_notes('secret_lifetime', 604_800)
#=> '7 days'

## DocsGenerator.load_catalog returns {} for a missing path
@gen.load_catalog('/no/such/billing.yaml')
#=> {}

## DocsGenerator.entitlements_from extracts the entitlements hash
@gen.entitlements_from(@catalog).key?('custom_domains')
#=> true

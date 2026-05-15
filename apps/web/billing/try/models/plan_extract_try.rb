# apps/web/billing/try/models/plan_extract_try.rb
#
# frozen_string_literal: true

require_relative '../../../../../try/support/test_helpers'

# Tests for catalog metadata validation and extraction.
#
# Covers Phase 1 of the entitlement-resolution consolidation (#3120):
# - plan_id is required on Stripe product metadata
# - extract_plan_data no longer falls back to `tier` when plan_id is absent
# - validate_product_metadata surfaces legacy field-name variants
#   (`planid`, `plan`) so they get migrated rather than silently mis-resolved.

require 'apps/web/billing/models/plan'

BillingTestHelpers.restore_billing!(enabled: true)

# Immutable mocks for Stripe shapes used by Plan class methods.
MockProductForExtract = Data.define(:id, :name, :metadata)
MockRecurring        = Data.define(:interval)
MockPriceForExtract  = Data.define(:id, :type, :currency, :unit_amount, :recurring, :active, :billing_scheme, :nickname)

def build_price(interval: 'month')
  MockPriceForExtract.new(
    id: 'price_test',
    type: 'recurring',
    currency: 'cad',
    unit_amount: 2900,
    recurring: MockRecurring.new(interval: interval),
    active: true,
    billing_scheme: 'per_unit',
    nickname: nil,
  )
end

## REQUIRED_PRODUCT_METADATA now includes plan_id
Billing::Plan::ClassMethods::REQUIRED_PRODUCT_METADATA.include?('plan_id')
#=> true

## validate_product_metadata reports plan_id as missing when absent
product = MockProductForExtract.new(
  id: 'prod_missing',
  name: 'Missing plan_id',
  metadata: { 'tier' => 'single_team', 'region' => 'global' },
)
Billing::Plan.validate_product_metadata(product)
#=> ["plan_id"]

## validate_product_metadata returns empty array when all required fields present
product = MockProductForExtract.new(
  id: 'prod_ok',
  name: 'Complete',
  metadata: { 'plan_id' => 'identity_plus_v1', 'tier' => 'single_team', 'region' => 'global' },
)
Billing::Plan.validate_product_metadata(product)
#=> []

## validate_product_metadata still reports plan_id as missing even when legacy `planid` is present
product = MockProductForExtract.new(
  id: 'prod_legacy',
  name: 'Legacy field name',
  metadata: { 'planid' => 'identity_plus_v1', 'tier' => 'single_team', 'region' => 'global' },
)
Billing::Plan.validate_product_metadata(product)
#=> ["plan_id"]

## extract_plan_data returns nil (not a tier-derived plan_id) when plan_id key is absent
product = MockProductForExtract.new(
  id: 'prod_missing',
  name: 'Missing plan_id',
  metadata: { 'tier' => 'single_team', 'region' => 'global' },
)
Billing::Plan.extract_plan_data(product, build_price)
#=> nil

## extract_plan_data raises ConfigError when plan_id key is present but blank
product = MockProductForExtract.new(
  id: 'prod_blank',
  name: 'Blank plan_id',
  metadata: { 'plan_id' => '   ', 'tier' => 'single_team', 'region' => 'global' },
)
begin
  Billing::Plan.extract_plan_data(product, build_price)
  :no_raise
rescue Onetime::ConfigError => ex
  ex.message.include?('missing plan_id metadata') ? :raised : :wrong_message
end
#=> :raised

## Teardown
BillingTestHelpers.cleanup_billing_state!
true
#=> true

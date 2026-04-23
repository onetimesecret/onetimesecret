# try/unit/models/custom_domain_homepage_config_try.rb
#
# frozen_string_literal: true

# Unit tests for CustomDomain::HomepageConfig model
#
# Covers:
#   - upsert creates a new record when none exists
#   - upsert returns a HomepageConfig object
#   - upsert updates an existing record (enabled state changes)
#   - upsert timestamp behaviour: created stable, updated changes on second call
#   - upsert raises Onetime::Problem when domain_id is empty or nil
#   - CustomDomain#allow_public_homepage? returns config.enabled? when record exists
#   - CustomDomain#allow_public_homepage? falls back to brand_settings when no record

require_relative '../../support/test_models'

OT.boot! :test

Familia.dbclient.flushdb
OT.info "Cleaned Redis for HomepageConfig test run"

@ts      = Familia.now.to_i
@entropy = SecureRandom.hex(4)
@owner   = Onetime::Customer.create!(email: "hp_cfg_owner_#{@ts}_#{@entropy}@test.com")
@org     = Onetime::Organization.create!("HpCfg Test Org #{@ts}", @owner, "hp_cfg_#{@ts}@test.com")
@domain  = Onetime::CustomDomain.create!("hp-cfg-#{@ts}.example.com", @org.objid)

# --- upsert: new record ---

## upsert returns a HomepageConfig instance when no record exists
@cfg = Onetime::CustomDomain::HomepageConfig.upsert(domain_id: @domain.identifier, enabled: false)
@cfg.class
#=> Onetime::CustomDomain::HomepageConfig

## upsert persists the record (exists_for_domain? is true after upsert)
Onetime::CustomDomain::HomepageConfig.exists_for_domain?(@domain.identifier)
#=> true

## upsert stores the correct domain_id
@cfg.domain_id
#=> @domain.identifier

## upsert stores enabled as string 'false'
@cfg.enabled
#=> 'false'

## upsert sets a positive created timestamp on first call
@cfg.created.to_i > 0
#=> true

## upsert sets a positive updated timestamp on first call
@cfg.updated.to_i > 0
#=> true

# --- upsert: update existing record ---
# Capture created_at inside a setup testcase so the instance variable is
# visible to subsequent testcases (orphaned code between ## blocks is not executed).

## Setup: capture created_at and advance time before second upsert
@created_at = @cfg.created.to_i
sleep 1
@created_at > 0
#=> true

## upsert with enabled: true updates existing record
@cfg2 = Onetime::CustomDomain::HomepageConfig.upsert(domain_id: @domain.identifier, enabled: true)
@cfg2.enabled
#=> 'true'

## upsert returns HomepageConfig on update
@cfg2.class
#=> Onetime::CustomDomain::HomepageConfig

## upsert does not change created timestamp on second call
@cfg2.created.to_i == @created_at
#=> true

## upsert changes updated timestamp on second call
@cfg2.updated.to_i > @created_at
#=> true

## updated record persists (reload from Redis reflects enabled: true)
@reloaded = Onetime::CustomDomain::HomepageConfig.find_by_domain_id(@domain.identifier)
@reloaded.enabled?
#=> true

## created timestamp is preserved after reload
@reloaded.created.to_i == @created_at
#=> true

# --- upsert: domain_id guard ---

## upsert raises Problem when domain_id is empty string
begin
  Onetime::CustomDomain::HomepageConfig.upsert(domain_id: '', enabled: true)
  'unexpected_success'
rescue Onetime::Problem => e
  e.message
end
#=> 'domain_id is required'

## upsert raises Problem when domain_id is nil
begin
  Onetime::CustomDomain::HomepageConfig.upsert(domain_id: nil, enabled: true)
  'unexpected_success'
rescue Onetime::Problem => e
  e.message
end
#=> 'domain_id is required'

# --- allow_public_homepage? with HomepageConfig record present ---

## allow_public_homepage? returns true when HomepageConfig.enabled? is true
@domain.allow_public_homepage?
#=> true

## allow_public_homepage? returns false after disabling via upsert
Onetime::CustomDomain::HomepageConfig.upsert(domain_id: @domain.identifier, enabled: false)
@domain.allow_public_homepage?
#=> false

## allow_public_homepage? returns true after re-enabling via upsert
Onetime::CustomDomain::HomepageConfig.upsert(domain_id: @domain.identifier, enabled: true)
@domain.allow_public_homepage?
#=> true

# --- allow_public_homepage? fallback to brand_settings when no HomepageConfig ---

## Setup: create a domain with no HomepageConfig record
@domain_no_cfg = Onetime::CustomDomain.create!("hp-cfg-nocfg-#{@ts}.example.com", @org.objid)
Onetime::CustomDomain::HomepageConfig.exists_for_domain?(@domain_no_cfg.identifier)
#=> false

## allow_public_homepage? returns false (brand_settings default) when no HomepageConfig exists
@domain_no_cfg.allow_public_homepage?
#=> false

# --- find_or_create_for_domain: atomic create-if-missing ---

## Setup: a fresh domain with no HomepageConfig
@focd_domain = Onetime::CustomDomain.create!("hp-cfg-focd-#{@ts}.example.com", @org.objid)
Onetime::CustomDomain::HomepageConfig.exists_for_domain?(@focd_domain.identifier)
#=> false

## find_or_create_for_domain on missing record returns :created
@focd_config, @focd_outcome = Onetime::CustomDomain::HomepageConfig.find_or_create_for_domain(
  domain_id: @focd_domain.identifier, enabled: true,
)
@focd_outcome
#=> :created

## Created record has the requested enabled value
@focd_config.enabled?
#=> true

## Created record persists (exists_for_domain? is true)
Onetime::CustomDomain::HomepageConfig.exists_for_domain?(@focd_domain.identifier)
#=> true

## find_or_create_for_domain on existing record returns :existed
@focd_config2, @focd_outcome2 = Onetime::CustomDomain::HomepageConfig.find_or_create_for_domain(
  domain_id: @focd_domain.identifier, enabled: false,
)
@focd_outcome2
#=> :existed

## Existing record's enabled value is preserved (proposed false did NOT overwrite the true)
@focd_config2.enabled?
#=> true

## Returned existing record has same domain_id
@focd_config2.domain_id == @focd_domain.identifier
#=> true

## Reload confirms the stored value was not overwritten by the second call
Onetime::CustomDomain::HomepageConfig.find_by_domain_id(@focd_domain.identifier).enabled?
#=> true

## find_or_create_for_domain raises Problem when domain_id is empty string
begin
  Onetime::CustomDomain::HomepageConfig.find_or_create_for_domain(domain_id: '', enabled: true)
  'unexpected_success'
rescue Onetime::Problem => e
  e.message
end
#=> 'domain_id is required'

## find_or_create_for_domain raises Problem when domain_id is nil
begin
  Onetime::CustomDomain::HomepageConfig.find_or_create_for_domain(domain_id: nil, enabled: true)
  'unexpected_success'
rescue Onetime::Problem => e
  e.message
end
#=> 'domain_id is required'

# Teardown
Familia.dbclient.flushdb

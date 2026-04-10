# try/unit/models/custom_domain_api_config_try.rb
#
# frozen_string_literal: true

# Unit tests for CustomDomain::ApiConfig model
#
# Covers:
#   - upsert creates a new record when none exists
#   - upsert returns an ApiConfig object
#   - upsert updates an existing record (enabled state changes)
#   - upsert timestamp behaviour: created stable, updated changes on second call
#   - upsert raises Onetime::Problem when domain_id is empty or nil
#   - CustomDomain#allow_public_api? returns config.enabled? when record exists
#   - CustomDomain#allow_public_api? falls back to brand_settings when no record

require_relative '../../support/test_models'

OT.boot! :test

Familia.dbclient.flushdb
OT.info "Cleaned Redis for ApiConfig test run"

@ts      = Familia.now.to_i
@entropy = SecureRandom.hex(4)
@owner   = Onetime::Customer.create!(email: "api_cfg_owner_#{@ts}_#{@entropy}@test.com")
@org     = Onetime::Organization.create!("ApiCfg Test Org #{@ts}", @owner, "api_cfg_#{@ts}@test.com")
@domain  = Onetime::CustomDomain.create!("api-cfg-#{@ts}.example.com", @org.objid)

# --- upsert: new record ---

## upsert returns an ApiConfig instance when no record exists
@cfg = Onetime::CustomDomain::ApiConfig.upsert(domain_id: @domain.identifier, enabled: false)
@cfg.class
#=> Onetime::CustomDomain::ApiConfig

## upsert persists the record (exists_for_domain? is true after upsert)
Onetime::CustomDomain::ApiConfig.exists_for_domain?(@domain.identifier)
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
@cfg2 = Onetime::CustomDomain::ApiConfig.upsert(domain_id: @domain.identifier, enabled: true)
@cfg2.enabled
#=> 'true'

## upsert returns ApiConfig on update
@cfg2.class
#=> Onetime::CustomDomain::ApiConfig

## upsert does not change created timestamp on second call
@cfg2.created.to_i == @created_at
#=> true

## upsert changes updated timestamp on second call
@cfg2.updated.to_i > @created_at
#=> true

## updated record persists (reload from Redis reflects enabled: true)
@reloaded = Onetime::CustomDomain::ApiConfig.find_by_domain_id(@domain.identifier)
@reloaded.enabled?
#=> true

## created timestamp is preserved after reload
@reloaded.created.to_i == @created_at
#=> true

# --- upsert: domain_id guard ---

## upsert raises Problem when domain_id is empty string
begin
  Onetime::CustomDomain::ApiConfig.upsert(domain_id: '', enabled: true)
  'unexpected_success'
rescue Onetime::Problem => e
  e.message
end
#=> 'domain_id is required'

## upsert raises Problem when domain_id is nil
begin
  Onetime::CustomDomain::ApiConfig.upsert(domain_id: nil, enabled: true)
  'unexpected_success'
rescue Onetime::Problem => e
  e.message
end
#=> 'domain_id is required'

# --- allow_public_api? with ApiConfig record present ---

## allow_public_api? returns true when ApiConfig.enabled? is true
@domain.allow_public_api?
#=> true

## allow_public_api? returns false after disabling via upsert
Onetime::CustomDomain::ApiConfig.upsert(domain_id: @domain.identifier, enabled: false)
@domain.allow_public_api?
#=> false

## allow_public_api? returns true after re-enabling via upsert
Onetime::CustomDomain::ApiConfig.upsert(domain_id: @domain.identifier, enabled: true)
@domain.allow_public_api?
#=> true

# --- allow_public_api? fallback to brand_settings when no ApiConfig ---

## Setup: create a domain with no ApiConfig record
@domain_no_cfg = Onetime::CustomDomain.create!("api-cfg-nocfg-#{@ts}.example.com", @org.objid)
Onetime::CustomDomain::ApiConfig.exists_for_domain?(@domain_no_cfg.identifier)
#=> false

## allow_public_api? returns false (brand_settings default) when no ApiConfig exists
@domain_no_cfg.allow_public_api?
#=> false

# Teardown
Familia.dbclient.flushdb

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
#   - CustomDomain.create! bootstraps a default-disabled HomepageConfig record
#   - CustomDomain#allow_public_homepage? returns config.enabled? when record exists
#   - CustomDomain#allow_public_homepage? fails closed (returns false) when record is missing

require_relative '../../support/test_models'

OT.boot! :test

Familia.dbclient.flushdb
OT.info "Cleaned Redis for HomepageConfig test run"

@ts      = Familia.now.to_i
@entropy = SecureRandom.hex(4)
@owner   = Onetime::Customer.create!(email: "hp_cfg_owner_#{@ts}_#{@entropy}@test.com")
@org     = Onetime::Organization.create!("HpCfg Test Org #{@ts}", @owner, "hp_cfg_#{@ts}@test.com")
@domain  = Onetime::CustomDomain.create!("hp-cfg-#{@ts}.example.com", @org.objid)

# --- bootstrap: CustomDomain.create! auto-creates a default-disabled HomepageConfig ---

## CustomDomain.create! bootstraps a HomepageConfig record for the new domain
Onetime::CustomDomain::HomepageConfig.exists_for_domain?(@domain.identifier)
#=> true

## Bootstrapped record defaults to disabled
Onetime::CustomDomain::HomepageConfig.find_by_domain_id(@domain.identifier).enabled?
#=> false

# Drop the bootstrap record so the remaining upsert tests start from a clean state.
Onetime::CustomDomain::HomepageConfig.delete_for_domain!(@domain.identifier)

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

# --- allow_public_homepage? fails closed when no HomepageConfig exists ---
# Post-#3026, BrandSettings no longer carries allow_public_homepage and
# CustomDomain.create! bootstraps a record, so a missing record at read
# time indicates data corruption (manual delete, partial restore).
# Read-path policy is fail-closed: return false (the safe default for a
# public-homepage toggle) and log via OT.le so ops can detect drift,
# rather than raising and 5xx-ing the user request — see the comment
# block above the predicate in lib/onetime/models/custom_domain.rb.

## Setup: create a domain, then delete its bootstrap record to simulate the
## corrupted-state case
@domain_no_cfg = Onetime::CustomDomain.create!("hp-cfg-nocfg-#{@ts}.example.com", @org.objid)
Onetime::CustomDomain::HomepageConfig.delete_for_domain!(@domain_no_cfg.identifier)
Onetime::CustomDomain::HomepageConfig.exists_for_domain?(@domain_no_cfg.identifier)
#=> false

## allow_public_homepage? returns false (safe default) when no HomepageConfig exists
@domain_no_cfg.allow_public_homepage?
#=> false

# --- find_or_create_for_domain: atomic create-if-missing ---

## Setup: a fresh domain with the auto-bootstrap record removed
@focd_domain = Onetime::CustomDomain.create!("hp-cfg-focd-#{@ts}.example.com", @org.objid)
Onetime::CustomDomain::HomepageConfig.delete_for_domain!(@focd_domain.identifier)
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

# -------------------------------------------------------------------
# signup_enabled / signin_enabled field coverage
# -------------------------------------------------------------------

# --- upsert: new record defaults ---

## Setup: fresh domain for signup/signin default tests
@su_domain = Onetime::CustomDomain.create!("hp-cfg-su-#{@ts}-#{@entropy}.example.com", @org.objid)
Onetime::CustomDomain::HomepageConfig.delete_for_domain!(@su_domain.identifier)
Onetime::CustomDomain::HomepageConfig.exists_for_domain?(@su_domain.identifier)
#=> false

## upsert without signup_enabled/signin_enabled defaults signup_enabled? to false (conservative)
@su_cfg = Onetime::CustomDomain::HomepageConfig.upsert(domain_id: @su_domain.identifier, enabled: false)
@su_cfg.signup_enabled?
#=> false

## upsert without signup_enabled/signin_enabled defaults signin_enabled? to false (conservative)
@su_cfg.signin_enabled?
#=> false

# --- upsert: explicit false persists ---

## upsert with explicit signup_enabled: false stores false; signup_enabled? returns false
@su_cfg2 = Onetime::CustomDomain::HomepageConfig.upsert(
  domain_id: @su_domain.identifier, enabled: false, signup_enabled: false
)
@su_cfg2.signup_enabled?
#=> false

## reload from Redis confirms signup_enabled: false was persisted
Onetime::CustomDomain::HomepageConfig.find_by_domain_id(@su_domain.identifier).signup_enabled?
#=> false

## upsert with explicit signin_enabled: false stores false; signin_enabled? returns false
@su_cfg3 = Onetime::CustomDomain::HomepageConfig.upsert(
  domain_id: @su_domain.identifier, enabled: false, signin_enabled: false
)
@su_cfg3.signin_enabled?
#=> false

## reload from Redis confirms signin_enabled: false was persisted
Onetime::CustomDomain::HomepageConfig.find_by_domain_id(@su_domain.identifier).signin_enabled?
#=> false

# --- upsert: no-clobber when kwargs omitted ---
# At this point @su_domain has signup_enabled=false, signin_enabled=false.
# Calling upsert with only `enabled:` must NOT reset them to true.

## upsert without signup_enabled/signin_enabled kwargs does not clobber stored false values
Onetime::CustomDomain::HomepageConfig.upsert(domain_id: @su_domain.identifier, enabled: true)
@noclobber = Onetime::CustomDomain::HomepageConfig.find_by_domain_id(@su_domain.identifier)
@noclobber.signup_enabled?
#=> false

## signin_enabled also preserved after clobber-risk upsert
@noclobber.signin_enabled?
#=> false

# --- predicate: nil field treated as disabled (conservative default) ---
# Familia's instantiate_from_hash uses allocate (no initialize), so init() is
# NOT called on load. A record saved without signup_enabled/signin_enabled will
# have those fields as nil when read back from Redis. Only an explicit boolean
# true shows the link, so a nil field reads as disabled.
# We simulate this by directly constructing an in-memory instance with nil fields.

## signup_enabled? returns false when field is nil (legacy record, no field in Redis)
@legacy = Onetime::CustomDomain::HomepageConfig.new(domain_id: @su_domain.identifier)
@legacy.signup_enabled = nil
@legacy.signup_enabled?
#=> false

## signin_enabled? returns false when field is nil (legacy record)
@legacy.signin_enabled = nil
@legacy.signin_enabled?
#=> false

# --- CustomDomain.create! bootstrap defaults signup/signin links off ---

## Setup: fresh domain, bootstrap record created by create!
@boot_domain = Onetime::CustomDomain.create!("hp-cfg-boot-#{@ts}-#{@entropy}.example.com", @org.objid)
@boot_cfg = Onetime::CustomDomain::HomepageConfig.find_by_domain_id(@boot_domain.identifier)
@boot_cfg.nil?
#=> false

## Bootstrapped record has signup_enabled? false (links hidden until opt-in)
@boot_cfg.signup_enabled?
#=> false

## Bootstrapped record has signin_enabled? false (links hidden until opt-in)
@boot_cfg.signin_enabled?
#=> false

# --- find_or_create_for_domain: persists new fields; preserves existing ---

## Setup: fresh domain, delete auto-bootstrap
@focd2_domain = Onetime::CustomDomain.create!("hp-cfg-focd2-#{@ts}-#{@entropy}.example.com", @org.objid)
Onetime::CustomDomain::HomepageConfig.delete_for_domain!(@focd2_domain.identifier)
Onetime::CustomDomain::HomepageConfig.exists_for_domain?(@focd2_domain.identifier)
#=> false

## find_or_create_for_domain with signup_enabled: false persists the value
@focd2_cfg, _ = Onetime::CustomDomain::HomepageConfig.find_or_create_for_domain(
  domain_id: @focd2_domain.identifier, enabled: true, signup_enabled: false, signin_enabled: false
)
@focd2_cfg.signup_enabled?
#=> false

## find_or_create_for_domain with signin_enabled: false persists the value
@focd2_cfg.signin_enabled?
#=> false

## find_or_create_for_domain on existing record does not overwrite stored signup_enabled
@focd2_cfg2, @focd2_outcome2 = Onetime::CustomDomain::HomepageConfig.find_or_create_for_domain(
  domain_id: @focd2_domain.identifier, enabled: true, signup_enabled: true, signin_enabled: true
)
@focd2_outcome2
#=> :existed

## Stored signup_enabled: false is preserved (proposed true did NOT overwrite it)
@focd2_cfg2.signup_enabled?
#=> false

## Stored signin_enabled: false is preserved
@focd2_cfg2.signin_enabled?
#=> false

# -------------------------------------------------------------------
# disabled_homepage_variant field coverage
# -------------------------------------------------------------------

## coerce_disabled_homepage_variant accepts a recognised variant
Onetime::CustomDomain::HomepageConfig.coerce_disabled_homepage_variant('minimal')
#=> 'minimal'

## coerce_disabled_homepage_variant trims surrounding whitespace
Onetime::CustomDomain::HomepageConfig.coerce_disabled_homepage_variant('  v1  ')
#=> 'v1'

## coerce_disabled_homepage_variant returns nil for an unknown value
Onetime::CustomDomain::HomepageConfig.coerce_disabled_homepage_variant('bogus')
#=> nil

## coerce_disabled_homepage_variant returns nil for blank input
Onetime::CustomDomain::HomepageConfig.coerce_disabled_homepage_variant('')
#=> nil

## Setup: fresh domain for variant tests
@var_domain = Onetime::CustomDomain.create!("hp-cfg-var-#{@ts}-#{@entropy}.example.com", @org.objid)
Onetime::CustomDomain::HomepageConfig.delete_for_domain!(@var_domain.identifier)
Onetime::CustomDomain::HomepageConfig.exists_for_domain?(@var_domain.identifier)
#=> false

## upsert without a variant leaves disabled_homepage_variant_value nil (use default)
@var_cfg = Onetime::CustomDomain::HomepageConfig.upsert(domain_id: @var_domain.identifier, enabled: true)
@var_cfg.disabled_homepage_variant_value
#=> nil

## upsert with a recognised variant stores it
@var_cfg = Onetime::CustomDomain::HomepageConfig.upsert(domain_id: @var_domain.identifier, enabled: true, disabled_homepage_variant: 'minimal')
@var_cfg.disabled_homepage_variant_value
#=> 'minimal'

## reload from Redis confirms the variant persisted
Onetime::CustomDomain::HomepageConfig.find_by_domain_id(@var_domain.identifier).disabled_homepage_variant_value
#=> 'minimal'

## upsert without the variant kwarg does not clobber the stored value
@var_cfg = Onetime::CustomDomain::HomepageConfig.upsert(domain_id: @var_domain.identifier, enabled: false)
@var_cfg.disabled_homepage_variant_value
#=> 'minimal'

## upsert with an unknown variant coerces to nil (clears the override)
@var_cfg = Onetime::CustomDomain::HomepageConfig.upsert(domain_id: @var_domain.identifier, enabled: true, disabled_homepage_variant: 'nope')
@var_cfg.disabled_homepage_variant_value
#=> nil

## upsert with explicit nil leaves a previously stored variant unchanged (merge semantics)
Onetime::CustomDomain::HomepageConfig.upsert(domain_id: @var_domain.identifier, enabled: true, disabled_homepage_variant: 'v1')
@var_cfg = Onetime::CustomDomain::HomepageConfig.upsert(domain_id: @var_domain.identifier, enabled: true, disabled_homepage_variant: nil)
@var_cfg.disabled_homepage_variant_value
#=> 'v1'

## upsert with an empty string clears a previously stored variant (reset to default)
@var_cfg = Onetime::CustomDomain::HomepageConfig.upsert(domain_id: @var_domain.identifier, enabled: true, disabled_homepage_variant: '')
@var_cfg.disabled_homepage_variant_value
#=> nil

## create! stores a coerced variant
@cr_domain = Onetime::CustomDomain.create!("hp-cfg-cr-#{@ts}-#{@entropy}.example.com", @org.objid)
Onetime::CustomDomain::HomepageConfig.delete_for_domain!(@cr_domain.identifier)
@cr_cfg = Onetime::CustomDomain::HomepageConfig.create!(domain_id: @cr_domain.identifier, enabled: true, disabled_homepage_variant: 'v1')
@cr_cfg.disabled_homepage_variant_value
#=> 'v1'

## validation_errors flags a stored value outside the recognised set
@bad_cfg = Onetime::CustomDomain::HomepageConfig.new(domain_id: 'x', disabled_homepage_variant: 'bogus')
@bad_cfg.validation_errors.any? { |e| e.include?('disabled_homepage_variant') }
#=> true

## validation_errors stays clean for a recognised variant
Onetime::CustomDomain::HomepageConfig.new(domain_id: 'x', disabled_homepage_variant: 'closed').validation_errors
#=> []

# Teardown
Familia.dbclient.flushdb

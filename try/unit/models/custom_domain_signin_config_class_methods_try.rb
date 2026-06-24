# try/unit/models/custom_domain_signin_config_class_methods_try.rb
#
# frozen_string_literal: true

# Tests for SigninConfig class methods and validation logic.
#
# Covers:
#   - validation_errors / valid? — domain_id required, restrict_to validation
#   - create! — raises on empty domain_id, raises on duplicate
#   - delete_for_domain! — true on delete, false when absent, false on empty
#   - find_by_domain_id — nil on empty, nil on missing, returns record
#   - exists_for_domain? — false on empty, false on missing, true when exists
#   - all / count — empty set, populated set
#   - sso_permitted_for? — master switch off + config present => true (defer)
#   - custom_domain / organization associations
#
# Run:
#   bundle exec try try/unit/models/custom_domain_signin_config_class_methods_try.rb --agent

require_relative '../../support/test_models'

OT.boot! :test

Familia.dbclient.flushdb
OT.info "Cleaned Redis for SigninConfig class methods test run"

@ts = Familia.now.to_i
@entropy = SecureRandom.hex(4)
@owner = Onetime::Customer.create!(email: "scm_owner_#{@ts}_#{@entropy}@test.com")
@org = Onetime::Organization.create!("SCM Test Org #{@ts}", @owner, "scm_#{@ts}@test.com")

# ============================================================
# validation_errors / valid?
# ============================================================

## validation_errors returns empty array for valid config
@valid = Onetime::CustomDomain::SigninConfig.new(domain_id: 'valid_domain_1')
@valid.validation_errors
#=> []

## valid? returns true for config with domain_id
@valid.valid?
#=> true

## validation_errors includes domain_id error when missing
@no_domain = Onetime::CustomDomain::SigninConfig.new
@no_domain.validation_errors.include?('domain_id is required')
#=> true

## valid? returns false when domain_id is missing
@no_domain.valid?
#=> false

## validation_errors includes domain_id error for empty string
@empty_domain = Onetime::CustomDomain::SigninConfig.new(domain_id: '')
@empty_domain.validation_errors.include?('domain_id is required')
#=> true

## validation_errors includes restrict_to error for invalid value
@bad_restrict = Onetime::CustomDomain::SigninConfig.new(domain_id: 'test_1')
@bad_restrict.restrict_to = 'invalid_method'
@bad_restrict.validation_errors.any? { |e| e.include?('restrict_to must be one of') }
#=> true

## valid? returns false for invalid restrict_to
@bad_restrict.valid?
#=> false

## validation_errors returns empty for valid restrict_to values
%w[password email_auth webauthn sso].each do |val|
  c = Onetime::CustomDomain::SigninConfig.new(domain_id: 'test_rt')
  c.restrict_to = val
  raise "Expected valid for #{val}" unless c.valid?
end
'all_valid'
#=> 'all_valid'

## validation_errors returns empty when restrict_to is nil
@nil_restrict = Onetime::CustomDomain::SigninConfig.new(domain_id: 'test_rt_nil')
@nil_restrict.restrict_to = nil
@nil_restrict.valid?
#=> true

# ============================================================
# create! error paths
# ============================================================

## create! raises Onetime::Problem on empty domain_id
begin
  Onetime::CustomDomain::SigninConfig.create!(domain_id: '')
  'unexpected_success'
rescue Onetime::Problem => ex
  ex.message
end
#=> 'domain_id is required'

## create! raises Onetime::Problem on nil domain_id
begin
  Onetime::CustomDomain::SigninConfig.create!(domain_id: nil)
  'unexpected_success'
rescue Onetime::Problem => ex
  ex.message
end
#=> 'domain_id is required'

## create! raises Onetime::Problem on duplicate domain_id
@domain_dup = Onetime::CustomDomain.create!("scm-dup-#{@ts}-#{SecureRandom.hex(2)}.example.com", @org.objid)
Onetime::CustomDomain::SigninConfig.create!(domain_id: @domain_dup.identifier)
begin
  Onetime::CustomDomain::SigninConfig.create!(domain_id: @domain_dup.identifier)
  'unexpected_success'
rescue Onetime::Problem => ex
  ex.message
end
#=> 'Signin config already exists for this domain'

# ============================================================
# delete_for_domain!
# ============================================================

## delete_for_domain! returns true when config exists
@domain_del = Onetime::CustomDomain.create!("scm-del-#{@ts}-#{SecureRandom.hex(2)}.example.com", @org.objid)
Onetime::CustomDomain::SigninConfig.create!(domain_id: @domain_del.identifier)
Onetime::CustomDomain::SigninConfig.delete_for_domain!(@domain_del.identifier)
#=> true

## delete_for_domain! returns false when config does not exist
Onetime::CustomDomain::SigninConfig.delete_for_domain!('nonexistent_domain_id_xyz')
#=> false

## delete_for_domain! returns false for empty string
Onetime::CustomDomain::SigninConfig.delete_for_domain!('')
#=> false

## delete_for_domain! returns false for nil
Onetime::CustomDomain::SigninConfig.delete_for_domain!(nil)
#=> false

## delete_for_domain! removes the record (find returns nil after)
@domain_del2 = Onetime::CustomDomain.create!("scm-del2-#{@ts}-#{SecureRandom.hex(2)}.example.com", @org.objid)
Onetime::CustomDomain::SigninConfig.create!(domain_id: @domain_del2.identifier)
Onetime::CustomDomain::SigninConfig.delete_for_domain!(@domain_del2.identifier)
Onetime::CustomDomain::SigninConfig.find_by_domain_id(@domain_del2.identifier)
#=> nil

# ============================================================
# find_by_domain_id
# ============================================================

## find_by_domain_id returns nil for empty string
Onetime::CustomDomain::SigninConfig.find_by_domain_id('')
#=> nil

## find_by_domain_id returns nil for nil
Onetime::CustomDomain::SigninConfig.find_by_domain_id(nil)
#=> nil

## find_by_domain_id returns nil for nonexistent id
Onetime::CustomDomain::SigninConfig.find_by_domain_id('nonexistent_abc123')
#=> nil

## find_by_domain_id returns the config when it exists
@domain_find = Onetime::CustomDomain.create!("scm-find-#{@ts}-#{SecureRandom.hex(2)}.example.com", @org.objid)
@config_find = Onetime::CustomDomain::SigninConfig.create!(domain_id: @domain_find.identifier, sso_enabled: true)
@found = Onetime::CustomDomain::SigninConfig.find_by_domain_id(@domain_find.identifier)
@found.sso_enabled?
#=> true

# ============================================================
# exists_for_domain?
# ============================================================

## exists_for_domain? returns false for empty string
Onetime::CustomDomain::SigninConfig.exists_for_domain?('')
#=> false

## exists_for_domain? returns false for nil
Onetime::CustomDomain::SigninConfig.exists_for_domain?(nil)
#=> false

## exists_for_domain? returns false for nonexistent id
Onetime::CustomDomain::SigninConfig.exists_for_domain?('nonexistent_xyz_456')
#=> false

## exists_for_domain? returns true when config exists
@domain_exists = Onetime::CustomDomain.create!("scm-exists-#{@ts}-#{SecureRandom.hex(2)}.example.com", @org.objid)
Onetime::CustomDomain::SigninConfig.create!(domain_id: @domain_exists.identifier)
Onetime::CustomDomain::SigninConfig.exists_for_domain?(@domain_exists.identifier)
#=> true

# ============================================================
# sso_permitted_for? — master switch off with config present
# ============================================================

## sso_permitted_for? returns true when config exists but master switch is off
@domain_sso_off = Onetime::CustomDomain.create!("scm-sso-off-#{@ts}-#{SecureRandom.hex(2)}.example.com", @org.objid)
Onetime::CustomDomain::SigninConfig.create!(
  domain_id: @domain_sso_off.identifier,
  enabled: false,
  sso_enabled: false,
)
Onetime::CustomDomain::SigninConfig.sso_permitted_for?(@domain_sso_off.identifier)
#=> true

## sso_permitted_for? returns true when no config exists
Onetime::CustomDomain::SigninConfig.sso_permitted_for?('no_config_domain_id')
#=> true

## sso_permitted_for? returns false when master on and sso_enabled false
@domain_sso_blocked = Onetime::CustomDomain.create!("scm-sso-blocked-#{@ts}-#{SecureRandom.hex(2)}.example.com", @org.objid)
Onetime::CustomDomain::SigninConfig.create!(
  domain_id: @domain_sso_blocked.identifier,
  enabled: true,
  sso_enabled: false,
)
Onetime::CustomDomain::SigninConfig.sso_permitted_for?(@domain_sso_blocked.identifier)
#=> false

## sso_permitted_for? returns true when master on and sso_enabled true
@domain_sso_on = Onetime::CustomDomain.create!("scm-sso-on-#{@ts}-#{SecureRandom.hex(2)}.example.com", @org.objid)
Onetime::CustomDomain::SigninConfig.create!(
  domain_id: @domain_sso_on.identifier,
  enabled: true,
  sso_enabled: true,
)
Onetime::CustomDomain::SigninConfig.sso_permitted_for?(@domain_sso_on.identifier)
#=> true

# ============================================================
# custom_domain / organization associations
# ============================================================

## custom_domain returns the associated CustomDomain
@domain_assoc = Onetime::CustomDomain.create!("scm-assoc-#{@ts}-#{SecureRandom.hex(2)}.example.com", @org.objid)
@config_assoc = Onetime::CustomDomain::SigninConfig.create!(domain_id: @domain_assoc.identifier)
@config_assoc.custom_domain.display_domain
#=> @domain_assoc.display_domain

## custom_domain returns nil for nonexistent domain_id
@orphan_config = Onetime::CustomDomain::SigninConfig.new(domain_id: 'orphan_domain_id_999')
@orphan_config.custom_domain
#=> nil

## organization returns the org via the custom domain
@config_assoc.organization.org_id
#=> @org.org_id

## organization returns nil when custom_domain is nil
@orphan_config.organization
#=> nil

# ============================================================
# RESTRICT_TO_VALUES constant
# ============================================================

## RESTRICT_TO_VALUES contains all expected auth methods
Onetime::CustomDomain::SigninConfig::RESTRICT_TO_VALUES.sort
#=> %w[email_auth password sso webauthn].sort

# ============================================================
# Timestamps
# ============================================================

## create! sets created timestamp
@domain_ts = Onetime::CustomDomain.create!("scm-ts-#{@ts}-#{SecureRandom.hex(2)}.example.com", @org.objid)
@config_ts = Onetime::CustomDomain::SigninConfig.create!(domain_id: @domain_ts.identifier)
@config_ts.created.to_i > 0
#=> true

## create! sets updated timestamp equal to created
@config_ts.updated.to_i == @config_ts.created.to_i
#=> true

## timestamps survive round-trip
@loaded_ts = Onetime::CustomDomain::SigninConfig.find_by_domain_id(@domain_ts.identifier)
@loaded_ts.created.to_i == @config_ts.created.to_i
#=> true

# --- Cleanup ---

Familia.dbclient.flushdb
OT.info "Cleaned Redis after SigninConfig class methods test run"

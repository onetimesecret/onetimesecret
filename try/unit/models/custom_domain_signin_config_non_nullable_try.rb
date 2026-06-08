# try/unit/models/custom_domain_signin_config_non_nullable_try.rb
#
# frozen_string_literal: true

# Tests for non-nullable boolean behavior of signin_enabled, email_auth_enabled,
# and sso_enabled.
#
# Covers:
#   - init defaults: all three fields default to false (not nil)
#   - Predicate methods: signin_enabled?, email_auth_enabled?, sso_enabled? return correct booleans
#   - Legacy nil coercion: predicates treat nil as false (conservative)
#   - create! defaults: omitted fields default to false
#   - create! with explicit true values
#   - restrict_to remains nullable (string, not boolean)
#   - Round-trip through save/load
#   - Serialization shape: predicates return boolean, not nil
#
# Run:
#   try try/unit/models/custom_domain_signin_config_non_nullable_try.rb --agent

require_relative '../../support/test_models'

OT.boot! :test

Familia.dbclient.flushdb
OT.info "Cleaned Redis for SigninConfig non-nullable boolean test run"

@ts = Familia.now.to_i
@entropy = SecureRandom.hex(4)
@owner = Onetime::Customer.create!(email: "si_owner_#{@ts}_#{@entropy}@test.com")
@org = Onetime::Organization.create!("SI Test Org #{@ts}", @owner, "si_#{@ts}@test.com")
@domain = Onetime::CustomDomain.create!("si-test-#{@ts}.example.com", @org.objid)

# --- init defaults ---

## New SigninConfig has signin_enabled == false (not nil)
@fresh = Onetime::CustomDomain::SigninConfig.new(domain_id: 'init_test_1')
@fresh.signin_enabled
#=> false

## New SigninConfig has email_auth_enabled == false (not nil)
@fresh2 = Onetime::CustomDomain::SigninConfig.new(domain_id: 'init_test_2')
@fresh2.email_auth_enabled
#=> false

## New SigninConfig has sso_enabled == false (not nil)
@fresh3 = Onetime::CustomDomain::SigninConfig.new(domain_id: 'init_test_3')
@fresh3.sso_enabled
#=> false

## signin_enabled is not nil after init
@fresh4 = Onetime::CustomDomain::SigninConfig.new(domain_id: 'init_test_4')
@fresh4.signin_enabled.nil?
#=> false

## email_auth_enabled is not nil after init
@fresh5 = Onetime::CustomDomain::SigninConfig.new(domain_id: 'init_test_5')
@fresh5.email_auth_enabled.nil?
#=> false

## sso_enabled is not nil after init
@fresh6 = Onetime::CustomDomain::SigninConfig.new(domain_id: 'init_test_6')
@fresh6.sso_enabled.nil?
#=> false

# --- Predicate methods ---

## signin_enabled? returns false when signin_enabled is false
@pred = Onetime::CustomDomain::SigninConfig.new(domain_id: 'pred_test_1')
@pred.signin_enabled = false
@pred.signin_enabled?
#=> false

## signin_enabled? returns true when signin_enabled is true
@pred.signin_enabled = true
@pred.signin_enabled?
#=> true

## email_auth_enabled? returns false when email_auth_enabled is false
@pred2 = Onetime::CustomDomain::SigninConfig.new(domain_id: 'pred_test_2')
@pred2.email_auth_enabled = false
@pred2.email_auth_enabled?
#=> false

## email_auth_enabled? returns true when email_auth_enabled is true
@pred2.email_auth_enabled = true
@pred2.email_auth_enabled?
#=> true

## sso_enabled? returns false when sso_enabled is false
@pred3 = Onetime::CustomDomain::SigninConfig.new(domain_id: 'pred_test_3')
@pred3.sso_enabled = false
@pred3.sso_enabled?
#=> false

## sso_enabled? returns true when sso_enabled is true
@pred3.sso_enabled = true
@pred3.sso_enabled?
#=> true

# --- Legacy nil coercion ---

## signin_enabled? returns false when field is forced to nil (legacy data)
@legacy = Onetime::CustomDomain::SigninConfig.new(domain_id: 'legacy_test_1')
@legacy.instance_variable_set(:@signin_enabled, nil)
@legacy.signin_enabled?
#=> false

## email_auth_enabled? returns false when field is forced to nil (legacy data)
@legacy2 = Onetime::CustomDomain::SigninConfig.new(domain_id: 'legacy_test_2')
@legacy2.instance_variable_set(:@email_auth_enabled, nil)
@legacy2.email_auth_enabled?
#=> false

## sso_enabled? returns false when field is forced to nil (legacy data)
@legacy3 = Onetime::CustomDomain::SigninConfig.new(domain_id: 'legacy_test_3')
@legacy3.instance_variable_set(:@sso_enabled, nil)
@legacy3.sso_enabled?
#=> false

## signin_enabled? returns false for string 'false' (not == true)
@legacy4 = Onetime::CustomDomain::SigninConfig.new(domain_id: 'legacy_test_4')
@legacy4.instance_variable_set(:@signin_enabled, 'false')
@legacy4.signin_enabled?
#=> false

## email_auth_enabled? returns false for string 'true' (not == true)
@legacy5 = Onetime::CustomDomain::SigninConfig.new(domain_id: 'legacy_test_5')
@legacy5.instance_variable_set(:@email_auth_enabled, 'true')
@legacy5.email_auth_enabled?
#=> false

## sso_enabled? returns false for string 'true' (not == true)
@legacy6 = Onetime::CustomDomain::SigninConfig.new(domain_id: 'legacy_test_6')
@legacy6.instance_variable_set(:@sso_enabled, 'true')
@legacy6.sso_enabled?
#=> false

# --- create! defaults ---

## create! without signin_enabled sets it to false
@ts_cd1 = Familia.now.to_i
@domain_cd1 = Onetime::CustomDomain.create!("si-cd1-#{@ts_cd1}-#{SecureRandom.hex(2)}.example.com", @org.objid)
@created_default = Onetime::CustomDomain::SigninConfig.create!(
  domain_id: @domain_cd1.identifier,
)
@created_default.signin_enabled
#=> false

## create! without email_auth_enabled sets it to false
@created_default.email_auth_enabled
#=> false

## create! without sso_enabled sets it to false
@created_default.sso_enabled
#=> false

## create! default signin_enabled? predicate returns false
@created_default.signin_enabled?
#=> false

## create! default email_auth_enabled? predicate returns false
@created_default.email_auth_enabled?
#=> false

## create! default sso_enabled? predicate returns false
@created_default.sso_enabled?
#=> false

# --- create! with explicit values ---

## create! with signin_enabled: true persists true
@ts_cd2 = Familia.now.to_i
@domain_cd2 = Onetime::CustomDomain.create!("si-cd2-#{@ts_cd2}-#{SecureRandom.hex(2)}.example.com", @org.objid)
@created_signin = Onetime::CustomDomain::SigninConfig.create!(
  domain_id: @domain_cd2.identifier,
  signin_enabled: true,
)
@created_signin.signin_enabled?
#=> true

## create! with email_auth_enabled: true persists true
@ts_cd3 = Familia.now.to_i
@domain_cd3 = Onetime::CustomDomain.create!("si-cd3-#{@ts_cd3}-#{SecureRandom.hex(2)}.example.com", @org.objid)
@created_email = Onetime::CustomDomain::SigninConfig.create!(
  domain_id: @domain_cd3.identifier,
  email_auth_enabled: true,
)
@created_email.email_auth_enabled?
#=> true

## create! with sso_enabled: true persists true
@ts_cd4 = Familia.now.to_i
@domain_cd4 = Onetime::CustomDomain.create!("si-cd4-#{@ts_cd4}-#{SecureRandom.hex(2)}.example.com", @org.objid)
@created_sso = Onetime::CustomDomain::SigninConfig.create!(
  domain_id: @domain_cd4.identifier,
  sso_enabled: true,
)
@created_sso.sso_enabled?
#=> true

## create! with signin_enabled: true still defaults others to false
@created_signin.email_auth_enabled?
#=> false

## create! with signin_enabled: true still defaults sso_enabled to false
@created_signin.sso_enabled?
#=> false

## create! with sso_enabled: true still defaults signin_enabled to false
@created_sso.signin_enabled?
#=> false

# --- restrict_to remains nullable ---

## restrict_to is nil by default after init
@rt_fresh = Onetime::CustomDomain::SigninConfig.new(domain_id: 'rt_test_1')
@rt_fresh.restrict_to
#=> nil

## restrict_to is nil by default after create!
@ts_rt1 = Familia.now.to_i
@domain_rt1 = Onetime::CustomDomain.create!("si-rt1-#{@ts_rt1}-#{SecureRandom.hex(2)}.example.com", @org.objid)
@created_rt = Onetime::CustomDomain::SigninConfig.create!(
  domain_id: @domain_rt1.identifier,
)
@created_rt.restrict_to
#=> nil

## restrict_to can be set to a valid value
@ts_rt2 = Familia.now.to_i
@domain_rt2 = Onetime::CustomDomain.create!("si-rt2-#{@ts_rt2}-#{SecureRandom.hex(2)}.example.com", @org.objid)
@created_rt2 = Onetime::CustomDomain::SigninConfig.create!(
  domain_id: @domain_rt2.identifier,
  restrict_to: 'sso',
)
@created_rt2.restrict_to
#=> 'sso'

# --- Round-trip through save/load ---

## Round-trip: set signin_enabled to true, save, reload, verify predicate
@ts_trip = Familia.now.to_i
@domain_trip = Onetime::CustomDomain.create!("si-trip-#{@ts_trip}-#{SecureRandom.hex(2)}.example.com", @org.objid)
@trip_config = Onetime::CustomDomain::SigninConfig.create!(
  domain_id: @domain_trip.identifier,
  signin_enabled: true,
)
@trip_loaded = Onetime::CustomDomain::SigninConfig.find_by_domain_id(@domain_trip.identifier)
@trip_loaded.signin_enabled?
#=> true

## Round-trip: set email_auth_enabled to true, save, reload, verify predicate
@ts_trip2 = Familia.now.to_i
@domain_trip2 = Onetime::CustomDomain.create!("si-trip2-#{@ts_trip2}-#{SecureRandom.hex(2)}.example.com", @org.objid)
@trip_config2 = Onetime::CustomDomain::SigninConfig.create!(
  domain_id: @domain_trip2.identifier,
  email_auth_enabled: true,
)
@trip_loaded2 = Onetime::CustomDomain::SigninConfig.find_by_domain_id(@domain_trip2.identifier)
@trip_loaded2.email_auth_enabled?
#=> true

## Round-trip: set sso_enabled to true, save, reload, verify predicate
@ts_trip3 = Familia.now.to_i
@domain_trip3 = Onetime::CustomDomain.create!("si-trip3-#{@ts_trip3}-#{SecureRandom.hex(2)}.example.com", @org.objid)
@trip_config3 = Onetime::CustomDomain::SigninConfig.create!(
  domain_id: @domain_trip3.identifier,
  sso_enabled: true,
)
@trip_loaded3 = Onetime::CustomDomain::SigninConfig.find_by_domain_id(@domain_trip3.identifier)
@trip_loaded3.sso_enabled?
#=> true

## Round-trip: false values survive save/load
@ts_trip4 = Familia.now.to_i
@domain_trip4 = Onetime::CustomDomain.create!("si-trip4-#{@ts_trip4}-#{SecureRandom.hex(2)}.example.com", @org.objid)
@trip_config4 = Onetime::CustomDomain::SigninConfig.create!(
  domain_id: @domain_trip4.identifier,
)
@trip_loaded4 = Onetime::CustomDomain::SigninConfig.find_by_domain_id(@domain_trip4.identifier)
@trip_loaded4.signin_enabled?
#=> false

## Round-trip: email_auth_enabled false survives save/load
@trip_loaded4.email_auth_enabled?
#=> false

## Round-trip: sso_enabled false survives save/load
@trip_loaded4.sso_enabled?
#=> false

# --- API serialization shape ---

## Serialized signin_enabled is boolean (not nil) via predicate
@serial = Onetime::CustomDomain::SigninConfig.create!(
  domain_id: Onetime::CustomDomain.create!("si-ser-#{Familia.now.to_i}-#{SecureRandom.hex(2)}.example.com", @org.objid).identifier,
)
@serial_result = {
  signin_enabled: @serial.signin_enabled?,
  email_auth_enabled: @serial.email_auth_enabled?,
  sso_enabled: @serial.sso_enabled?,
}
@serial_result[:signin_enabled].is_a?(FalseClass) || @serial_result[:signin_enabled].is_a?(TrueClass)
#=> true

## Serialized email_auth_enabled is boolean (not nil) via predicate
@serial_result[:email_auth_enabled].is_a?(FalseClass) || @serial_result[:email_auth_enabled].is_a?(TrueClass)
#=> true

## Serialized sso_enabled is boolean (not nil) via predicate
@serial_result[:sso_enabled].is_a?(FalseClass) || @serial_result[:sso_enabled].is_a?(TrueClass)
#=> true

## Serialized shape matches API contract when all false
@serial_result
#=> {signin_enabled: false, email_auth_enabled: false, sso_enabled: false}

## Serialized shape matches API contract when all true
@serial_true = Onetime::CustomDomain::SigninConfig.create!(
  domain_id: Onetime::CustomDomain.create!("si-ser2-#{Familia.now.to_i}-#{SecureRandom.hex(2)}.example.com", @org.objid).identifier,
  signin_enabled: true,
  email_auth_enabled: true,
  sso_enabled: true,
)
@serial_true_result = {
  signin_enabled: @serial_true.signin_enabled?,
  email_auth_enabled: @serial_true.email_auth_enabled?,
  sso_enabled: @serial_true.sso_enabled?,
}
@serial_true_result
#=> {signin_enabled: true, email_auth_enabled: true, sso_enabled: true}

# --- Cleanup ---

Familia.dbclient.flushdb
OT.info "Cleaned Redis after SigninConfig non-nullable boolean test run"

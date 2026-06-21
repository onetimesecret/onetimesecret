# try/unit/models/custom_domain_signup_config_non_nullable_try.rb
#
# frozen_string_literal: true

# Tests for non-nullable boolean behavior of signup_enabled and autoverify.
#
# Covers:
#   - init defaults: both fields default to false (not nil)
#   - Predicate methods: signup_enabled? and autoverify? return correct booleans
#   - Legacy nil coercion: predicates treat nil as false (conservative)
#   - create! defaults: omitted fields default to false
#   - create! with explicit true values
#   - Round-trip through save/load
#   - Serialization shape: predicates return boolean, not nil
#
# Run:
#   try try/unit/models/custom_domain_signup_config_non_nullable_try.rb --agent

require_relative '../../support/test_models'

OT.boot! :test

Familia.dbclient.flushdb
OT.info "Cleaned Redis for SignupConfig non-nullable boolean test run"

@ts = Familia.now.to_i
@entropy = SecureRandom.hex(4)
@owner = Onetime::Customer.create!(email: "nn_owner_#{@ts}_#{@entropy}@test.com")
@org = Onetime::Organization.create!("NN Test Org #{@ts}", @owner, "nn_#{@ts}@test.com")
@domain = Onetime::CustomDomain.create!("nn-test-#{@ts}.example.com", @org.objid)

# --- init defaults ---

## New SignupConfig has signup_enabled == false (not nil)
@fresh = Onetime::CustomDomain::SignupConfig.new(domain_id: 'init_test_1')
@fresh.signup_enabled
#=> false

## New SignupConfig has autoverify == false (not nil)
@fresh2 = Onetime::CustomDomain::SignupConfig.new(domain_id: 'init_test_2')
@fresh2.autoverify
#=> false

## signup_enabled is not nil after init
@fresh3 = Onetime::CustomDomain::SignupConfig.new(domain_id: 'init_test_3')
@fresh3.signup_enabled.nil?
#=> false

## autoverify is not nil after init
@fresh4 = Onetime::CustomDomain::SignupConfig.new(domain_id: 'init_test_4')
@fresh4.autoverify.nil?
#=> false

# --- Predicate methods ---

## signup_enabled? returns false when signup_enabled is false
@pred = Onetime::CustomDomain::SignupConfig.new(domain_id: 'pred_test_1')
@pred.signup_enabled = false
@pred.signup_enabled?
#=> false

## signup_enabled? returns true when signup_enabled is true
@pred.signup_enabled = true
@pred.signup_enabled?
#=> true

## autoverify? returns false when autoverify is false
@pred2 = Onetime::CustomDomain::SignupConfig.new(domain_id: 'pred_test_2')
@pred2.autoverify = false
@pred2.autoverify?
#=> false

## autoverify? returns true when autoverify is true
@pred2.autoverify = true
@pred2.autoverify?
#=> true

# --- Legacy nil coercion ---

## signup_enabled? returns false when field is forced to nil (legacy data)
@legacy = Onetime::CustomDomain::SignupConfig.new(domain_id: 'legacy_test_1')
@legacy.instance_variable_set(:@signup_enabled, nil)
@legacy.signup_enabled?
#=> false

## autoverify? returns false when field is forced to nil (legacy data)
@legacy2 = Onetime::CustomDomain::SignupConfig.new(domain_id: 'legacy_test_2')
@legacy2.instance_variable_set(:@autoverify, nil)
@legacy2.autoverify?
#=> false

## signup_enabled? returns false for string 'false' (not == true)
@legacy3 = Onetime::CustomDomain::SignupConfig.new(domain_id: 'legacy_test_3')
@legacy3.instance_variable_set(:@signup_enabled, 'false')
@legacy3.signup_enabled?
#=> false

## autoverify? returns false for string 'true' (not == true)
@legacy4 = Onetime::CustomDomain::SignupConfig.new(domain_id: 'legacy_test_4')
@legacy4.instance_variable_set(:@autoverify, 'true')
@legacy4.autoverify?
#=> false

# --- create! defaults ---

## create! without signup_enabled sets it to false
@ts_cd1 = Familia.now.to_i
@domain_cd1 = Onetime::CustomDomain.create!("nn-cd1-#{@ts_cd1}-#{SecureRandom.hex(2)}.example.com", @org.objid)
@created_default = Onetime::CustomDomain::SignupConfig.create!(
  domain_id: @domain_cd1.identifier,
  validation_strategy: 'passthrough',
)
@created_default.signup_enabled
#=> false

## create! without autoverify sets it to false
@created_default.autoverify
#=> false

## create! default signup_enabled? predicate returns false
@created_default.signup_enabled?
#=> false

## create! default autoverify? predicate returns false
@created_default.autoverify?
#=> false

# --- create! with explicit values ---

## create! with signup_enabled: true persists true
@ts_cd2 = Familia.now.to_i
@domain_cd2 = Onetime::CustomDomain.create!("nn-cd2-#{@ts_cd2}-#{SecureRandom.hex(2)}.example.com", @org.objid)
@created_enabled = Onetime::CustomDomain::SignupConfig.create!(
  domain_id: @domain_cd2.identifier,
  validation_strategy: 'passthrough',
  signup_enabled: true,
)
@created_enabled.signup_enabled?
#=> true

## create! with autoverify: true persists true
@ts_cd3 = Familia.now.to_i
@domain_cd3 = Onetime::CustomDomain.create!("nn-cd3-#{@ts_cd3}-#{SecureRandom.hex(2)}.example.com", @org.objid)
@created_av = Onetime::CustomDomain::SignupConfig.create!(
  domain_id: @domain_cd3.identifier,
  validation_strategy: 'passthrough',
  autoverify: true,
)
@created_av.autoverify?
#=> true

## create! with autoverify: true still defaults signup_enabled to false
@created_av.signup_enabled?
#=> false

## create! with signup_enabled: true still defaults autoverify to false
@created_enabled.autoverify?
#=> false

# --- Round-trip through save/load ---

## Round-trip: set signup_enabled to true, save, reload, verify predicate
@ts_rt = Familia.now.to_i
@domain_rt = Onetime::CustomDomain.create!("nn-rt-#{@ts_rt}-#{SecureRandom.hex(2)}.example.com", @org.objid)
@rt_config = Onetime::CustomDomain::SignupConfig.create!(
  domain_id: @domain_rt.identifier,
  validation_strategy: 'passthrough',
  signup_enabled: true,
)
@rt_loaded = Onetime::CustomDomain::SignupConfig.find_by_domain_id(@domain_rt.identifier)
@rt_loaded.signup_enabled?
#=> true

## Round-trip: set autoverify to true, save, reload, verify predicate
@ts_rt2 = Familia.now.to_i
@domain_rt2 = Onetime::CustomDomain.create!("nn-rt2-#{@ts_rt2}-#{SecureRandom.hex(2)}.example.com", @org.objid)
@rt_config2 = Onetime::CustomDomain::SignupConfig.create!(
  domain_id: @domain_rt2.identifier,
  validation_strategy: 'passthrough',
  autoverify: true,
)
@rt_loaded2 = Onetime::CustomDomain::SignupConfig.find_by_domain_id(@domain_rt2.identifier)
@rt_loaded2.autoverify?
#=> true

## Round-trip: false values survive save/load
@ts_rt3 = Familia.now.to_i
@domain_rt3 = Onetime::CustomDomain.create!("nn-rt3-#{@ts_rt3}-#{SecureRandom.hex(2)}.example.com", @org.objid)
@rt_config3 = Onetime::CustomDomain::SignupConfig.create!(
  domain_id: @domain_rt3.identifier,
  validation_strategy: 'passthrough',
)
@rt_loaded3 = Onetime::CustomDomain::SignupConfig.find_by_domain_id(@domain_rt3.identifier)
@rt_loaded3.signup_enabled?
#=> false

## Round-trip: autoverify false survives save/load
@rt_loaded3.autoverify?
#=> false

# --- API serialization shape ---

## Serialized signup_enabled is boolean (not nil) via predicate
@serial = Onetime::CustomDomain::SignupConfig.create!(
  domain_id: Onetime::CustomDomain.create!("nn-ser-#{Familia.now.to_i}-#{SecureRandom.hex(2)}.example.com", @org.objid).identifier,
  validation_strategy: 'passthrough',
)
@serial_result = { signup_enabled: @serial.signup_enabled?, autoverify: @serial.autoverify? }
@serial_result[:signup_enabled].is_a?(FalseClass) || @serial_result[:signup_enabled].is_a?(TrueClass)
#=> true

## Serialized autoverify is boolean (not nil) via predicate
@serial_result[:autoverify].is_a?(FalseClass) || @serial_result[:autoverify].is_a?(TrueClass)
#=> true

## Serialized signup_enabled is not nil
@serial_result[:signup_enabled].nil?
#=> false

## Serialized autoverify is not nil
@serial_result[:autoverify].nil?
#=> false

## Serialized shape matches API contract when both false
@serial_result
#=> {signup_enabled: false, autoverify: false}

## Serialized shape matches API contract when both true
@serial_true = Onetime::CustomDomain::SignupConfig.create!(
  domain_id: Onetime::CustomDomain.create!("nn-ser2-#{Familia.now.to_i}-#{SecureRandom.hex(2)}.example.com", @org.objid).identifier,
  validation_strategy: 'passthrough',
  signup_enabled: true,
  autoverify: true,
)
@serial_true_result = { signup_enabled: @serial_true.signup_enabled?, autoverify: @serial_true.autoverify? }
@serial_true_result
#=> {signup_enabled: true, autoverify: true}

# --- Cleanup ---

Familia.dbclient.flushdb
OT.info "Cleaned Redis after SignupConfig non-nullable boolean test run"

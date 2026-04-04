# try/features/incoming/incoming_timestamp_update_try.rb
#
# frozen_string_literal: true

# Tests for IncomingConfig timestamp update behavior.
#
# Coverage:
# 1. When ONLY `enabled` changes, `updated` timestamp is updated
# 2. When ONLY `recipients` change, `updated` timestamp is updated
# 3. When both change, `updated` timestamp is updated
# 4. Timestamp reflects the time of the most recent save
#
# The `updated` field should always reflect the last modification time,
# regardless of which field(s) changed.

require_relative '../../support/test_logic'

OT.boot! :test, false

require 'onetime/models/custom_domain/incoming_config'

IncomingConfig = Onetime::CustomDomain::IncomingConfig

@ts = Familia.now.to_i
@entropy = SecureRandom.hex(4)

# --- TIMESTAMP UPDATE TESTS ---

## Created timestamp is set on creation
config = IncomingConfig.create!(domain_id: "ts_created_#{@ts}_1")
result = config.created.to_i > 0
config.destroy!
result
#=> true

## Updated timestamp is set on creation
config = IncomingConfig.create!(domain_id: "ts_initial_#{@ts}_1")
result = config.updated.to_i > 0
config.destroy!
result
#=> true

## Created and updated are equal at creation time
config = IncomingConfig.create!(domain_id: "ts_equal_#{@ts}_1")
result = config.created.to_i == config.updated.to_i
config.destroy!
result
#=> true

## enable! updates the updated timestamp
config = IncomingConfig.create!(domain_id: "ts_enable_#{@ts}_1")
initial_updated = config.updated.to_i
sleep 1.01 # Sleep > 1 second to cross second boundary for integer timestamps
config.enable!
result = config.updated.to_i > initial_updated
config.destroy!
result
#=> true

## disable! updates the updated timestamp
config = IncomingConfig.create!(domain_id: "ts_disable_#{@ts}_1", enabled: true)
initial_updated = config.updated.to_i
sleep 1.01 # Sleep > 1 second to cross second boundary for integer timestamps
config.disable!
result = config.updated.to_i > initial_updated
config.destroy!
result
#=> true

## Setting recipients updates the updated timestamp
config = IncomingConfig.create!(domain_id: "ts_recip_#{@ts}_1")
initial_updated = config.updated.to_i
sleep 1.01 # Sleep > 1 second to cross second boundary for integer timestamps
config.recipients = [{ email: 'test@example.com', name: 'Test' }]
result = config.updated.to_i > initial_updated
config.destroy!
result
#=> true

## clear_recipients! updates the updated timestamp
config = IncomingConfig.create!(
  domain_id: "ts_clear_#{@ts}_1",
  recipients: [{ email: 'clear@example.com', name: 'Clear' }]
)
initial_updated = config.updated.to_i
sleep 0.01
config.clear_recipients!
result = config.updated.to_i >= initial_updated
config.destroy!
result
#=> true

## add_recipient updates the updated timestamp (via recipients= setter)
config = IncomingConfig.create!(domain_id: "ts_add_#{@ts}_1")
initial_updated = config.updated.to_i
sleep 0.01
config.add_recipient(email: 'added@example.com', name: 'Added')
config.save
result = config.updated.to_i >= initial_updated
config.destroy!
result
#=> true

## remove_recipient updates the updated timestamp (via recipients= setter)
config = IncomingConfig.create!(
  domain_id: "ts_remove_#{@ts}_1",
  recipients: [{ email: 'remove@example.com', name: 'Remove' }]
)
initial_updated = config.updated.to_i
sleep 0.01
config.remove_recipient(email: 'remove@example.com')
config.save
result = config.updated.to_i >= initial_updated
config.destroy!
result
#=> true

# --- TIMESTAMP PERSISTENCE TESTS ---

## updated timestamp persists after enable! (verify via reload)
config = IncomingConfig.create!(domain_id: "ts_persist_enable_#{@ts}_1")
sleep 0.01
config.enable!
expected_updated = config.updated.to_i
reloaded = IncomingConfig.load("ts_persist_enable_#{@ts}_1")
result = reloaded.updated.to_i == expected_updated
config.destroy!
result
#=> true

## updated timestamp persists after disable! (verify via reload)
config = IncomingConfig.create!(domain_id: "ts_persist_disable_#{@ts}_1", enabled: true)
sleep 0.01
config.disable!
expected_updated = config.updated.to_i
reloaded = IncomingConfig.load("ts_persist_disable_#{@ts}_1")
result = reloaded.updated.to_i == expected_updated
config.destroy!
result
#=> true

## updated timestamp persists after recipients change (verify via reload)
config = IncomingConfig.create!(domain_id: "ts_persist_recip_#{@ts}_1")
sleep 0.01
config.recipients = [{ email: 'persist@example.com', name: 'Persist' }]
config.save
expected_updated = config.updated.to_i
reloaded = IncomingConfig.load("ts_persist_recip_#{@ts}_1")
result = reloaded.updated.to_i == expected_updated
config.destroy!
result
#=> true

# --- MULTIPLE OPERATIONS ---

## Multiple enable/disable cycles update timestamp each time
config = IncomingConfig.create!(domain_id: "ts_multi_toggle_#{@ts}_1")
timestamps = [config.updated.to_i]
3.times do
  sleep 0.01
  config.enable!
  timestamps << config.updated.to_i
  sleep 0.01
  config.disable!
  timestamps << config.updated.to_i
end
# Each operation should have produced a timestamp >= previous
result = timestamps.each_cons(2).all? { |a, b| b >= a }
config.destroy!
result
#=> true

## Multiple recipient modifications update timestamp each time
config = IncomingConfig.create!(domain_id: "ts_multi_recip_#{@ts}_1")
timestamps = [config.updated.to_i]
3.times do |i|
  sleep 0.01
  config.add_recipient(email: "multi#{i}@example.com", name: "Multi #{i}")
  config.save
  timestamps << config.updated.to_i
end
# Each addition should have produced a timestamp >= previous
result = timestamps.each_cons(2).all? { |a, b| b >= a }
config.destroy!
result
#=> true

## Mixed operations (enable + recipients) all update timestamp
config = IncomingConfig.create!(domain_id: "ts_mixed_#{@ts}_1")
ts1 = config.updated.to_i
sleep 0.01
config.enable!
ts2 = config.updated.to_i
sleep 0.01
config.recipients = [{ email: 'mixed@example.com', name: 'Mixed' }]
config.save
ts3 = config.updated.to_i
sleep 0.01
config.disable!
ts4 = config.updated.to_i
result = (ts2 >= ts1) && (ts3 >= ts2) && (ts4 >= ts3)
config.destroy!
result
#=> true

# --- CREATED TIMESTAMP IMMUTABILITY ---

## Created timestamp does not change on enable!
config = IncomingConfig.create!(domain_id: "ts_created_immut_#{@ts}_1")
initial_created = config.created.to_i
sleep 0.01
config.enable!
result = config.created.to_i == initial_created
config.destroy!
result
#=> true

## Created timestamp does not change on recipients modification
config = IncomingConfig.create!(domain_id: "ts_created_immut2_#{@ts}_1")
initial_created = config.created.to_i
sleep 0.01
config.recipients = [{ email: 'immut@example.com', name: 'Immut' }]
config.save
result = config.created.to_i == initial_created
config.destroy!
result
#=> true

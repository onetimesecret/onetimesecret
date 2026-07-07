# try/unit/models/secret_active_counter_try.rb
#
# frozen_string_literal: true

# Unit tryouts for the per-customer live-secret counter (issue #60).
#
# Covers:
# - Receipt.spawn_pair increments the owner's secrets_active counter (exactly
#   once per created secret, at the single creation chokepoint)
# - anonymous / ownerless creates ('anon' or nil owner_id) do NOT increment
# - Customer.increment_secrets_active guards anon/nil/blank owner ids
# - a fresh Customer.new(objid:) reads the same counter key (no full load)
#
# Run: try --agent try/unit/models/secret_active_counter_try.rb

require_relative '../../support/test_helpers'

OT.boot! :test

@stamp = Familia.now.to_f.to_s.gsub('.', '')
@cust  = Onetime::Customer.create!(email: "active_#{@stamp}@ctr.example")

# TRYOUTS

## a brand-new customer starts with a zero secrets_active counter
@cust.secrets_active.to_i
#=> 0

## spawn_pair increments the owner's secrets_active by exactly one
Onetime::Receipt.spawn_pair(@cust.objid, 3600, 'first secret')
@cust.secrets_active.to_i
#=> 1

## two more creates advance the counter to three (one per create)
2.times { Onetime::Receipt.spawn_pair(@cust.objid, 3600, 'more') }
@cust.secrets_active.to_i
#=> 3

## the increment is visible through a fresh, unloaded Customer.new(objid:)
Onetime::Customer.new(objid: @cust.objid).secrets_active.to_i
#=> 3

## an anonymous ('anon' owner) create does NOT touch any customer counter
@anon_before = @cust.secrets_active.to_i
Onetime::Receipt.spawn_pair('anon', 3600, 'anon secret')
@cust.secrets_active.to_i == @anon_before
#=> true

## an ownerless (nil owner_id) create does not raise and counts nothing
Onetime::Receipt.spawn_pair(nil, 3600, 'ownerless secret')
@cust.secrets_active.to_i
#=> 3

## increment_secrets_active is a no-op for the 'anon' sentinel
Onetime::Customer.increment_secrets_active('anon')
Onetime::Customer.new(objid: 'anon').secrets_active.to_i
#=> 0

## increment_secrets_active is a no-op for nil / blank owner ids
[Onetime::Customer.increment_secrets_active(nil),
 Onetime::Customer.increment_secrets_active('')]
#=> [nil, nil]

## increment_secrets_active bumps a real owner id by one
@direct = Onetime::Customer.create!(email: "direct_#{@stamp}@ctr.example")
Onetime::Customer.increment_secrets_active(@direct.objid)
@direct.secrets_active.to_i
#=> 1

# TEARDOWN

[@cust, @direct].each { |c| c.destroy! rescue nil }

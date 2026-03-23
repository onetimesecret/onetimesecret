# try/unit/models/anonymous_ownership_try.rb
#
# frozen_string_literal: true

# These tryouts test the anonymous? and owner? methods for Receipt and Secret.
#
# Both models share identical logic for these methods:
# - anonymous? returns true when owner_id is 'anon'
# - owner? returns true when a customer's objid matches owner_id (and not anonymous)
#
# This consolidates testing for issue #2733 which adds Secret#anonymous? to
# match Receipt#anonymous? for consistent anonymous detection across models.

require_relative '../../support/test_models'

OT.boot! :test, true

# ----------------------------------------------------------------
# Receipt#anonymous? tests
# ----------------------------------------------------------------

## Receipt#anonymous? returns true when owner_id is 'anon'
receipt, secret = Onetime::Receipt.spawn_pair 'anon', 3600, 'test secret'
receipt.anonymous?
#=> true

## Receipt#anonymous? returns false when owner_id is a customer objid
cust = Onetime::Customer.new
cust.custid = "test+#{Familia.now.to_i}@example.com"
cust.role = 'customer'
cust.save
receipt, secret = Onetime::Receipt.spawn_pair cust.objid, 3600, 'test secret'
receipt.anonymous?
#=> false

## Receipt#anonymous? handles nil owner_id gracefully
receipt = Onetime::Receipt.new state: :new
receipt.owner_id = nil
receipt.anonymous?
#=> false

## Receipt#anonymous? handles empty string owner_id
receipt = Onetime::Receipt.new state: :new
receipt.owner_id = ''
receipt.anonymous?
#=> false

# ----------------------------------------------------------------
# Secret#anonymous? tests
# ----------------------------------------------------------------

## Secret#anonymous? returns true when owner_id is 'anon'
receipt, secret = Onetime::Receipt.spawn_pair 'anon', 3600, 'test secret'
secret.anonymous?
#=> true

## Secret#anonymous? returns false when owner_id is a customer objid
cust = Onetime::Customer.new
cust.custid = "test+secret#{Familia.now.to_i}@example.com"
cust.role = 'customer'
cust.save
receipt, secret = Onetime::Receipt.spawn_pair cust.objid, 3600, 'test secret'
secret.anonymous?
#=> false

## Secret#anonymous? handles nil owner_id gracefully
secret = Onetime::Secret.new state: :new
secret.owner_id = nil
secret.anonymous?
#=> false

## Secret#anonymous? handles empty string owner_id
secret = Onetime::Secret.new state: :new
secret.owner_id = ''
secret.anonymous?
#=> false

# ----------------------------------------------------------------
# Receipt#owner? tests
# ----------------------------------------------------------------

## Receipt#owner? returns false for anonymous receipts
receipt, secret = Onetime::Receipt.spawn_pair 'anon', 3600, 'test secret'
cust = Onetime::Customer.new
cust.custid = "owner+test1#{Familia.now.to_i}@example.com"
cust.role = 'customer'
cust.save
receipt.owner?(cust)
#=> false

## Receipt#owner? returns true when customer matches owner_id
cust = Onetime::Customer.new
cust.custid = "owner+test2#{Familia.now.to_i}@example.com"
cust.role = 'customer'
cust.save
receipt, secret = Onetime::Receipt.spawn_pair cust.objid, 3600, 'test secret'
receipt.owner?(cust)
#=> true

## Receipt#owner? returns false when customer does not match owner_id
owner = Onetime::Customer.new
owner.custid = "owner+test3#{Familia.now.to_i}@example.com"
owner.role = 'customer'
owner.save
other = Onetime::Customer.new
other.custid = "other+test3#{Familia.now.to_i}@example.com"
other.role = 'customer'
other.save
receipt, secret = Onetime::Receipt.spawn_pair owner.objid, 3600, 'test secret'
receipt.owner?(other)
#=> false

## Receipt#owner? returns falsy (nil) when fobj is nil
cust = Onetime::Customer.new
cust.custid = "owner+test4#{Familia.now.to_i}@example.com"
cust.role = 'customer'
cust.save
receipt, secret = Onetime::Receipt.spawn_pair cust.objid, 3600, 'test secret'
receipt.owner?(nil)
#=> nil

# ----------------------------------------------------------------
# Secret#owner? tests
# ----------------------------------------------------------------

## Secret#owner? returns false for anonymous secrets
receipt, secret = Onetime::Receipt.spawn_pair 'anon', 3600, 'test secret'
cust = Onetime::Customer.new
cust.custid = "secret+owner1#{Familia.now.to_i}@example.com"
cust.role = 'customer'
cust.save
secret.owner?(cust)
#=> false

## Secret#owner? returns true when customer matches owner_id
cust = Onetime::Customer.new
cust.custid = "secret+owner2#{Familia.now.to_i}@example.com"
cust.role = 'customer'
cust.save
receipt, secret = Onetime::Receipt.spawn_pair cust.objid, 3600, 'test secret'
secret.owner?(cust)
#=> true

## Secret#owner? returns false when customer does not match owner_id
owner = Onetime::Customer.new
owner.custid = "secret+owner3#{Familia.now.to_i}@example.com"
owner.role = 'customer'
owner.save
other = Onetime::Customer.new
other.custid = "secret+other3#{Familia.now.to_i}@example.com"
other.role = 'customer'
other.save
receipt, secret = Onetime::Receipt.spawn_pair owner.objid, 3600, 'test secret'
secret.owner?(other)
#=> false

## Secret#owner? returns falsy (nil) when fobj is nil
cust = Onetime::Customer.new
cust.custid = "secret+owner4#{Familia.now.to_i}@example.com"
cust.role = 'customer'
cust.save
receipt, secret = Onetime::Receipt.spawn_pair cust.objid, 3600, 'test secret'
secret.owner?(nil)
#=> nil

# ----------------------------------------------------------------
# Consistency tests: Receipt and Secret behave identically
# ----------------------------------------------------------------

## Receipt and Secret anonymous? return same value for 'anon' owner
receipt, secret = Onetime::Receipt.spawn_pair 'anon', 3600, 'test secret'
[receipt.anonymous?, secret.anonymous?]
#=> [true, true]

## Receipt and Secret anonymous? return same value for real customer
cust = Onetime::Customer.new
cust.custid = "consistency+test1#{Familia.now.to_i}@example.com"
cust.role = 'customer'
cust.save
receipt, secret = Onetime::Receipt.spawn_pair cust.objid, 3600, 'test secret'
[receipt.anonymous?, secret.anonymous?]
#=> [false, false]

## Receipt and Secret owner? return same value for matching customer
cust = Onetime::Customer.new
cust.custid = "consistency+test2#{Familia.now.to_i}@example.com"
cust.role = 'customer'
cust.save
receipt, secret = Onetime::Receipt.spawn_pair cust.objid, 3600, 'test secret'
[receipt.owner?(cust), secret.owner?(cust)]
#=> [true, true]

## Receipt and Secret owner? return same value for non-matching customer
owner = Onetime::Customer.new
owner.custid = "consistency+owner3#{Familia.now.to_i}@example.com"
owner.role = 'customer'
owner.save
other = Onetime::Customer.new
other.custid = "consistency+other3#{Familia.now.to_i}@example.com"
other.role = 'customer'
other.save
receipt, secret = Onetime::Receipt.spawn_pair owner.objid, 3600, 'test secret'
[receipt.owner?(other), secret.owner?(other)]
#=> [false, false]

## Receipt and Secret owner? return same value for anonymous secrets
receipt, secret = Onetime::Receipt.spawn_pair 'anon', 3600, 'test secret'
cust = Onetime::Customer.new
cust.custid = "consistency+test4#{Familia.now.to_i}@example.com"
cust.role = 'customer'
cust.save
[receipt.owner?(cust), secret.owner?(cust)]
#=> [false, false]

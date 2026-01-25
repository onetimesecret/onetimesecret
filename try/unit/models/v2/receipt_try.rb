# try/unit/models/v2/receipt_try.rb
#
# frozen_string_literal: true

# These tryouts test the Onetime::Receipt class functionality.
# The Receipt class is responsible for managing receipt records associated
# with secrets in the Onetime application.
#
# We're testing various aspects of the Receipt class, including:
# 1. Creation and initialization of Receipt objects
# 2. Consistency of Redis keys and secret keys
# 3. Saving and destroying Receipt objects
# 4. Checking existence of Receipt in the database
#
# These tests aim to ensure that receipts can be correctly created,
# stored, and managed, which is crucial for maintaining information
# about secrets in the application.

require 'securerandom'

require_relative '../../../support/test_models'

#Familia.debug = true

OT.boot! :test, true

@iterations = 1000

## Can create a Receipt
m = Onetime::Receipt.new :private
[m.class, m.dbclient.connection[:db], m.secret_identifier]
#=> [Onetime::Receipt, 0, nil]

## Can explicitly set the secret key
m = Onetime::Receipt.new :private
m.secret_identifier = 'hihi'
[m.class, m.dbclient.connection[:db], m.secret_identifier]
#=> [Onetime::Receipt, 0, 'hihi']

## Keys are always unique for Receipt
## NOTE: Prior to Familia v1.0.0.pre.rc1 upgrade the receipt key
## here was `ivfn09cpriklqii1zagw6fc96suh8bp` (1 of 2)
unique_values = Set.new
@iterations.times do
  s = Onetime::Receipt.new state: :receipt
  unique_values.add(s.dbkey)
end
unique_values.size
#=> @iterations

## And are not affected (or effected) by arguments
## NOTE: Prior to Familia v1.0.0.pre.rc1 upgrade the receipt key
## here was `ivfn09cpriklqii1zagw6fc96suh8bp` (2 of 2)
unique_values = Set.new
@iterations.times do
  s = Onetime::Receipt.new state: %i[some fixed values]
  unique_values.add(s.dbkey)
end
unique_values.size
#=> @iterations

## Doesn't exist yet
@receipt = Onetime::Receipt.new :receipt, [OT.instance, Familia.now.to_f, SecureRandom.hex]
@receipt.exists?
#=> false

## Does exist
@receipt.save
p @receipt.to_h # from ruby memory to hash
p @receipt.hgetall # from db memory to hash
@receipt.exists?
#=> true

@receipt.destroy!

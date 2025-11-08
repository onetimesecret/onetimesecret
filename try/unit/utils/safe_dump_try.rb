# try/unit/utils/safe_dump_try.rb
#
# frozen_string_literal: true

# These tryouts test the safe dumping functionality.

require_relative '../../support/test_models'

OT.boot! :test, true

@email = 'tryouts-19@onetimesecret.com'

## Implementing models like Customer can define safe dump fields
fields = Customer.safe_dump_fields
# Check that essential fields are present (order-independent)
[:identifier, :custid, :email, :role, :objid, :extid].all? { |f| fields.include?(f) }
#=> true

## Implementing models like Customer can safely dump their fields
cust = Customer.new
dumped = cust.safe_dump
# Check for key fields with expected default values (ignore generated IDs)
dumped[:role] == "customer" && dumped[:email].nil? && dumped[:secrets_created] == "0"
#=> true

## Implementing models like Customer do have other fields
## that are by default considered not safe to dump.
cust = Customer.new(name: 'Lucy', custid: @email)

all_non_safe_fields = cust.instance_variables.map { |el|
  el.to_s[1..-1].to_sym # slice off the leading @
}.sort

safe_fields = cust.class.safe_dump_fields.sort
# Check that essential fields are in the safe list
[:custid, :email, :role, :secrets_created, :secrets_burned].all? { |f| safe_fields.include?(f) }
#=> true

## Implementing models like Customer can rest assured knowing
## any other field not in the safe list will not be dumped.
cust = Customer.new
cust.instance_variable_set(:"@haircut", "coupe de longueuil")

all_safe_fields = cust.safe_dump.keys.sort

all_non_safe_fields = cust.instance_variables.map { |el|
  el.to_s[1..-1].to_sym # slice off the leading @
}.sort

# Check that our custom @haircut field is NOT in the safe dump
all_safe_fields.include?(:haircut)
#=> false

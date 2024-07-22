# frozen_string_literal: true

# These tryouts test the safe dumping functionality.

require_relative '../lib/onetime'

# Use the default config file for tests
OT::Config.path = File.join(__dir__, '..', 'etc', 'config.test')
OT.boot!

## By default there are no safe dump fields
OT::Models::SafeDump.safe_dump_fields
#=> []

## Implementing models like Customer can define safe dump fields
Onetime::Customer.safe_dump_fields
#=> [:custid, :role, :planid, :verified, :updated, :created, :secrets_created, :active]

## Implementing models like Customer can safely dump their fields
cust = Onetime::Customer.new
cust.safe_dump
{:custid=>:anon, :role=>"customer", :planid=>nil, :verified=>nil, :updated=>nil, :created=>nil, :active=>false}

## Implementing models like Customer do have other fields
## that are by default considered not safe to dump.
cust = Onetime::Customer.new(name: 'Lucy')

all_non_safe_fields = cust.instance_variables.map { |el|
  el.to_s[1..-1].to_sym # slice off the leading @
}.sort

all_non_safe_fields.sort
#=> [:cache, :custid, :db, :name, :opts, :parent, :prefix, :redis, :suffix, :ttl]

## Implementing models like Customer can rest assured knowing
## any other field not in the safe list will not be dumped.
cust = Onetime::Customer.new(name: 'Lucy')
all_safe_fields = cust.safe_dump.keys.sort

all_non_safe_fields = cust.instance_variables.map { |el|
  el.to_s[1..-1].to_sym # slice off the leading @
}.sort

# Check if any of the non-safe fields are in the safe dump
all_non_safe_fields & all_safe_fields
#=> [:custid]

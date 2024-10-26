# frozen_string_literal: true

# These tryouts test the customer custom domain relations


require 'onetime'

# Load the app
OT::Config.path = File.join(Onetime::HOME, 'tests', 'unit', 'ruby', 'config.test.yaml')
OT.boot! :test

# Setup some variables for these tryouts
@now = Time.now
@email_address = "tryouts+#{@now.to_i}@onetimesecret.com"
@cust = OT::Customer.new @email_address

@valid_domain = 'another.subdomain.onetimesecret.com'
@input_domains = [
  'example.com',
  'subdomain.example.com'
]

# TRYOUTS

## Customer has a custom domain list
@cust.custom_domains.class
#=> Familia::SortedSet

## Customer's custom domain list is stored as a sorted set
@cust.custom_domains_list.class
#=> Array

## Customer's custom domain list is empty to start
@cust.custom_domains.empty?
#=> true

## Ditto for the sorted set
@cust.custom_domains_list.empty?
#=> true

## A customer's custom_domain list updates when a new domain is added
OT::CustomDomain.create(@valid_domain, @cust.custid)
@cust.custom_domains.empty?
#=> false

## A customer's custom_domain list updates when a new domain is added
custom_domain = OT::CustomDomain.load(@valid_domain, @cust.custid)
[custom_domain.class, custom_domain.display_domain]
#=> [OT::CustomDomain, @valid_domain]

## A customer's custom_domain list updates when a new domain is added
@cust.custom_domains.first
#=> @valid_domain

## A custom domain has an owner (via model instance)
custom_domain = OT::CustomDomain.create(@valid_domain, @cust.custid)
custom_domain.owner?(@cust)
#=> true

## A custom domain has an owner (via email string)
custom_domain = OT::CustomDomain.create(@valid_domain, @cust.custid)
custom_domain.owner?(@cust.custid)
#=> true

## A custom domain has an owner (nil)
custom_domain = OT::CustomDomain.create(@valid_domain, @cust.custid)
custom_domain.owner?(nil)
#=> false

## A custom domain has an owner (via different email string)
custom_domain = OT::CustomDomain.create(@valid_domain, @cust.custid)
custom_domain.owner?('anothercustomer@onetimesecret.com')
#=> false

## A custom domain has an owner (via different customer)
cust = OT::Customer.create("anothercustome+#{@now.to_i}r@onetimesecret.com")
custom_domain = OT::CustomDomain.create(@valid_domain, @cust.custid)
custom_domain.owner?(cust)
#=> false

## A customer's custom_domain list updates when a new domain is added
custom_domain = @cust.custom_domains_list.first
[custom_domain.class, custom_domain.display_domain]
#=> [OT::CustomDomain, @valid_domain]

## A customer's custom_domain list updates when an existing domain is removed
custom_domain = @cust.custom_domains_list.first
@cust.remove_custom_domain(custom_domain)
#=> true

## A customer's custom_domain list is empty again after removing a domain
@cust.custom_domains.empty?
#=> true

## CustomDomain uses the correct Redis database
OT::CustomDomain.db
#=> 6

## CustomDomain has the correct prefix
OT::CustomDomain.prefix
#=> :customdomain

## CustomDomain.values is a Familia::SortedSet
OT::CustomDomain.values.class
#=> Familia::SortedSet

## CustomDomain.owners is a Familia::HashKey
OT::CustomDomain.owners.class
#=> Familia::HashKey

## CustomDomain.values Redis key is correctly prefixed
OT::CustomDomain.values.rediskey
#=> "customdomain:values"

## CustomDomain.owners Redis key is correctly prefixed
OT::CustomDomain.owners.rediskey
#=> "customdomain:owners"

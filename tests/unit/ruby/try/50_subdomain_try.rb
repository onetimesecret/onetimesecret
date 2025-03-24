# frozen_string_literal: true

# These tryouts test the subdomain functionality in the OneTime application.
# They cover various aspects of subdomain management, including:
#
# 1. Creating and normalizing subdomains
# 2. Checking subdomain existence and ownership
# 3. Mapping subdomains to customer IDs
# 4. Destroying subdomains
#
# These tests aim to verify the correct behavior of the Onetime::Subdomain class,
# which is essential for managing custom subdomains in the application.
#
# The tryouts simulate different subdomain scenarios and test the Onetime::Subdomain class's
# behavior without needing to interact with actual DNS, allowing for targeted testing
# of these specific features.


require_relative '../test_helpers'
require 'onetime/models/subdomain'

# Use the default config file for tests
OT.boot! :test

## Can create Subdomain instance
s = Onetime::Subdomain.new custid: 'tryouts@onetimesecret.com', cname: 'testcname'
s.class
#=> Onetime::Subdomain

## Normalize cname #1
OT::Subdomain.normalize_cname 'BIGNAMECO'
#=> 'bignameco'

## Normalize cname #2
OT::Subdomain.normalize_cname './*&^%$#@!BignAMECO.'
#=> 'bignameco'

## Subdomain has an identifier
s = Onetime::Subdomain.new custid: 'tryouts@onetimesecret.com', cname: 'bignameco'
[s.identifier, s.cname, s.rediskey]
#=> ['tryouts@onetimesecret.com', 'bignameco', 'customer:tryouts@onetimesecret.com:subdomain']

## Subdomain knows if it doesn't exists
Onetime::Subdomain.exists? 'tryouts@onetimesecret.com'
#=> false

## Create subdomain
@subdomain = Onetime::Subdomain.create('bignameco', 'tryouts@onetimesecret.com')
@subdomain.exists?
#=> true

## Subdomain knows if it exists
Onetime::Subdomain.exists? 'tryouts@onetimesecret.com'
#=> true

## Has a mapping to custid
OT::Subdomain.map 'bignameco'
##=> 'tryouts@onetimesecret.com'

## Knows it's mapped
OT::Subdomain.mapped? 'bignameco'
##=> true

## Mapping knows the owner
OT::Subdomain.owned_by? 'bignameco', 'tryouts@onetimesecret.com'
##=> true

## Destroy subdomain
@subdomain.destroy!
#=> true

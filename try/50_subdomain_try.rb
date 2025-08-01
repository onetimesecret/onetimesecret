# try/50_subdomain_try.rb

# These tryouts test the subdomain functionality in the Onetime application.
# They cover various aspects of subdomain management, including:
#
# 1. Creating and normalizing subdomains
# 2. Checking subdomain existence and ownership
# 3. Mapping subdomains to customer IDs
# 4. Destroying subdomains
#
# These tests aim to verify the correct behavior of the V1::Subdomain class,
# which is essential for managing custom subdomains in the application.
#
# The tryouts simulate different subdomain scenarios and test the V1::Subdomain class's
# behavior without needing to interact with actual DNS, allowing for targeted testing
# of these specific features.


require_relative 'test_helpers'
require 'v1/models/subdomain'

OT.boot! :test, false

## Can create Subdomain instance
s = V1::Subdomain.new custid: 'tryouts@onetimesecret.com', cname: 'testcname'
s.class
#=> V1::Subdomain

## Normalize cname #1
V1::Subdomain.normalize_cname 'BIGNAMECO'
#=> 'bignameco'

## Normalize cname #2
V1::Subdomain.normalize_cname './*&^%$#@!BignAMECO.'
#=> 'bignameco'

## Subdomain has an identifier
s = V1::Subdomain.new custid: 'tryouts@onetimesecret.com', cname: 'bignameco'
[s.identifier, s.cname, s.rediskey]
#=> ['tryouts@onetimesecret.com', 'bignameco', 'customer:tryouts@onetimesecret.com:subdomain']

## Subdomain knows if it doesn't exists
V1::Subdomain.exists? 'tryouts@onetimesecret.com'
#=> false

## Create subdomain
@subdomain = V1::Subdomain.create('bignameco', 'tryouts@onetimesecret.com')
@subdomain.exists?
#=> true

## Subdomain knows if it exists
V1::Subdomain.exists? 'tryouts@onetimesecret.com'
#=> true

## Has a mapping to custid
V1::Subdomain.map 'bignameco'
##=> 'tryouts@onetimesecret.com'

## Knows it's mapped
V1::Subdomain.mapped? 'bignameco'
##=> true

## Mapping knows the owner
V1::Subdomain.owned_by? 'bignameco', 'tryouts@onetimesecret.com'
##=> true

## Destroy subdomain
@subdomain.destroy!
#=> true

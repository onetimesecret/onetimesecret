require 'onetime'

OT.load! :app

## Can create Subdomain instance
s = Onetime::Subdomain.new 'tryouts@onetimesecret.com'
s.class
#=> Onetime::Subdomain

## Normalize cname #1
OT::Subdomain.normalize_cname 'BIGNAMECO'
#=> 'bignameco'

## Normalize cname #2
OT::Subdomain.normalize_cname './*&^%$#@!BignAMECO.'
#=> 'bignameco'

## Subdomain has an identifier
s = Onetime::Subdomain.new 'tryouts@onetimesecret.com', 'bignameco'
[s.identifier, s.cname, s.rediskey]
#=> ['tryouts@onetimesecret.com', 'bignameco', 'customer:tryouts@onetimesecret.com:subdomain']

## Subdomain knows if it doesn't exists
Onetime::Subdomain.exists? 'tryouts@onetimesecret.com'
#=> false

## Create subdomain
@subdomain = Onetime::Subdomain.create 'tryouts@onetimesecret.com', 'bignameco'
@subdomain.exists?
#=> true

## Subdomain knows if it exists
Onetime::Subdomain.exists? 'tryouts@onetimesecret.com'
#=> true

## Has a mapping to custid
OT::Subdomain.map 'bignameco'
#=> 'tryouts@onetimesecret.com'

## Knows it's mapped
OT::Subdomain.mapped? 'bignameco'
#=> true

## Mapping knows the owner
OT::Subdomain.owned_by? 'bignameco', 'tryouts@onetimesecret.com'
#=> true

## Destroy subdomain
@subdomain.destroy!
#=> 1
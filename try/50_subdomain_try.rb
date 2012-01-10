require 'onetime'

OT.load! :app

## Can create Subdomain instance
s = Onetime::Subdomain.new 'bignameco'
s.class
#=> Onetime::Subdomain

## Normalize cname #1
OT::Subdomain.normalize 'BIGNAMECO'
#=> 'bignameco'

## Normalize cname #2
OT::Subdomain.normalize './*&^%$#@!BignAMECO.'
#=> 'bignameco'

## Subdomain has an identifier
s = Onetime::Subdomain.new 'bignameco'
[s.identifier, s.cname, s.rediskey]
#=> ['bignameco', 'bignameco', 'subdomain:bignameco:object']

## Subdomain knows if it doesn't exists
Onetime::Subdomain.exists? 'bignameco'
#=> false

## Create subdomain
@subdomain = Onetime::Subdomain.create 'bignameco', 'tryouts'
@subdomain.exists?
#=> true

## Subdomain knows if it exists
Onetime::Subdomain.exists? 'bignameco'
#=> true

## Destroy subdomain
@subdomain.destroy!
#=> 1
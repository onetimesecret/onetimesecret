# try/20_models/27_domains_try.rb

# These tryouts test domain-related functionality using the PublicSuffix gem

require 'public_suffix'

require_relative '../test_models'

# Load the app
OT.boot! :test, false

@email = "Tryouts+27+#{Time.now.to_i}@onetimesecret.com"
@email2 = "Tryouts+27b+#{Time.now.to_i}@onetimesecret.com"
@customer = V1::Customer.create @email
@valid_domain = 'another.subdomain.onetimesecret.com'
@input_domains = [
  'example.com',
  'subdomain.example.com',
  @valid_domain,
  'invalid',
  'localhost',
  'user@example.com'
]
@unique_identifier_collector = []

## Can parse an input domain into a base domain
@input_domains.map { |input_domain|
  begin
    V2::CustomDomain.base_domain(input_domain)

  rescue OT::Problem => e
    e.message
  end
}
#=> ["example.com", "example.com", "onetimesecret.com", nil, nil, "user@example.com"]


## Can parse an input domain into a display domain, which includes the
## subdomain if it exists.
@input_domains.map { |input_domain|
  begin
    V2::CustomDomain.display_domain(input_domain)

  rescue OT::Problem => e
    e.message
  end
}
#=> ["example.com", "subdomain.example.com", "another.subdomain.onetimesecret.com", "`invalid` is not a valid domain", "`localhost` is not a valid domain", "user@example.com"]


## CustomDomain unique identifier is based on the domain name and customer id
## so it's possible to create multiple custom domains for a single and for two
## different customers to verify the same domain.
obj = V2::CustomDomain.new('tryouts.onetimesecret.com', '12345@example.com')
@unique_identifier_collector << obj.identifier
obj.identifier
#=> "0669deb998dbf949b308"

## A subdomain of a custom domain will have its own unique identifier
obj = V2::CustomDomain.new('a.tryouts.onetimesecret.com', '12345@example.com')
@unique_identifier_collector << obj.identifier
obj.identifier
#=> "5a2430213c958311834a"

## Another subdomain of a custom domain will have a different unique identifier
## (i.e. not the same as a.tryouts.onetimesecret.com).
obj = V2::CustomDomain.new('b.tryouts.onetimesecret.com', '12345@example.com')
@unique_identifier_collector << obj.identifier
obj.identifier
#=> "c6dcda580fdba6afc860"

## An apex domain will have its unique identifier too
## (i.e. not the same as a.tryouts.onetimesecret.com).
obj = V2::CustomDomain.new('onetimesecret.com', '12345@example.com')
@unique_identifier_collector << obj.identifier
obj.identifier
#=> "47797c9de5e182fea584"

## Unique identifiers for the same display domains but a different
## customer id are different too.
obj = V2::CustomDomain.new('tryouts.onetimesecret.com', '67890@example.com')
@unique_identifier_collector << obj.identifier
obj.identifier
#=> "e9b334e43f13c0104ee3"

## A subdomain of a custom domain will have its own unique identifier
obj = V2::CustomDomain.new('a.tryouts.onetimesecret.com', '67890@example.com')
@unique_identifier_collector << obj.identifier
obj.identifier
#=> "48d29d89a138e2b59f2f"

## Another subdomain of a custom domain will have a different unique identifier
## (i.e. not the same as a.tryouts.onetimesecret.com).
obj = V2::CustomDomain.new('b.tryouts.onetimesecret.com', '67890@example.com')
@unique_identifier_collector << obj.identifier
obj.identifier
#=> "3e660c308bfc7d29ff45"

## An apex domain will have its unique identifier too
## (i.e. not the same as a.tryouts.onetimesecret.com).
obj = V2::CustomDomain.new('onetimesecret.com', '67890@example.com')
@unique_identifier_collector << obj.identifier
obj.identifier
#=> "dc916d060de2210d9d9d"

## Check txt validation record host for apex domain
obj = V2::CustomDomain.new('onetimesecret.com', '12345@example.com')
host, value = obj.generate_txt_validation_record
host
#=> "_onetime-challenge-47797c9"

## As a paranoid measure, let's check the unique identifiers we have
## collected so far to make sure they are all different.
idset = Set.new(@unique_identifier_collector)

# Print out the set and the array so we can always cross-check the results
p idset.to_a, @unique_identifier_collector

equal_length = (@unique_identifier_collector.length == idset.length)
not_empty = !idset.empty?
[equal_length, not_empty]
#=> [true, true]

## Can create txt record for DNS
custom_domain = V2::CustomDomain.new(@valid_domain, "user@example.com")
host, value = custom_domain.generate_txt_validation_record
[host, value.length]
#=> ["_onetime-challenge-40f341a.another.subdomain", 32]

## CustomDomain.create must be called with a customer ID
begin
  V2::CustomDomain.create('tryouts.onetimesecret.com')
rescue ArgumentError => e
  e.message
end
#=> "wrong number of arguments (given 1, expected 2)"

## CustomDomain identifier is nil if customer ID is not provided
begin
  obj = V2::CustomDomain.parse('tryouts.onetimesecret.com', nil)
  obj.identifier
rescue OT::Problem => e
  e.message
end
#=> "Customer ID required"

## Check txt validation record host before generating
obj = V2::CustomDomain.new('onetimesecret.com', '12345@example.com')
obj.txt_validation_host
#=> nil

## Check txt validation record host for apex domain
obj = V2::CustomDomain.new('onetimesecret.com', '12345@example.com')
obj.generate_txt_validation_record
obj.txt_validation_host
#=> "_onetime-challenge-47797c9"

## Check txt validation record host for www. + apex domain
obj = V2::CustomDomain.new('www.onetimesecret.com', '12345@example.com')
obj.generate_txt_validation_record
obj.txt_validation_host
#=> "_onetime-challenge-7dd438f.www"

## Check txt validation record host for subdomain
obj = V2::CustomDomain.new('tryouts.onetimesecret.com', '12345@example.com')
obj.generate_txt_validation_record
obj.txt_validation_host
#=> "_onetime-challenge-0669deb.tryouts"

## Check txt validation record host for double subdomain
obj = V2::CustomDomain.new('a.tryouts.onetimesecret.com', '12345@example.com')
obj.generate_txt_validation_record
obj.txt_validation_host
#=> "_onetime-challenge-5a24302.a.tryouts"

## For some reason PublicSuffix.valid? returns true for a domain with a comma
V2::CustomDomain.valid?('tryouts,onetimesecret.com')
#=> true

## Domain with utf8 characters is valid
V2::CustomDomain.valid?('tést.com')
#=> true

## Domain with an emoji is valid
V2::CustomDomain.valid?('😀.com')
#=> true

## Domain with a kanji character is valid
V2::CustomDomain.valid?('テスト.com')
#=> true

## Domain with pinyin characters is valid
V2::CustomDomain.valid?('测试.com')
#=> true

## Domain with a japanese character is valid
V2::CustomDomain.valid?('テスト.com')
#=> true

## Domain with a mix of characters in the subdomain is valid
V2::CustomDomain.valid?('tést.😀.com')
#=> true


@customer.destroy!

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


## CustomDomain unique identifier is now a random ID while preserving domain-specific properties
## Check that unique identifiers are generated for each domain variant
obj1 = V2::CustomDomain.new('tryouts.onetimesecret.com', '12345@example.com')
@unique_identifier_collector << obj1.identifier
obj1.identifier  # Captures a random but unique ID
obj1.identifier.size  # Ensure the ID is not empty
#=> 20  # Previously defined length for compatibility

## A subdomain has a different unique identifier
obj2 = V2::CustomDomain.new('a.tryouts.onetimesecret.com', '12345@example.com')
@unique_identifier_collector << obj2.identifier
obj2.identifier  # Captures a different random ID
obj2.identifier.size  # Ensure the ID is not empty
#=> 20

## Another subdomain has another unique identifier
obj3 = V2::CustomDomain.new('b.tryouts.onetimesecret.com', '12345@example.com')
@unique_identifier_collector << obj3.identifier
obj3.identifier  # Captures a different random ID
obj3.identifier.size  # Ensure the ID is not empty
#=> 20

## An apex domain also has a unique identifier
obj4 = V2::CustomDomain.new('onetimesecret.com', '12345@example.com')
@unique_identifier_collector << obj4.identifier
obj4.identifier  # Captures a different random ID
obj4.identifier.size  # Ensure the ID is not empty
#=> 20

## Unique identifiers for the same display domains but a different
## customer id are still different
obj5 = V2::CustomDomain.new('tryouts.onetimesecret.com', '67890@example.com')
@unique_identifier_collector << obj5.identifier
obj5.identifier  # Captures a different random ID
obj5.identifier.size  # Ensure the ID is not empty
#=> 20

## Various subdomains and customers have unique IDs
obj6 = V2::CustomDomain.new('a.tryouts.onetimesecret.com', '67890@example.com')
@unique_identifier_collector << obj6.identifier
obj6.identifier  # Captures a different random ID
obj6.identifier.size  # Ensure the ID is not empty
#=> 20

## Another subdomain variant
obj7 = V2::CustomDomain.new('b.tryouts.onetimesecret.com', '67890@example.com')
@unique_identifier_collector << obj7.identifier
obj7.identifier  # Captures a different random ID
obj7.identifier.size  # Ensure the ID is not empty
#=> 20

## An apex domain for another customer
obj8 = V2::CustomDomain.new('onetimesecret.com', '67890@example.com')
@unique_identifier_collector << obj8.identifier
obj8.identifier  # Captures a different random ID
obj8.identifier.size  # Ensure the ID is not empty
#=> 20

## Check txt validation record host for apex domain
obj = V2::CustomDomain.new('onetimesecret.com', '12345@example.com')
host, value = obj.generate_txt_validation_record
host =~ /^_onetime-challenge-[0-9a-f]{7}$/
#=> 0  # Successful regex match

## As a paranoid measure, let's check the unique identifiers we have
## collected so far to make sure they are all different.
idset = Set.new(@unique_identifier_collector)

# Print out the set and the array so we can always cross-check the results
p idset.to_a, @unique_identifier_collector

# Check that we have unique identifiers and they all have the right characteristics
unique_count = idset.length
unique_ids_valid = idset.all? { |id| id.length == 20 }
not_empty = !idset.empty?
[unique_count, unique_ids_valid, not_empty]
#=> [8, true, true]

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

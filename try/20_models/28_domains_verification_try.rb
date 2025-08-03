# try/20_models/28_domains_verification_try.rb
# frozen_string_literal: true

# These tryouts test the validation and verification status functionality of custom domains

require 'securerandom'

require_relative '../test_models'

@reminder = lambda do
  puts "=" * 80
  puts "🚨 IMPORTANT NOTICE: CUSTOMER<>CUSTOMDOMAIN RELATIONS NEED FIXING! 🚨"
  puts "=" * 80
  puts "This test suite is running with temporary workarounds for the"
  puts "Customer<>CustomDomain relationship domainid change. "
  puts
  puts __FILE__
  puts __LINE__
  puts
  puts "=" * 80
  puts
end


OT.boot! :test, false

@now = Time.now
@customer_email = "tryouts28+#{@now.to_i}@onetimesecret.com"
@customer = V1::Customer.create(@customer_email)
@apex_domain = "example.com"
@valid_domain = "valid-domain-#{SecureRandom.hex(4)}.example.com"
@invalid_domain = "invalid_domain_with_no_tld"
@existing_domain = "existing-domain-#{SecureRandom.hex(4)}.example.com"

V2::CustomDomain.create(@existing_domain, @customer.custid) # Ensure the existing domain is created and added to values

## Can successfully create a custom domain with a valid domain name
begin
  custom_domain = V2::CustomDomain.create(@valid_domain, @customer.custid)
  [custom_domain.display_domain, custom_domain.custid]
rescue OT::Problem => e
  e.message
end
#=> [@valid_domain, @customer.custid]

## Cannot create a custom domain with an invalid domain name
begin
  custom_domain = V2::CustomDomain.create(@invalid_domain, @customer.custid)
rescue OT::Problem => e
  e.message
end
#=> "`invalid_domain_with_no_tld` is not a valid domain"

## Cannot create a duplicate custom domain for the same customer
5.times { @reminder.call }
custom_domain = V2::CustomDomain.create(@existing_domain, @customer.custid)
#=!> OT::Problem

## Can generate TXT validation record for a custom domain
custom_domain = V2::CustomDomain.new(@valid_domain, @customer.custid)
host, value = custom_domain.generate_txt_validation_record
[host.class, value.length]
#=> [String, 32]

## TXT validation record host is correctly formatted
custom_domain = V2::CustomDomain.new(@valid_domain, @customer.custid)
host, _ = custom_domain.generate_txt_validation_record
subdomain = custom_domain.trd
host.match?(/\A_onetime-challenge-\w{7}(\.)#{subdomain}\z/)
#=> true

## TXT validation record value is a 32-character hex string
custom_domain = V2::CustomDomain.new(@valid_domain, @customer.custid)
_, value = custom_domain.generate_txt_validation_record
value.match?(/^\h{32}$/)
#=> true

## Validation record is correctly built
custom_domain = V2::CustomDomain.new(@valid_domain, @customer.custid)
custom_domain.generate_txt_validation_record
validation_record = custom_domain.validation_record
expected_validation_record = [custom_domain.txt_validation_host, custom_domain.base_domain].join('.')
validation_record == expected_validation_record
#=> true

## Verification state is :unverified before any verification attempts
custom_domain = V2::CustomDomain.new(@valid_domain, @customer.custid)
custom_domain.verification_state
#=> :unverified

## Verification state is :pending after TXT validation record is generated
custom_domain = V2::CustomDomain.new(@valid_domain, @customer.custid)
custom_domain.generate_txt_validation_record # not called automatically
custom_domain.verification_state
#=> :pending

## Verification state is :resolving when resolving is true but verified is false
custom_domain = V2::CustomDomain.new(@valid_domain, @customer.custid)
custom_domain.generate_txt_validation_record # not called automatically
custom_domain.resolving = 'true'
custom_domain.verified = 'false'
custom_domain.verification_state
#=> :resolving

## Verification state is :verified when both resolving and verified are true
custom_domain = V2::CustomDomain.new(@valid_domain, @customer.custid)
custom_domain.generate_txt_validation_record # not called automatically
custom_domain.resolving = 'true'
custom_domain.verified = 'true'
custom_domain.verification_state
#=> :verified

## Verification state is :pending when resolving is false
custom_domain = V2::CustomDomain.new(@valid_domain, @customer.custid)
custom_domain.generate_txt_validation_record # not called automatically
custom_domain.resolving = 'false'
custom_domain.verified = 'false'
custom_domain.verification_state
#=> :pending

## Custom domain is ready when verification_state is :verified
custom_domain = V2::CustomDomain.new(@valid_domain, @customer.custid)
custom_domain.generate_txt_validation_record # not called automatically
custom_domain.verified = 'true'
custom_domain.resolving = 'true'
custom_domain.ready?
#=> true

## Custom domain is not ready when verification_state is not :verified
custom_domain = V2::CustomDomain.new(@valid_domain, @customer.custid)
custom_domain.generate_txt_validation_record # not called automatically
custom_domain.verified = 'false'
custom_domain.resolving = 'false'
custom_domain.ready?
#=> false

## Attempting to validate TXT record host with invalid characters raises an error
custom_domain = V2::CustomDomain.new(@valid_domain, @customer.custid)
custom_domain.txt_validation_host = 'invalid host with spaces'
begin
  custom_domain.validate_txt_record!
rescue OT::Problem => e
  e.message
end
#=> "TXT record hostname can only contain letters, numbers, dots, underscores, and hyphens"

## Attempting to validate TXT record value with incorrect format raises an error
custom_domain = V2::CustomDomain.new(@valid_domain, @customer.custid)
custom_domain.txt_validation_host = '_onetime-challenge-valid'
custom_domain.txt_validation_value = 'shortvalue'
begin
  custom_domain.validate_txt_record!
rescue OT::Problem => e
  e.message
end
#=> "TXT record value must be a 32-character hexadecimal string"

## Can validate correct TXT record host and value without errors
custom_domain = V2::CustomDomain.new(@valid_domain, @customer.custid)
custom_domain.txt_validation_host = '_onetime-challenge-valid'
custom_domain.txt_validation_value = SecureRandom.hex(16)
begin
  custom_domain.validate_txt_record!
  'No error'
rescue OT::Problem => e
  e.message
end
#=> "No error"

## Deleting custom domain removes associated keys in Redis
domain_to_delete = "delete-test-#{SecureRandom.hex(4)}.example.com"
custom_domain = V2::CustomDomain.create(domain_to_delete, @customer.custid)
redis_keys_before = custom_domain.redis.keys("#{custom_domain.rediskey}*")
custom_domain.destroy!(@customer)
redis_keys_after = custom_domain.redis.keys("#{custom_domain.rediskey}*")
[redis_keys_before.empty?, redis_keys_after.empty?]
#=> [false, true]

## Custom domain is removed from customer's domains upon destruction
domain_to_destroy = "destroy-test-#{SecureRandom.hex(4)}.example.com"
custom_domain = V2::CustomDomain.create(domain_to_destroy, @customer.custid)
custom_domain.destroy!(@customer)
@customer.custom_domains.member?(custom_domain.display_domain)
#=> false

# Continue writing tryouts to test additional scenarios for validation and verification

## Can create a custom domain with a domain already associated to another
## customer; each custom has a different TXT verification record.
@other_customer_email = "tryouts+other+#{SecureRandom.hex(4)}@onetimesecret.com"
@other_customer = V1::Customer.create(@other_customer_email)
conflicting_domain = "conflict-domain-#{SecureRandom.hex(4)}.example.com"
# First, create the domain with the original customer
cd1 = V2::CustomDomain.create(conflicting_domain, @customer.custid)
cd2 = V2::CustomDomain.create(conflicting_domain, @other_customer.custid)
[
  cd1.txt_validation_host == cd2.txt_validation_host,
  cd1.txt_validation_value == cd2.txt_validation_value
]
#=> [false, false]

## Testing apex? method for apex domains
apex_domain = "apex-domain-#{SecureRandom.hex(4)}.com"
custom_domain = V2::CustomDomain.create(apex_domain, @customer.custid)
custom_domain.apex?
#=> true

## Testing apex? method for subdomains
subdomain = "sub.example.com"
custom_subdomain = V2::CustomDomain.create(subdomain, @customer.custid)
custom_subdomain.apex?
#=> false

## derive_id generates consistent IDs for the same domain and customer
custom_domain1 = V2::CustomDomain.new(@apex_domain, @customer.custid)
id1 = custom_domain1.derive_id
custom_domain2 = V2::CustomDomain.new(@apex_domain, @customer.custid)
id2 = custom_domain2.derive_id
id1 == id2
#=> true

## derive_id generates different IDs for different domains or customers
custom_domain3 = V2::CustomDomain.new(@apex_domain, @customer.custid)
custom_domain3b = V2::CustomDomain.new(@apex_domain, @other_customer.custid)
id3 = custom_domain3.derive_id
id3b = custom_domain3b.derive_id
id3 == id3b
#=> false

## derive_id generates different IDs for different domains or customers
custom_domain4 = V2::CustomDomain.new(@valid_domain, @other_customer.custid)
custom_domain4b = V2::CustomDomain.new(@apex_domain, @other_customer.custid)
id4 = custom_domain4.derive_id
id4b = custom_domain4b.derive_id
id4 == id4b
#=> false

## parse_vhost returns empty hash for nil
custom_domain = V2::CustomDomain.new(@valid_domain, @customer.custid)
custom_domain.vhost = nil
custom_domain.parse_vhost
#=> {}

## parse_vhost returns empty hash for empty vhost
custom_domain = V2::CustomDomain.new(@valid_domain, @customer.custid)
custom_domain.vhost = ''
custom_domain.parse_vhost
#=> {}

## parse_vhost correctly parses valid JSON strings
custom_domain = V2::CustomDomain.new(@valid_domain, @customer.custid)
custom_domain.vhost = '{"ssl": true, "redirect": "https"}'
custom_domain.parse_vhost
#=> {"ssl"=>true, "redirect"=>"https"}

## parse_vhost returns empty hash for invalid JSON and logs the error
custom_domain = V2::CustomDomain.new(@valid_domain, @customer.custid)
custom_domain.vhost = '{invalid_json}'
parsed_vhost = custom_domain.parse_vhost
parsed_vhost.empty?
#=> true

## exists? method returns true for existing custom domains
existing_domain = "exist-test-#{SecureRandom.hex(4)}.example.com"
custom_domain_exist = V2::CustomDomain.create(existing_domain, @customer.custid)
custom_domain_exist.exists?
#=> true

## exists? method returns false for non-existing custom domains
non_existing_domain = V2::CustomDomain.new("non-exist-#{SecureRandom.hex(4)}.example.com", @customer.custid)
non_existing_domain.exists?
#=> false

## Attempting to load a non-existing custom domain raises RecordNotFound
begin
  V2::CustomDomain.load("non-existent-domain.example.com", @customer.custid)
rescue OT::RecordNotFound => e
  e.message
end
#=> "Domain not found non-existent-domain.example.com"

## Validate handling of domains with maximum subdomain depth
max_depth_subdomain = ('a.' * (V2::CustomDomain::MAX_SUBDOMAIN_DEPTH - 2)) + 'example.com'
custom_domain_depth = V2::CustomDomain.create(max_depth_subdomain, @customer.custid)
custom_domain_depth.display_domain == max_depth_subdomain
#=> true

## Exceeding maximum subdomain depth raises an error
too_deep_domain = ('a.' * V2::CustomDomain::MAX_SUBDOMAIN_DEPTH) + 'example.com'
begin
  V2::CustomDomain.create(too_deep_domain, @customer.custid)
rescue OT::Problem => e
  e.message
end
#=> "Domain too deep (max: 10)"

## Validate handling of domains with maximum total length
max_length_domain = ('a' * (V2::CustomDomain::MAX_TOTAL_LENGTH - 11)) + '.com'
custom_domain_length = V2::CustomDomain.create(max_length_domain, @customer.custid)
custom_domain_length.display_domain == max_length_domain
#=> true

## Exceeding maximum total domain length raises an error
too_long_domain = ('a' * V2::CustomDomain::MAX_TOTAL_LENGTH) + '.com'
begin
  V2::CustomDomain.create(too_long_domain, @customer.custid)
rescue OT::Problem => e
  e.message
end
#=> "Domain too long (max: 253)"

## Validate that default_domain? method works correctly 1 of 2
old_conf = OT.instance_variable_get(:@conf)
new_conf = { 'site' => { 'host' => 'default.example.com' } }
OT.instance_variable_set(:@conf, new_conf)
success = V2::CustomDomain.default_domain?('default.example.com')
OT.instance_variable_set(:@conf, old_conf)
success
#=> true

## Validate that default_domain? method works correctly 2 of 3
old_conf = OT.instance_variable_get(:@conf)
new_conf = { 'site' => { 'host' => 'default.example.com' } }
OT.instance_variable_set(:@conf, new_conf)
success = V2::CustomDomain.default_domain?('non-default.example.com')
OT.instance_variable_set(:@conf, old_conf)
success
#=> false

# Tear down
@customer.destroy!
@other_customer.destroy!

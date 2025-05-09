# tests/unit/ruby/try/20_models/27_domains_methods_try.rb

require 'securerandom'

require_relative '../test_models'

# Load the app
OT.boot! :test, false

@customer = Customer.create "Tryouts+27+#{SecureRandom.uuid}@onetimesecret.com"
@alt_customer = Customer.create "Tryouts+27+#{SecureRandom.uuid}@onetimesecret.com"
@apex_domain = 'example.com'
@subdomain = 'sub.example.com'
@nested_subdomain = 'nested.sub.example.com'

## Produces consistent identifier for the same domain and customer
email = 'same@example.com'
obj1 = CustomDomain.new(@apex_domain, email)
obj2 = CustomDomain.new(@subdomain, email)
[obj1.identifier, obj2.identifier]
#=> ["ff9755e2bbe007552ea8", "fa9939df15a1c2731be0"]

## Raises an exception for an invalid domain
begin
  CustomDomain.create('bogus_with_no_tld', @customer.custid)
rescue  => e
  [e.class, e.message]
end
#=> [Onetime::Problem, "`bogus_with_no_tld` is not a valid domain"]

## Raises an exception for duplicate domain by customer
domain = 'c.new.example.com'
CustomDomain.create(domain, @customer.custid)
begin
  CustomDomain.create(domain, @customer.custid)
rescue OT::Problem => e
  e.message
end
#=> 'Duplicate domain for customer'

## Can detect apex domain correctly
obj = CustomDomain.create(@apex_domain, "Tryouts+27+#{SecureRandom.uuid}@onetimesecret.com")
obj.apex?
#=> true

## Can detect non-apex domain correctly
obj = CustomDomain.create(@subdomain, "Tryouts+27+#{SecureRandom.uuid}@onetimesecret.com")
obj.apex?
#=> false

## Can detect nested subdomain correctly
obj = CustomDomain.create(@nested_subdomain, "Tryouts+27+#{SecureRandom.uuid}@onetimesecret.com")
obj.apex?
#=> false

## Can verify owner with customer object
email = "Tryouts+27+#{SecureRandom.uuid}@onetimesecret.com"
obj = CustomDomain.create('a.new.example.com', @customer.email)
p [:'with customer object', obj.custid, @customer.email, obj.owner?(@customer)]
obj.owner?(@customer)
#=> true

## Can verify owner with customer ID string
email = "Tryouts+27+#{SecureRandom.uuid}@onetimesecret.com"
obj = CustomDomain.create(@apex_domain, email)
obj.owner?(email)
#=> true

## Returns false for non-owner
email = "Tryouts+27+#{SecureRandom.uuid}@onetimesecret.com"
obj = CustomDomain.create('b.new.example.com', email)
obj.owner?('wrong-customer-id')
#=> false

## Can parse valid vhost JSON
email = "Tryouts+27+#{SecureRandom.uuid}@onetimesecret.com"
obj = CustomDomain.create(@apex_domain, email)
obj.vhost = '{"key": "value"}'
obj.parse_vhost
#=> {"key"=>"value"}

## Returns empty hash for empty vhost
email = "Tryouts+27+#{SecureRandom.uuid}@onetimesecret.com"
obj = CustomDomain.create(@apex_domain, email)
obj.vhost = ''
obj.parse_vhost
#=> {}

## Returns empty hash for invalid JSON in vhost
email = "Tryouts+27+#{SecureRandom.uuid}@onetimesecret.com"
obj = CustomDomain.create(@apex_domain, email)
obj.vhost = '{invalid json}'
obj.parse_vhost
#=> {}

## Generates correct validation record for apex domain
email = "Tryouts+27+#{SecureRandom.uuid}@onetimesecret.com"
obj = CustomDomain.create(@apex_domain, email)
obj.validation_record.end_with?(@apex_domain)
#=> true

## Generates correct validation record for subdomain
email = "Tryouts+27+#{SecureRandom.uuid}@onetimesecret.com"
obj = CustomDomain.create(@subdomain, email)
obj.validation_record.end_with?('example.com')
#=> true

## Can delete domain and remove from values
email = "Tryouts+27+#{SecureRandom.uuid}@onetimesecret.com"
obj = CustomDomain.create('delete-test.example.com', email)
identifier = obj.identifier
obj.delete!
CustomDomain.values.member?(identifier)
#=> false

## Can destroy domain and remove from customer's domains
obj = CustomDomain.create('destroy-test.example.com', @customer.custid)
domain = obj.display_domain
obj.destroy!(@customer)
@customer.custom_domains.member?(domain)
#=> false

## Handles long domain names
long_subdomain = 'a' * 63 + '.example.com'  # Max label length is 63 chars
obj = CustomDomain.parse(long_subdomain, @customer.custid)
obj.display_domain == long_subdomain
#=> true

## Handles domain with maximum number of levels
many_levels = (['a'] * 10).join('.') + '.com'  # Max 10 levels
begin
  cd = CustomDomain.create(many_levels, @customer.custid)
  pp [cd]
rescue OT::Problem => e
  !e.message.nil? && e.message.include?('too deep')
end
#=> true

## Handles domain with maximum length
many_labels = ('a' * 255) + '.example.com'
begin
  cd = CustomDomain.create(many_labels, @customer.custid)
  pp [cd]
rescue OT::Problem => e
  !e.message.nil? && e.message.include?('too long')
end
#=> true

## Handles domain with trailing dot
obj = CustomDomain.create('dot.example.com.', @customer.custid)
obj.display_domain
#=> "dot.example.com"

@customer.destroy!
@alt_customer.destroy!

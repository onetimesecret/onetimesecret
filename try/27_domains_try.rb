# frozen_string_literal: true

# These tryouts test domain-related functionality using the PublicSuffix gem

require 'public_suffix'

require_relative '../lib/onetime'

# Load the app
OT::Config.path = File.join(__dir__, '..', 'etc', 'config.test')
OT.boot! :app

@customer = OT::Customer.create 'Tryouts+27@onetimesecret.com'
@valid_domain = 'another.subdomain.onetimesecret.com'
@input_domains = [
  'example.com',
  'subdomain.example.com',
  @valid_domain,
  'invalid',
  'localhost',
  'user@example.com'
]

## Can parse an input domain into a base domain
@input_domains.map { |input_domain|
  begin
    OT::CustomDomain.base_domain(input_domain)

  rescue OT::Problem => e
    e.message
  end
}
#=> ["example.com", "example.com", "onetimesecret.com", nil, nil, "user@example.com"]


## Can parse an input domain into a display domain, which includes the
## subdomain if it exists.
@input_domains.map { |input_domain|
  begin
    OT::CustomDomain.display_domain(input_domain)

  rescue OT::Problem => e
    e.message
  end
}
#=> ["example.com", "subdomain.example.com", "another.subdomain.onetimesecret.com", "`invalid` is not a valid domain", "`localhost` is not a valid domain", "user@example.com"]


## Can create txt record for DNS
custom_domain = OT::CustomDomain.create(@valid_domain, @customer.custid)
host, value = OT::CustomDomain.generate_txt_validation_record(custom_domain)
[host, value.length]
#=> ["_onetime-challenge-46fbc15.another.subdomain", 32]

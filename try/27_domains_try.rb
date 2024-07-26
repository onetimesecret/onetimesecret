# frozen_string_literal: true

# These tryouts test domain-related functionality using the PublicSuffix gem

require 'public_suffix'

require_relative '../lib/onetime'

# Load the app
OT::Config.path = File.join(__dir__, '..', 'etc', 'config.test')
OT.boot! :app

@domains = [
  'example.com',
  'subdomain.example.com',
  'another.subdomain.example.co.uk',
  'invalid',
  'localhost',
  'user@example.com'
]

## Normalize domain examples
@domains.map { |domain|
  OT::CustomDomain.normalize(domain)
}
#=> ["example.com", "example.com", "example.co.uk", nil, nil, "user@example.com"]


## Can parse a domain

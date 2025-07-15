# ./tryouts/models/domains_publicsuffix_try.rb

# These tryouts test domain-related functionality using the PublicSuffix gem

require 'public_suffix'

require_relative '../helpers/test_helpers'

# Load the app
OT.boot! :test, false

# Setup
@public_suffix_list = PublicSuffix::List.default
@domains = [
  'example.com',
  'subdomain.example.com',
  'another.subdomain.example.co.uk',
  'invalid',
  'localhost',
  'user@example.com',
  'http://user@example.com'
]


## Check if a domain is valid
@domains.map { |domain| PublicSuffix.valid?(domain) }
#=> [true, true, true, false, false, true, false]

## Extract the top-level domain (TLD) from a domain
@domains.map { |domain| PublicSuffix.domain(domain) rescue nil }
#=> ["example.com", "example.com", "example.co.uk", nil, nil, "user@example.com", nil]

## Get the subdomain of a given domain
@domains.map { |domain| PublicSuffix.parse(domain)&.subdomain rescue nil }
#=> [nil, "subdomain.example.com", "another.subdomain.example.co.uk", nil, nil, nil, nil]

## Check if a domain is a subdomain
@domains.map { |domain| PublicSuffix.parse(domain)&.subdomain? rescue false }
#=> [false, true, true, false, false, false, false]

## Get the registrable domain (domain without subdomains)
@domains.map { |domain| PublicSuffix.parse(domain)&.domain rescue nil }
#=> ["example.com", "example.com", "example.co.uk", nil, nil, "user@example.com", nil]

## Check if a domain uses a public suffix
@domains.map { |domain| @public_suffix_list.find(domain) ? true : false }
#=> [true, true, true, true, true, true, true]

## Get the public suffix for a domain
@domains.map { |domain| PublicSuffix.parse(domain)&.tld rescue nil }
#=> ["com", "com", "co.uk", nil, nil, "com", nil]

## Normalize a domain (remove leading/trailing spaces, convert to lowercase)
@domains.map { |domain| PublicSuffix.normalize(domain).to_s rescue nil }
#=> ["example.com", "subdomain.example.com", "another.subdomain.example.co.uk", "invalid", "localhost", "user@example.com", "http://user@example.com is not expected to contain a scheme"]

## Explicitly forbidden, it is listed as a private domain
PublicSuffix.valid?("blogspot.com")
# => false

## Extract a domain including private domains (by default)
PublicSuffix.domain("something.blogspot.com")
#=> "something.blogspot.com"

## Extract a domain excluding private domains
PublicSuffix.domain("something.blogspot.com", ignore_private: true)
#=> "blogspot.com"

## Extract a onetimesecret including private domains (by default)
PublicSuffix.domain("status.onetimesecret.com")
#=> "onetimesecret.com"

## Extract a onetimesecret excluding private domains
PublicSuffix.domain("status.onetimesecret.com", ignore_private: true)
#=> "onetimesecret.com"

## Unknown/not-listed TLD domains are valid by default
PublicSuffix.valid?("example.tldnotlisted")
#=> true

## Unknown/not-listed TLD domains without the * rule are not valid
PublicSuffix.valid?("example.tldnotlisted", default_rule: nil)
#=> false

# Private domains are not valid with the * rule
PublicSuffix.valid?("blogspot.com")
#=> false

## Private domains without the * rule are not valid
PublicSuffix.valid?("blogspot.com", default_rule: nil)
#=> false

## Private domains are only valid (when it rains), I mean when ignoring private domains
PublicSuffix.valid?("blogspot.com", ignore_private: true)
#=> true

# Teardown (if needed)
# Add any cleanup code here

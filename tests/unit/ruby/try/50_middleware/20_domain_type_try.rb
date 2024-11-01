# frozen_string_literal: true

# These tryouts test the DomainType middleware class that handles
# domain strategy determination and validation using a state machine

require 'onetime'
require 'middleware/detect_host'
require 'onetime/middleware/domain_type'

OT::Config.path = File.join(Onetime::HOME, 'tests', 'unit', 'ruby', 'config.test.yaml')
OT.boot! :test

# In test setup
OT.conf[:site] = {
  domains: {
    enabled: true,
    default: 'onetimesecret.com'
  }
}

@canonical_domain = 'onetimesecret.com'
@valid_subdomain = 'sub.onetimesecret.com'
@invalid_subdomain = 'sub..onetimesecret.com'
@custom_domain = 'example.com'
@idn_domain = 'xn--mnchen-3ya.de'
@long_domain = "#{'a' * 64}.example.com"
@domain_with_port = 'example.com:8080'
@ip_with_port = '127.0.0.1:3000'
@ipv6 = '[2001:db8::1]'

@app = lambda { |env| [200, {}, ['OK']] }
@domain_type = Onetime::DomainType.new(@app)

# Tryouts

## DomainType determines canonical state for nil host
pp [:lop, @domain_type]
@domain_type.send(:process_domain, nil).value # access private method
#=> :canonical

## DomainType determines canonical state for matching domain
@domain_type.send(:process_domain, @canonical_domain).value
#=> :canonical

## DomainType determines subdomain state for valid subdomain
@domain_type.send(:process_domain, @valid_subdomain).value
#=> :subdomain

## DomainType determines custom state for different domain
@domain_type.send(:process_domain, @custom_domain).value
#=> :custom

## DomainType normalizes IDN domains
Onetime::DomainType::Normalizer.normalize(@idn_domain).include?('xn--')
#=> true

## DomainType rejects domains exceeding max length
Onetime::DomainType::Normalizer.normalize(@long_domain)
#=> nil

## DomainType strips ports from domain
Onetime::DomainType::Normalizer.normalize(@domain_with_port)
#=> "example.com"

## DomainType handles IP addresses with ports
Onetime::DomainType::Normalizer.normalize(@ip_with_port)
#=> "127.0.0.1"

## DomainType rejects double dots
Onetime::DomainType::Normalizer.normalize(@invalid_subdomain)
#=> nil

## DomainType validates domain parts correctly
Onetime::DomainType::Parser::Parts.new(['example', 'com']).valid?
#=> true

## DomainType rejects invalid domain parts
Onetime::DomainType::Parser::Parts.new(['exam@ple', 'com']).valid?
#=> false

## DomainType identifies valid subdomains
@domain_type.send(:is_subdomain?, @valid_subdomain, # access private method
  Onetime::DomainType::Parser.parse(@valid_subdomain))
#=> true

## DomainType rejects malicious subdomain attempts
@domain_type.send(:is_subdomain?, "#{@canonical_domain}.evil.com",
  Onetime::DomainType::Parser.parse("#{@canonical_domain}.evil.com"))
#=> false

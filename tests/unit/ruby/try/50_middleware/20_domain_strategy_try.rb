# frozen_string_literal: true

# These tryouts test the DomainStrategy middleware class that handles
# domain strategy determination and validation using a state machine

require 'onetime'
require 'middleware/detect_host'
require 'onetime/middleware/domain_strategy'

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
@domain_strategy = Onetime::DomainStrategy.new(@app)

# Tryouts

## DomainStrategy determines canonical state for nil host
pp [:lop, @domain_strategy]
@domain_strategy.send(:process_domain, nil).value # access private method
#=> :canonical

## DomainStrategy determines canonical state for matching domain
@domain_strategy.send(:process_domain, @canonical_domain).value
#=> :canonical

## DomainStrategy determines subdomain state for valid subdomain
@domain_strategy.send(:process_domain, @valid_subdomain).value
#=> :subdomain

## DomainStrategy determines custom state for different domain
@domain_strategy.send(:process_domain, @custom_domain).value
#=> :custom

## DomainStrategy normalizes IDN domains
Onetime::DomainStrategy::Normalizer.normalize(@idn_domain).include?('xn--')
#=> true

## DomainStrategy rejects domains exceeding max length
Onetime::DomainStrategy::Normalizer.normalize(@long_domain)
#=> nil

## DomainStrategy strips ports from domain
Onetime::DomainStrategy::Normalizer.normalize(@domain_with_port)
#=> "example.com"

## DomainStrategy handles IP addresses with ports
Onetime::DomainStrategy::Normalizer.normalize(@ip_with_port)
#=> "127.0.0.1"

## DomainStrategy rejects double dots
Onetime::DomainStrategy::Normalizer.normalize(@invalid_subdomain)
#=> nil

## DomainStrategy validates domain parts correctly
Onetime::DomainStrategy::Parser::Parts.new(['example', 'com']).valid?
#=> true

## DomainStrategy rejects invalid domain parts
Onetime::DomainStrategy::Parser::Parts.new(['exam@ple', 'com']).valid?
#=> false

## DomainStrategy identifies valid subdomains
@domain_strategy.send(:is_subdomain?, @valid_subdomain, # access private method
  Onetime::DomainStrategy::Parser.parse(@valid_subdomain))
#=> true

## DomainStrategy rejects malicious subdomain attempts
@domain_strategy.send(:is_subdomain?, "#{@canonical_domain}.evil.com",
  Onetime::DomainStrategy::Parser.parse("#{@canonical_domain}.evil.com"))
#=> false

## DomainStrategy class method 'normalize_canonical_domain' returns the correct normalized domain
@config_with_domains = {
  domains: {
    enabled: true,
    default: ' OnetimeSecret.Com '
  }
}
Onetime::DomainStrategy.normalize_canonical_domain(@config_with_domains)
#=> 'onetimesecret.com'

## DomainStrategy 'normalize_canonical_domain' handles missing default domain
@config_without_default = {
  domains: {
    enabled: true
  }
}
Onetime::DomainStrategy.normalize_canonical_domain(@config_without_default)
#=> nil

## DomainStrategy 'normalize_canonical_domain' when domains are disabled uses host from config
@config_domains_disabled = {
  domains: {
    enabled: false,
    default: 'onetimesecret.com'
  },
  host: ' backupdomain.com '
}
Onetime::DomainStrategy.normalize_canonical_domain(@config_domains_disabled)
#=> 'backupdomain.com'

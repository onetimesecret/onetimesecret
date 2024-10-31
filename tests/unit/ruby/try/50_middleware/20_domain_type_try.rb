# frozen_string_literal: true

# These tryouts test the DomainType middleware class that handles
# domain strategy determination and validation


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

## DomainType determines canonical strategy for nil host
pp [:lop, @domain_type]
@domain_type.determine_domain_strategy(nil)
#=> :canonical

## DomainType determines canonical strategy for matching domain
@domain_type.determine_domain_strategy(@canonical_domain)
#=> :canonical

## DomainType determines subdomain strategy for valid subdomain
@domain_type.determine_domain_strategy(@valid_subdomain)
#=> :subdomain

## DomainType determines custom strategy for different domain
@domain_type.determine_domain_strategy(@custom_domain)
#=> :custom

## DomainType normalizes IDN domains
@domain_type.send(:normalize_host, @idn_domain).include?('xn--')
#=> true

## DomainType rejects domains exceeding max length
@domain_type.send(:normalize_host, @long_domain)
#=> nil

## DomainType strips ports from domain
@domain_type.send(:normalize_host, @domain_with_port)
#=> "example.com"

## DomainType handles IP addresses with ports
@domain_type.send(:normalize_host, @ip_with_port)
#=> "127.0.0.1"

## DomainType rejects double dots
@domain_type.send(:normalize_host, @invalid_subdomain)
#=> nil

## DomainType validates domain parts correctly
@domain_type.send(:valid_domain_parts?, ['example', 'com'])
#=> true

## DomainType rejects invalid domain parts
@domain_type.send(:valid_domain_parts?, ['exam@ple', 'com'])
#=> false

## DomainType identifies valid subdomains
@domain_type.send(:is_valid_subdomain?, @valid_subdomain, @valid_subdomain.split('.'), @canonical_domain.split('.'))
#=> true

## DomainType rejects malicious subdomain attempts
@domain_type.send(:is_valid_subdomain?, "#{@canonical_domain}.evil.com", "#{@canonical_domain}.evil.com".split('.'), @canonical_domain.split('.'))
#=> false

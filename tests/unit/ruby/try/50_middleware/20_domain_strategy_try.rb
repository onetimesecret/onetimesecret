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

## DomainStrategy chooses invlaid state when input host is nil
Onetime::DomainStrategy::Chooserator.choose_strategy(nil, @canonical_domain)
#=> :canonical

## DomainStrategy normalizes IDN domains
Onetime::DomainStrategy::Parser.normalize(@idn_domain).include?('xn--')
#=> true

## DomainStrategy rejects domains exceeding max length
Onetime::DomainStrategy::Parser.normalize(@long_domain)
#=> nil

## DomainStrategy class method 'normalize_canonical_domain' returns the correct normalized domain
@config_with_domains = {
  domains: {
    enabled: true,
    default: ' OnetimeSecret.Com '
  }
}
Onetime::DomainStrategy.get_canonical_domain(@config_with_domains)
#=> 'onetimesecret.com'

## DomainStrategy rejects domains exceeding max length
Onetime::DomainStrategy::Chooserator.choose_strategy(@valid_subdomain, @canonical_domain)
#=> :subdomain

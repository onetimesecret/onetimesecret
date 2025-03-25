# tests/unit/ruby/try/50_middleware/22_domain_strategy_chooserator_try.rb

require_relative '../test_helpers'
require 'middleware/detect_host'
require 'onetime/middleware/domain_strategy'

@base_domain = 'example.com'
@canonical = PublicSuffix.parse(@base_domain)

## equal_to? matches exact domains
Onetime::DomainStrategy::Chooserator.equal_to?(
  PublicSuffix.parse('example.com'),
  @canonical
)
#=> true

## equal_to? matches case-insensitive domains
Onetime::DomainStrategy::Chooserator.equal_to?(
  PublicSuffix.parse('EXAMPLE.COM'),
  @canonical
)
#=> true

## equal_to? matches www subdomain
Onetime::DomainStrategy::Chooserator.equal_to?(
  PublicSuffix.parse('www.example.com'),
  @canonical
)
#=> true

## equal_to? rejects different domains
Onetime::DomainStrategy::Chooserator.equal_to?(
  PublicSuffix.parse('different.com'),
  @canonical
)
#=> false

## peer_of? matches sibling subdomains
Onetime::DomainStrategy::Chooserator.peer_of?(
  PublicSuffix.parse('blog.example.com'),
  PublicSuffix.parse('shop.example.com')
)
#=> true

## peer_of? rejects different base domains
Onetime::DomainStrategy::Chooserator.peer_of?(
  PublicSuffix.parse('blog.example.com'),
  PublicSuffix.parse('blog.different.com')
)
#=> false

## parent_of? matches parent to child relationship
Onetime::DomainStrategy::Chooserator.parent_of?(
  PublicSuffix.parse('example.com'),
  PublicSuffix.parse('sub.example.com')
)
#=> true

## parent_of? matches parent to child relationship (configured eu.example.com)
Onetime::DomainStrategy::Chooserator.parent_of?(
  PublicSuffix.parse('example.com'),
  PublicSuffix.parse('eu.example.com')
)
#=> true

## parent_of? matches parent to child relationship (configured example.com)
Onetime::DomainStrategy::Chooserator.subdomain_of?(
  PublicSuffix.parse('eu.example.com'),
  PublicSuffix.parse('example.com')
)
#=> true

## parent_of? rejects unrelated domains
Onetime::DomainStrategy::Chooserator.parent_of?(
  PublicSuffix.parse('example.com'),
  PublicSuffix.parse('other.com')
)
#=> false

## subdomain_of? matches child to parent relationship
Onetime::DomainStrategy::Chooserator.subdomain_of?(
  PublicSuffix.parse('sub.example.com'),
  PublicSuffix.parse('example.com')
)
#=> true

## subdomain_of? matches deep subdomains
Onetime::DomainStrategy::Chooserator.subdomain_of?(
  PublicSuffix.parse('deep.sub.example.com'),
  PublicSuffix.parse('example.com')
)
#=> true

## subdomain_of? rejects same domain
Onetime::DomainStrategy::Chooserator.subdomain_of?(
  PublicSuffix.parse('example.com'),
  PublicSuffix.parse('example.com')
)
#=> false

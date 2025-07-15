# ./tryouts/middleware/domain_strategy_try.rb

# These tryouts test the DomainStrategy middleware class that handles
# domain strategy determination and validation using a state machine

require_relative '../helpers/test_models'

require 'middleware/detect_host'
require 'onetime/middleware/domain_strategy'

OT.boot! :test, false

# In test setup

new_conf = {
  domains: {
    enabled: true,
    default: 'onetimesecret.com'
  }
}
OT.instance_variable_set(:@conf, new_conf)

@canonical_domain = 'onetimesecret.com'
@customer_id = 'cus_test1234' + rand(36**5).to_s(36)
@chooser = Onetime::DomainStrategy::Chooserator
@delete_domains = []

# Tryouts


## Creates custom domain with base domain
custom_domain = CustomDomain.create('example.com', @customer_id)
@delete_domains << custom_domain
@chooser.choose_strategy(custom_domain.display_domain, @canonical_domain)
#=> :custom

## Creates custom domain with subdomain
custom_domain = CustomDomain.create('app.example.com', @customer_id)
@delete_domains << custom_domain
@chooser.choose_strategy(custom_domain.display_domain, @canonical_domain)
#=> :custom

## Creates custom domain with multiple subdomains
custom_domain = CustomDomain.create('dev.app.example.com', @customer_id)
@delete_domains << custom_domain
@chooser.choose_strategy(custom_domain.display_domain, @canonical_domain)
#=> :custom

## Creates custom domain that matches canonical domain
custom_domain = CustomDomain.create(@canonical_domain, @customer_id)
@delete_domains << custom_domain
@chooser.choose_strategy(custom_domain.display_domain, @canonical_domain)
#=> :canonical

## parent_of? matches parent to child relationship (configured onetimesecret.com)
custom_domain = CustomDomain.create('fr.example.com', @customer_id)
@delete_domains << custom_domain
@chooser.known_custom_domain?(custom_domain.display_domain)
#=> true


# Teardown
@delete_domains.map { |d|
  OT.ld "Deleting custom domain: #{d}"
  d.destroy!
}

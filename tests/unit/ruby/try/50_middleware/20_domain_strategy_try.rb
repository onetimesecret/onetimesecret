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
@customer_id = 'cus_test1234' + rand(36**5).to_s(36)
@chooser = Onetime::DomainStrategy::Chooserator
@delete_domains = []

# Tryouts


## Creates custom domain with base domain
custom_domain = Onetime::CustomDomain.create('example.com', @customer_id)
@delete_domains << custom_domain
@chooser.choose_strategy(custom_domain.display_domain, @canonical_domain)
#=> :custom

## Creates custom domain with subdomain
custom_domain = Onetime::CustomDomain.create('app.example.com', @customer_id)
@delete_domains << custom_domain
@chooser.choose_strategy(custom_domain.display_domain, @canonical_domain)
#=> :custom

## Creates custom domain with multiple subdomains
custom_domain = Onetime::CustomDomain.create('dev.app.example.com', @customer_id)
@delete_domains << custom_domain
@chooser.choose_strategy(custom_domain.display_domain, @canonical_domain)
#=> :custom

## Creates custom domain that matches canonical domain
custom_domain = Onetime::CustomDomain.create(@canonical_domain, @customer_id)
@delete_domains << custom_domain
@chooser.choose_strategy(custom_domain.display_domain, @canonical_domain)
#=> :canonical

# Teardown
@delete_domains.map { |d|
  OT.ld "Deleting custom domain: #{d}"
  d.destroy!
}

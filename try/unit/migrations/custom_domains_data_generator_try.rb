require_relative '../../support/test_models'
require_relative '../../../migrations/core/custom_domains_to_orgs_data_generator'

begin
  OT.boot! :test, false
rescue Redis::CannotConnectError, Redis::ConnectionError => e
  puts "SKIP: Requires Redis connection (#{e.class})"
  exit 0
end

## Generate test data
@stats = Onetime::Migration::CustomDomainsToOrgsDataGenerator.generate_test_data
@stats.class
#=> Hash

## Customers created
@stats[:customers]
#=> 8

## Organizations created (scenario 1: 3, scenario 2: 1, scenario 3: 2, scenario 4: 1)
@stats[:organizations]
#=> 7

## Domains created (scenario 1: 6, scenario 2: 10, scenario 4: 2)
@stats[:domains]
#=> 18

## Verify customer data exists in Redis
Customer.dbclient.keys('customer:*').size >= 8
#=> true

## All customers have at least one organization
customer_keys = Customer.dbclient.keys('customer:*')
customer_keys.map { |k| Customer.load(k.split(':').last) }.compact.all? { |c| c.organization_instances.any? }
#=> true

## Verify domain data exists in Redis
CustomDomain.dbclient.keys('customdomain:*').size >= 18
#=> true

## Sample a domain to verify org_id is set
sample_domain_key = CustomDomain.dbclient.keys('customdomain:*').first
domain_data = CustomDomain.dbclient.hgetall(sample_domain_key)
!domain_data['org_id'].nil? && !domain_data['org_id'].empty?
#=> true

## Data generation completed successfully
@stats[:domains] > 0 && @stats[:customers] > 0 && @stats[:organizations] > 0
#=> true

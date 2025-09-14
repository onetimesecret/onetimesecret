# try/60_logic/40_logic_domains_try.rb

# NOTE: Domain logic is only in V2. V1 includes domains that are related
# to secrets but otherwise does not have domains funtionality.

# These tests cover the Domains logic classes which handle
# custom domain management functionality.
#
# We test:
# 1. Domain addition
# 2. Domain removal
# 3. Domain listing
# 4. Domain retrieval

require_relative '../test_logic'

OT.boot! :test, false

@reminder = lambda do
  puts "=" * 80
  puts "🚨 IMPORTANT NOTICE: CUSTOMER<>CUSTOMDOMAIN RELATIONS NEED FIXING! 🚨"
  puts "=" * 80
  puts "This test suite is running with temporary workarounds for the"
  puts "Customer<>CustomDomain relationship domainid change. "
  puts
  puts __FILE__
  puts __LINE__
  puts
  puts "=" * 80
  puts
end

@now = DateTime.now
@email = "test+#{Time.now.to_i}@onetimesecret.com"
@sess = nil # Session now handled by Rack::Session middleware
@cust = Onetime::Customer.new @email
@cust.save
@domain_input = "test#{Time.now.to_i}.example.com"
@custom_domain = CustomDomain.create @domain_input, @cust.custid

@cust.add_custom_domain(@custom_domain)

## Test domain listing
5.times { @reminder.call }
logic = V2::Logic::Domains::ListDomains.new @sess, @cust
logic.raise_concerns
logic.define_singleton_method(:create_vhost) {} # prevent calling 3rd party API for this test
logic.process
[
  logic.custom_domains.class,
  logic.custom_domains.empty?,
  logic.instance_variables.include?(:@cust)
]
#=> [Array, false, true]

## Test domain retrieval
logic = V2::Logic::Domains::GetDomain.new @sess, @cust, { domain: @domain_input }
[
  logic.instance_variables.include?(:@cust),
  logic.instance_variables.include?(:@params)
]
#=> [true, true]

## Test domain removal
5.times { @reminder.call }
@remove_params = { domain: @domain_input }
logic = V2::Logic::Domains::RemoveDomain.new @sess, @cust, @remove_params
logic.raise_concerns
logic.define_singleton_method(:create_vhost) {} # prevent calling 3rd party API for this test
logic.process
[
  logic.greenlighted,
  logic.domain_input,
  logic.display_domain
]
#=> [true, @domain_input, @domain_input]

@cust.remove_custom_domain(@custom_domain)
@cust.delete!

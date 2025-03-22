# frozen_string_literal: true

# These tests cover the Domains logic classes which handle
# custom domain management functionality.
#
# We test:
# 1. Domain addition
# 2. Domain removal
# 3. Domain listing
# 4. Domain retrieval

require 'onetime'
require 'securerandom'

# Load the app with test configuration
OT::Config.path = File.join(Onetime::HOME, 'tests', 'unit', 'ruby', 'config.test.yaml')
OT.boot! :test

# Setup common test variables
@now = DateTime.now
@email = "test#{SecureRandom.uuid}@onetimesecret.com"
@sess = OT::Session.new '255.255.255.255', 'anon'
@cust = OT::Customer.new @email
@cust.save
@domain_input = 'test.example.com'
@domain_input2 = 'test2.example.com'
@custom_domain = V2::CustomDomain.create @domain_input, @cust.custid
@cust.add_custom_domain @custom_domain

# AddDomain Tests

## Test successful domain addition

@add_params = { domain: @domain_input2 }
logic = OT::Logic::Domains::AddDomain.new @sess, @cust, @add_params
logic.raise_concerns
logic.define_singleton_method(:create_vhost) {} # prevent calling 3rd party API for this test
logic.process
[
  logic.greenlighted,
  logic.custom_domain.display_domain,
  logic.instance_variables.include?(:@cust)
]
#=> [true, @domain_input2, true]

## Test empty domain input
begin
  @add_params = { domain: '' }
  logic = OT::Logic::Domains::AddDomain.new @sess, @cust, @add_params
  logic.raise_concerns
rescue OT::FormError => e
  [e.class.name, e.message]
end
#=> ['Onetime::FormError', 'Please enter a domain']

## Test invalid domain format
begin
  @add_params = { domain: 'not-a-valid-domain' }
  logic = OT::Logic::Domains::AddDomain.new @sess, @cust, @add_params
  logic.raise_concerns
rescue OT::FormError => e
  [e.class.name, e.message]
end
#=> ['Onetime::FormError', 'Not a valid public domain']

## Test duplicate domain addition
begin
  # First addition
  @add_params = { domain: 'duplicate.example.com' }
  logic = OT::Logic::Domains::AddDomain.new @sess, @cust, @add_params
  logic.raise_concerns
  logic.process

  # Second addition of same domain
  logic2 = OT::Logic::Domains::AddDomain.new @sess, @cust, @add_params
  logic2.raise_concerns
rescue OT::Problem => e
  [e.class.name, e.message]
end
#=> ['Onetime::FormError', "Duplicate domain"]

## Test success data structure
@add_params = { domain: 'success-data.example.com' }
logic = OT::Logic::Domains::AddDomain.new @sess, @cust, @add_params
logic.raise_concerns
logic.define_singleton_method(:create_vhost) {}
logic.process
success_data = logic.success_data
[
  success_data.key?(:custid),
  success_data.key?(:record),
  success_data.key?(:details),
  success_data[:details].key?(:cluster)
]
#=> [true, true, true, true]

## Test vhost creation error handling
@add_params = { domain: 'vhost-error.example.com' }
logic = OT::Logic::Domains::AddDomain.new @sess, @cust, @add_params
logic.raise_concerns
logic.define_singleton_method(:create_vhost) { raise HTTParty::ResponseError.new('test error') }
begin
  logic.process
  [true, logic.greenlighted] # Should still complete despite vhost error
rescue StandardError
  [false] # Should not reach here
end
#=> [true, true]

## Test domain normalization
email = "test#{SecureRandom.uuid}@onetimesecret.com"
cust = OT::Customer.new email
@add_params = { domain: '  TEST.EXAMPLE.COM  ' }
logic = OT::Logic::Domains::AddDomain.new @sess, cust, @add_params
logic.raise_concerns
[
  logic.greenlighted,  # nil b/c logic.process hasn't been called
  logic.display_domain == 'test.example.com'
]
#=> [nil, true]

# Cleanup test data
@cust.remove_custom_domain(@custom_domain)
@cust.destroy!
@custom_domain.destroy!

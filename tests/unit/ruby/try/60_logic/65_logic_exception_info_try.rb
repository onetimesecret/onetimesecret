# frozen_string_literal: true

require 'onetime'
require 'securerandom'

# Setup
OT::Config.path = File.join(Onetime::HOME, 'tests', 'unit', 'ruby', 'config.test.yaml')
OT.boot! :test

@now = DateTime.now
@email = "test#{SecureRandom.uuid}@onetimesecret.com"
@sess = OT::Session.new '255.255.255.255', 'anon'
@environment = 'test'
@cust = OT::Customer.new @email
@cust.save

## Basic Exception Logging

# Successful exception report
@exception_params = {
  message: 'Test error occurred',
  type: 'StandardError',
  stack: "line1\nline2\nline3",
  url: 'https://example.com/test',
  line: 42,
  column: 10,
  environment: @environment,
  release: '1.0.0'
}
logic = OT::Logic::Misc::ReceiveException.new @sess, @cust, @exception_params
logic.process
[
  logic.greenlighted,
  logic.success_data[:record][:key].nil?,
  logic.success_data[:record][:environment],
  logic.success_data[:details][:message]
]
#=> [true, false, 'test', "Exception logged"]

## Exception Data Validation

# Prevent empty exception message
begin
  empty_params = @exception_params.merge(message: '')
  logic = OT::Logic::Misc::ReceiveException.new @sess, @cust, empty_params
  logic.raise_concerns
rescue OT::FormError => e
  [e.class.name, e.message]
end
#=> ['Onetime::FormError', 'Exception data required']

## Exception Model Serialization

# Verify ExceptionInfo safe dump fields
exception = OT::ExceptionInfo.new
exception.apply_fields(**@exception_params)
exception.save

dumped_data = exception.to_h
p [:keys, dumped_data.keys]
[
  dumped_data.key?(:key),
  dumped_data.key?(:timestamp),
  dumped_data.key?(:user_agent),
  dumped_data.key?(:environment)
]
#=> [true, true, true, true]

## Exception Querying

# Query recent exceptions
ret = OT::ExceptionInfo.recent(1.minute)
pp [:recent, ret]
ret.any?
#=> true

# Teardown
@cust.destroy!

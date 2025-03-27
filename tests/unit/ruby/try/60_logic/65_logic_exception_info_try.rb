# tests/unit/ruby/try/60_logic/65_logic_exception_info_try.rb

require_relative '../test_logic'
require 'securerandom'

# Setup
OT.boot! :test, false

@now = DateTime.now
@email = "test#{SecureRandom.uuid}@onetimesecret.com"
@sess = Session.new '255.255.255.255', 'anon'
@environment = 'test'
@cust = Customer.new @email
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
logic = Logic::ReceiveException.new @sess, @cust, @exception_params
logic.process
[
  logic.greenlighted,
  logic.success_data[:record][:identifier].nil?,
  logic.success_data[:record][:environment],
  logic.success_data[:details][:message]
]
#=> [true, false, 'test', "Exception logged"]

## Test valid exception

params = {
  message: "Test error",
  type: "TypeError",
  stack: "Error\n  at line 1\n  at line 2",
  url: "https://example.com/test",
  line: 42,
  column: 10,
  user_agent: "Mozilla/5.0",
  environment: @environment,
  release: "1.0.0"
}
logic = Logic::ReceiveException.new @sess, @cust, params
logic.process_params
logic.process
[
  logic.greenlighted,
  logic.success_data[:record][:identifier].nil?,
  logic.success_data[:record][:environment],
  logic.success_data[:details][:message]
]
#=> [true, false, 'test', "Exception logged"]

## Test truncates long values

long_params = {
  message: "x" * 2000,
  type: "y" * 200,
  stack: "z" * 20000,
  url: "u" * 2000
}
logic = Logic::ReceiveException.new @sess, @cust, long_params
logic.process_params
data = logic.instance_variable_get(:@exception_data)
[
  data[:message].length,
  data[:type].length,
  data[:stack].length,
  data[:url].length
]
#=> [256, 100, 2500, 256]

## Test rate limiting
V1::RateLimit.register_event(:report_exception, 3)
V2::RateLimit.register_event(:report_exception, 3)
params = { message: "Test", type: "Error", url: "https://status.onetime.co" }
begin
  # Submit multiple exceptions quickly
  4.times do
    logic = Logic::ReceiveException.new @sess, @cust, params
    logic.process_params
    logic.raise_concerns
  end
rescue OT::LimitExceeded => e
  e.class.name
end
#=> 'Onetime::LimitExceeded'

## Exception Data Validation

# Prevent empty exception message
begin
  empty_params = @exception_params.merge(message: '')
  logic = Logic::ReceiveException.new @sess, @cust, empty_params
  logic.raise_concerns
rescue OT::FormError => e
  [e.class.name, e.message]
end
#=> ['Onetime::FormError', 'Exception data required']

## Exception Model Serialization

# Verify ExceptionInfo safe dump fields
exception = ExceptionInfo.new
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
ret = ExceptionInfo.recent(1.minute)
ret.any?
#=> true

# Teardown
@cust.destroy!


require 'test/unit'
require_relative 'test/helper'

# Add test files here
require_relative 'logic/tests/exception_test'
require_relative 'app/api/v2/tests/api_test'

# Run the tests
Test::Unit::AutoRunner.run

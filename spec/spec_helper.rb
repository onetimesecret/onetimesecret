# spec/spec_helper.rb

require 'rspec'

RSpec.configure do |config|
  config.expect_with :rspec do |expectations|
    # Use default expectations configuration
  end

  config.mock_with :rspec do |mocks|
    mocks.verify_partial_doubles = true
  end

  config.filter_run_when_matching :focus
  config.warnings = false
  config.order = :random
  Kernel.srand config.seed
end

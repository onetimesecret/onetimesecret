# frozen_string_literal: true

require 'bundler/setup'
require_relative '../lib/onetime'

# Use test configuration
OT::Configurator.path = File.join(__dir__, '../tests/unit/ruby/config.test.yaml')
OT.boot! :test

RSpec.configure do |config|
  config.expect_with :rspec do |expectations|
    expectations.include_chain_clauses_in_custom_matcher_descriptions = true
  end

  config.mock_with :rspec do |mocks|
    mocks.verify_partial_doubles = true
  end

  config.shared_context_metadata_behavior = :apply_to_host_groups
  config.filter_run_when_matching :focus
  config.example_status_persistence_file_path = "spec/.rspec_status"
  config.disable_monkey_patching!
  config.warnings = true

  if config.files_to_run.one?
    config.default_formatter = "doc"
  end

  config.profile_examples = 10
  config.order = :random
  Kernel.srand config.seed

  # Load support files
  Dir[File.join(__dir__, 'support', '**', '*.rb')].sort.each { |f| require f }
end

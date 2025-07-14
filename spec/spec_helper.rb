# spec/spec_helper.rb

require 'bundler/setup'
require_relative '../lib/onetime'

# This tells OT::Configurator#load_with_impunity! to look in the preset list
# of paths to look for config, find a config that matches this basename.
# See ./tests/unit/ruby/rspec/onetime/configurator_spec.rb
ENV['ONETIME_CONFIG_FILE_BASENAME'] = 'config.test'

Warning[:deprecated] = true if ['development', 'dev', 'test'].include?(ENV['RACK_ENV'])

RSpec.configure do |config|
  config.expect_with :rspec do |expectations|
    expectations.include_chain_clauses_in_custom_matcher_descriptions = true
  end

  config.mock_with :rspec do |mocks|
    mocks.verify_partial_doubles = true
  end

  config.warnings                             = true
  config.shared_context_metadata_behavior     = :apply_to_host_groups
  config.example_status_persistence_file_path = 'spec/.rspec_status'
  config.filter_run_when_matching :focus
  config.disable_monkey_patching!


  config.default_formatter = 'doc' if config.files_to_run.one?

  config.profile_examples = 10
  config.order            = :random
  Kernel.srand config.seed

  # Load support files
  Dir[File.join(__dir__, 'support', '**', '*.rb')].sort.each { |f| require f }
end

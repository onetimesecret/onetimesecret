# spec/spec_helper.rb

require 'bundler/setup'
require 'rsfc'

# Configure RSFC for testing
RSFC.configure do |config|
  config.default_locale = 'en'
  config.app_environment = 'test'
  config.development_enabled = false
  config.template_paths = [File.join(__dir__, 'fixtures', 'templates')]
  config.cache_templates = false
  config.features = { test_feature: true }
end

RSpec.configure do |config|
  # Enable flags like --only-failures and --next-failure
  config.example_status_persistence_file_path = ".rspec_status"

  # Disable RSpec exposing methods globally on Module and main
  config.disable_monkey_patching!

  config.expect_with :rspec do |c|
    c.syntax = :expect
  end

  # Reset RSFC configuration between tests
  config.before(:each) do
    RSFC.reset_configuration!
    RSFC.configure do |rsfc_config|
      rsfc_config.default_locale = 'en'
      rsfc_config.app_environment = 'test'
      rsfc_config.development_enabled = false
      rsfc_config.template_paths = [File.join(__dir__, 'fixtures', 'templates')]
      rsfc_config.cache_templates = false
      rsfc_config.features = { test_feature: true }
    end
  end
end
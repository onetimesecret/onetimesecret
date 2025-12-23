# spec/support/vcr_config.rb
#
# NOTE: Billing tests use apps/web/billing/spec/support/vcr_setup.rb instead,
# with cassettes stored in apps/web/billing/spec/fixtures/vcr_cassettes/
#
# frozen_string_literal: true

require 'vcr'

VCR.configure do |config|
  config.cassette_library_dir = 'spec/cassettes'
  config.hook_into :webmock
  config.ignore_localhost = true

  # Configure VCR to work well with RSpec
  config.configure_rspec_metadata!

  # Allow real HTTP connections when no cassette is loaded
  # This is useful for integration tests that use Rack::Test
  config.allow_http_connections_when_no_cassette = true

  # Filter sensitive data from cassettes
  config.filter_sensitive_data('<STRIPE_API_KEY>') { ENV['STRIPE_API_KEY'] }
  config.filter_sensitive_data('<STRIPE_SECRET_KEY>') { ENV['STRIPE_SECRET_KEY'] }
  config.filter_sensitive_data('<SENTRY_DSN>') { ENV['SENTRY_DSN'] }

  # Default record mode - use :new_episodes to record new HTTP interactions
  # while playing back existing ones
  config.default_cassette_options = {
    record: :new_episodes,
    match_requests_on: %i[method uri body]
  }
end

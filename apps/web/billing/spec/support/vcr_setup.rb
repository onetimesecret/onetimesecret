# spec/support/vcr_setup.rb
#
# frozen_string_literal: true

#
# VCR configuration for recording/replaying HTTP interactions with Stripe API.
#
# Usage Modes:
#
# 1. Record new cassettes (uses REAL Stripe test API):
#    STRIPE_API_KEY=sk_test_xxx bundle exec rspec
#
# 2. Replay recorded cassettes (default):
#    bundle exec rspec
#
# 3. Force re-recording:
#    VCR_MODE=all bundle exec rspec
#
# Cassettes are stored in: spec/fixtures/vcr_cassettes/

require 'vcr'
require 'webmock'

spec_root = File.expand_path('..', __dir__)

module VCRHelper
  # Determine VCR record mode based on environment
  def self.record_mode
    mode = ENV.fetch('VCR_MODE', nil)

    return mode.to_sym if mode

    # Default to :new_episodes for integration tests
    # This allows recording new requests while replaying existing ones
    :new_episodes
  end
end

VCR.configure do |config|
  # Store cassettes in spec/fixtures/vcr_cassettes/
  config.cassette_library_dir = File.join(spec_root, 'fixtures', 'vcr_cassettes')

  # Use webmock for HTTP stubbing
  config.hook_into :webmock

  # Default cassette options
  config.default_cassette_options = {
    record: VCRHelper.record_mode,
    match_requests_on: [:method, :uri, :body],
    allow_playback_repeats: true,
  }

  # Filter sensitive data from cassettes
  config.filter_sensitive_data('<STRIPE_API_KEY>') do |interaction|
    if interaction.request.headers['Authorization']
      interaction.request.headers['Authorization'].first
    end
  end

  # Preserve exact body matching for Stripe requests
  config.preserve_exact_body_bytes do |http_message|
    http_message.body.encoding.name == 'ASCII-8BIT' ||
      !http_message.body.valid_encoding?
  end

  # Allow connections to stripe-mock server AND real Stripe API
  config.ignore_localhost = false
  # Don't ignore localhost - we want to record stripe-mock requests too
  # config.ignore_hosts 'localhost', '127.0.0.1'

  # Configure for different Stripe endpoints
  config.before_record do |interaction|
    # Normalize Stripe API version headers
    interaction.request.headers['Stripe-Version']  = ['<STRIPE_VERSION>']
    interaction.response.headers['Stripe-Version'] = ['<STRIPE_VERSION>']

    # Remove request ID headers (unique per request)
    interaction.response.headers.delete('Request-Id')
    interaction.response.headers.delete('Stripe-Request-Id')
  end
end

# WebMock configuration
WebMock.disable_net_connect!(
  allow_localhost: true,
  allow: [
    'localhost:12111', # stripe-mock server
    '127.0.0.1:12111',
  ],
)

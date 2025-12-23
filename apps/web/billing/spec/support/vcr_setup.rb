# apps/web/billing/spec/support/vcr_setup.rb
#
# frozen_string_literal: true

# VCR configuration for recording/replaying HTTP interactions with Stripe API.
#
# Usage Modes:
#
# 1. Record new cassettes (uses REAL Stripe test API):
#    STRIPE_API_KEY=sk_test_xxx pnpm run test:rspec
#
# 2. Replay recorded cassettes (default):
#    pnpm run test:rspec
#
# 3. Force re-recording:
#    VCR_MODE=all pnpm run test:rspec
#
# Cassettes are stored in: spec/fixtures/vcr_cassettes/
#
# VCR modes:
#
#   Mode         | Behavior
#  --------------|---------------------------------------
#   all          | Re-record all requests
#   new_episodes | Replay existing, record new (default)
#   none         | Playback only, error if missing
#   once         | Record once, then playback forever

require 'vcr'
require 'webmock'

spec_root = File.expand_path('..', __dir__)

module VCRHelper
  # Determine VCR record mode based on environment
  def self.record_mode
    mode = ENV.fetch('VCR_MODE', nil)

    return mode.to_sym if mode

    # In CI, use :none mode to fail fast if cassette is missing
    # This prevents flaky tests from attempting real API calls
    return :none if ENV['CI']

    # Default to :new_episodes for local development
    # This allows recording new requests while replaying existing ones
    :new_episodes
  end
end

# Guard: Require STRIPE_API_KEY when recording new cassettes
# Prevents flaky failures from attempting to record without credentials
if %w[all record].include?(ENV['VCR_MODE'])
  unless ENV['STRIPE_API_KEY'].to_s.strip != ''
    warn 'SKIP: VCR_MODE=%s requires STRIPE_API_KEY to record cassettes' % ENV['VCR_MODE']
    exit 0
  end
end

# Skip billing specs that require VCR in CI if cassettes may be invalid
# Re-record cassettes locally with: STRIPE_API_KEY=sk_test_xxx VCR_MODE=all bundle exec rspec
BILLING_VCR_SKIP_IN_CI = ENV['CI'] && !ENV['STRIPE_API_KEY']

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

  # Allow connections to real Stripe API for VCR recording
  config.ignore_localhost = true

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
if ENV['CI']
  # In CI, block ALL external connections - cassettes must exist
  WebMock.disable_net_connect!(allow_localhost: true)
else
  # Allow Stripe API for VCR recording locally
  WebMock.disable_net_connect!(
    allow_localhost: true,
    allow: [
      'api.stripe.com',     # Real Stripe API (for VCR recording)
      /\.stripe\.com\z/,    # All Stripe subdomains (anchored)
    ],
  )
end

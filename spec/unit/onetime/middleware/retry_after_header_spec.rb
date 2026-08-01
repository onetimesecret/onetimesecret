# spec/unit/onetime/middleware/retry_after_header_spec.rb
#
# frozen_string_literal: true

# Security audit 2026-07-30, finding #2, residual 2: a 429 carried retry_after
# in the JSON body only, so proxies and well-behaved clients — which read the
# HTTP header — had no back-off cue. The value is stashed in env by
# ErrorCorrelation (both routing stacks call it) and turned into a header here.

require 'spec_helper'
require 'onetime/middleware/retry_after_header'

RSpec.describe Onetime::Middleware::RetryAfterHeader do
  let(:env_key) { described_class::ENV_RETRY_AFTER }

  # Downstream app that echoes whatever status/headers the example set up,
  # mimicking what Otto's error handler returns (plain Hash, lowercase keys).
  def app_returning(status, headers = { 'content-type' => 'application/json' })
    described_class.new(->(_env) { [status, headers, ['{}']] })
  end

  def call(app, env = {})
    app.call(env)
  end

  it 'sets Retry-After from the stashed value on a 429' do
    _status, headers, = call(app_returning(429), { env_key => 900 })

    expect(headers['retry-after']).to eq('900')
  end

  it 'uses the lowercase header name Rack 3 requires' do
    _status, headers, = call(app_returning(429), { env_key => 60 })

    expect(headers.keys).to include('retry-after')
    expect(headers.keys).not_to include('Retry-After')
  end

  it 'accepts a zero delay (a legal delay-seconds value)' do
    _status, headers, = call(app_returning(429), { env_key => 0 })

    expect(headers['retry-after']).to eq('0')
  end

  it 'leaves non-429 responses untouched even when env carries a delay' do
    _status, headers, = call(app_returning(200), { env_key => 900 })

    expect(headers).not_to have_key('retry-after')
  end

  it 'adds nothing when no delay was stashed' do
    _status, headers, = call(app_returning(429), {})

    expect(headers).not_to have_key('retry-after')
  end

  it 'ignores a negative delay rather than emitting a malformed header' do
    _status, headers, = call(app_returning(429), { env_key => -5 })

    expect(headers).not_to have_key('retry-after')
  end

  it 'ignores a non-Integer delay' do
    _status, headers, = call(app_returning(429), { env_key => '900' })

    expect(headers).not_to have_key('retry-after')
  end

  # apps/web/auth/routes/link_sso.rb and sso_link_confirm.rb rescue
  # LimitExceeded inline and set 'Retry-After' themselves, in that casing.
  it 'never overwrites a header a route already set, whatever its casing' do
    app = app_returning(429, { 'Retry-After' => '30' })

    _status, headers, = call(app, { env_key => 900 })

    expect(headers['Retry-After']).to eq('30')
    expect(headers).not_to have_key('retry-after')
  end

  it 'passes status and body through unchanged' do
    status, _headers, body = call(app_returning(429), { env_key => 900 })

    expect(status).to eq(429)
    expect(body).to eq(['{}'])
  end

  it 'tolerates a nil header hash' do
    app = described_class.new(->(_env) { [429, nil, ['{}']] })

    expect { call(app, { env_key => 900 }) }.not_to raise_error
  end
end

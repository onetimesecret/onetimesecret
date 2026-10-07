# frozen_string_literal: true

require 'spec_helper'
require 'onetime/middleware/assume_https'
require 'onetime/middleware/strip_forwarded_host'
require 'onetime/session'

RSpec.describe Onetime::Middleware::AssumeHttps, :aggregate_failures do
  let(:session) do
    Onetime::Session.new(
      ->(_env) { [200, {}, ['ok']] },
      secret: 's' * 128,
      key: 'test.session',
      secure: true,
    )
  end

  around do |example|
    original = Rack::Request.forwarded_priority
    example.run
  ensure
    Rack::Request.forwarded_priority = original
  end

  def request_through_stack(enabled, trusted, header, value)
    allow(OT).to receive(:conf).and_return(
      'site' => { 'network' => { 'assume_https' => enabled } },
    )
    Rack::Request.forwarded_priority = header == 'HTTP_FORWARDED' ? [:forwarded] : [:x_forwarded]

    env = Rack::MockRequest.env_for(
      'http://onetime.test/',
      'REMOTE_ADDR' => '203.0.113.7',
      Rack::DetectHost::VIA_TRUSTED_PROXY_KEY => trusted,
      header => value,
    )
    app = ->(_env) { [200, {}, ['ok']] }
    described_class.new(Onetime::Middleware::StripForwardedHost.new(app)).call(env)
    env
  end

  [true, false].each do |enabled|
    [true, false].each do |trusted|
      {
        'HTTP_X_FORWARDED_PROTO' => 'https',
        'HTTP_X_FORWARDED_SCHEME' => 'https',
        'HTTP_X_FORWARDED_SSL' => 'on',
        'HTTP_FORWARDED' => 'proto=https;host=onetime.test',
      }.each do |header, value|
        it "keeps HTTPS policy #{enabled} after stripping #{header} from a peer with trust #{trusted}" do
          env          = request_through_stack(enabled, trusted, header, value)
          expected_ssl = enabled || trusted
          request      = Rack::Request.new(env)
          expect(request.ssl?).to eq(expected_ssl)
          expect(session.send(:security_matches?, request, { secure: true })).to eq(expected_ssl)
          expect(env).not_to have_key(header) if !trusted || header == 'HTTP_FORWARDED'
        end
      end
    end
  end

  it 'leaves the environment unchanged when disabled' do
    allow(OT).to receive(:conf).and_return(
      'site' => { 'network' => { 'assume_https' => false } },
    )
    env      = Rack::MockRequest.env_for('http://onetime.test/', 'HTTP_X_FORWARDED_PROTO' => 'https')
    original = env.dup

    described_class.new(->(_env) { [200, {}, ['ok']] }).call(env)

    expect(env).to eq(original)
  end

  it 'does not alter forwarded headers when enabled' do
    allow(OT).to receive(:conf).and_return(
      'site' => { 'network' => { 'assume_https' => true } },
    )
    env = Rack::MockRequest.env_for('http://onetime.test/', 'HTTP_X_FORWARDED_PROTO' => 'http')

    described_class.new(->(_env) { [200, {}, ['ok']] }).call(env)

    expect(env['HTTP_X_FORWARDED_PROTO']).to eq('http')
    expect(Rack::Request.new(env).scheme).to eq('https')
  end
end

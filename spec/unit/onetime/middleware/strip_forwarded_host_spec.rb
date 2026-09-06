# spec/unit/onetime/middleware/strip_forwarded_host_spec.rb
#
# frozen_string_literal: true

require 'spec_helper'
require 'onetime/middleware/strip_forwarded_host'
require 'onetime/initializers/configure_rack'

# Unit tests for StripForwardedHost (finding G-01, defense in depth).
#
# The middleware's contract has two halves and both are security-relevant:
#
#   1. No forwarded AUTHORITY survives. `X-Forwarded-Host` is deleted
#      outright, and every `host=` parameter is removed from the RFC 7239
#      `Forwarded` header, so `Rack::Request#host` (which honors both from
#      ANY client, ungated by proxy trust) can only ever resolve the `Host:`
#      authority the edge actually received.
#
#   2. The OTHER RFC 7239 parameters survive. `Forwarded` multiplexes host
#      with `proto`/`for`/`by`, and Rack reads those too (`Request#scheme`
#      via forwarded_scheme, `#forwarded_for`, `#forwarded_port`). A proxy
#      that speaks only `Forwarded` — no `X-Forwarded-Proto` — must not lose
#      its TLS scheme here, or every absolute URL built downstream degrades
#      to http. Deleting the whole header was the original (reviewed-out)
#      behavior; these examples pin the surgical one.
RSpec.describe Onetime::Middleware::StripForwardedHost do
  subject(:middleware) { described_class.new(app) }

  let(:app) { ->(env) { @seen_env = env; [200, {}, ['ok']] } }

  def call_with(env)
    middleware.call(env)
    @seen_env
  end

  describe 'X-Forwarded-Host' do
    it 'deletes the header unconditionally' do
      env = call_with('HTTP_X_FORWARDED_HOST' => 'evil.example.com', 'HTTP_HOST' => 'onetime.test')
      expect(env).not_to have_key('HTTP_X_FORWARDED_HOST')
      expect(env['HTTP_HOST']).to eq('onetime.test')
    end
  end

  describe 'RFC 7239 Forwarded' do
    it 'removes a lone host parameter and deletes the emptied header' do
      env = call_with('HTTP_FORWARDED' => 'host=evil.example.com')
      expect(env).not_to have_key('HTTP_FORWARDED')
    end

    it 'preserves proto and for while removing host (case-insensitively)' do
      env = call_with('HTTP_FORWARDED' => 'for=192.0.2.60;proto=https;Host=evil.example.com')
      expect(env['HTTP_FORWARDED']).to eq('for=192.0.2.60;proto=https')
    end

    it 'keeps a host-free header completely intact' do
      env = call_with('HTTP_FORWARDED' => 'for=192.0.2.60;proto=https')
      expect(env['HTTP_FORWARDED']).to eq('for=192.0.2.60;proto=https')
    end

    it 'removes host from every element of a multi-hop header' do
      env = call_with(
        'HTTP_FORWARDED' => 'for=192.0.2.60;host=evil.example.com, for=198.51.100.1;proto=https;host=evil2.example.com',
      )
      expect(env['HTTP_FORWARDED']).to eq('for=192.0.2.60, for=198.51.100.1;proto=https')
    end

    it 'drops an element made empty and keeps the others' do
      env = call_with('HTTP_FORWARDED' => 'host=evil.example.com, for=198.51.100.1')
      expect(env['HTTP_FORWARDED']).to eq('for=198.51.100.1')
    end

    it 'removes a quoted host value containing a separator without breaking the element' do
      env = call_with('HTTP_FORWARDED' => 'host="evil;example,com";for=192.0.2.60')
      expect(env['HTTP_FORWARDED']).to eq('for=192.0.2.60')
    end

    it 'does not split a quoted non-host value on embedded separators' do
      env = call_with('HTTP_FORWARDED' => 'for="[2001:db8:cafe::17]:4711";host=evil.example.com')
      expect(env['HTTP_FORWARDED']).to eq('for="[2001:db8:cafe::17]:4711"')
    end

    it 'leaves the env untouched when no Forwarded header is present' do
      env = call_with('HTTP_HOST' => 'onetime.test')
      expect(env).not_to have_key('HTTP_FORWARDED')
      expect(env['HTTP_HOST']).to eq('onetime.test')
    end
  end

  # Rack's forwarded_priority is process-global class state. It is pinned to
  # [:x_forwarded] by Onetime::Initializers::ConfigureRack at boot, so whether
  # Rack reads the surviving Forwarded `proto` depends on whether a boot ran
  # earlier in this process. Each example sets the priority it is asserting
  # against so the outcome does not depend on spec ordering.
  describe 'post-strip Rack resolution' do
    around do |example|
      original = Rack::Request.forwarded_priority
      example.run
    ensure
      Rack::Request.forwarded_priority = original
    end

    let(:env) do
      Rack::MockRequest.env_for(
        'http://onetime.test/',
        'HTTP_X_FORWARDED_HOST' => 'evil.example.com',
        'HTTP_FORWARDED' => 'for=192.0.2.60;proto=https;host=evil.example.com',
      )
    end

    it 'resolves host from Host: regardless of forwarded_priority' do
      Rack::Request.forwarded_priority = [:forwarded, :x_forwarded]
      expect(Rack::Request.new(call_with(env)).host).to eq('onetime.test')
    end

    it 'leaves the surviving Forwarded proto readable under the Rack default priority' do
      # The surgical strip exists so env-level readers (Otto's depth-mode
      # Forwarded IP resolution, the redacted fingerprint) and any process
      # running Rack's default priority still see proto/for.
      Rack::Request.forwarded_priority = [:forwarded, :x_forwarded]
      expect(Rack::Request.new(call_with(env)).scheme).to eq('https')
    end

    it 'does not read the surviving Forwarded proto once ConfigureRack pins the priority' do
      Rack::Request.forwarded_priority = Onetime::Initializers::ConfigureRack::FORWARDED_PRIORITY.dup
      expect(Rack::Request.new(call_with(env)).scheme).to eq('http')
    end
  end
end

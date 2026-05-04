# spec/unit/onetime/middleware/normalize_content_type_spec.rb
#
# frozen_string_literal: true

require 'spec_helper'
require 'stringio'
require 'onetime/middleware/normalize_content_type'

RSpec.describe Onetime::Middleware::NormalizeContentType do
  let(:downstream) do
    lambda { |env|
      [200, { 'content-type' => 'text/plain' }, [env['CONTENT_TYPE'].to_s]]
    }
  end

  let(:middleware) { described_class.new(downstream) }

  def env_for(method:, content_type:, body: '')
    {
      'REQUEST_METHOD' => method,
      'CONTENT_TYPE' => content_type,
      'rack.input' => StringIO.new(body),
    }
  end

  describe 'comma-joined Content-Type values' do
    it 'prefers application/x-www-form-urlencoded when both are joined' do
      env = env_for(
        method: 'POST',
        content_type: 'text/html; charset=utf-8, application/x-www-form-urlencoded',
        body: 'secret=hi&ttl=60',
      )

      middleware.call(env)

      expect(env['CONTENT_TYPE']).to eq('application/x-www-form-urlencoded')
    end

    it 'prefers application/json when joined with an unparseable type' do
      env = env_for(
        method: 'POST',
        content_type: 'text/html, application/json; charset=utf-8',
        body: '{"secret":"hi"}',
      )

      middleware.call(env)

      expect(env['CONTENT_TYPE']).to eq('application/json; charset=utf-8')
    end

    it 'leaves the value alone when no joined part is parseable' do
      env = env_for(
        method: 'POST',
        content_type: 'text/html; charset=utf-8, text/plain',
        body: 'plain text body',
      )

      middleware.call(env)

      # Body did not look like JSON or form data, so no override.
      expect(env['CONTENT_TYPE']).to eq('text/html; charset=utf-8, text/plain')
    end
  end

  describe 'body sniffing for unparseable Content-Type' do
    it 'rewrites text/html to form-urlencoded when body looks form-encoded' do
      env = env_for(
        method: 'POST',
        content_type: 'text/html; charset=utf-8',
        body: 'secret=hello-world&ttl=3600',
      )

      middleware.call(env)

      expect(env['CONTENT_TYPE']).to eq('application/x-www-form-urlencoded')
    end

    it 'rewrites text/html to JSON when body looks like a JSON object' do
      env = env_for(
        method: 'POST',
        content_type: 'text/html; charset=utf-8',
        body: '  {"secret":"hi"}',
      )

      middleware.call(env)

      expect(env['CONTENT_TYPE']).to eq('application/json')
    end

    it 'rewrites text/html to JSON when body looks like a JSON array' do
      env = env_for(
        method: 'POST',
        content_type: 'text/html',
        body: '[1, 2, 3]',
      )

      middleware.call(env)

      expect(env['CONTENT_TYPE']).to eq('application/json')
    end

    it 'leaves CONTENT_TYPE alone when the body does not look parseable' do
      env = env_for(
        method: 'POST',
        content_type: 'text/html; charset=utf-8',
        body: '<html><body>not parseable</body></html>',
      )

      middleware.call(env)

      expect(env['CONTENT_TYPE']).to eq('text/html; charset=utf-8')
    end

    it 'rewinds the body so downstream can read it' do
      body_io = StringIO.new('secret=hi')
      env = {
        'REQUEST_METHOD' => 'POST',
        'CONTENT_TYPE' => 'text/html',
        'rack.input' => body_io,
      }

      middleware.call(env)

      expect(body_io.read).to eq('secret=hi')
    end

    it 'does not modify CONTENT_TYPE for GET requests even with form-shaped body' do
      env = env_for(
        method: 'GET',
        content_type: 'text/html',
        body: 'foo=bar',
      )

      middleware.call(env)

      expect(env['CONTENT_TYPE']).to eq('text/html')
    end

    it 'does not touch already-parseable Content-Type' do
      env = env_for(
        method: 'POST',
        content_type: 'application/json; charset=utf-8',
        body: 'not really json but we trust the header',
      )

      middleware.call(env)

      expect(env['CONTENT_TYPE']).to eq('application/json; charset=utf-8')
    end

    it 'leaves multipart/form-data alone' do
      env = env_for(
        method: 'POST',
        content_type: 'multipart/form-data; boundary=----abc',
        body: '------abc\r\nContent-Disposition: form-data; name="x"\r\n\r\nhi\r\n------abc--',
      )

      middleware.call(env)

      expect(env['CONTENT_TYPE']).to eq('multipart/form-data; boundary=----abc')
    end

    it 'tolerates a missing Content-Type header' do
      env = {
        'REQUEST_METHOD' => 'POST',
        'rack.input' => StringIO.new('secret=hi'),
      }

      expect { middleware.call(env) }.not_to raise_error
      expect(env['CONTENT_TYPE']).to eq('application/x-www-form-urlencoded')
    end

    it 'tolerates an empty body' do
      env = env_for(
        method: 'POST',
        content_type: 'text/html',
        body: '',
      )

      expect { middleware.call(env) }.not_to raise_error
      expect(env['CONTENT_TYPE']).to eq('text/html')
    end
  end

  describe 'integration with Rack::Parser parser registry' do
    it 'matches the parseable types Rack::Parser is configured for' do
      parsers = Onetime::Application::MiddlewareStack.instance_variable_get(:@parsers)
      expect(parsers.keys).to include('application/json', 'application/x-www-form-urlencoded')
    end
  end
end

# spec/unit/onetime/middleware/validate_multipart_spec.rb
#
# frozen_string_literal: true

require 'spec_helper'
require 'stringio'
require 'onetime/middleware/validate_multipart'

# ValidateMultipart (#4283)
#
# The downstream stand-in app reads Rack::Request#params, which is exactly
# what Otto::Locale::Middleware does on every request — the first param
# read in the real stack, and the frame the Sentry 500s (BACKEND-AD/AR)
# were raised from. Each rejection example first shows the raw failure
# mode against the bare downstream app (the repro), then shows the
# middleware converting it into a 400.
RSpec.describe Onetime::Middleware::ValidateMultipart do
  let(:boundary) { 'AaB03x' }

  let(:downstream) do
    lambda { |env|
      params = Rack::Request.new(env).params
      [200, { 'content-type' => 'application/json' }, [JSON.generate(params)]]
    }
  end

  let(:middleware) { described_class.new(downstream) }

  def multipart_body(fields = { 'secret' => 'hello world' })
    fields.map { |name, value|
      "--#{boundary}\r\nContent-Disposition: form-data; name=\"#{name}\"\r\n\r\n#{value}\r\n"
    }.join << "--#{boundary}--\r\n"
  end

  def env_for(content_type:, body: '', content_length: :auto, method: 'POST')
    env = {
      'REQUEST_METHOD' => method,
      'CONTENT_TYPE' => content_type,
      'PATH_INFO' => '/share',
      'QUERY_STRING' => '',
      'rack.input' => StringIO.new(body.dup),
    }
    content_length          = body.bytesize.to_s if content_length == :auto
    env['CONTENT_LENGTH']   = content_length unless content_length.nil?
    env
  end

  def parsed_body(response)
    JSON.parse(response[2].join)
  end

  describe 'empty multipart body without Content-Length' do
    let(:env) do
      env_for(
        content_type: "multipart/form-data; boundary=#{boundary}",
        body: '',
        content_length: nil,
      )
    end

    it 'reproduces: Rack raises EmptyContentError from the first params read' do
      expect { downstream.call(env) }.to raise_error(Rack::Multipart::EmptyContentError)
    end

    it 'is rejected with a 400 instead of raising' do
      status, _headers, _body = middleware.call(env)
      expect(status).to eq(400)
    end
  end

  describe 'declared boundary never appears in the body (BACKEND-AR shape)' do
    # BOUNDARY_START_LIMIT is 16KB: junk beyond that without the declared
    # boundary makes the parser give up rather than buffer unboundedly.
    let(:env) do
      env_for(
        content_type: "multipart/form-data; boundary=#{boundary}",
        body: 'x' * (17 * 1024),
      )
    end

    it 'reproduces: Rack raises "multipart boundary not found within limit"' do
      expect { downstream.call(env) }
        .to raise_error(Rack::Multipart::BoundaryTooLongError, /boundary not found within limit/)
    end

    it 'is rejected with a 400 instead of raising' do
      status, _headers, _body = middleware.call(env)
      expect(status).to eq(400)
    end
  end

  describe 'body shorter than Content-Length' do
    let(:env) do
      env_for(
        content_type: "multipart/form-data; boundary=#{boundary}",
        body: multipart_body[0, 20],
        content_length: '4096',
      )
    end

    it 'reproduces: Rack raises EOFError for the truncated body' do
      expect { downstream.call(env) }.to raise_error(EOFError)
    end

    it 'is rejected with a 400 instead of raising' do
      status, _headers, _body = middleware.call(env)
      expect(status).to eq(400)
    end
  end

  describe 'multipart Content-Type without a boundary parameter' do
    let(:env) do
      env_for(content_type: 'multipart/form-data', body: multipart_body)
    end

    it 'reproduces: Rack silently parses the multipart body as urlencoded garbage' do
      response = downstream.call(env)
      expect(response[0]).to eq(200)
      # No exception, but no 'secret' field either — the raw multipart
      # syntax was fed through the urlencoded parser. This is what reached
      # V1 /share as "You did not provide anything to share" (BACKEND-AH).
      expect(parsed_body(response)).not_to have_key('secret')
    end

    it 'is rejected with a 400 and an explanatory message' do
      status, headers, body = middleware.call(env)
      expect(status).to eq(400)
      expect(headers['Content-Type']).to eq('application/json')
      expect(JSON.parse(body.join)['message']).to match(/boundary/)
    end
  end

  describe 'multipart request with Content-Length: 0' do
    let(:env) do
      env_for(
        content_type: "multipart/form-data; boundary=#{boundary}",
        body: '',
        content_length: '0',
      )
    end

    it 'reproduces: Rack short-circuits to empty params without raising' do
      response = downstream.call(env)
      expect(response[0]).to eq(200)
      expect(parsed_body(response)).to eq({})
    end

    it 'is rejected with a 400' do
      status, _headers, _body = middleware.call(env)
      expect(status).to eq(400)
    end
  end

  describe 'multipart request with an empty-string Content-Length' do
    # Spec-invalid (Rack SPEC: digits-only when present), but if a server
    # ever forwards it, Rack's own parse treats ''.to_i == 0 the same as
    # an explicit zero and never multipart-parses the body — it falls back
    # to urlencoded-parsing the raw multipart syntax into garbage params
    # with no usable fields (the BACKEND-AH shape). Rejecting up front is
    # the honest answer; passing it through could never succeed.
    let(:env) do
      env_for(
        content_type: "multipart/form-data; boundary=#{boundary}",
        body: multipart_body,
        content_length: '',
      )
    end

    it 'reproduces: Rack drops every field without raising' do
      response = downstream.call(env)
      expect(response[0]).to eq(200)
      expect(parsed_body(response)).not_to have_key('secret')
    end

    it 'is rejected with a 400' do
      status, _headers, _body = middleware.call(env)
      expect(status).to eq(400)
    end
  end

  describe 'a well-formed multipart request' do
    let(:env) do
      env_for(
        content_type: "multipart/form-data; boundary=#{boundary}",
        body: multipart_body('secret' => 'hello world', 'ttl' => '3600'),
      )
    end

    it 'passes through with all fields visible downstream' do
      status, _headers, _body = response = middleware.call(env)
      expect(status).to eq(200)
      expect(parsed_body(response)).to eq('secret' => 'hello world', 'ttl' => '3600')
    end

    it 'memoizes the parsed params into the env' do
      middleware.call(env)
      expect(env['rack.request.form_hash']).to include('secret' => 'hello world')
    end

    it 'rewinds rack.input before calling downstream' do
      body_seen = nil
      probe     = described_class.new(lambda { |e|
        body_seen = e['rack.input'].read
        [200, {}, []]
      })

      probe.call(env)

      expect(body_seen).to eq(multipart_body('secret' => 'hello world', 'ttl' => '3600'))
    end
  end

  describe 'non-multipart requests' do
    it 'does not touch a JSON POST' do
      env      = env_for(content_type: 'application/json', body: '{"secret":"hi"}')
      original = env['rack.input']

      # Probe downstream instead of the params-reading app: reading params
      # is itself what memoizes rack.request.form_hash, so the check for
      # "middleware did not parse" must happen before any downstream read.
      parsed_at_entry = nil
      probe = described_class.new(lambda { |e|
        parsed_at_entry = e.key?('rack.request.form_hash')
        [200, {}, []]
      })

      status, _headers, _body = probe.call(env)

      expect(status).to eq(200)
      expect(parsed_at_entry).to be(false)
      expect(env['rack.input']).to equal(original)
      expect(env['rack.input'].pos).to eq(0)
    end

    it 'does not touch a GET without a body' do
      env = {
        'REQUEST_METHOD' => 'GET',
        'PATH_INFO' => '/share',
        'QUERY_STRING' => '',
        'rack.input' => StringIO.new,
      }
      status, _headers, _body = middleware.call(env)
      expect(status).to eq(200)
    end

    it 'leaves unparseable multipart subtypes alone' do
      # Rack never body-parses multipart/alternative, so neither do we.
      env = env_for(content_type: 'multipart/alternative', body: 'anything')
      status, _headers, _body = middleware.call(env)
      expect(status).to eq(200)
    end
  end
end

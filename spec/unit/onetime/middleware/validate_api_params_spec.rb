# frozen_string_literal: true

require 'spec_helper'
require 'stringio'
require 'onetime/middleware/validate_api_params'
require 'onetime/middleware/validate_multipart'

RSpec.describe Onetime::Middleware::ValidateAPIParams, :aggregate_failures do
  let(:downstream) { ->(_env) { [200, {}, ['ok']] } }
  let(:middleware) { described_class.new(downstream) }

  def env_for(query: '', body: '', type: nil, path: '/status', mount: '/api/v3')
    Rack::MockRequest.env_for(path, method: 'POST', input: body).merge(
      'SCRIPT_NAME' => mount, 'QUERY_STRING' => query, 'CONTENT_TYPE' => type,
    )
  end

  def expect_bad_request(env, message)
    allow(downstream).to receive(:call).and_call_original
    status, headers, body = middleware.call(env)
    expect(downstream).not_to have_received(:call)
    expect(status).to eq(400)
    expect(headers).to include('content-type' => 'application/json', 'cache-control' => 'private, no-store')
    expect(JSON.parse(body.join)).to eq('message' => message)
  end

  it 'rejects type-conflicting queries before downstream parameter consumers' do
    expect_bad_request(env_for(query: 'x=one&x[]=two'), 'Invalid query parameters')
  end

  it 'rejects invalid percent encoding using a raw Rack query' do
    expect_bad_request(env_for(query: 'x=%ZZ'), 'Invalid query parameters')
  end

  it 'rejects Rack nesting errors without rescuing arbitrary RangeErrors' do
    expect_bad_request(env_for(query: "x#{'[x]' * 40}=value"), 'Invalid query parameters')
  end

  it 'allows valid array/hash queries rather than deciding operation-level types' do
    env = env_for(query: 'scope[]=org&filter[x]=domain')
    expect(middleware.call(env).first).to eq(200)
    expect(Rack::Request.new(env).GET).to eq('scope' => ['org'], 'filter' => { 'x' => 'domain' })
  end

  it 'rejects malformed JSON without exposing input or parser diagnostics' do
    expect_bad_request(env_for(body: '{"private-value":', type: 'application/json'), 'Invalid JSON request body')
  end

  it 'rewinds malformed JSON input even when rejecting it' do
    env = env_for(body: '{', type: 'application/json')
    expect(middleware.call(env).first).to eq(400)
    expect(env['rack.input'].pos).to eq(0)
  end

  [false, nil, 3, 'text', [], { 'secret' => { 'secret' => 'content' } }].each do |value|
    it "preserves valid JSON #{value.inspect} and leaves the input for the existing parser" do
      body = JSON.generate(value)
      env  = env_for(body: body, type: 'application/json')
      allow(downstream).to receive(:call) do |received|
        expect(received['rack.input'].read).to eq(body)
        expect(received).not_to have_key('rack.request.form_hash')
        [200, {}, []]
      end
      expect(middleware.call(env).first).to eq(200)
      expect(downstream).to have_received(:call)
    end
  end

  it 'rejects type-conflicting form bodies' do
    expect_bad_request(env_for(body: 'x=one&x[]=two', type: 'application/x-www-form-urlencoded'), 'Invalid form parameters')
  end

  it 'rejects malformed form percent encoding' do
    expect_bad_request(env_for(body: 'x=%ZZ', type: 'application/x-www-form-urlencoded'), 'Invalid form parameters')
  end

  it 'preserves valid form data and rewinds the input' do
    env = env_for(body: 'secret[secret]=body', type: 'application/x-www-form-urlencoded')
    expect(middleware.call(env).first).to eq(200)
    expect(env['rack.input'].pos).to eq(0)
    expect(Rack::Request.new(env).POST).to eq('secret' => { 'secret' => 'body' })
  end

  %w[/api/v1 /api/account /api/v30 /api/incoming-other /auth].each do |mount|
    it "does not change the parser boundary for #{mount}" do
      expect(middleware.call(env_for(query: 'x=%ZZ', body: '{', type: 'application/json', mount: mount)).first).to eq(200)
    end
  end

  it 'recognizes an unmounted full API path' do
    expect_bad_request(env_for(query: 'x=%ZZ', mount: '', path: '/api/incoming/config'), 'Invalid query parameters')
  end

  it 'does not catch unexpected JSON parser failures' do
    allow(Familia::JsonSerializer).to receive(:parse).and_raise(RuntimeError, 'internal parser fault')
    expect { middleware.call(env_for(body: '{}', type: 'application/json')) }.to raise_error(RuntimeError, 'internal parser fault')
  end

  it 'does not catch arbitrary query consumer errors' do
    env     = env_for
    request = instance_double(Rack::Request)
    allow(Rack::Request).to receive(:new).with(env).and_return(request)
    allow(request).to receive(:GET).and_raise(ArgumentError, 'internal query fault')
    expect { middleware.call(env) }.to raise_error(ArgumentError, 'internal query fault')
  end

  it 'does not catch input IO failures' do
    env               = env_for(type: 'application/json')
    input             = instance_double(StringIO)
    allow(input).to receive(:read).and_raise(IOError, 'unavailable input')
    allow(input).to receive(:rewind)
    env['rack.input'] = input
    expect { middleware.call(env) }.to raise_error(IOError, 'unavailable input')
  end

  [Rack::QueryParser::ParameterTypeError, Familia::SerializerError, Redis::CannotConnectError].each do |error|
    it "does not classify downstream #{error} as a client parsing failure" do
      allow(downstream).to receive(:call).and_raise(error, 'downstream failure')
      expect { middleware.call(env_for) }.to raise_error(error, 'downstream failure')
    end
  end

  describe 'composition at the existing multipart boundary' do
    let(:multipart_boundary) { Onetime::Middleware::ValidateMultipart.new(downstream) }
    let(:multipart) { "--boundary\r\nContent-Disposition: form-data; name=\"secret\"\r\n\r\ncontent\r\n--boundary--\r\n" }

    it 'still parses and memoizes valid multipart before validating its query' do
      env = env_for(body: multipart, type: 'multipart/form-data; boundary=boundary')
      allow(downstream).to receive(:call) do |received|
        expect(Rack::Request.new(received).POST).to eq('secret' => 'content')
        expect(received['rack.input'].pos).to eq(0)
        [200, {}, []]
      end
      expect(multipart_boundary.call(env).first).to eq(200)
      expect(downstream).to have_received(:call)
    end

    it 'rejects a malformed query even with a valid multipart body' do
      env                   = env_for(body: multipart, type: 'multipart/form-data; boundary=boundary', query: 'x=%ZZ')
      allow(downstream).to receive(:call).and_call_original
      status, headers, body = multipart_boundary.call(env)
      expect(downstream).not_to have_received(:call)
      expect(status).to eq(400)
      expect(headers['cache-control']).to eq('private, no-store')
      expect(JSON.parse(body.join)).to eq('message' => 'Invalid query parameters')
    end

    it 'uses the established multipart message with API cache policy' do
      env                   = env_for(body: 'broken', type: 'multipart/form-data')
      status, headers, body = multipart_boundary.call(env)
      expect(status).to eq(400)
      expect(headers['content-type']).to eq('application/json')
      expect(headers['cache-control']).to eq('private, no-store')
      expect(JSON.parse(body.join)['message']).to start_with('Invalid multipart request:')
    end

    it 'does not change the existing non-API multipart error response' do
      env                   = env_for(body: 'broken', type: 'multipart/form-data', mount: '', path: '/share')
      status, headers, body = multipart_boundary.call(env)
      expect(status).to eq(400)
      expect(headers).to eq('Content-Type' => 'application/json')
      expect(JSON.parse(body.join)['message']).to start_with('Invalid multipart request:')
    end
  end

  it 'omits content on HEAD parser failures' do
    env                   = env_for(query: 'x=%ZZ').merge('REQUEST_METHOD' => 'HEAD')
    status, headers, body = middleware.call(env)
    expect(status).to eq(400)
    expect(headers['cache-control']).to eq('private, no-store')
    expect(body).to eq([])
  end
end

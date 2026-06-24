# spec/unit/onetime/application/request_logger_spec.rb
#
# frozen_string_literal: true

require 'spec_helper'
require 'rack/mock'
require 'json'

RSpec.describe Onetime::Application::RequestLogger do
  # Capture what the HTTP logger receives. log_request calls
  # @logger.send(level, json_string), so each entry is [level, parsed_payload].
  let(:captured) { [] }
  let(:logger) do
    sink = captured
    obj  = Object.new
    %i[trace debug info warn error fatal].each do |lvl|
      obj.define_singleton_method(lvl) { |msg| sink << [lvl, JSON.parse(msg)] }
    end
    obj
  end

  # capture: standard so request_id is in the payload (the field error_id used
  # to be impossible to correlate with). The downstream app stands in for the
  # Otto router: on the error path it stashes otto.error_type into env exactly
  # like OttoHooks#with_error_correlation does mid-request.
  let(:config) { { 'capture' => 'standard' } }
  let(:downstream) do
    lambda do |env|
      env['otto.error_type'] = error_type if error_type
      [status, {}, []]
    end
  end
  let(:status) { 200 }
  let(:error_type) { nil }

  subject(:middleware) { described_class.new(downstream, config) }

  before { allow(Onetime).to receive(:get_logger).with('HTTP').and_return(logger) }

  def call(path: '/api/v3/secret/abc', request_id: 'req-xyz-1')
    env = Rack::MockRequest.env_for(path, 'HTTP_X_REQUEST_ID' => request_id)
    middleware.call(env)
    captured.last
  end

  context 'on a typed error response (e.g. 404 RecordNotFound)' do
    let(:status) { 404 }
    let(:error_type) { 'RecordNotFound' }

    it 'logs the request at :warn (4xx)' do
      level, _payload = call
      expect(level).to eq(:warn)
    end

    it 'records error_type alongside the request_id in a single line' do
      _level, payload = call(request_id: 'req-xyz-1')
      expect(payload['error_type']).to eq('RecordNotFound')
      expect(payload['request_id']).to eq('req-xyz-1')
      expect(payload['status']).to eq(404)
    end
  end

  context 'on a successful response' do
    let(:status) { 200 }

    it 'logs at :info and omits error_type' do
      level, payload = call
      expect(level).to eq(:info)
      expect(payload).not_to have_key('error_type')
      expect(payload['request_id']).to eq('req-xyz-1')
    end
  end

  # :minimal capture (the YAML default) normally omits request_id. Error lines
  # must still carry it so the id the client received is greppable here.
  context 'in :minimal capture mode' do
    let(:config) { { 'capture' => 'minimal' } }

    context 'on an error response' do
      let(:status) { 404 }
      let(:error_type) { 'RecordNotFound' }

      it 'forces request_id onto the line alongside error_type' do
        _level, payload = call(request_id: 'rid-min-1')
        expect(payload['error_type']).to eq('RecordNotFound')
        expect(payload['request_id']).to eq('rid-min-1')
      end
    end

    context 'on a successful response' do
      let(:status) { 200 }

      it 'stays lean (no request_id)' do
        _level, payload = call
        expect(payload).not_to have_key('request_id')
        expect(payload).not_to have_key('error_type')
      end
    end
  end
end

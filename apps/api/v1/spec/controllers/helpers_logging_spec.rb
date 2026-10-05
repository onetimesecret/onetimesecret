# apps/api/v1/spec/controllers/helpers_logging_spec.rb
#
# frozen_string_literal: true

# V1 capability routes (/receipt/:key, /private/:key, /metadata/:key,
# /secret/:key) carry the credential in the path. Every successful
# authenticated request is logged through log_customer_activity at INFO,
# and the rescue branches log the path at ERROR, so those lines must go
# through the same capability redactor as the request logger — never the
# raw PATH_INFO.

require_relative '../../application'
require_relative File.join(Onetime::HOME, 'spec', 'spec_helper')
require 'v1/controllers'

RSpec.describe V1::ControllerHelpers, 'request path logging' do
  let(:controller_class) do
    Class.new do
      include V1::ControllerHelpers

      attr_reader :req, :cust, :sess

      def initialize(request:, customer: nil, session: nil)
        @req  = request
        @cust = customer
        @sess = session
      end

      # ControllerHelpers reads these via the including controller.
      def session
        @sess || {}
      end
    end
  end

  let(:receipt_key) { 'r3c31ptk3y0123456789abcdef' }

  def request_for(method:, path_info:, script_name: '/api/v1')
    # String-keyed opts are copied into the env after the URL is parsed, so
    # the mount prefix lands in SCRIPT_NAME the way URLMap would place it.
    env = Rack::MockRequest.env_for(
      "https://example.com#{script_name}#{path_info}",
      method: method,
      'HTTP_X_FORWARDED_FOR' => '203.0.113.195',
      'SCRIPT_NAME' => script_name,
      'PATH_INFO' => path_info,
    )
    Rack::Request.new(env)
  end

  describe '#stringify_request_details' do
    it 'redacts the receipt key from a GET /receipt/:key line' do
      controller = controller_class.new(request: request_for(method: 'GET', path_info: "/receipt/#{receipt_key}"))

      details = controller.stringify_request_details(controller.req)

      expect(details).not_to include(receipt_key)
      expect(details).to include('GET /api/v1/receipt/[REDACTED]')
    end

    it 'redacts the key but keeps the action on POST /receipt/:key/burn' do
      controller = controller_class.new(request: request_for(method: 'POST', path_info: "/receipt/#{receipt_key}/burn"))

      details = controller.stringify_request_details(controller.req)

      expect(details).not_to include(receipt_key)
      expect(details).to include('POST /api/v1/receipt/[REDACTED]/burn')
    end

    it 'leaves static capability actions readable' do
      controller = controller_class.new(request: request_for(method: 'POST', path_info: '/secret/conceal'))

      expect(controller.stringify_request_details(controller.req)).to include('POST /api/v1/secret/conceal')
    end

    it 'still carries the client ip and proxy headers' do
      controller = controller_class.new(request: request_for(method: 'GET', path_info: '/status'))

      details = controller.stringify_request_details(controller.req)

      expect(details).to include('GET /api/v1/status')
      expect(details).to match(/X-Forwarded-For:\s*203\.0\.113\.195/)
    end
  end

  describe '#redacted_request_path' do
    it 'is the redacted full mount path used by the error-branch log lines' do
      controller = controller_class.new(request: request_for(method: 'GET', path_info: "/private/#{receipt_key}"))

      expect(controller.redacted_request_path).to eq('/api/v1/private/[REDACTED]')
    end
  end

  describe '#log_customer_activity' do
    let(:customer) { double('Customer', anonymous?: false, obscure_email: 'u***@example.com') }

    it 'never writes the capability key to the INFO log' do
      lines      = []
      controller = controller_class.new(
        request: request_for(method: 'GET', path_info: "/receipt/#{receipt_key}"),
        customer: customer,
      )
      allow(OT).to receive(:info) { |line| lines << line }

      controller.log_customer_activity

      expect(lines.join).not_to include(receipt_key)
      expect(lines.join).to include('GET /api/v1/receipt/[REDACTED]')
    end
  end
end

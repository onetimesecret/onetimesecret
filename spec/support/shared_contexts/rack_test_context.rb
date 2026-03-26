# spec/support/shared_contexts/rack_test_context.rb
#
# frozen_string_literal: true

# Shared context for Rack::Test integration with mocked request/response.
# Used by controller and view specs that need Rack request/response doubles.
#
# Usage:
#   RSpec.describe 'Controller' do
#     include_context 'rack_test_context'
#
#     it 'handles request' do
#       expect(rack_request.path_info).to eq('/test')
#     end
#   end
#
RSpec.shared_context 'rack_test_context' do
  # Otto::Request/Response extend Rack::Request/Response with app_path,
  # redirect, etc. Use Otto types so instance_double allows those methods.
  let(:rack_request) do
    instance_double(Otto::Request,
      params: {},
      get?: false,
      post?: false,
      path_info: '/test',
      env: {
        'REMOTE_ADDR' => '127.0.0.1',
        'HTTP_HOST' => 'example.com',
        'rack.session' => {},
        'HTTP_ACCEPT' => 'application/json',
        'ots.locale' => 'en'
      },
      cookies: {},
      session: {},
      script_name: '',
      body: StringIO.new)
  end

  let(:rack_response) do
    instance_double(Otto::Response,
      status: 200,
      headers: {},
      body: [],
      set_cookie: nil,
      finish: [200, {}, []],
      write: nil).tap do |resp|
      allow(resp).to receive(:[]=) { |k, v| resp.headers[k] = v }
      allow(resp).to receive(:[]) { |k| resp.headers[k] }
      allow(resp).to receive(:body=)
    end
  end
end

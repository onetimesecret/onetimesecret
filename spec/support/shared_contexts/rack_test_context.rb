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
  let(:rack_request) do
    instance_double(Rack::Request,
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
    instance_double(Rack::Response,
      status: 200,
      headers: {},
      header: {},
      body: [],
      set_cookie: nil,
      finish: [200, {}, []],
      write: nil).tap do |resp|
      allow(resp).to receive(:[]=) { |k, v| resp.headers[k] = v }
      allow(resp).to receive(:[]) { |k| resp.headers[k] }
      allow(resp).to receive(:header).and_return(resp.headers)
      allow(resp).to receive(:body=)
    end
  end
end

# spec/support/rack_context.rb

RSpec.shared_context "rack_test_context" do
  let(:rack_request) do
    # Use regular double since Otto adds methods at runtime
    double('Rack::Request',
      params: {},
      get?: false,
      post?: false,
      path_info: '/test',
      env: {
        'REMOTE_ADDR' => '127.0.0.1',
        'HTTP_HOST' => 'example.com',
        'rack.session' => {},
        'HTTP_ACCEPT' => 'application/json',
        'ots.locale' => 'en',
      },
      cookies: {},
      session: {},
      script_name: '',
      body: StringIO.new).tap do |req|
      # Otto extensions - methods added at runtime to Rack::Request
      allow(req).to receive(:check_locale!) do |locale, options|
        req.env['ots.locale'] = options[:default_locale] || 'en'
        options[:default_locale] || 'en'
      end
      allow(req).to receive(:app_path) { |path| path }
    end
  end

  let(:rack_response) do
    # Use regular double since Otto adds methods at runtime
    double('Rack::Response',
      status: 200,
      headers: {},
      body: [],
      set_cookie: nil,
      finish: [200, {}, []],
      write: nil).tap do |resp|
      allow(resp).to receive(:[]=) { |k,v| resp.headers[k] = v }
      allow(resp).to receive(:[]) { |k| resp.headers[k] }
      allow(resp).to receive(:body=)

      # Otto extensions - methods added at runtime to Rack::Response
      allow(resp).to receive(:app_path) { |path| path }
      allow(resp).to receive(:redirect)
    end
  end
end

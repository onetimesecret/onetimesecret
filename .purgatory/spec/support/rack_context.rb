# spec/support/rack_context.rb

RSpec.shared_context "rack_test_context" do
  let(:rack_request) do
    instance_double(Rack::Request,
      params: {},
      get?: false,
      post?: false,
      path_info: '/test',
      env: {
        'REMOTE_ADDR' => '127.0.0.1',
        'HTTP_HOST' => 'example.com',
        'onetime.session' => {},
        'HTTP_ACCEPT' => 'application/json',
        'ots.locale' => 'en',
      },
      cookies: {},
      session: {},
      script_name: '',
      body: StringIO.new)
  end

  let(:rack_response) do
    double('Rack::Response',
      status: 200,
      headers: {},
      body: [],
      set_cookie: nil,
      finish: [200, {}, []],
      write: nil,
      redirect: nil).tap do |resp|
      allow(resp).to receive(:[]=) { |k,v| resp.headers[k] = v }
      allow(resp).to receive(:[]) { |k| resp.headers[k] }
      allow(resp).to receive(:body=)
      allow(resp).to receive(:app_path) { |path| path }
    end
  end
end

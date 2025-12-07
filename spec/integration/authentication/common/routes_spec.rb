# Generated rspec code for /Users/d/Projects/opensource/onetime/onetimesecret/try/integration/authentication/common/routes_try.rb
# Updated: 2025-12-06 19:02:09 -0800

require 'spec_helper'

RSpec.describe 'routes_try' do
  before(:all) do
    require 'rack'
    require 'rack/mock'
    @app = Rack::Builder.parse_file('config.ru')
    @mock_request = Rack::MockRequest.new(@app)
  end

  it 'Authentication is enabled' do
    result = begin
      OT.conf['site']['authentication']['signin']
    end
    expect(result).to eq(true)
  end

  it 'With default configuration, can access the sign-in page' do
    result = begin
      response = @mock_request.get('/signin')
      response.status
    end
    expect(result).to eq(200)
  end

  it 'With default configuration, can access the sign-in page' do
    result = begin
      response = @mock_request.get('/signup')
      response.status
    end
    expect(result).to eq(200)
  end

  it 'With default configuration, dashboard redirects to sign-in' do
    result = begin
      response = @mock_request.get('/dashboard')
      [response.status, response.headers["location"]]
    end
    expect(result).to eq([302, "/signin"])
  end

  it 'Disable authentication for all routes' do
    result = begin
      old_conf = OT.instance_variable_get(:@conf)
      new_conf = {
        'site' => {
          'secret' => 'notnil',
          'authentication' => {
            'enabled' => false,
            'signin' => true,
          }
        },
        'mail' => {
          'truemail' => {},
        }
      }
      OT.instance_variable_set(:@conf, new_conf)
      processed_conf = OT::Config.after_load(OT.conf)
      OT.instance_variable_set(:@conf, old_conf)
      processed_conf['site']['authentication']['signin']
    end
    expect(result).to eq(false)
  end

  it 'With auth disabled, dashboard still redirects' do
    result = begin
      old_conf = OT.instance_variable_get(:@conf)
      new_conf = {
        'site' => {
          'secret' => 'notnil',
          'authentication' => {
            'enabled' => false,
          },
        },
        'mail' => {
          'truemail' => {},
        },
      }
      OT.instance_variable_set(:@conf, new_conf)
      response = @mock_request.get('/dashboard')
      OT.instance_variable_set(:@conf, old_conf)
      response.status
    end
    expect(result).to eq(302)
  end

  it 'Can access the API generate endpoint' do
    result = begin
      response = @mock_request.post('/api/v1/generate')
      response.status
    end
    expect(result).to eq(500)
  end

  it 'Can post to a bogus endpoint and get a 404' do
    result = begin
      response = @mock_request.post('/api/v1/generate2')
      content = Familia::JsonSerializer.parse(response.body)
      [response.status, content["error"]]
    end
    expect(result).to eq([404, 'Not Found'])
  end

  it 'Can access the API status' do
    result = begin
      response = @mock_request.get('/api/v2/status')
      content = Familia::JsonSerializer.parse(response.body)
      [response.status, content["status"], content["locale"]]
    end
    expect(result).to eq([200, "nominal", "en"])
  end

  it 'Can access the API share endpoint' do
    result = begin
      response = @mock_request.post('/api/v2/secret/conceal', {secret:{secret: 'hello', value: 'world'}})
      response.status
    end
    expect(result).to eq(422)
  end

  it 'Can post to a bogus endpoint and get a 404' do
    result = begin
      response = @mock_request.post('/api/v2/generate2')
      content = Familia::JsonSerializer.parse(response.body)
      [response.status, content["success"], content["error"]]
    end
    expect(result).to eq([404, nil, 'Not Found'])
  end

  it 'Can post to a bogus endpoint and get a 404' do
    result = begin
      response = @mock_request.post('/api/v2/colonel/info')
      content = Familia::JsonSerializer.parse(response.body)
      [response.status, content["success"], content["custid"]]
    end
    expect(result).to eq([404, nil, nil])
  end

end

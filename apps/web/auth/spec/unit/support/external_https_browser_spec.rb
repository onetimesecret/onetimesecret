# apps/web/auth/spec/unit/support/external_https_browser_spec.rb
#
# frozen_string_literal: true

# The external HTTPS browser model (spec/support/external_https_browser.rb)
# against a bare Rack app: what it changes in Rack::Test's cookie jar, what
# it keeps, and what it never touches in the Rack environment. No boot.

require 'json'
require 'rack'
require 'rack/test'
require_relative '../../support/external_https_browser'

RSpec.describe ExternalHttpsBrowser do
  # GET /set?cookie=<Set-Cookie value> sets that cookie; GET /echo reports
  # the Cookie header received and how Rack read the request's scheme.
  let(:app) do
    lambda do |env|
      req = Rack::Request.new(env)
      case req.path
      when '/set'
        [200, { 'set-cookie' => req.params.fetch('cookie') }, ['set']]
      else
        body = {
          cookie: env['HTTP_COOKIE'].to_s,
          https: env['HTTPS'],
          url_scheme: env['rack.url_scheme'],
          ssl: req.ssl?,
        }
        [200, { 'content-type' => 'application/json' }, [JSON.generate(body)]]
      end
    end
  end

  def echo(path = '/echo', env = {})
    get path, {}, env
    JSON.parse(last_response.body)
  end

  # The behaviour the model exists to replace, stated as the control: a
  # Secure cookie set in response to an http request is never stored.
  context 'without the model (plain Rack::Test session)' do
    include Rack::Test::Methods

    it 'withholds a Secure cookie from http requests' do
      get '/set', cookie: 'sid=1; Secure; HttpOnly'
      expect(rack_mock_session.cookie_jar.to_hash).to eq({})
      expect(echo['cookie']).to eq('')
    end

    it 'sends a cookie without Secure' do
      get '/set', cookie: 'plain=1'
      expect(echo['cookie']).to eq('plain=1')
    end
  end

  context 'with the model' do
    # Rack::Test::Methods included last on purpose: a plain override of its
    # build_rack_test_session would lose here; the respond_to? hook does not.
    include_context 'external HTTPS browser'
    include Rack::Test::Methods

    it 'builds its own session through the Rack::Test hook, whichever module came first' do
      expect(rack_mock_session).to be_a(ExternalHttpsBrowser::Session)
      expect(rack_mock_session.cookie_jar).to be_a(ExternalHttpsBrowser::CookieJar)
    end

    it 'stores a Secure cookie set in response to an http request and sends it on the next one' do
      get '/set', cookie: 'sid=1; Secure; HttpOnly'
      expect(rack_mock_session.cookie_jar.to_hash).to eq('sid' => '1')
      expect(echo['cookie']).to eq('sid=1')
    end

    it 'sends a Secure cookie on an https:// request as before' do
      get 'https://example.org/set', cookie: 'sid=1; Secure'
      expect(echo('https://example.org/echo')['cookie']).to eq('sid=1')
    end

    it 'treats a cookie without Secure exactly as Rack::Test does' do
      get '/set', cookie: 'plain=1'
      expect(echo['cookie']).to eq('plain=1')
    end

    it 'keeps the model across clear_cookies' do
      get '/set', cookie: 'sid=1; Secure'
      clear_cookies
      expect(echo['cookie']).to eq('')
      expect(rack_mock_session.cookie_jar).to be_a(ExternalHttpsBrowser::CookieJar)
      get '/set', cookie: 'sid=2; Secure'
      expect(echo['cookie']).to eq('sid=2')
    end

    it 'stores a Secure cookie given to set_cookie without a URI' do
      set_cookie 'sid=3; Secure'
      expect(echo['cookie']).to eq('sid=3')
    end

    describe 'the restrictions it keeps' do
      it 'still matches Domain' do
        get '/set', cookie: 'sid=1; Secure; Domain=other.example'
        expect(echo['cookie']).to eq('')
      end

      it 'still matches Path' do
        get '/set', cookie: 'sid=1; Secure; Path=/admin'
        expect(echo['cookie']).to eq('')
        expect(echo('/admin/echo')['cookie']).to eq('sid=1')
      end

      it 'still replaces a cookie by name, domain and path' do
        get '/set', cookie: 'sid=1; Secure'
        get '/set', cookie: 'sid=2'
        expect(echo['cookie']).to eq('sid=2')
      end

      it 'still drops a cookie its Set-Cookie expires' do
        get '/set', cookie: 'sid=1; Secure'
        get '/set', cookie: 'sid=; Secure; Max-Age=0; Expires=Thu, 01 Jan 1970 00:00:00 GMT'
        expect(echo['cookie']).to eq('')
      end
    end

    describe 'the Rack environment it leaves alone' do
      it 'does not make the application see https' do
        get '/set', cookie: 'sid=1; Secure'
        seen = echo
        expect(seen['cookie']).to eq('sid=1')
        expect(seen['https']).to eq('off')
        expect(seen['url_scheme']).to eq('http')
        expect(seen['ssl']).to be(false)
      end

      it 'leaves the scheme to the headers the example sends' do
        header 'X-Forwarded-Proto', 'https'
        expect(echo['ssl']).to be(true)
        header 'X-Forwarded-Proto', nil
        expect(echo['ssl']).to be(false)
      end

      it 'still sets HTTPS=on for an https:// URL, as Rack::Test does' do
        seen = echo('https://example.org/echo')
        expect(seen['https']).to eq('on')
        expect(seen['ssl']).to be(true)
      end
    end
  end
end

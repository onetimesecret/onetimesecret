# spec/unit/onetime/middleware/signin_return_path_spec.rb
#
# frozen_string_literal: true

# Otto answers a signed-out GET of a session route with a bare 302 to /signin,
# built inside the gem with no hook for the request path, so a full page load
# of /recent (the link in the expiration-warning email) lost its destination
# at sign-in. This middleware adds it as ?redirect=, the query the app's own
# router guard writes and its sign-in flow consumes (#4844).

require 'spec_helper'
require 'onetime/utils'
require 'onetime/middleware/signin_return_path'

RSpec.describe Onetime::Middleware::SigninReturnPath do
  # What Otto's auth chain leaves behind when every strategy failed.
  let(:failed_chain) do
    Struct.new(:metadata).new({ auth_failure: 'All authentication strategies failed', failure_reasons: [] })
  end

  # What it leaves behind when a strategy admitted the request (noauth, or an
  # authenticated session); the handler then chose to redirect.
  let(:admitted_chain) { Struct.new(:metadata).new({ ip: '192.0.2.1' }) }

  def otto_redirect(location = '/signin')
    [302, { 'location' => location, 'x-frame-options' => 'DENY' }, ["Redirecting to #{location}"]]
  end

  def call(response, env)
    described_class.new(->(_env) { response }).call(env)
  end

  def env_for(path, method: 'GET', query: '', script_name: '', result: failed_chain)
    env = {
      'REQUEST_METHOD' => method,
      'SCRIPT_NAME' => script_name,
      'PATH_INFO' => path,
      'QUERY_STRING' => query,
    }
    env['otto.strategy_result'] = result unless result.nil?
    env
  end

  describe 'a session page refused by the auth chain' do
    subject(:result) { call(otto_redirect, env_for('/recent')) }

    it 'sends the visitor to sign in with the page as the return path' do
      expect(result[1]['location']).to eq('/signin?redirect=%2Frecent')
    end

    it 'keeps the status, the body and the other headers' do
      expect(result[0]).to eq(302)
      expect(result[2]).to eq(['Redirecting to /signin'])
      expect(result[1]['x-frame-options']).to eq('DENY')
    end

    it 'keeps the query string inside the return path' do
      _status, headers, _body = call(otto_redirect, env_for('/recent', query: 'page=2'))

      expect(headers['location']).to eq('/signin?redirect=%2Frecent%3Fpage%3D2')
    end

    it 'includes the script name, the path the browser asked for' do
      _status, headers, _body = call(otto_redirect, env_for('/recent', script_name: '/app'))

      expect(headers['location']).to eq('/signin?redirect=%2Fapp%2Frecent')
    end

    it 'treats HEAD like GET' do
      _status, headers, _body = call(otto_redirect, env_for('/dashboard', method: 'HEAD'))

      expect(headers['location']).to eq('/signin?redirect=%2Fdashboard')
    end

    it 'writes location under the key the response used' do
      response = [302, { 'Location' => '/signin' }, []]
      _status, headers, _body = call(response, env_for('/account'))

      expect(headers.keys).to eq(['Location'])
      expect(headers['Location']).to eq('/signin?redirect=%2Faccount')
    end
  end

  describe 'responses it leaves alone' do
    it 'a POST refused by the chain: its path is not a page to return to' do
      _status, headers, _body = call(otto_redirect, env_for('/account/delete', method: 'POST'))

      expect(headers['location']).to eq('/signin')
    end

    it "an app's own redirect to sign in after the chain admitted the request (sign-out)" do
      _status, headers, _body = call(otto_redirect, env_for('/logout', result: admitted_chain))

      expect(headers['location']).to eq('/signin')
    end

    it 'a request no Otto auth chain ran for' do
      _status, headers, _body = call(otto_redirect, env_for('/logout', result: nil))

      expect(headers['location']).to eq('/signin')
    end

    it 'a sign-in redirect that already has a query' do
      response = otto_redirect('/signin?auth_error=sso_failed')
      _status, headers, _body = call(response, env_for('/recent'))

      expect(headers['location']).to eq('/signin?auth_error=sso_failed')
    end

    it 'a redirect to somewhere other than the sign-in page' do
      _status, headers, _body = call(otto_redirect('/'), env_for('/recent'))

      expect(headers['location']).to eq('/')
    end

    it 'a status other than 302' do
      response = [401, { 'content-type' => 'application/json' }, ['{}']]

      expect(call(response, env_for('/recent'))).to eq(response)
    end

    # The validator the app mirrors in isValidInternalPath. A path that
    # fails it never becomes a redirect target, so the bare /signin stands.
    it 'a return path that is not a safe internal path (protocol-relative)' do
      _status, headers, _body = call(otto_redirect, env_for('//evil.example/recent'))

      expect(headers['location']).to eq('/signin')
    end

    it 'a return path with a backslash' do
      _status, headers, _body = call(otto_redirect, env_for('/recent\\evil'))

      expect(headers['location']).to eq('/signin')
    end

    it 'a return path with a traversal segment smuggled in the query' do
      _status, headers, _body = call(otto_redirect, env_for('/recent', query: 'next=/../admin'))

      expect(headers['location']).to eq('/signin')
    end
  end
end

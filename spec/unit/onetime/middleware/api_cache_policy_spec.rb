# spec/unit/onetime/middleware/api_cache_policy_spec.rb
#
# frozen_string_literal: true

# RISK-2026-09-19-03: /api responses sent no Cache-Control at all. The rack
# level is pinned in the customer-session failure matrix specs (both lanes).

require 'spec_helper'
require 'onetime/middleware/api_cache_policy'

RSpec.describe Onetime::Middleware::ApiCachePolicy do
  def app_returning(status, headers = { 'content-type' => 'application/json' })
    described_class.new(->(_env) { [status, headers, ['{}']] })
  end

  # The universal stack runs inside each Rack::URLMap mount: the mount prefix
  # is SCRIPT_NAME, the remainder PATH_INFO.
  def mounted(script_name, path_info = '/')
    { 'SCRIPT_NAME' => script_name, 'PATH_INFO' => path_info }
  end

  %w[/api/v1 /api/v2 /api/v3 /api/account /api/colonel /api/organizations /api/domains /api/invite /api/incoming].each do |mount|
    it "defaults a response under #{mount} to private, no-store" do
      _status, headers, = app_returning(200).call(mounted(mount, '/anything'))

      expect(headers['cache-control']).to eq('private, no-store')
    end
  end

  [200, 201, 204, 302, 401, 403, 404, 422, 429, 500, 503].each do |status|
    it "covers a #{status}: a refusal or an error is no more cacheable than a success" do
      _status, headers, = app_returning(status).call(mounted('/api/v2'))

      expect(headers['cache-control']).to eq('private, no-store')
    end
  end

  it 'uses the lowercase header name Rack 3 requires' do
    _status, headers, = app_returning(200).call(mounted('/api/v2'))

    expect(headers.keys).to include('cache-control')
    expect(headers.keys).not_to include('Cache-Control')
  end

  it 'matches an unmounted app by its full path too' do
    _status, headers, = app_returning(200).call(mounted('', '/api/v2/status'))

    expect(headers['cache-control']).to eq('private, no-store')
  end

  # A route that decided for itself keeps its decision, whatever it is.
  ['no-store', 'public, max-age=300', 'private, max-age=0, must-revalidate'].each do |explicit|
    it "never overwrites a route's own policy (#{explicit})" do
      _status, headers, = app_returning(200, { 'cache-control' => explicit }).call(mounted('/api/colonel'))

      expect(headers['cache-control']).to eq(explicit)
    end
  end

  it "sees a route's own header whatever its case" do
    _status, headers, = app_returning(200, { 'Cache-Control' => 'no-store' }).call(mounted('/api/colonel'))

    expect(headers).to eq('Cache-Control' => 'no-store')
  end

  [
    ['Web Core', '', '/dashboard'],
    ['the /auth app', '/auth', '/login'],
    ['a static asset', '', '/dist/assets/app.js'],
    ['a path that merely starts with the letters', '', '/apiary'],
    ['a docs path', '', '/api-docs'],
  ].each do |label, script_name, path_info|
    it "leaves #{label} alone: those set their own policy" do
      _status, headers, = app_returning(200).call(mounted(script_name, path_info))

      expect(headers).not_to have_key('cache-control')
    end
  end

  it 'passes status and body through untouched' do
    status, _headers, body = app_returning(418).call(mounted('/api/v2'))

    expect([status, body]).to eq([418, ['{}']])
  end

  it 'tolerates a response with no headers' do
    app = described_class.new(->(_env) { [204, nil, []] })

    expect(app.call(mounted('/api/v2'))).to eq([204, nil, []])
  end
end

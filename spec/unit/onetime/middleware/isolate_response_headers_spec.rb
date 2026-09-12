# spec/unit/onetime/middleware/isolate_response_headers_spec.rb
#
# frozen_string_literal: true

require 'spec_helper'
require 'rack'
require 'onetime/middleware/isolate_response_headers'

# Unit tests for the per-request response header isolation layer.
#
# The middleware exists for one reason: an app below it (Otto's static
# `not_found` / `server_error` triples) returns the SAME headers hash on
# every request, and rack-session's commit appends this request's Set-Cookie
# to whatever that hash already holds. The tests below model exactly that:
# a downstream app that returns one shared triple, a header writer above the
# middleware that behaves like rack-session (Rack::Response::Raw#set_cookie,
# which is what `commit_session` calls), and assertions that the shared
# object never changes and no request sees another's cookie.
RSpec.describe Onetime::Middleware::IsolateResponseHeaders do
  subject(:middleware) { described_class.new(downstream) }

  # The failure shape: one hash, one triple, returned by reference forever.
  let(:shared_headers) { { 'content-type' => 'application/json' } }
  let(:shared_triple)  { [404, shared_headers, ['{"error":"Not Found"}']] }
  let(:downstream)     { ->(_env) { shared_triple } }

  # What rack-session does on the way out, verbatim: wrap the returned
  # headers in Rack::Response::Raw and set_cookie on it (in place).
  def commit_cookie(headers, value)
    Rack::Response::Raw.new(404, headers).set_cookie('onetime.session', value)
  end

  def set_cookie_values(headers)
    Array(headers['set-cookie']).flat_map { |v| v.to_s.split("\n") }
  end

  it 'returns the same status and body' do
    status, _headers, body = middleware.call({})

    expect([status, body]).to eq([404, ['{"error":"Not Found"}']])
  end

  it 'returns a headers hash that is not the downstream object' do
    _status, headers, _body = middleware.call({})

    expect(headers).not_to equal(shared_headers)
  end

  it 'returns equal header content' do
    _status, headers, _body = middleware.call({})

    expect(headers).to eq(shared_headers)
  end

  it 'returns a different headers object on every call' do
    _s, first, _b  = middleware.call({})
    _s, second, _b = middleware.call({})

    expect(first).not_to equal(second)
  end

  describe 'with a rack-session style cookie commit above it' do
    it 'leaves the shared downstream hash untouched' do
      _s, headers, _b = middleware.call({})
      commit_cookie(headers, 'sid-1')

      expect(shared_headers).to eq('content-type' => 'application/json')
    end

    it 'gives the second request only its own cookie' do
      _s, first, _b = middleware.call({})
      commit_cookie(first, 'sid-1')

      _s, second, _b = middleware.call({})
      commit_cookie(second, 'sid-2')

      expect(set_cookie_values(second)).to eq(['onetime.session=sid-2'])
    end

    it 'does not grow across a burst of commits' do
      counts = Array.new(25) do |i|
        _s, headers, _b = middleware.call({})
        commit_cookie(headers, "sid-#{i}")
        set_cookie_values(headers).size
      end

      expect(counts).to all(eq(1))
    end
  end

  describe 'when the downstream hash already carries a multi-valued header' do
    # Rack 3 represents repeated headers as Arrays. A shallow hash copy alone
    # would share that Array, and rack's set_cookie appends to an existing
    # Array in place — so the copy must reach one level down.
    let(:shared_headers) do
      { 'content-type' => 'application/json', 'set-cookie' => ['stale=1'] }
    end

    it 'does not append into the shared Array' do
      _s, headers, _b = middleware.call({})
      commit_cookie(headers, 'sid-1')

      expect(shared_headers['set-cookie']).to eq(['stale=1'])
    end

    it 'still exposes the downstream value plus this request\'s own' do
      _s, headers, _b = middleware.call({})
      commit_cookie(headers, 'sid-1')

      expect(set_cookie_values(headers)).to eq(['stale=1', 'onetime.session=sid-1'])
    end
  end

  describe 'when the downstream returns Rack::Headers' do
    let(:shared_headers) { Rack::Headers.new.merge!('Content-Type' => 'text/html') }

    it 'preserves the headers class' do
      _s, headers, _b = middleware.call({})

      expect(headers).to be_a(Rack::Headers)
    end

    it 'keeps case-insensitive lookup working on the copy' do
      _s, headers, _b = middleware.call({})

      expect(headers['content-type']).to eq('text/html')
    end
  end

  describe 'when the downstream returns a fresh hash per request (the normal case)' do
    let(:downstream) { ->(_env) { [200, { 'content-type' => 'text/plain' }, ['ok']] } }

    it 'passes the content through unchanged' do
      expect(middleware.call({})).to eq([200, { 'content-type' => 'text/plain' }, ['ok']])
    end
  end

  describe 'when the downstream returns nil headers (malformed response)' do
    let(:downstream) { ->(_env) { [500, nil, []] } }

    it 'leaves nil in place rather than inventing a hash' do
      _s, headers, _b = middleware.call({})

      expect(headers).to be_nil
    end
  end
end

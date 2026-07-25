# spec/unit/auth/json_body_spec.rb
#
# frozen_string_literal: true

require 'spec_helper'
require 'json'
require 'rack'
require 'auth/routes/json_body'

# Pins Auth::Routes::JsonBody#json_body_params — the shared body parser for the
# hand-rolled SSO-linking routes (link_sso, sso_link_confirm).
#
# The load-bearing behavior (PR #3900 review): an EXPLICIT JSON value must win
# over a form/query param of the same name even when it is FALSY (false, 0,
# null). The previous `parsed[key] || request.params[key]` treated those as
# absent and silently fell back — changing the meaning of a request for any
# future route that accepts boolean or numeric JSON fields. Presence is now
# decided with Hash#key?, never truthiness.
RSpec.describe Auth::Routes::JsonBody do
  let(:harness) { Class.new { include Auth::Routes::JsonBody }.new }

  # A real Rack::Request: a JSON POST body plus a query param riding the URL.
  # (Rack never form-parses an application/json body, so request.params sees
  # only the query string — exactly the fallback source the parser consults.)
  def request_for(json_body, query: '')
    env = Rack::MockRequest.env_for(
      "/route#{query}",
      method: 'POST',
      input: json_body,
      'CONTENT_TYPE' => 'application/json',
    )
    Rack::Request.new(env)
  end

  def parse(request, *keys)
    harness.send(:json_body_params, request, *keys)
  end

  it 'lets an explicit JSON false win over a query param of the same name' do
    request = request_for(JSON.generate(flag: false), query: '?flag=from-query')
    expect(parse(request, :flag)).to eq(flag: 'false')
  end

  it 'lets an explicit JSON 0 win over a query param of the same name' do
    request = request_for(JSON.generate(count: 0), query: '?count=9')
    expect(parse(request, :count)).to eq(count: '0')
  end

  # An explicit null is a SENT value, not an absent key: it stringifies to ''
  # (indistinguishable from missing, per the parser's contract) and must NOT
  # resurrect a form/query param the JSON body deliberately nulled out.
  it 'treats an explicit JSON null as empty, not as absent (no fallback)' do
    request = request_for(JSON.generate(token: nil), query: '?token=from-query')
    expect(parse(request, :token)).to eq(token: '')
  end

  it 'falls back to form/query params only when the key is ABSENT from the JSON body' do
    request = request_for(JSON.generate(other: 'x'), query: '?token=from-query')
    expect(parse(request, :token, :other)).to eq(token: 'from-query', other: 'x')
  end

  it 'returns empty strings for keys present nowhere' do
    request = request_for(JSON.generate({}))
    expect(parse(request, :token)).to eq(token: '')
  end

  it 'falls back to params for an unparseable body, leaving the input rewound' do
    request = request_for('{not json', query: '?token=from-query')
    expect(parse(request, :token)).to eq(token: 'from-query')
    expect(request.body.read).to eq('{not json')
  end
end

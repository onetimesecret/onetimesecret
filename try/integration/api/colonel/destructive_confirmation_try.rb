# try/integration/api/colonel/destructive_confirmation_try.rb
#
# frozen_string_literal: true

# Server-side destructive-action confirmation (#4326) over a REAL Rack stack.
#
# The unit specs prove the guard; this proves the TRANSPORT — that the
# X-OTS-Confirm request header actually reaches the logic layer through the
# colonel session auth strategy's metadata, and that nothing else does.
#
# Covers, against DELETE /api/colonel/users/:user_id (PurgeUser, TIER 1):
# - no header                    -> 403 error_code=confirmation_required
# - wrong header                 -> 403, same body (no oracle)
# - ?confirm=<email>, no header  -> STILL 403. The query parameter is not a
#                                   fallback: putting a target's email in a URL
#                                   writes it into every access log, proxy log
#                                   and browser history, which is the whole
#                                   reason this is a header.
# - percent-encoded header       -> accepted (a non-ASCII token has to survive
#                                   the ISO-8859-1 header charset)
# - correct header               -> 200, the account is really gone
# - a POST verb (unverify, TIER 2) reads the SAME header, so there is one rule
# - the rejections write NO ColonelAuditEvent (Forbidden family — otherwise a
#   hammered gate is a log-eviction primitive against the count-capped trail)
#
# Run: try --agent try/integration/api/colonel/destructive_confirmation_try.rb

require 'rack/test'
require_relative '../../../support/test_helpers'

OT.boot! :test

require 'onetime/application/registry'
Onetime::Application::Registry.prepare_application_registry

@test = Object.new
@test.extend Rack::Test::Methods

def @test.app
  Onetime::Application::Registry.generate_rack_url_map
end

def post(*args);   @test.post(*with_csrf(args));   end
def delete(*args); @test.delete(*with_csrf(args)); end
def last_response; @test.last_response; end
def body; JSON.parse(last_response.body); end

AE = Onetime::ColonelAuditEvent

@timestamp = Familia.now.to_i

@colonel = Onetime::Customer.create!(email: "colonel_dconf_#{@timestamp}@example.com")
@colonel.role     = 'colonel'
@colonel.verified = 'true'
@colonel.save

@target = Onetime::Customer.create!(email: "target_dconf_#{@timestamp}@example.com")
@target.verified = 'true'
@target.save

@unverify_target = Onetime::Customer.create!(email: "unver_dconf_#{@timestamp}@example.com")
@unverify_target.verified = 'true'
@unverify_target.save

@colonel_session = {
  'authenticated' => true,
  'external_id'   => @colonel.extid,
  'email'         => @colonel.email,
}

# `confirm` is the percent-encoded token, exactly as the console sends it.
def colonel_headers(confirm = nil)
  headers = { 'rack.session' => @colonel_session, 'HTTP_ACCEPT' => 'application/json' }
  headers['HTTP_X_OTS_CONFIRM'] = confirm if confirm
  headers
end

@purge_url = "/api/colonel/users/#{@target.extid}"

## Without the confirmation header the purge is refused
delete @purge_url, {}, colonel_headers
[last_response.status, body['error_type'], body['error_code'], body['field']]
#=> [403, "ConfirmationRequired", "confirmation_required", "user_id"]

## The refusal names the header and what to put in it, never the value itself
[body['error'].include?('X-OTS-Confirm'), body['error'].include?(@target.email)]
#=> [true, false]

## A wrong token gets the identical body — no oracle on which half was wrong
@refusal = body
delete @purge_url, {}, colonel_headers('someone%40else.example')
[last_response.status, body['error'] == @refusal['error']]
#=> [403, true]

## The account is still there after both refusals
Onetime::Customer.load(@target.objid)&.exists?
#=> true

## A `confirm` QUERY PARAMETER is NOT a fallback — the header is the transport
delete "#{@purge_url}?confirm=#{Rack::Utils.escape(@target.email)}", {}, colonel_headers
[last_response.status, body['error_code']]
#=> [403, "confirmation_required"]

## A `confirm` BODY parameter is not a fallback either
delete @purge_url, { 'confirm' => @target.email }, colonel_headers
[last_response.status, body['error_code']]
#=> [403, "confirmation_required"]

## None of those refusals wrote an audit event
AE.events.revrange(0, -1).map { |id| AE.load(id) }.compact.count do |event|
  event.target.to_s == @target.extid && event.verb.to_s == 'account.purge'
end
#=> 0

## The SAME header gates a POST verb (unverify, TIER 2) — one rule, not two
post "/api/colonel/users/#{@unverify_target.extid}/unverify", {}, colonel_headers
[last_response.status, body['error_code']]
#=> [403, "confirmation_required"]

## ...and the correct token lets that POST through
post "/api/colonel/users/#{@unverify_target.extid}/unverify", {},
  colonel_headers(Rack::Utils.escape(@unverify_target.email))
last_response.status
#=> 200

## The restorative twin (verify) needs no header at all
post "/api/colonel/users/#{@unverify_target.extid}/verify", {}, colonel_headers
last_response.status
#=> 200

## A percent-encoded token decodes server-side and is accepted
delete @purge_url, {}, colonel_headers(Rack::Utils.escape(@target.email))
[last_response.status, body['record']['deleted']]
#=> [200, true]

## ...and the account really is gone
!Onetime::Customer.load(@target.objid)&.exists?
#=> true

# Teardown.
@unverify_target.destroy! if @unverify_target.exists?
@colonel.destroy! if @colonel.exists?

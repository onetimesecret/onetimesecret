# try/integration/api/colonel/get_system_settings_try.rb
#
# frozen_string_literal: true

# Integration tests for the colonel system-settings endpoint credential masking
# (ITEM 11 — no-creds-in-payload):
#
#   GET /api/colonel/config
#
# The emailer section carries SMTP user/pass; the mail (TrueMail) section can
# carry a verification-API key. Both must be masked (last-4 visible) before they
# cross the wire, while non-secret config (host / port / from / verifier_email)
# stays visible. Covers:
# - emailer.user / emailer.pass masked (not cleartext), host/port/from visible
# - mail.verifier_api_key masked, verifier_email / smtp_secure visible
# - 403 non-colonel, 401 anonymous
#
# Run: try --agent try/integration/api/colonel/get_system_settings_try.rb

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

def get(*args);    @test.get(*args);    end
def last_response; @test.last_response; end

@timestamp = Familia.now.to_i

@colonel = Onetime::Customer.create!(email: "colonel_gss_#{@timestamp}@example.com")
@colonel.role = 'colonel'
@colonel.verified = 'true'
@colonel.save

@regular = Onetime::Customer.create!(email: "regular_gss_#{@timestamp}@example.com")
@regular.verified = 'true'
@regular.save

@colonel_session = {
  'authenticated' => true, 'external_id' => @colonel.extid, 'email' => @colonel.email,
}
@regular_session = {
  'authenticated' => true, 'external_id' => @regular.extid, 'email' => @regular.email,
}

def colonel_headers
  { 'rack.session' => @colonel_session, 'HTTP_ACCEPT' => 'application/json' }
end

# Inject known secret-bearing config (test-mode conf is NOT deep-frozen). Saved
# and restored at teardown so this file does not leak state into the process.
@orig_emailer = OT.conf['emailer']
@orig_mail    = OT.conf['mail']

OT.conf['emailer'] = {
  'mode' => 'smtp',
  'host' => 'smtp.example.com',
  'port' => 587,
  'from' => 'noreply@example.com',
  'user' => 'smtp-user-abcd',
  'pass' => 'super-secret-password',
}
OT.conf['mail'] = {
  'verifier_email' => 'verify@example.com',
  'smtp_secure'    => true,
  'verifier_api_key' => 'truemail-api-key-wxyz',
}

URL = '/api/colonel/config'

# ----------------------------------------------------------------
# Authorization
# ----------------------------------------------------------------

## Non-colonel gets 403
get URL, {}, { 'rack.session' => @regular_session, 'HTTP_ACCEPT' => 'application/json' }
last_response.status
#=> 403

## Anonymous gets 401
@test.clear_cookies
get URL, {}, { 'HTTP_ACCEPT' => 'application/json' }
last_response.status
#=> 401

# ----------------------------------------------------------------
# Emailer masking
# ----------------------------------------------------------------

## 200 with an emailer section
get URL, {}, colonel_headers
@resp = JSON.parse(last_response.body)
[last_response.status, @resp['details'].key?('emailer')]
#=> [200, true]

## emailer.user is masked (not cleartext) but keeps its last 4 chars
@resp = JSON.parse(last_response.body)
u = @resp['details']['emailer']['user']
[u != 'smtp-user-abcd', u.include?('*'), u.end_with?('abcd')]
#=> [true, true, true]

## emailer.pass is masked (no cleartext secret on the wire)
@resp = JSON.parse(last_response.body)
p = @resp['details']['emailer']['pass']
[p != 'super-secret-password', p.include?('*')]
#=> [true, true]

## non-secret emailer config stays visible (host / port / from)
@resp = JSON.parse(last_response.body)
e = @resp['details']['emailer']
[e['host'], e['port'], e['from']]
#=> ['smtp.example.com', 587, 'noreply@example.com']

# ----------------------------------------------------------------
# Mail (TrueMail) masking
# ----------------------------------------------------------------

## mail.verifier_api_key is masked, keeping last 4
@resp = JSON.parse(last_response.body)
k = @resp['details']['mail']['verifier_api_key']
[k != 'truemail-api-key-wxyz', k.include?('*'), k.end_with?('wxyz')]
#=> [true, true, true]

## non-secret mail config stays visible (verifier_email / smtp_secure)
@resp = JSON.parse(last_response.body)
m = @resp['details']['mail']
[m['verifier_email'], m['smtp_secure']]
#=> ['verify@example.com', true]

# ----------------------------------------------------------------
# Teardown
# ----------------------------------------------------------------
OT.conf['emailer'] = @orig_emailer
OT.conf['mail']    = @orig_mail
@colonel.destroy!  rescue nil
@regular.destroy!  rescue nil

# try/integration/api/colonel/add_email_suppression_try.rb
#
# frozen_string_literal: true

# Integration tests for the colonel manual add-to-suppression endpoint (ITEM 6):
#
#   POST /api/colonel/email/deliverability/suppressions
#
# Covers:
# - 200 + one audit event (verb email.suppress) on a NEW address; record.created true
# - re-POST of the same address → :updated → STILL audits; record.created false
# - blank address → 422 form error AND NO audit event (suppress! returned nil)
# - reason/source are fixed SERVER-SIDE ('manual' / 'colonel') — audit detail proves it
# - 403 for non-colonel, 401 for anonymous
#
# Run: try --agent try/integration/api/colonel/add_email_suppression_try.rb

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

def post(*args);   @test.post(*args);   end
def get(*args);    @test.get(*args);    end
def last_response; @test.last_response; end

AE  = Onetime::AdminAuditEvent
SUP = Onetime::EmailSuppression

@timestamp = Familia.now.to_i

@colonel = Onetime::Customer.create!(email: "colonel_aes_#{@timestamp}@example.com")
@colonel.role = 'colonel'
@colonel.verified = 'true'
@colonel.save

@regular = Onetime::Customer.create!(email: "regular_aes_#{@timestamp}@example.com")
@regular.verified = 'true'
@regular.save

@colonel_session = {
  'authenticated' => true,
  'external_id'   => @colonel.extid,
  'email'         => @colonel.email,
}
@regular_session = {
  'authenticated' => true,
  'external_id'   => @regular.extid,
  'email'         => @regular.email,
}

def colonel_headers
  { 'rack.session' => @colonel_session, 'HTTP_ACCEPT' => 'application/json' }
end

@addr = "suppress_me_#{@timestamp}@example.com"
SUP.remove!(@addr) # clean slate

URL = '/api/colonel/email/deliverability/suppressions'

# ----------------------------------------------------------------
# Authorization
# ----------------------------------------------------------------

## Non-colonel gets 403
post URL, { 'address' => @addr },
  { 'rack.session' => @regular_session, 'HTTP_ACCEPT' => 'application/json' }
last_response.status
#=> 403

## Anonymous gets 401
@test.clear_cookies
post URL, { 'address' => @addr }, { 'HTTP_ACCEPT' => 'application/json' }
last_response.status
#=> 401

# ----------------------------------------------------------------
# Create (new address → :created, audits once)
# ----------------------------------------------------------------

## Colonel POST of a NEW address → 200 with record.created true
@before = AE.count
post URL, { 'address' => @addr }, colonel_headers
@resp = JSON.parse(last_response.body)
[last_response.status, @resp['record']['address'], @resp['record']['created']]
#=> [200, @addr, true]

## exactly one audit event, verb email.suppress, target = address, colonel actor
@evt = AE.recent(1).first
[
  AE.count - @before,
  @evt['verb'],
  @evt['actor'] == @colonel.extid,
  @evt['target'] == @addr,
  @evt['result'],
]
#=> [1, 'email.suppress', true, true, 'success']

## audit detail proves reason/source are server-fixed to manual/colonel
@evt = AE.recent(1).first
[@evt['detail']['reason'], @evt['detail']['source'], @evt['detail']['change']]
#=> ['manual', 'colonel', 'created']

# ----------------------------------------------------------------
# Update (re-POST same address → :updated, STILL audits)
# ----------------------------------------------------------------

## re-POST the same address → 200, record.created false (already existed)
@before = AE.count
post URL, { 'address' => @addr }, colonel_headers
@resp = JSON.parse(last_response.body)
[last_response.status, @resp['record']['created']]
#=> [200, false]

## the update STILL records an audit event (change = updated)
@evt = AE.recent(1).first
[AE.count - @before, @evt['verb'], @evt['detail']['change']]
#=> [1, 'email.suppress', 'updated']

# ----------------------------------------------------------------
# Blank address → 422, NO audit
# ----------------------------------------------------------------

## blank address → 422 form error AND audit count UNCHANGED
@before = AE.count
post URL, { 'address' => '   ' }, colonel_headers
[last_response.status, AE.count - @before]
#=> [422, 0]

# ----------------------------------------------------------------
# Teardown
# ----------------------------------------------------------------
SUP.remove!(@addr)   rescue nil
@colonel.destroy!    rescue nil
@regular.destroy!    rescue nil

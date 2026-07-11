# try/integration/api/colonel/get_billing_catalog_try.rb
#
# frozen_string_literal: true

# Integration tests for the colonel billing-catalog drift endpoint:
#
#   GET /api/colonel/billing/catalog
#
# Part of the Colonel Admin Rebuild epic (#3653), Phase 3 ticket #45. The
# endpoint is a READ-ONLY adapter over the incumbent Billing::Plan source
# (list_plans + list_plans_from_config) — no op extraction, no mutating route
# (spec: read-only drift first; sync stays CLI-only). It returns BOTH the
# configured catalog and the live Stripe-synced plans plus a computed drift
# summary.
#
# Covers:
# - 401 for anonymous, 403 for non-colonel (defense-in-depth: router + logic)
# - 200 for colonel with the record/details envelope
# - details carries config_plans + live_plans + a drift summary
# - source is "local_config" when the Stripe cache is empty (test env)
# - READ-ONLY: the request records NO AdminAuditEvent (CONTRACT 4)
#
# Run: try --agent try/integration/api/colonel/get_billing_catalog_try.rb

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

# Colonel user (role persisted so session auth reads it)
@colonel = Onetime::Customer.create!(email: "colonel_billing_#{@timestamp}@example.com")
@colonel.role = 'colonel'
@colonel.verified = 'true'
@colonel.save

# Regular (non-colonel) customer
@regular = Onetime::Customer.create!(email: "regular_billing_#{@timestamp}@example.com")
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

@path = '/api/colonel/billing/catalog'

# TRYOUTS

## Anonymous (no session) gets 401
@test.clear_cookies
get @path, {}, { 'HTTP_ACCEPT' => 'application/json' }
last_response.status
#=> 401

## Non-colonel gets 403
get @path, {}, { 'rack.session' => @regular_session, 'HTTP_ACCEPT' => 'application/json' }
last_response.status
#=> 403

## Colonel gets 200 with the record/details envelope
get @path, {}, { 'rack.session' => @colonel_session, 'HTTP_ACCEPT' => 'application/json' }
@resp = JSON.parse(last_response.body)
[last_response.status, @resp['details'].is_a?(Hash)]
#=> [200, true]

## details exposes both catalog sides plus a drift summary
d = @resp['details']
[d['config_plans'].is_a?(Array), d['live_plans'].is_a?(Array), d['drift'].is_a?(Hash)]
#=> [true, true, true]

## the drift summary carries the expected key set
@resp['details']['drift'].keys.sort
#=> ["changed", "in_sync", "only_in_config", "only_in_live"]

## with no Stripe cache in test env, source is local_config and live is empty
d = @resp['details']
[d['source'], d['live_plans'].empty?, d['stripe_configured']]
#=> ["local_config", true, false]

## every configured plan carries the shared PlanEntry field set
plan = @resp['details']['config_plans'].first
plan.nil? || (%w[planid name tier entitlements limits] - plan.keys).empty?
#=> true

## READ-ONLY: the request records NO AdminAuditEvent (CONTRACT 4)
@before = Onetime::AdminAuditEvent.events.size
get @path, {}, { 'rack.session' => @colonel_session, 'HTTP_ACCEPT' => 'application/json' }
Onetime::AdminAuditEvent.events.size - @before
#=> 0

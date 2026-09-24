# try/integration/api/colonel/webhook_visibility_try.rb
#
# frozen_string_literal: true

# Integration coverage for Colonel-local webhook visibility:
# - list retained webhook records and one safe detail projection;
# - list legacy pending federation records without their email hashes;
# - enforce the router's colonel gate;
# - detail reads append one access observation, while list reads append none.

require 'rack/test'
require_relative '../../../support/test_helpers'

OT.boot! :test

require 'onetime/application/registry'
require 'billing/models/stripe_webhook_event'
require 'billing/models/pending_federated_subscription'
Onetime::Application::Registry.prepare_application_registry

@test = Object.new
@test.extend Rack::Test::Methods

def @test.app
  Onetime::Application::Registry.generate_rack_url_map
end

def get(*args); @test.get(*args); end
def last_response; @test.last_response; end

@timestamp = Familia.now.to_i
@colonel = Onetime::Customer.create!(email: "colonel_webhook_visibility_#{@timestamp}@example.com")
@colonel.role = 'colonel'
@colonel.verified = 'true'
@colonel.save
@regular = Onetime::Customer.create!(email: "regular_webhook_visibility_#{@timestamp}@example.com")
@regular.verified = 'true'
@regular.save

@colonel_headers = {
  'rack.session' => { 'authenticated' => true, 'external_id' => @colonel.extid, 'email' => @colonel.email },
  'HTTP_ACCEPT' => 'application/json',
}
@regular_headers = {
  'rack.session' => { 'authenticated' => true, 'external_id' => @regular.extid, 'email' => @regular.email },
  'HTTP_ACCEPT' => 'application/json',
}

@event_id = "evt_colonel_visibility_#{@timestamp}"
@event = Billing::StripeWebhookEvent.new(stripe_event_id: @event_id)
@event.event_type = 'customer.subscription.updated'
@event.processing_status = 'retrying'
@event.first_seen_at = @timestamp.to_s
@event.attempt_count = '1'
@event.error_message = 'customer cus_should_not_be_exposed failed'
@event.data_object_id = 'cus_should_not_be_exposed'
@event.event_payload = '{"customer":"cus_should_not_be_exposed"}'
@event.save
# WebhookVisibility reads a write-time sorted-set index instead of scanning
# the object keyspace. Real callers register through
# Billing::WebhookValidator#initialize_event_record; this fixture writes the
# row directly, so the index has to be populated the same way.
Billing::StripeWebhookEvent.record_recent_index(@event)

@pending_hash = "pending_hash_should_not_be_exposed_#{@timestamp}"
@pending = Billing::PendingFederatedSubscription.new(@pending_hash)
@pending.subscription_status = 'active'
@pending.planid = 'pro_v1'
@pending.region = 'eu'
@pending.received_at = @timestamp.to_s
@pending.save
Billing::PendingFederatedSubscription.record_recent_index(@pending)

## Anonymous webhook list gets 401
get '/api/colonel/billing/webhook-events', {}, { 'HTTP_ACCEPT' => 'application/json' }
last_response.status
#=> 401

## Non-colonel webhook list gets 403
get '/api/colonel/billing/webhook-events', {}, @regular_headers
last_response.status
#=> 403

## Colonel webhook list returns the safe paginated envelope
get '/api/colonel/billing/webhook-events', { 'per_page' => '100' }, @colonel_headers
@webhooks = JSON.parse(last_response.body)
[@webhooks['details']['events'].any? { |event| event['event_id'] == @event_id }, @webhooks['details']['pagination']['capped']]
#=> [true, false]

## Webhook detail returns safe metadata but never payload/customer identifiers/error text
@access_before = Onetime::ColonelAuditEvent.access_count
get "/api/colonel/billing/webhook-events/#{@event_id}", {}, @colonel_headers
@detail = JSON.parse(last_response.body)
[
  last_response.status,
  @detail['record']['event_id'],
  @detail['details']['error_present'],
  @detail.to_s.include?('cus_should_not_be_exposed'),
  @detail.to_s.include?('event_payload'),
]
#=> [200, @event_id, true, false, false]

## Webhook detail writes exactly one safe access observation
@access_events = Onetime::ColonelAuditEvent.recent_access(1)
[
  Onetime::ColonelAuditEvent.access_count - @access_before,
  @access_events.first['verb'],
  @access_events.first['target'],
  @access_events.first.to_s.include?('cus_should_not_be_exposed'),
]
#=> [1, "billing.webhook.inspect", @event_id, false]

## Missing or expired webhook ids 404
get "/api/colonel/billing/webhook-events/evt_missing_#{@timestamp}", {}, @colonel_headers
last_response.status
#=> 404

## Pending federation list omits the email hash and gives legacy rows an unavailable source state
get '/api/colonel/billing/pending-federated-subscriptions', { 'per_page' => '100' }, @colonel_headers
@pending_response = JSON.parse(last_response.body)
@pending_row = @pending_response['details']['subscriptions'].find { |row| row['received_at'] == @timestamp }
[
  last_response.status,
  @pending_row['subscription_status'],
  @pending_row['region'],
  @pending_row['source_webhook']['state'],
  @pending_response.to_s.include?(@pending_hash),
]
#=> [200, "active", "eu", "no_correlation", false]

# The read path relies on load_multi leaving nil (never a blank shell) for an
# id whose object key is gone. That is Familia behaviour, so pin it against a
# real datastore rather than a stub: the index entry outlives the object.
@gone_id = "evt_colonel_visibility_gone_#{@timestamp}"
@gone = Billing::StripeWebhookEvent.new(stripe_event_id: @gone_id)
@gone.event_type = 'invoice.paid'
@gone.first_seen_at = (@timestamp + 1).to_s
@gone.save
@gone.destroy!
Billing::StripeWebhookEvent.record_recent_index(@gone)

@orphan_hash = "pending_hash_orphan_source_#{@timestamp}"
@orphan = Billing::PendingFederatedSubscription.new(@orphan_hash)
@orphan.subscription_status = 'past_due'
@orphan.received_at = (@timestamp + 1).to_s
@orphan.source_stripe_event_id = @gone_id
@orphan.save
Billing::PendingFederatedSubscription.record_recent_index(@orphan)

## A pending record whose source event key is gone reports 'expired', not 'available'
get '/api/colonel/billing/pending-federated-subscriptions', { 'per_page' => '100' }, @colonel_headers
@orphan_row = JSON.parse(last_response.body)['details']['subscriptions'].find { |row| row['received_at'] == @timestamp + 1 }
@orphan_row['source_webhook']
#=> { 'state' => 'expired', 'processing_status' => nil, 'outcome' => nil }

## An indexed event whose object key is gone is counted stale, pruned, and never rendered as a blank row
get '/api/colonel/billing/webhook-events', { 'per_page' => '100' }, @colonel_headers
@stale_page = JSON.parse(last_response.body)['details']
[
  @stale_page['events'].any? { |event| event['event_id'] == @gone_id || event['event_id'].nil? },
  @stale_page['stale_count'] >= 1,
  Billing::StripeWebhookEvent.recent_events.member?(@gone_id),
]
#=> [false, true, false]

Billing::StripeWebhookEvent.recent_events.remove(@gone_id) rescue nil
Billing::PendingFederatedSubscription.recent_records.remove(@orphan_hash) rescue nil
Billing::PendingFederatedSubscription.recent_records.remove(@pending_hash) rescue nil
Billing::StripeWebhookEvent.recent_events.remove(@event_id) rescue nil
@orphan.destroy! rescue nil
@event.destroy! rescue nil
@pending.destroy! rescue nil
@colonel.destroy! rescue nil
@regular.destroy! rescue nil

# apps/api/v2/spec/models/organization_audit_trail_spec.rb
#
# frozen_string_literal: true

require_relative '../../application'
require_relative File.join(Onetime::HOME, 'spec', 'spec_helper')

# Audit-fidelity coverage for the organization audit trail (#3633).
#
# The trail backs the paid `audit_logs` entitlement, so these specs pin the
# properties an audit consumer relies on:
#
#   COMPLETENESS - every receipt event (access fetches, lifecycle
#     transitions, creation) with org context lands in the trail exactly
#     once; guarded transitions cannot double-record.
#   ACCURACY - events carry the right kind, timestamp, and shortid context;
#     two identical events in the same second are both retained (the nonce
#     prevents silent ZADD overwrites).
#   ISOLATION - events land only in the owning org's trail; receipts
#     without org context write nowhere and raise nothing.
#   CONTAINMENT - a failing trail write never breaks or reverts the
#     product action it observes (reveal/burn must still succeed).
#   NON-LEAKAGE - events carry shortids only; the full secret identifier
#     is a capability token and must never appear in the trail.
RSpec.describe Onetime::Organization, type: :integration do
  before(:all) do
    require 'onetime'
    Onetime.boot! :test
  end

  let(:org) do
    described_class.new(
      display_name: 'Audit Fidelity Test Org',
      contact_email: "audit-#{SecureRandom.hex(6)}@example.com",
    ).tap(&:save)
  end

  let!(:pair)   { Onetime::Receipt.spawn_pair(nil, 3600, 'a secret value') }
  let(:receipt) { pair.first }
  let(:secret)  { pair.last }

  def link_to_org!(receipt, organization)
    receipt.org_id = organization.objid
    receipt.save_fields(:org_id)
  end

  describe '#record_audit_event (accuracy)' do
    it 'stores kind, timestamp and context, and pages newest-first' do
      t1 = Familia.now.to_f - 20
      t2 = Familia.now.to_f - 10
      org.record_audit_event('created', at: t1, 'receipt' => 'abc123')
      org.record_audit_event('revealed', at: t2, 'receipt' => 'abc123')

      events = org.audit_events_page
      expect(events.size).to eq(2)

      newest, oldest = events
      expect(newest['kind']).to eq('revealed')
      expect(newest['at']).to be_within(0.001).of(t2)
      expect(newest['receipt']).to eq('abc123')
      expect(oldest['kind']).to eq('created')
      expect(oldest['at']).to be_within(0.001).of(t1)
    end

    it 'records nothing for a blank kind' do
      expect(org.record_audit_event('')).to be_nil
      expect(org.record_audit_event(nil)).to be_nil
      expect(org.audit_event_count).to eq(0)
    end

    it 'retains two identical events in the same second (no silent overwrite)' do
      at = Familia.now.to_f
      org.record_audit_event('secret_get', at: at, 'receipt' => 'abc123')
      org.record_audit_event('secret_get', at: at, 'receipt' => 'abc123')

      expect(org.audit_event_count).to eq(2)
    end

    it 'evicts only the oldest events past the retention cap' do
      stub_const('Onetime::Organization::Features::AuditTrail::AUDIT_EVENTS_MAX', 5)

      base = Familia.now.to_f - 100
      8.times { |i| org.record_audit_event('secret_get', at: base + i) }

      expect(org.audit_event_count).to eq(5)
      ats = org.audit_events_page.map { |e| e['at'] }
      expect(ats.min).to be_within(0.001).of(base + 3)
      expect(ats.max).to be_within(0.001).of(base + 7)
    end

    it 'clamps pagination inputs and windows correctly' do
      base = Familia.now.to_f - 100
      5.times { |i| org.record_audit_event('secret_get', at: base + i) }

      page = org.audit_events_page(offset: 2, limit: 2)
      expect(page.size).to eq(2)
      expect(page[0]['at']).to be_within(0.001).of(base + 2)
      expect(page[1]['at']).to be_within(0.001).of(base + 1)

      expect(org.audit_events_page(offset: -3, limit: 0).size).to eq(1)
      expect(org.audit_events_page(offset: 0, limit: 9_999).size).to eq(5)
    end
  end

  describe 'fan-out from receipt access (completeness)' do
    it 'mirrors access-timeline events into the org trail with shortid context' do
      link_to_org!(receipt, org)

      receipt.record_access_event('status_get')

      events = org.audit_events_page
      expect(events.size).to eq(1)
      expect(events.first['kind']).to eq('status_get')
      expect(events.first['receipt']).to eq(receipt.shortid)
      expect(events.first['secret']).to eq(receipt.secret_shortid)
    end

    it 'never leaks the full secret identifier into the trail' do
      link_to_org!(receipt, org)
      receipt.record_access_event('secret_get')

      raw = org.audit_events.membersraw.join
      expect(raw).not_to include(secret.identifier)
      expect(raw).not_to include(receipt.identifier)
    end

    it 'writes nowhere and raises nothing for receipts without org context' do
      expect { receipt.record_access_event('status_get') }.not_to raise_error
      expect(org.audit_event_count).to eq(0)
    end

    it 'caps one receipt\'s fetch contribution so a hammered link cannot flood the trail' do
      stub_const('Onetime::Receipt::Features::AccessTimeline::ACCESS_EVENTS_MAX', 3)
      link_to_org!(receipt, org)

      5.times { receipt.record_access_event('status_get') }

      # The receipt's own timeline saturates at the cap, and fan-out stops
      # with it: other receipts' history in the org trail stays safe.
      expect(receipt.access_count).to eq(3)
      expect(org.audit_event_count).to eq(3)

      # Lifecycle transitions are not subject to the fetch bound.
      receipt.revealed!
      expect(org.audit_events_page.first['kind']).to eq('revealed')
    end
  end

  describe 'fan-out from lifecycle transitions (completeness + no duplicates)' do
    before { link_to_org!(receipt, org) }

    it 'records the receipt view exactly once, under its unambiguous audit kind' do
      receipt.record_receipt_view!
      receipt.record_receipt_view! # guard: claim_once! already stamped receipt_viewed_at

      # 'preview' is UI language; the trail records what mechanically
      # happened: the receipt page was loaded.
      kinds = org.audit_events_page.map { |e| e['kind'] }
      expect(kinds).to eq(['receipt_viewed'])
    end

    it 'records revealed exactly once even if called repeatedly' do
      receipt.revealed!
      receipt.revealed! # guard: state is no longer :new/:previewed

      kinds = org.audit_events_page.map { |e| e['kind'] }
      expect(kinds).to eq(['revealed'])
    end

    it 'records burned exactly once' do
      receipt.burned!
      receipt.burned!

      kinds = org.audit_events_page.map { |e| e['kind'] }
      expect(kinds).to eq(['burned'])
    end

    it 'records orphaned exactly once' do
      receipt.orphaned!
      receipt.orphaned!

      kinds = org.audit_events_page.map { |e| e['kind'] }
      expect(kinds).to eq(['orphaned'])
    end

    it 'does not record expired for a receipt that has not expired' do
      receipt.expired!

      expect(org.audit_event_count).to eq(0)
      expect(receipt.state).to eq('new')
    end

    it 'records expired exactly once for a genuinely expired receipt' do
      # Backdate creation past the secret TTL so secret_expired? is true.
      receipt.created = Familia.now.to_i - receipt.secret_ttl.to_i - 60
      receipt.save_fields(:created)

      receipt.expired!
      receipt.expired! # second call: state already advanced, guard holds

      kinds = org.audit_events_page.map { |e| e['kind'] }
      expect(kinds).to eq(['expired'])
    end

    it 'reaches the trail through the full reveal cascade (secret -> receipt -> org)' do
      expect(secret.reveal!).to eq('a secret value')

      kinds = org.audit_events_page.map { |e| e['kind'] }
      expect(kinds).to eq(['revealed'])
    end
  end

  # Actor attribution on lifecycle events (#3639). The revealed/burned events
  # must carry WHO acted; the discriminator is computed at the request-scoped
  # logic layer and threaded through the atomic consume cascade. These model
  # specs pin the trail-facing half of that contract:
  #   * record_org_audit_event forwards arbitrary string-keyed event_attrs;
  #   * revealed!/burned! record the threaded actor exactly once (CAS-gated);
  #   * a missing actor context fails safe to 'anonymous' (never 'creator');
  #   * the full Secret -> Receipt -> Org cascade carries the actor down.
  describe 'actor attribution on lifecycle events (#3639)' do
    before { link_to_org!(receipt, org) }

    it 'record_org_audit_event forwards extra string-keyed attrs into the event' do
      receipt.record_org_audit_event('revealed', 'actor' => 'creator', 'actor_id' => 'abcd1234')

      event = org.audit_events_page.first
      expect(event['kind']).to eq('revealed')
      expect(event['actor']).to eq('creator')
      expect(event['actor_id']).to eq('abcd1234')
    end

    it 'threads the actor through revealed! into the trail' do
      receipt.revealed!(actor_context: { 'actor' => 'creator', 'actor_id' => 'abcd1234' })

      event = org.audit_events_page.first
      expect(event['kind']).to eq('revealed')
      expect(event['actor']).to eq('creator')
      expect(event['actor_id']).to eq('abcd1234')
    end

    it 'threads the actor through burned! into the trail' do
      receipt.burned!(actor_context: { 'actor' => 'authenticated_other', 'actor_id' => 'beef5678' })

      event = org.audit_events_page.first
      expect(event['kind']).to eq('burned')
      expect(event['actor']).to eq('authenticated_other')
      expect(event['actor_id']).to eq('beef5678')
    end

    it 'defaults a missing actor context to anonymous on revealed! (never misattributed)' do
      receipt.revealed! # v1 / account-verification path: no request context

      event = org.audit_events_page.first
      expect(event['actor']).to eq('anonymous')
      expect(event).not_to have_key('actor_id')
    end

    it 'defaults a blank actor to anonymous on burned! (never misattributed)' do
      receipt.burned!(actor_context: { 'actor' => '' })

      event = org.audit_events_page.first
      expect(event['actor']).to eq('anonymous')
    end

    it 'records the threaded actor exactly once; a race-loser records nothing' do
      loser = Onetime::Receipt.load(receipt.identifier)

      expect(receipt.revealed!(actor_context: { 'actor' => 'creator', 'actor_id' => 'abcd1234' })).to be true
      # The loser lost the CAS: it neither transitions nor appends an event.
      expect(loser.revealed!(actor_context: { 'actor' => 'authenticated_other' })).to be_falsey

      events = org.audit_events_page
      expect(events.map { |e| e['kind'] }).to eq(['revealed'])
      expect(events.first['actor']).to eq('creator')
    end

    it 'carries the actor down the full Secret -> Receipt -> Org reveal cascade' do
      expect(secret.reveal!(actor_context: { 'actor' => 'authenticated_other', 'actor_id' => 'beef5678' }))
        .to eq('a secret value')

      event = org.audit_events_page.first
      expect(event['kind']).to eq('revealed')
      expect(event['actor']).to eq('authenticated_other')
      expect(event['actor_id']).to eq('beef5678')
    end

    it 'carries the actor down the full Secret -> Receipt -> Org burn cascade' do
      expect(secret.burned!(actor_context: { 'actor' => 'creator', 'actor_id' => 'abcd1234' })).to be true

      event = org.audit_events_page.first
      expect(event['kind']).to eq('burned')
      expect(event['actor']).to eq('creator')
      expect(event['actor_id']).to eq('abcd1234')
    end
  end

  describe 'isolation' do
    let(:other_org) do
      described_class.new(
        display_name: 'Uninvolved Org',
        contact_email: "audit-other-#{SecureRandom.hex(6)}@example.com",
      ).tap(&:save)
    end

    it 'writes only to the owning organization' do
      link_to_org!(receipt, org)
      other_org # materialize before the event

      receipt.record_access_event('secret_get')
      receipt.revealed!

      expect(org.audit_event_count).to eq(2)
      expect(other_org.audit_event_count).to eq(0)
    end
  end

  describe 'containment' do
    before { link_to_org!(receipt, org) }

    it 'a failing trail write does not break or revert the state transition' do
      allow(Onetime::Organization).to receive(:load).and_raise(Familia::Problem, 'trail down')

      expect { receipt.revealed! }.not_to raise_error
      expect(Onetime::Receipt.load(receipt.identifier).state).to eq('revealed')
    end

    it 'a missing (deleted) organization is skipped silently' do
      org.destroy!

      expect { receipt.record_access_event('status_get') }.not_to raise_error
      expect(Onetime::Receipt.load(receipt.identifier).access_count).to eq(1)
    end
  end
end

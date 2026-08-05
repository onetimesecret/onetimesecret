# apps/api/v2/spec/models/organization_secret_activity_spec.rb
#
# frozen_string_literal: true

require_relative '../../application'
require_relative File.join(Onetime::HOME, 'spec', 'spec_helper')
require 'onetime/security/request_context'

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
#   NON-LEAKAGE - receipt/secret context carries shortids only; those full
#     identifiers are capability tokens and must never appear in the trail.
#     The actor_id is deliberately the OPPOSITE convention: the FULL customer
#     objid, stored untruncated for unique traceability (NIST AU-3, PCI DSS
#     10.2.2) -- an objid grants no access, and identity is resolved at
#     read/export time. An email must never enter the trail in any field.
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

  describe '#record_secret_activity_event (accuracy)' do
    it 'stores kind, timestamp and context, and pages newest-first' do
      t1 = Familia.now.to_f - 20
      t2 = Familia.now.to_f - 10
      org.record_secret_activity_event('created', at: t1, 'receipt' => 'abc123')
      org.record_secret_activity_event('revealed', at: t2, 'receipt' => 'abc123')

      events = org.secret_activity_events_page
      expect(events.size).to eq(2)

      newest, oldest = events
      expect(newest['kind']).to eq('revealed')
      expect(newest['at']).to be_within(0.001).of(t2)
      expect(newest['receipt']).to eq('abc123')
      expect(oldest['kind']).to eq('created')
      expect(oldest['at']).to be_within(0.001).of(t1)
    end

    it 'records nothing for a blank kind' do
      expect(org.record_secret_activity_event('')).to be_nil
      expect(org.record_secret_activity_event(nil)).to be_nil
      expect(org.secret_activity_event_count).to eq(0)
    end

    it 'retains two identical events in the same second (no silent overwrite)' do
      at = Familia.now.to_f
      org.record_secret_activity_event('secret_get', at: at, 'receipt' => 'abc123')
      org.record_secret_activity_event('secret_get', at: at, 'receipt' => 'abc123')

      expect(org.secret_activity_event_count).to eq(2)
    end

    it 'evicts only the oldest events past the retention cap' do
      feature = Onetime::Organization::Features::SecretActivity

      # configure! clamps to the MIN_MAX_EVENTS floor, so the smallest
      # testable cap is the floor itself — pin the clamp while we're here.
      expect(feature.configure!(5)).to eq(feature::MIN_MAX_EVENTS)

      # configure! is boot-time-only: an org whose accessor already ran has
      # memoized a DataType with the old cap, so use a FRESH org here.
      capped_org = described_class.new(
        display_name: 'Capped Trail Org',
        contact_email: "audit-cap-#{SecureRandom.hex(6)}@example.com",
      ).tap(&:save)

      cap  = feature::MIN_MAX_EVENTS
      base = Familia.now.to_f - 200
      (cap + 3).times { |i| capped_org.record_secret_activity_event('secret_get', at: base + i) }

      expect(capped_org.secret_activity_event_count).to eq(cap)
      ats = capped_org.secret_activity_events_page(limit: 200).map { |e| e['at'] }
      expect(ats.min).to be_within(0.001).of(base + 3)
      expect(ats.max).to be_within(0.001).of(base + cap + 2)
    ensure
      Onetime::Organization::Features::SecretActivity.configure!(
        Onetime::Organization::Features::SecretActivity::DEFAULT_MAX_EVENTS,
      )
    end

    it 'clamps pagination inputs and windows correctly' do
      base = Familia.now.to_f - 100
      5.times { |i| org.record_secret_activity_event('secret_get', at: base + i) }

      page = org.secret_activity_events_page(offset: 2, limit: 2)
      expect(page.size).to eq(2)
      expect(page[0]['at']).to be_within(0.001).of(base + 2)
      expect(page[1]['at']).to be_within(0.001).of(base + 1)

      expect(org.secret_activity_events_page(offset: -3, limit: 0).size).to eq(1)
      expect(org.secret_activity_events_page(offset: 0, limit: 9_999).size).to eq(5)
    end
  end

  # Instance-level collection toggle (SECRET_ACTIVITY_COLLECT, #3990) — the
  # data-existence axis (GDPR minimization): whether events come to exist at
  # all. Default-true contract: only an explicit false pauses recording — an
  # absent key (older config file) must still record. Pausing never touches
  # reads: existing events stay fully readable (hiding them is the separate
  # ORGS_AUDIT_LOGS_ENABLED axis).
  describe 'collection toggle (features.secret_activity.collect)' do
    def conf_with_collect_flag(secret_activity)
      base     = OT.conf
      features = (base['features'] || {}).merge('secret_activity' => secret_activity)
      base.merge('features' => features)
    end

    # Parity with ConfigSerializer#build_feature_flags: a hand-edited config
    # can deliver the string 'false' where the shipped ERB emits a real
    # boolean. If only the serializer handled it, the UI would show the
    # paused banner while the backend kept recording.
    it "pauses recording on the string 'false' while existing events stay readable" do
      t1 = Familia.now.to_f - 10
      org.record_secret_activity_event('created', at: t1, 'receipt' => 'abc123')

      allow(OT).to receive(:conf)
        .and_return(conf_with_collect_flag('collect' => 'false'))

      expect(org.record_secret_activity_event('secret_get')).to be_nil
      expect(org.secret_activity_event_count).to eq(1)

      events = org.secret_activity_events_page
      expect(events.size).to eq(1)
      expect(events.first['kind']).to eq('created')
      expect(events.first['at']).to be_within(0.001).of(t1)
    end

    it 'pauses recording on native false (shipped ERB boolean)' do
      allow(OT).to receive(:conf)
        .and_return(conf_with_collect_flag('collect' => false))

      expect(org.record_secret_activity_event('secret_get')).to be_nil
      expect(org.secret_activity_event_count).to eq(0)
    end

    it "keeps recording on the string 'true'" do
      allow(OT).to receive(:conf)
        .and_return(conf_with_collect_flag('collect' => 'true'))

      expect(org.record_secret_activity_event('secret_get')).to be_a(Hash)
      expect(org.secret_activity_event_count).to eq(1)
    end

    it 'keeps recording when nil (default-true contract)' do
      allow(OT).to receive(:conf)
        .and_return(conf_with_collect_flag('collect' => nil))

      expect(org.record_secret_activity_event('secret_get')).to be_a(Hash)
      expect(org.secret_activity_event_count).to eq(1)
    end

    it 'keeps recording when the key is absent (older config file)' do
      allow(OT).to receive(:conf).and_return(conf_with_collect_flag({}))

      expect(org.record_secret_activity_event('secret_get')).to be_a(Hash)
      expect(org.secret_activity_event_count).to eq(1)
    end
  end

  # Retention-cap configuration (SECRET_ACTIVITY_MAX_EVENTS, #3990). The cap
  # lives on the stored related-field definition; configure! is the single
  # boot-time mutation point (ConfigureSecretActivity initializer).
  describe '.configure! (retention cap)' do
    let(:feature) { Onetime::Organization::Features::SecretActivity }

    def stored_cap
      Onetime::Organization.related_fields[:secret_activity_events].opts[:max_length]
    end

    after do
      feature.configure!(feature::DEFAULT_MAX_EVENTS)
    end

    it 'applies and returns a cap above the floor' do
      expect(feature.configure!(2_500)).to eq(2_500)
      expect(stored_cap).to eq(2_500)
    end

    it 'clamps values below the floor to MIN_MAX_EVENTS' do
      expect(feature.configure!(99)).to eq(feature::MIN_MAX_EVENTS)
      expect(feature.configure!(1)).to eq(feature::MIN_MAX_EVENTS)
      expect(feature.configure!(0)).to eq(feature::MIN_MAX_EVENTS)
      expect(feature.configure!(-10)).to eq(feature::MIN_MAX_EVENTS)
      expect(stored_cap).to eq(feature::MIN_MAX_EVENTS)
    end

    it 'accepts the floor itself unclamped' do
      expect(feature.configure!(feature::MIN_MAX_EVENTS)).to eq(feature::MIN_MAX_EVENTS)
    end

    it 'coerces an integer-shaped string (ENV/hand-edited YAML deliver one)' do
      expect(feature.configure!('500')).to eq(500)
      expect(stored_cap).to eq(500)
    end

    it 'raises on non-integer input before mutating anything (initializer owns the fallback)' do
      expect { feature.configure!('unbounded') }.to raise_error(ArgumentError)
      expect { feature.configure!(nil) }.to raise_error(TypeError)
      # Integer() raised before the definition was touched: cap unchanged.
      expect(stored_cap).to eq(feature::DEFAULT_MAX_EVENTS)
    end

    # BOOT-ORDERING (the memoization trap the initializer doc warns about):
    # per-org DataType instances snapshot the definition's opts when they
    # materialize (Familia copies opts into the frozen DataType), so
    # configure! only reaches trails materialized AFTER it runs. This is why
    # ConfigureSecretActivity must run at boot, before any org traffic.
    it 'applies only to trails materialized after it runs (boot-time-only)' do
      stale_org = described_class.new(
        display_name: 'Materialized Before Configure',
        contact_email: "audit-stale-#{SecureRandom.hex(6)}@example.com",
      ).tap(&:save)
      # Touch the accessor: the DataType memoizes with the current cap.
      expect(stale_org.secret_activity_events.max_length).to eq(feature::DEFAULT_MAX_EVENTS)

      feature.configure!(2_500)

      fresh_org = described_class.new(
        display_name: 'Materialized After Configure',
        contact_email: "audit-fresh-#{SecureRandom.hex(6)}@example.com",
      ).tap(&:save)

      expect(fresh_org.secret_activity_events.max_length).to eq(2_500)
      # The already-materialized trail keeps the cap it was born with.
      expect(stale_org.secret_activity_events.max_length).to eq(feature::DEFAULT_MAX_EVENTS)
    end
  end

  describe 'fan-out from receipt access (completeness)' do
    it 'mirrors access-timeline events into the org trail with shortid context' do
      link_to_org!(receipt, org)

      receipt.record_access_event('status_get')

      events = org.secret_activity_events_page
      expect(events.size).to eq(1)
      expect(events.first['kind']).to eq('status_get')
      expect(events.first['receipt']).to eq(receipt.shortid)
      expect(events.first['secret']).to eq(receipt.secret_shortid)
      # A fetch recorded without actor context falls to the fail-safe actor:
      # every event in the trail carries a recognized 'actor' (#3637), and the
      # fail-safe is the explicit 'unknown' sentinel (ADR-023).
      expect(events.first['actor']).to eq('unknown')
      expect(events.first).not_to have_key('actor_id')
    end

    it 'never leaks the full secret identifier into the trail' do
      link_to_org!(receipt, org)
      receipt.record_access_event('secret_get')

      raw = org.secret_activity_events.membersraw.join
      expect(raw).not_to include(secret.identifier)
      expect(raw).not_to include(receipt.identifier)
    end

    # Network context capture (#3640, ADR-022). The fetch path threads a
    # privacy-safe context hash into record_access_event, which forwards it to
    # the trail. These specs pin that the AGREED representation lands -- masked
    # partial IP, partial UA, keyed correlation hash -- and, critically, that a
    # raw IP or full UA can NEVER reach the stored event.
    describe 'network context fan-out' do
      # Represents what the capture layer produces: already-reduced values.
      let(:context) do
        {
          'net_ip_partial' => '203.0.113.0',
          'net_ua_partial' => 'Mozilla/*.* Chrome/*.*.*.*',
          'net_ip_hash' => 'd5cc375856c803a88c2aed517a5ae82244be6819a7ac0c11e08deeb679ecff39',
        }
      end

      before { link_to_org!(receipt, org) }

      it 'carries the masked partial IP, partial UA, and keyed hash into the trail' do
        receipt.record_access_event('secret_get', context: context)

        event = org.secret_activity_events_page.first
        expect(event['kind']).to eq('secret_get')
        expect(event['net_ip_partial']).to eq('203.0.113.0')
        expect(event['net_ua_partial']).to eq('Mozilla/*.* Chrome/*.*.*.*')
        expect(event['net_ip_hash']).to eq(context['net_ip_hash'])
        # Alongside the existing shortid context, not instead of it.
        expect(event['receipt']).to eq(receipt.shortid)
      end

      it 'keeps the shortid-only context intact when no network context is given' do
        receipt.record_access_event('status_get')

        event = org.secret_activity_events_page.first
        expect(event).to include('receipt', 'secret', 'kind', 'at')
        expect(event.keys).not_to include('net_ip_partial', 'net_ua_partial', 'net_ip_hash')
      end

      # NO-REGRESSION GUARD (primary privacy safety net): a raw dotted-quad IP
      # or a full user-agent string must NEVER appear in any recorded event
      # attribute. Even if a caller hands record_access_event a context built
      # from raw values, only the masked representation may be persisted -- so
      # here we build the context through the real capture helper from RAW
      # inputs and assert the raw values are absent from the stored trail.
      it 'never persists a raw IP or full UA anywhere in the recorded event' do
        raw_ip   = '203.0.113.42'
        raw_ipv6 = '2001:db8:1234:5678:9abc:def0:1234:5678'
        full_ua  = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 ' \
                   '(KHTML, like Gecko) Chrome/119.0.0.0 Safari/537.36'

        [raw_ip, raw_ipv6].each do |ip|
          real_context = Onetime::Security::RequestContext.capture(ip: ip, user_agent: full_ua)
          receipt.record_access_event('secret_get', context: real_context)
        end

        raw = org.secret_activity_events.membersraw.join

        # No raw dotted-quad IPv4, no full IPv6, no full UA, no version token.
        expect(raw).not_to include(raw_ip)
        expect(raw).not_to include(raw_ipv6)
        expect(raw).not_to include(full_ua)
        expect(raw).not_to include('119.0.0.0')

        # Belt and suspenders: scan every stored attribute value directly.
        org.secret_activity_events_page(limit: 200).each do |event|
          event.each_value do |value|
            expect(value.to_s).not_to include(raw_ip)
            expect(value.to_s).not_to include(raw_ipv6)
            expect(value.to_s).not_to include(full_ua)
          end
        end
      end

      it 'records a stable, keyed correlation hash across two events from the same source' do
        real_context = Onetime::Security::RequestContext.capture(
          ip: '203.0.113.42', user_agent: 'UA/1.0',
        )
        2.times { receipt.record_access_event('status_get', context: real_context) }

        hashes = org.secret_activity_events_page.map { |e| e['net_ip_hash'] }
        expect(hashes.uniq.size).to eq(1)
        expect(hashes.first).to match(/\A[0-9a-f]{64}\z/)
      end
    end

    it 'writes nowhere and raises nothing for receipts without org context' do
      expect { receipt.record_access_event('status_get') }.not_to raise_error
      expect(org.secret_activity_event_count).to eq(0)
    end

    it 'caps one receipt\'s fetch contribution so a hammered link cannot flood the trail' do
      stub_const('Onetime::Receipt::Features::AccessTimeline::ACCESS_EVENTS_MAX', 3)
      link_to_org!(receipt, org)

      5.times { receipt.record_access_event('status_get') }

      # The receipt's own timeline saturates at the cap, and fan-out stops
      # with it: other receipts' history in the org trail stays safe.
      expect(receipt.access_count).to eq(3)
      expect(org.secret_activity_event_count).to eq(3)

      # Lifecycle transitions are not subject to the fetch bound.
      receipt.revealed!
      expect(org.secret_activity_events_page.first['kind']).to eq('revealed')
    end
  end

  describe 'fan-out from lifecycle transitions (completeness + no duplicates)' do
    before { link_to_org!(receipt, org) }

    it 'records the receipt view exactly once, under its unambiguous audit kind' do
      receipt.record_receipt_view!
      receipt.record_receipt_view! # guard: claim_once! already stamped receipt_viewed_at

      # 'preview' is UI language; the trail records what mechanically
      # happened: the receipt page was loaded.
      kinds = org.secret_activity_events_page.map { |e| e['kind'] }
      expect(kinds).to eq(['receipt_viewed'])
    end

    it 'threads the actor context from the receipt view into the trail (#3637)' do
      full_objid = "customer_objid_#{SecureRandom.hex(12)}"
      receipt.record_receipt_view!(actor_context: { 'actor' => 'creator', 'actor_id' => full_objid })

      event = org.secret_activity_events_page.first
      expect(event['kind']).to eq('receipt_viewed')
      expect(event['actor']).to eq('creator')
      expect(event['actor_id']).to eq(full_objid)
    end

    it 'records the receipt view without actor context under the fail-safe actor' do
      receipt.record_receipt_view!

      event = org.secret_activity_events_page.first
      expect(event['kind']).to eq('receipt_viewed')
      expect(event['actor']).to eq('unknown')
      expect(event).not_to have_key('actor_id')
    end

    it 'records revealed exactly once even if called repeatedly' do
      receipt.revealed!
      receipt.revealed! # guard: state is no longer :new/:previewed

      kinds = org.secret_activity_events_page.map { |e| e['kind'] }
      expect(kinds).to eq(['revealed'])
    end

    it 'records burned exactly once' do
      receipt.burned!
      receipt.burned!

      kinds = org.secret_activity_events_page.map { |e| e['kind'] }
      expect(kinds).to eq(['burned'])
    end

    it 'records orphaned exactly once, as a system actor with no actor_id' do
      receipt.orphaned!
      receipt.orphaned!

      events = org.secret_activity_events_page
      expect(events.map { |e| e['kind'] }).to eq(['orphaned'])
      # System-detected transition: no acting individual, so 'system' and
      # never an actor_id (#3637).
      expect(events.first['actor']).to eq('system')
      expect(events.first).not_to have_key('actor_id')
    end

    it 'does not record expired for a receipt that has not expired' do
      receipt.expired!

      expect(org.secret_activity_event_count).to eq(0)
      expect(receipt.state).to eq('new')
    end

    it 'records expired exactly once for a genuinely expired receipt' do
      # Backdate creation past the secret TTL so secret_expired? is true.
      receipt.created = Familia.now.to_i - receipt.secret_ttl.to_i - 60
      receipt.save_fields(:created)

      receipt.expired!
      receipt.expired! # second call: state already advanced, guard holds

      events = org.secret_activity_events_page
      expect(events.map { |e| e['kind'] }).to eq(['expired'])
      # System-detected, like orphaned: 'system' actor, never an actor_id.
      expect(events.first['actor']).to eq('system')
      expect(events.first).not_to have_key('actor_id')
    end

    it 'reaches the trail through the full reveal cascade (secret -> receipt -> org)' do
      expect(secret.reveal!).to eq('a secret value')

      kinds = org.secret_activity_events_page.map { |e| e['kind'] }
      expect(kinds).to eq(['revealed'])
    end
  end

  # Actor attribution on lifecycle events (#3639). The revealed/burned events
  # must carry WHO acted; the discriminator is computed at the request-scoped
  # logic layer and threaded through the atomic consume cascade. These model
  # specs pin the trail-facing half of that contract:
  #   * record_org_secret_activity_event forwards arbitrary string-keyed event_attrs;
  #   * revealed!/burned! record the threaded actor exactly once (CAS-gated);
  #   * a missing actor context fails safe to 'unknown' (ADR-023: never
  #     'creator', and never 'anonymous' — that would assert "unauthenticated",
  #     a fact an actorless event cannot support);
  #   * the full Secret -> Receipt -> Org cascade carries the actor down.
  describe 'actor attribution on lifecycle events (#3639)' do
    before { link_to_org!(receipt, org) }

    let(:full_objid) { "customer_objid_#{SecureRandom.hex(12)}" }

    it 'record_org_secret_activity_event forwards extra string-keyed attrs into the event' do
      receipt.record_org_secret_activity_event('revealed', 'actor' => 'creator', 'actor_id' => full_objid)

      event = org.secret_activity_events_page.first
      expect(event['kind']).to eq('revealed')
      expect(event['actor']).to eq('creator')
      expect(event['actor_id']).to eq(full_objid)
    end

    it 'threads the actor through revealed! into the trail' do
      receipt.revealed!(actor_context: { 'actor' => 'creator', 'actor_id' => full_objid })

      event = org.secret_activity_events_page.first
      expect(event['kind']).to eq('revealed')
      expect(event['actor']).to eq('creator')
      expect(event['actor_id']).to eq(full_objid)
    end

    it 'threads the actor through burned! into the trail' do
      receipt.burned!(actor_context: { 'actor' => 'authenticated_other', 'actor_id' => full_objid })

      event = org.secret_activity_events_page.first
      expect(event['kind']).to eq('burned')
      expect(event['actor']).to eq('authenticated_other')
      expect(event['actor_id']).to eq(full_objid)
    end

    it 'defaults a missing actor context to unknown on revealed! (ADR-023, never misattributed)' do
      receipt.revealed! # defensive path: no request context threaded

      event = org.secret_activity_events_page.first
      expect(event['actor']).to eq('unknown')
      expect(event).not_to have_key('actor_id')
    end

    it 'defaults a blank actor to unknown on burned! (ADR-023, never misattributed)' do
      receipt.burned!(actor_context: { 'actor' => '' })

      event = org.secret_activity_events_page.first
      expect(event['actor']).to eq('unknown')
    end

    # Privacy no-regression guards for the centralized actor validation in
    # record_org_secret_activity_event (#3637). These pin the ways an actor context is
    # reduced before it is stored, so a future change can't silently start
    # leaking identity (or misattributing events) in the trail.
    it 'never attaches an actor_id to an anonymous event, even if one is supplied' do
      # An anonymous actor has no identity to record; an id riding along on the
      # context must be dropped, not stored against 'anonymous'.
      receipt.revealed!(actor_context: { 'actor' => 'anonymous', 'actor_id' => 'abcd1234' })

      event = org.secret_activity_events_page.first
      expect(event['actor']).to eq('anonymous')
      expect(event).not_to have_key('actor_id')
    end

    it 'fails an unrecognized actor safe to unknown and keeps its id (ADR-023)' do
      # An actor label outside the known set is never recorded verbatim: it
      # fails safe to the explicit 'unknown' sentinel (never misattributed to
      # the creator, never asserted 'anonymous'). A valid id riding along is
      # KEPT — record what is known, mark the rest unknown.
      receipt.revealed!(actor_context: { 'actor' => 'root', 'actor_id' => full_objid })

      event = org.secret_activity_events_page.first
      expect(event['actor']).to eq('unknown')
      expect(event['actor_id']).to eq(full_objid)
    end

    it 'records an explicit unknown actor with its id (indeterminate ownership, ADR-023)' do
      # The nil-target_secret branch in lifecycle_actor_context records
      # 'unknown' + the authenticated principal's objid; the validator must
      # pass both through unchanged (unknown is id-carrying).
      receipt.burned!(actor_context: { 'actor' => 'unknown', 'actor_id' => full_objid })

      event = org.secret_activity_events_page.first
      expect(event['actor']).to eq('unknown')
      expect(event['actor_id']).to eq(full_objid)
    end

    it 'stores the full actor objid untruncated (unique traceability, AU-3 / PCI 10.2.2)' do
      # The trail must bind the event to a uniquely resolvable individual; a
      # truncated id collides. An objid grants no access, so the shortid
      # convention for receipt/secret capability tokens does not apply here.
      receipt.burned!(actor_context: { 'actor' => 'creator', 'actor_id' => full_objid })

      event = org.secret_activity_events_page.first
      expect(event['actor']).to eq('creator')
      expect(event['actor_id']).to eq(full_objid)
      expect(event['actor_id'].length).to be > 8
    end

    it 'drops an email-like actor_id (an email must never enter the trail)' do
      # GDPR minimization: the append-only trail is exempt from erasure only
      # because no personal identifier ever enters it. Defense in depth
      # against a caller passing cust.email where an objid belongs.
      receipt.burned!(actor_context: { 'actor' => 'creator', 'actor_id' => 'person@example.com' })

      event = org.secret_activity_events_page.first
      expect(event['actor']).to eq('creator')
      expect(event).not_to have_key('actor_id')
      expect(org.secret_activity_events.membersraw.join).not_to include('person@example.com')
    end

    it 'drops a blank actor_id rather than storing an empty token' do
      receipt.burned!(actor_context: { 'actor' => 'creator', 'actor_id' => '' })

      event = org.secret_activity_events_page.first
      expect(event['actor']).to eq('creator')
      expect(event).not_to have_key('actor_id')
    end

    it 'never attaches an actor_id to a system event, even if one is supplied' do
      receipt.record_org_secret_activity_event('expired', 'actor' => 'system', 'actor_id' => full_objid)

      event = org.secret_activity_events_page.first
      expect(event['actor']).to eq('system')
      expect(event).not_to have_key('actor_id')
    end

    it 'records the threaded actor exactly once; a race-loser records nothing' do
      loser = Onetime::Receipt.load(receipt.identifier)

      expect(receipt.revealed!(actor_context: { 'actor' => 'creator', 'actor_id' => 'abcd1234' })).to be true
      # The loser lost the CAS: it neither transitions nor appends an event.
      expect(loser.revealed!(actor_context: { 'actor' => 'authenticated_other' })).to be_falsey

      events = org.secret_activity_events_page
      expect(events.map { |e| e['kind'] }).to eq(['revealed'])
      expect(events.first['actor']).to eq('creator')
    end

    it 'carries the actor down the full Secret -> Receipt -> Org reveal cascade' do
      expect(secret.reveal!(actor_context: { 'actor' => 'authenticated_other', 'actor_id' => 'beef5678' }))
        .to eq('a secret value')

      event = org.secret_activity_events_page.first
      expect(event['kind']).to eq('revealed')
      expect(event['actor']).to eq('authenticated_other')
      expect(event['actor_id']).to eq('beef5678')
    end

    it 'carries the actor down the full Secret -> Receipt -> Org burn cascade' do
      expect(secret.burned!(actor_context: { 'actor' => 'creator', 'actor_id' => 'abcd1234' })).to be true

      event = org.secret_activity_events_page.first
      expect(event['kind']).to eq('burned')
      expect(event['actor']).to eq('creator')
      expect(event['actor_id']).to eq('abcd1234')
    end
  end

  # Domain context on custom-domain shares (#3642). Events for receipts
  # created through a registered custom domain carry WHERE the share lives:
  # the domain_id shortid (8 chars, matching the trail-wide shortid policy)
  # and the public FQDN. Default-domain shares carry neither key -- absent,
  # not null. The guard is domain_id: share_domain can be set even when no
  # CustomDomain record resolved, and alone it must not imply one.
  describe 'domain context on custom-domain shares (#3642)' do
    # Realistic CustomDomain objid: long enough that the 8-char slice
    # differs from the full value, so leakage is detectable.
    let(:domain_id) { '01997b2a8f3e4d5c6b7a8901' }

    before { link_to_org!(receipt, org) }

    it 'carries the domain_id shortid and FQDN for a custom-domain receipt' do
      receipt.domain_id    = domain_id
      receipt.share_domain = 'secrets.example.com'
      receipt.save_fields(:domain_id, :share_domain)

      receipt.record_org_secret_activity_event('created')

      event = org.secret_activity_events_page.first
      expect(event['domain_id']).to eq(domain_id[0, 8])
      expect(event['domain']).to eq('secrets.example.com')
      # Alongside the existing shortid context, not instead of it.
      expect(event['receipt']).to eq(receipt.shortid)
      expect(event['secret']).to eq(receipt.secret_shortid)
    end

    it 'omits both keys entirely for a default-domain receipt' do
      receipt.record_org_secret_activity_event('created')

      event = org.secret_activity_events_page.first
      expect(event.keys).not_to include('domain_id', 'domain')
    end

    it 'omits the domain key when domain_id is set without a share_domain' do
      # A writer outside spawn_pair (migration, admin tool) can stamp
      # domain_id alone; the absent-not-null contract applies per key, so
      # the event must not carry 'domain' => nil.
      receipt.domain_id = domain_id
      receipt.save_fields(:domain_id)

      receipt.record_org_secret_activity_event('created')

      event = org.secret_activity_events_page.first
      expect(event['domain_id']).to eq(domain_id[0, 8])
      expect(event.keys).not_to include('domain')
    end

    it 'omits both keys when share_domain is set without a registered domain' do
      # index_receipt_to_domain can stamp share_domain with no CustomDomain
      # resolved; the trail must not fabricate a domain_id-less "custom
      # domain" event from it.
      receipt.share_domain = 'secrets.example.com'
      receipt.save_fields(:share_domain)

      receipt.record_org_secret_activity_event('created')

      event = org.secret_activity_events_page.first
      expect(event.keys).not_to include('domain_id', 'domain')
    end

    it 'never leaks the full domain objid into the trail' do
      receipt.domain_id    = domain_id
      receipt.share_domain = 'secrets.example.com'
      receipt.save_fields(:domain_id, :share_domain)

      receipt.record_org_secret_activity_event('secret_get')

      raw = org.secret_activity_events.membersraw.join
      expect(raw).to include(domain_id[0, 8])
      expect(raw).not_to include(domain_id)
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

      expect(org.secret_activity_event_count).to eq(2)
      expect(other_org.secret_activity_event_count).to eq(0)
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

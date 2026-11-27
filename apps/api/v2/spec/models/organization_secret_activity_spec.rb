# apps/api/v2/spec/models/organization_secret_activity_spec.rb
#
# frozen_string_literal: true

require_relative '../../application'
require_relative File.join(Onetime::HOME, 'spec', 'spec_helper')
require 'onetime/security/request_context'
require 'onetime/operations/domains/transfer'

# Audit-fidelity coverage for the organization audit trail (#3633).
#
# The trail backs the paid `audit_logs` entitlement, so these specs pin the
# properties an audit consumer relies on:
#
#   COMPLETENESS - every receipt event (access fetches, lifecycle
#     transitions, creation) with org context lands in the trail exactly
#     once; guarded transitions cannot double-record.
#   ACCURACY - events carry the right kind, timestamp, and shortid context;
#     identical fetches in one coalesce window share a row and its count
#     goes up; lifecycle events never share a row.
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

  let(:feature) { Onetime::Organization::Features::SecretActivity }

  # Runs the block with the given caps/window in force, restoring the
  # previous settings afterwards. The settings are read at write time, so
  # they apply to every organization at once.
  def with_secret_activity_settings(**overrides)
    saved = feature.settings
    merged = saved.merge(overrides)
    feature.configure!(merged[:max_events], max_guest_events: merged[:max_guest_events],
      coalesce_window: merged[:coalesce_window])
    yield
  ensure
    feature.configure!(saved[:max_events], max_guest_events: saved[:max_guest_events],
      coalesce_window: saved[:coalesce_window])
  end

  # Everything the trail stores for an organization, as raw bytes: the
  # detail JSON, the partition members (ids) and the legacy set.
  def raw_details(organization)
    detail = organization.secret_activity_detail
    client = detail.dbclient
    [
      *client.hvals(detail.dbkey),
      *[organization.secret_activity_member, organization.secret_activity_guest,
        organization.secret_activity_events].flat_map { |zset| client.zrange(zset.dbkey, 0, -1) },
    ].join("\n")
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

    it 'counts two identical fetches in one window as one row (no silent loss)' do
      at = Familia.now.to_f
      org.record_secret_activity_event('secret_get', at: at, 'receipt' => 'abc123')
      org.record_secret_activity_event('secret_get', at: at + 1, 'receipt' => 'abc123')

      expect(org.secret_activity_event_count).to eq(1)
      event = org.secret_activity_events_page.first
      expect(event['count']).to eq(2)
      expect(event['first_at']).to be_within(0.001).of(at)
      expect(event['last_at']).to be_within(0.001).of(at + 1)
      expect(event['at']).to eq(event['last_at'])
    end

    it 'retains two identical lifecycle events in the same second as two rows' do
      at = Familia.now.to_f
      org.record_secret_activity_event('revealed', at: at, 'receipt' => 'abc123')
      org.record_secret_activity_event('revealed', at: at, 'receipt' => 'abc123')

      expect(org.secret_activity_event_count).to eq(2)
      expect(org.secret_activity_events_page.map { |e| e['count'] }).to eq([1, 1])
    end

    it 'evicts only the oldest events past the retention cap' do
      with_secret_activity_settings(max_events: 5) do
        # configure! clamps to the MIN_MAX_EVENTS floor.
        expect(feature.max_events).to eq(feature::MIN_MAX_EVENTS)

        cap  = feature::MIN_MAX_EVENTS
        base = Familia.now.to_f - 200
        (cap + 3).times { |i| org.record_secret_activity_event('revealed', at: base + i) }

        expect(org.secret_activity_event_count).to eq(cap)
        expect(org.secret_activity_trimmed?).to be(true)
        ats = org.secret_activity_events_page(limit: 200).map { |e| e['at'] }
        expect(ats.min).to be_within(0.001).of(base + 3)
        expect(ats.max).to be_within(0.001).of(base + cap + 2)
      end
    end

    it 'clamps pagination inputs and windows correctly' do
      base = Familia.now.to_f - 100
      5.times { |i| org.record_secret_activity_event('revealed', at: base + i) }

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
      features = OT.conf.get('features', {}).merge('secret_activity' => secret_activity)
      OT.conf.merge('features' => features)
    end

    # Parity with ConfigSerializer#build_feature_flags: a hand-edited config
    # can deliver the string 'false' where the shipped ERB emits a real
    # boolean. If only the serializer handled it, the UI would show the
    # paused banner while the backend kept recording.
    it "pauses recording on the string 'false' while existing events stay readable" do
      t1 = Familia.now.to_f - 10
      org.record_secret_activity_event('created', at: t1, 'receipt' => 'abc123')

      allow(OT).to receive(:conf)
        .and_return(OT::Config.wrap(conf_with_collect_flag('collect' => 'false')))

      expect(org.record_secret_activity_event('secret_get')).to be_nil
      expect(org.secret_activity_event_count).to eq(1)

      events = org.secret_activity_events_page
      expect(events.size).to eq(1)
      expect(events.first['kind']).to eq('created')
      expect(events.first['at']).to be_within(0.001).of(t1)
    end

    it 'pauses recording on native false (shipped ERB boolean)' do
      allow(OT).to receive(:conf)
        .and_return(OT::Config.wrap(conf_with_collect_flag('collect' => false)))

      expect(org.record_secret_activity_event('secret_get')).to be_nil
      expect(org.record_secret_activity_event('created', partition: :guest)).to be_nil
      expect(org.secret_activity_event_count).to eq(0)
      expect(org.secret_activity_detail.dbclient.exists(org.secret_activity_detail.dbkey)).to eq(0)
      expect(org.secret_activity_count.dbclient.exists(org.secret_activity_count.dbkey)).to eq(0)
    end

    it "keeps recording on the string 'true'" do
      allow(OT).to receive(:conf)
        .and_return(OT::Config.wrap(conf_with_collect_flag('collect' => 'true')))

      expect(org.record_secret_activity_event('secret_get')).to be_a(Hash)
      expect(org.secret_activity_event_count).to eq(1)
    end

    it 'keeps recording when nil (default-true contract)' do
      allow(OT).to receive(:conf)
        .and_return(OT::Config.wrap(conf_with_collect_flag('collect' => nil)))

      expect(org.record_secret_activity_event('secret_get')).to be_a(Hash)
      expect(org.secret_activity_event_count).to eq(1)
    end

    it 'keeps recording when the key is absent (older config file)' do
      allow(OT).to receive(:conf).and_return(OT::Config.wrap(conf_with_collect_flag({})))

      expect(org.record_secret_activity_event('secret_get')).to be_a(Hash)
      expect(org.secret_activity_event_count).to eq(1)
    end
  end

  # Retention caps and coalescing window (SECRET_ACTIVITY_MAX_EVENTS,
  # _MAX_GUEST_EVENTS, _COALESCE_WINDOW). configure! is the single mutation
  # point (ConfigureSecretActivity initializer); the values apply at write
  # time to every organization.
  describe '.configure!' do
    around { |example| with_secret_activity_settings { example.run } }

    it 'applies and returns a cap above the floor' do
      expect(feature.configure!(2_500)).to eq(2_500)
      expect(feature.max_events).to eq(2_500)
    end

    it 'clamps caps below the floor to MIN_MAX_EVENTS' do
      expect(feature.configure!(99)).to eq(feature::MIN_MAX_EVENTS)
      expect(feature.configure!(-10, max_guest_events: 1)).to eq(feature::MIN_MAX_EVENTS)
      expect(feature.max_guest_events).to eq(feature::MIN_MAX_EVENTS)
    end

    it 'coerces integer-shaped strings (ENV/hand-edited YAML deliver them)' do
      feature.configure!('500', max_guest_events: '700', coalesce_window: '60')
      expect(feature.settings).to eq(max_events: 500, max_guest_events: 700, coalesce_window: 60)
    end

    it 'floors a negative window at 0 (coalescing off)' do
      feature.configure!(500, coalesce_window: -5)
      expect(feature.coalesce_window).to eq(0)
    end

    it 'raises on non-integer input before changing anything (initializer owns the fallback)' do
      before_settings = feature.settings
      expect { feature.configure!('unbounded') }.to raise_error(ArgumentError)
      expect { feature.configure!(nil) }.to raise_error(TypeError)
      expect { feature.configure!(500, coalesce_window: 'x') }.to raise_error(ArgumentError)
      expect(feature.settings).to eq(before_settings)
    end

    it 'reaches organizations that already exist' do
      org.record_secret_activity_event('revealed')
      feature.configure!(feature::MIN_MAX_EVENTS)

      base = Familia.now.to_f
      (feature::MIN_MAX_EVENTS + 1).times { |i| org.record_secret_activity_event('revealed', at: base + i) }
      expect(org.secret_activity_event_count).to eq(feature::MIN_MAX_EVENTS)
    end
  end

  # Deterministic ids: what makes two events "identical".
  describe '.event_id' do
    let(:attrs) do
      { 'receipt' => 'abc12345', 'secret' => 'def67890', 'actor' => 'anonymous',
        'net_ip_hash' => 'a' * 64, 'net_ua_partial' => 'Chrome/119', 'domain_id' => 'dom12345' }
    end
    let(:at) { 1_795_000_000.0 }

    def id_for(kind = 'secret_get', overrides = {}, at: self.at, window: 3600)
      feature.event_id(kind, attrs.merge(overrides), at: at, window: window)
    end

    it 'is e1: plus 20 hex characters' do
      expect(id_for).to match(/\Ae1:[0-9a-f]{20}\z/)
    end

    it 'is the same for the same identity in one window' do
      window_start = (at / 3600).floor * 3600
      expect(id_for(at: window_start)).to eq(id_for(at: window_start + 3599))
    end

    it 'differs across windows' do
      window_start = (at / 3600).floor * 3600
      expect(id_for(at: window_start)).not_to eq(id_for(at: window_start + 3600))
    end

    it 'differs when the network, actor, kind, secret or domain differs' do
      base = id_for
      expect(id_for('secret_get', { 'net_ip_hash' => 'b' * 64 })).not_to eq(base)
      expect(id_for('secret_get', { 'net_ua_partial' => 'Firefox/120' })).not_to eq(base)
      expect(id_for('secret_get', { 'actor' => 'creator', 'actor_id' => 'cust1' })).not_to eq(base)
      expect(id_for('status_get')).not_to eq(base)
      expect(id_for('secret_get', { 'secret' => 'other123' })).not_to eq(base)
      expect(id_for('secret_get', { 'domain_id' => 'other123' })).not_to eq(base)
    end

    it 'never coalesces lifecycle kinds' do
      %w[created receipt_viewed revealed burned expired orphaned unknown].each do |kind|
        expect(id_for(kind)).not_to eq(id_for(kind)), kind
      end
    end

    it 'coalesces every listed fetch kind' do
      feature::COALESCIBLE_KINDS.each do |kind|
        expect(id_for(kind)).to eq(id_for(kind)), kind
      end
    end

    it 'never coalesces when the window is 0' do
      expect(id_for(window: 0)).not_to eq(id_for(window: 0))
    end
  end

  # The Lua write: one atomic step adds the row, bumps its count and trims
  # the partition, deleting evicted ids from both hashes.
  describe 'storage (write and trim)' do
    def hash_size(field)
      field.dbclient.hlen(field.dbkey)
    end

    it 'trims the detail and count hashes with the partition' do
      with_secret_activity_settings(max_events: feature::MIN_MAX_EVENTS) do
        base = Familia.now.to_f - 500
        (feature::MIN_MAX_EVENTS + 5).times { |i| org.record_secret_activity_event('revealed', at: base + i) }

        expect(org.secret_activity_member.element_count).to eq(feature::MIN_MAX_EVENTS)
        expect(hash_size(org.secret_activity_detail)).to eq(feature::MIN_MAX_EVENTS)
        expect(hash_size(org.secret_activity_count)).to eq(feature::MIN_MAX_EVENTS)
        expect(hash_size(org.secret_activity_first_at)).to eq(feature::MIN_MAX_EVENTS)
      end
    end

    it 'is not trimmed at the cap exactly, and stays trimmed after the cap is raised' do
      cap  = feature::MIN_MAX_EVENTS
      base = Familia.now.to_f - 500
      with_secret_activity_settings(max_events: cap) do
        cap.times { |i| org.record_secret_activity_event('revealed', at: base + i) }
        expect(org.secret_activity_event_count).to eq(cap)
        expect(org.secret_activity_trimmed?).to be(false)

        org.record_secret_activity_event('revealed', at: base + cap)
        expect(org.secret_activity_trimmed?).to be(true)
        expect(org.secret_activity_trim.dbclient.hget(org.secret_activity_trim.dbkey, 'member:evicted')).to eq('1')
      end

      with_secret_activity_settings(max_events: cap * 2) do
        org.record_secret_activity_event('revealed', at: base + cap + 1)
        expect(org.secret_activity_trimmed?).to be(true)
      end
    end

    it 'caps each partition separately, so a guest flood cannot evict member events' do
      with_secret_activity_settings(max_events: feature::MIN_MAX_EVENTS,
        max_guest_events: feature::MIN_MAX_EVENTS) do
        base = Familia.now.to_f - 1000
        3.times { |i| org.record_secret_activity_event('created', at: base + i, 'actor' => 'creator') }
        (feature::MIN_MAX_EVENTS * 2).times do |i|
          org.record_secret_activity_event('created', at: base + 10 + i, partition: :guest, 'actor' => 'anonymous')
        end

        expect(org.secret_activity_member.element_count).to eq(3)
        expect(org.secret_activity_trimmed?).to be(true)
        expect(org.secret_activity_guest.element_count).to eq(feature::MIN_MAX_EVENTS)
        expect(hash_size(org.secret_activity_detail)).to eq(feature::MIN_MAX_EVENTS + 3)
      end
    end

    it 'keeps the newer time as last_at when an older repeat arrives late' do
      at = (Familia.now.to_f / 3600).floor * 3600 + 100
      org.record_secret_activity_event('secret_get', at: at + 50, 'receipt' => 'abc123')
      org.record_secret_activity_event('secret_get', at: at, 'receipt' => 'abc123')

      event = org.secret_activity_events_page.first
      expect(event['count']).to eq(2)
      expect(event['first_at']).to be_within(0.001).of(at)
      expect(event['last_at']).to be_within(0.001).of(at + 50)
    end

    it 'returns the recorded row with its id and count' do
      event = org.record_secret_activity_event('secret_get', 'receipt' => 'abc123')
      expect(event).to include('kind' => 'secret_get', 'count' => 1, 'receipt' => 'abc123')
      expect(event['id']).to start_with('e1:')
    end
  end

  # Reads merge both partitions newest-first.
  describe 'read merge' do
    it 'merges member and guest rows newest-first and pages across them' do
      base = Familia.now.to_f - 100
      org.record_secret_activity_event('revealed', at: base + 2, 'receipt' => 'mem12345')
      org.record_secret_activity_event('created', at: base + 3, partition: :guest, 'receipt' => 'gst12345')
      org.record_secret_activity_event('created', at: base + 4, 'receipt' => 'mem12345')

      page = org.secret_activity_events_page(limit: 10)
      expect(page.map { |e| e['receipt'] }).to eq(%w[mem12345 gst12345 mem12345])
      expect(org.secret_activity_events_page(offset: 1, limit: 1).map { |e| e['receipt'] }).to eq(%w[gst12345])
    end

    it 'returns every tied row exactly once across a page boundary' do
      at = Familia.now.to_f - 50
      5.times { |i| org.record_secret_activity_event('revealed', at: at, 'receipt' => "tie#{i}xxxx") }
      2.times { |i| org.record_secret_activity_event('created', at: at, partition: :guest, 'receipt' => "gtie#{i}xxx") }

      paged = (0...7).flat_map { |offset| org.secret_activity_events_page(offset: offset, limit: 1) }
      ids   = paged.map { |e| e['id'] }
      expect(ids.size).to eq(7)
      expect(ids.uniq.size).to eq(7)
      expect(ids).to eq(org.secret_activity_events_page(limit: 10).map { |e| e['id'] })

      pairs = (0...7).step(2).flat_map { |offset| org.secret_activity_events_page(offset: offset, limit: 2) }
      expect(pairs.map { |e| e['id'] }).to eq(ids)
    end

    # The base revision's client schema requires a string nonce, a number
    # at and a string kind on every record. A tab still running that bundle
    # during the rollout must keep parsing both row types.
    it 'keeps the previous client contract (string nonce) on new and migrated rows' do
      base = Familia.now.to_f - 100
      org.secret_activity_events.add({ 'kind' => 'burned', 'at' => base, 'nonce' => 'abcd1234' }, base)
      org.record_secret_activity_event('secret_get', at: base + 1, 'receipt' => 'mem12345')

      rows = org.secret_activity_events_page(limit: 10)
      expect(rows.size).to eq(2)
      rows.each do |row|
        expect(row['nonce']).to be_a(String).and(satisfy { |n| !n.empty? })
        expect(row['at']).to be_a(Numeric)
        expect(row['kind']).to be_a(String)
      end
      new_row, legacy_row = rows
      expect(new_row['nonce']).to eq(new_row['id'])
      expect(legacy_row['nonce']).to eq('abcd1234')
    end
  end

  # The pre-coalescing trail moves into the member partition on first use,
  # so the member cap covers it.
  describe 'legacy trail migration' do
    def add_legacy(count, base)
      count.times do |i|
        org.secret_activity_events.add(
          { 'kind' => 'revealed', 'at' => base + i, 'nonce' => format('n%07d', i), 'receipt' => 'old12345' },
          base + i,
        )
      end
    end

    it 'keeps 100 rows when 100 legacy rows meet one new event under a cap of 100' do
      cap  = feature::MIN_MAX_EVENTS
      base = Familia.now.to_f - 1000
      with_secret_activity_settings(max_events: cap) do
        add_legacy(cap, base)
        org.record_secret_activity_event('created', at: base + 500, 'receipt' => 'new12345')

        expect(org.secret_activity_events.exists?).to be(false)
        expect(org.secret_activity_event_count).to eq(cap)
        rows = org.secret_activity_events_page(limit: 200)
        expect(rows.size).to eq(cap)
        expect(rows.map { |e| e['nonce'] }).not_to include('n0000000')
        expect(rows.first['receipt']).to eq('new12345')
        expect(org.secret_activity_trimmed?).to be(true)
      end
    end

    it 'migrates a legacy row as count 1 with its original nonce and times' do
      base = Familia.now.to_f - 100
      add_legacy(1, base)

      row = org.secret_activity_events_page.first
      expect(row).to include('id' => 'l1:n0000000', 'nonce' => 'n0000000', 'count' => 1, 'kind' => 'revealed',
        'receipt' => 'old12345')
      expect(row['first_at']).to be_within(0.001).of(base)
      expect(row['last_at']).to be_within(0.001).of(base)
      expect(row['at']).to be_within(0.001).of(base)
      expect(org.secret_activity_events.exists?).to be(false)
    end

    it 'trims migrated rows on the next write after the cap is lowered' do
      cap  = feature::MIN_MAX_EVENTS
      base = Familia.now.to_f - 1000
      add_legacy(cap + 20, base)
      expect(org.migrate_legacy_secret_activity!).to eq(cap + 20)
      expect(org.secret_activity_event_count).to eq(cap + 20)

      with_secret_activity_settings(max_events: cap) do
        org.record_secret_activity_event('created', at: base + 900)
        expect(org.secret_activity_event_count).to eq(cap)
      end
    end

    it 'is a no-op when run twice' do
      base = Familia.now.to_f - 100
      add_legacy(3, base)

      expect(org.migrate_legacy_secret_activity!).to eq(3)
      before = raw_details(org)
      expect(org.migrate_legacy_secret_activity!).to eq(0)
      expect(raw_details(org)).to eq(before)
      expect(org.secret_activity_event_count).to eq(3)
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

      raw = raw_details(org)
      expect(raw).to include(receipt.shortid)
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

        raw = raw_details(org)
        expect(raw).to include(receipt.shortid)

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

      # Country capture (#3989) rides the same **event_attrs splat as the rest
      # of the network context, so the trail-facing half of the contract is
      # that a gated-ON net_country survives receipt -> org unchanged and
      # lands alongside the shortid context. Whether country is captured AT
      # ALL is the logic layer's default-OFF decision (ADR-021 Decision 4;
      # see access_telemetry_spec.rb) -- by the time a context reaches here
      # that gate has already been applied.
      it 'carries a resolved net_country into the trail without ever storing the raw IP' do
        raw_ip  = '203.0.113.42'
        full_ua = 'Mozilla/5.0 (X11; Linux x86_64) Chrome/119.0.0.0 Safari/537.36'

        real_context = Onetime::Security::RequestContext.capture(
          ip: raw_ip, user_agent: full_ua, country: 'US',
        )
        receipt.record_access_event('secret_get', context: real_context)

        event = org.secret_activity_events_page.first
        expect(event['net_country']).to eq('US')
        expect(event['net_ip_partial']).to eq('203.0.113.0')
        # Alongside the existing shortid context, not instead of it.
        expect(event['receipt']).to eq(receipt.shortid)

        # Country is the COARSEST geo signal; capturing it must not relax the
        # IP stance -- the raw dotted-quad still never reaches the trail.
        expect(event.to_json).not_to include(raw_ip)
        expect(raw_details(org)).to include(receipt.shortid)
        expect(raw_details(org)).not_to include(raw_ip)
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
      # with it: other receipts' history in the org trail stays safe. The
      # three fanned-out fetches are identical, so they share one row.
      expect(receipt.access_count).to eq(3)
      expect(org.secret_activity_event_count).to eq(1)
      expect(org.secret_activity_events_page.first['count']).to eq(3)

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
      expect(raw_details(org)).to include(receipt.shortid)
      expect(raw_details(org)).not_to include('person@example.com')
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
  # Which partition a receipt's events go to, and the second write to the
  # domain owner's trail when the domain belongs to another organization.
  describe 'partition and domain-owner fan-out' do
    let(:owner) { Onetime::Customer.create!(email: "fanout-#{SecureRandom.hex(6)}@example.com") }
    let(:other_org) do
      described_class.new(display_name: 'Domain Owner Org',
        contact_email: "owner-#{SecureRandom.hex(6)}@example.com").tap(&:save)
    end

    after do
      @domains&.each { |d| d.destroy! if d.exists? }
      other_org.destroy! if other_org.exists?
      @new_owner.destroy! if @new_owner&.exists?
      owner.destroy! if owner.exists?
    end

    def domain_owned_by(organization)
      domain = Onetime::CustomDomain.create!("fanout-#{SecureRandom.hex(4)}.example.com", organization.objid)
      (@domains ||= []) << domain
      domain
    end

    def member_owned!(receipt)
      receipt.owner_id = owner.objid
      receipt.save_fields(:owner_id)
    end

    # As spawn_pair stamps it: domain_org_id only when the domain's owner
    # is not the receipt's organization. Call after link_to_org!.
    def on_domain!(receipt, domain)
      receipt.domain_id     = domain.objid
      receipt.share_domain  = domain.display_domain
      receipt.domain_org_id = domain.org_id unless domain.org_id.to_s == receipt.org_id.to_s
      receipt.save_fields(:domain_id, :share_domain, :domain_org_id)
    end

    def transfer!(domain, to_org)
      Onetime::Operations::Domains::Transfer.new(domain: domain, to_org: to_org, actor: 'spec-admin',
        dry_run: false).call
    end

    it "records a guest receipt's events in the guest partition" do
      link_to_org!(receipt, org)
      receipt.record_org_secret_activity_event('created', 'actor' => 'anonymous')

      expect(org.secret_activity_guest.element_count).to eq(1)
      expect(org.secret_activity_member.element_count).to eq(0)
    end

    it "records an owned receipt's events in the member partition" do
      member_owned!(receipt)
      link_to_org!(receipt, org)
      receipt.record_org_secret_activity_event('created', 'actor' => 'creator', 'actor_id' => owner.objid)

      expect(org.secret_activity_member.element_count).to eq(1)
      expect(org.secret_activity_guest.element_count).to eq(0)
    end

    it "also records to the domain owner's trail when another org owns the domain" do
      member_owned!(receipt)
      link_to_org!(receipt, org)
      on_domain!(receipt, domain_owned_by(other_org))

      receipt.record_org_secret_activity_event('created', 'actor' => 'creator', 'actor_id' => owner.objid)

      [org, other_org].each do |trail_org|
        events = trail_org.secret_activity_events_page
        expect(events.size).to eq(1)
        expect(events.first).to include('kind' => 'created', 'receipt' => receipt.shortid)
      end
      expect(other_org.secret_activity_member.element_count).to eq(1)
    end

    it 'records once when the domain belongs to the same org' do
      member_owned!(receipt)
      link_to_org!(receipt, org)
      on_domain!(receipt, domain_owned_by(org))

      receipt.record_org_secret_activity_event('created', 'actor' => 'creator', 'actor_id' => owner.objid)

      expect(org.secret_activity_event_count).to eq(1)
    end

    it 'records once for a guest on the domain org (org_id is the domain owner)' do
      domain = domain_owned_by(org)
      link_to_org!(receipt, org)
      on_domain!(receipt, domain)

      receipt.record_org_secret_activity_event('created', 'actor' => 'anonymous')

      expect(org.secret_activity_event_count).to eq(1)
    end

    it 'gives no second write to a receipt without the creation-time binding' do
      member_owned!(receipt)
      link_to_org!(receipt, org)
      domain = domain_owned_by(other_org)
      receipt.domain_id = domain.objid
      receipt.save_fields(:domain_id)

      receipt.record_org_secret_activity_event('created', 'actor' => 'creator', 'actor_id' => owner.objid)

      expect(other_org.secret_activity_event_count).to eq(0)
    end

    context 'after a domain transfer' do
      # Destroyed by the group's after hook, once its domains are gone.
      let(:new_owner) do
        @new_owner = described_class.new(display_name: 'New Domain Owner',
          contact_email: "new-owner-#{SecureRandom.hex(6)}@example.com").tap(&:save)
      end

      it 'keeps sending an earlier receipt to the original owner, never the new one' do
        domain = domain_owned_by(other_org)
        member_owned!(receipt)
        link_to_org!(receipt, org)
        on_domain!(receipt, domain)

        expect(transfer!(domain, new_owner).status).to eq(:transferred)
        expect(Onetime::CustomDomain.load(domain.objid).org_id).to eq(new_owner.objid)

        receipt.record_org_secret_activity_event('secret_get', 'actor' => 'creator', 'actor_id' => owner.objid)
        receipt.expired!

        expect(new_owner.secret_activity_event_count).to eq(0)
        expect(other_org.secret_activity_events_page.map { |e| e['kind'] }).to include('secret_get')
        expect(org.secret_activity_event_count).to be >= 1
      end

      it 'sends a receipt created after the transfer to the new owner' do
        domain = domain_owned_by(other_org)
        transfer!(domain, new_owner)

        later, _secret = Onetime::Receipt.spawn_pair(owner.objid, 3600, 'later value',
          org_id: org.objid, domain_id: domain.objid,
          domain_org_id: Onetime::CustomDomain.load(domain.objid).org_id)
        expect(later.domain_org_id).to eq(new_owner.objid)

        later.record_org_secret_activity_event('created', 'actor' => 'creator', 'actor_id' => owner.objid)

        expect(new_owner.secret_activity_event_count).to eq(1)
        expect(other_org.secret_activity_event_count).to eq(0)
      end
    end

    it 'skips an archived domain owner' do
      member_owned!(receipt)
      link_to_org!(receipt, org)
      on_domain!(receipt, domain_owned_by(other_org))
      other_org.archive!

      receipt.record_org_secret_activity_event('created', 'actor' => 'creator', 'actor_id' => owner.objid)

      expect(org.secret_activity_event_count).to eq(1)
      expect(other_org.secret_activity_event_count).to eq(0)
    end

    it "keeps the primary write when the domain owner's write fails" do
      member_owned!(receipt)
      link_to_org!(receipt, org)
      on_domain!(receipt, domain_owned_by(other_org))
      allow(Onetime::Organization).to receive(:load).and_call_original
      allow(Onetime::Organization).to receive(:load).with(other_org.objid).and_raise(Redis::CannotConnectError)

      expect(receipt.record_org_secret_activity_event('created', 'actor' => 'creator',
        'actor_id' => owner.objid)).to include('kind' => 'created')
      expect(org.secret_activity_event_count).to eq(1)
      # The after hook loads organizations to clean up.
      allow(Onetime::Organization).to receive(:load).and_call_original
    end
  end

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
      # Creation stamps share_domain even when receipt_custom_domain resolves
      # no CustomDomain; the trail must not fabricate a domain_id-less
      # "custom domain" event from it.
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

      raw = raw_details(org)
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

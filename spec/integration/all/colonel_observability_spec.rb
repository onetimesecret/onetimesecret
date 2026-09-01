# spec/integration/all/colonel_observability_spec.rb
#
# frozen_string_literal: true

require 'spec_helper'
require 'csv'
require 'json'
require 'securerandom'

# Load the ColonelAPI application and its dependencies
# (apps/api is in the load path from spec_helper).
require 'colonel/application'

# Integration tests for the observability colonel endpoints against real Redis
# (port 2163; type: :integration flushes after each example):
#
#   1. Audit log reader — ListColonelAuditEvents (GET /api/colonel/audit): newest-first
#      pagination, actor/verb filters, and CONTRACT 4 as it now reads (#4335):
#      a read never writes the OPERATOR trail, and a CURATED sensitive read —
#      which reading the audit log is — records one observation on the
#      separately-budgeted access trail.
#   1b. Audit export — ExportColonelAuditEvents (GET /api/colonel/audit/export):
#      the same merged trails and the same field allowlist, serialised as
#      CSV / NDJSON for download. Same posture, its own verb.
#   2. Trends — GetTrends (GET /api/colonel/trends): 30-day zero-filled series
#      fed by the DailyMetric chokepoint counters. NOT curated — aggregate
#      counters expose no customer material — so it stays wholly unaudited, on
#      either trail.
RSpec.describe 'Colonel observability endpoints', type: :integration do
  # Build the StrategyResult double Logic::Base expects (mirrors
  # colonel_customer_support_spec.rb). The colonel is a REAL verified customer
  # so verify_one_of_roles!(colonel: true) exercises the actual policy.
  def strategy_result_for(user)
    double(
      'StrategyResult',
      session: {},
      user: user,
      metadata: { ip: '127.0.0.1' },
      auth_method: 'sessionauth',
    )
  end

  def create_customer(email:, role: 'customer', verified: 'true')
    cust          = Onetime::Customer.create!(email: email)
    cust.role     = role
    cust.verified = verified
    cust.save
    cust
  end

  let(:colonel) do
    create_customer(email: "colonel-#{SecureRandom.hex(4)}@example.com", role: 'colonel')
  end

  before do
    Onetime::ColonelAuditEvent.events.clear
    Onetime::ColonelAuditEvent.security_events.clear
    Onetime::ColonelAuditEvent.access_events.clear
  end

  def record_event(actor: 'ur_colonel1', verb: 'customer.set_role', target: 'ur_target', result: :success, detail: nil)
    Onetime::ColonelAuditEvent.record(actor: actor, verb: verb, target: target, result: result, detail: detail)
  end

  # The second trail: events an UNAUTHENTICATED caller can cause, stored under
  # their own cap so they cannot evict operator records.
  def record_security_event(actor: 'anonymous', verb: 'auth.reset_request_throttled', target: 'ip:203.0.x.x',
                            result: :failure, detail: nil)
    Onetime::ColonelAuditEvent.record_security(
      actor: actor, verb: verb, target: target, result: result, detail: detail,
    )
  end

  # ---------------------------------------------------------------------------
  # 1. Audit log reader (ListColonelAuditEvents)
  # ---------------------------------------------------------------------------
  describe 'ListColonelAuditEvents' do
    # Read + drop this read's OWN observation (#4335). Every read now appends
    # one row to the access trail, which lands at the head of the merged feed
    # and would shift the offsets an ordering assertion depends on between the
    # calls it makes. Examples that pin PAGINATION over a fixed trail use this
    # so they stay about pagination; the observation itself is pinned by its
    # own examples below, which use the plain `list`.
    def list_over_fixed_trail(params = {})
      list(params).tap { Onetime::ColonelAuditEvent.access_events.clear }
    end

    def list(params = {})
      logic = ColonelAPI::Logic::Colonel::ListColonelAuditEvents.new(
        strategy_result_for(colonel), params,
      )
      logic.raise_concerns
      logic.process
    end

    it 'returns events newest-first with the pagination envelope' do
      record_event(verb: 'customer.set_role')
      record_event(verb: 'session.delete')
      record_event(verb: 'banner.set')

      data = list

      verbs = data[:details][:events].map { |e| e[:verb] }
      expect(verbs).to eq(%w[banner.set session.delete customer.set_role])
      expect(data[:details][:pagination]).to include(
        page: 1, per_page: 50, total_count: 3, total_pages: 1,
      )
    end

    it 'emits the explicit event fields (timestamp/actor/action/target/detail)' do
      record_event(
        actor: 'ur_actor1', verb: 'customer.purge', target: 'ur_victim',
        detail: { 'reason' => 'gdpr' },
      )

      event = list[:details][:events].first

      expect(event.keys).to contain_exactly(:id, :actor, :verb, :target, :result, :detail, :created, :trail)
      expect(event).to include(
        actor: 'ur_actor1', verb: 'customer.purge', target: 'ur_victim', result: 'success',
        detail: { 'reason' => 'gdpr' },
      )
      expect(event[:created]).to be_a(Float)
    end

    it 'paginates newest-first: page 2 carries the older slice' do
      5.times { |i| record_event(verb: "v#{i}") } # v4 is the newest

      page1 = list_over_fixed_trail('page' => 1, 'per_page' => 2)
      page2 = list_over_fixed_trail('page' => 2, 'per_page' => 2)
      page3 = list_over_fixed_trail('page' => 3, 'per_page' => 2)

      expect(page1[:details][:events].map { |e| e[:verb] }).to eq(%w[v4 v3])
      expect(page2[:details][:events].map { |e| e[:verb] }).to eq(%w[v2 v1])
      expect(page3[:details][:events].map { |e| e[:verb] }).to eq(%w[v0])
      expect(page1[:details][:pagination]).to include(total_count: 5, total_pages: 3)
    end

    it 'returns an empty page (not an error) past the last page' do
      record_event

      data = list('page' => 9, 'per_page' => 50)

      expect(data[:details][:events]).to eq([])
      expect(data[:details][:pagination][:total_count]).to eq(1)
    end

    # The model keeps operator activity and unauthenticated security telemetry
    # in two separately-capped collections, so a flood of anonymous events can
    # never evict a privileged record. That is a storage split only: the reader
    # merges both trails, so the operator still sees one feed.
    it 'merges the security-telemetry trail into the same chronological feed' do
      record_event(verb: 'customer.set_role')
      record_security_event(verb: 'auth.reset_request_throttled')
      record_event(verb: 'banner.set')

      data = list

      expect(data[:details][:events].map { |e| e[:verb] })
        .to eq(%w[banner.set auth.reset_request_throttled customer.set_role])
      expect(data[:details][:pagination][:total_count]).to eq(3)
    end

    it 'filters and paginates across both trails' do
      record_security_event(verb: 'auth.reset_request_throttled')
      record_event(verb: 'customer.purge')

      filtered = list_over_fixed_trail('verb' => 'auth')
      expect(filtered[:details][:events].map { |e| e[:actor] }).to eq(%w[anonymous])
      expect(filtered[:details][:pagination][:total_count]).to eq(1)

      # Merged order is [customer.purge, auth.reset_request_throttled]; page 2
      # exercises the offset slice over the merge, not a raw ZREVRANGE offset.
      page2 = list_over_fixed_trail('page' => 2, 'per_page' => 1)
      expect(page2[:details][:events].map { |e| e[:verb] }).to eq(%w[auth.reset_request_throttled])
    end

    it 'filters by actor with case-insensitive substring matching' do
      record_event(actor: 'ur_alice123', verb: 'v.alice')
      record_event(actor: 'ur_bob456', verb: 'v.bob')

      data = list('actor' => 'ALICE')

      expect(data[:details][:events].map { |e| e[:verb] }).to eq(%w[v.alice])
      expect(data[:details][:pagination]).to include(total_count: 1, actor: 'ALICE')
    end

    it 'filters by exact action verb' do
      record_event(verb: 'customer.set_role')
      record_event(verb: 'customer.purge')

      data = list('verb' => 'customer.purge')

      expect(data[:details][:events].map { |e| e[:verb] }).to eq(%w[customer.purge])
    end

    it 'filters by action category prefix (customer matches customer.*)' do
      record_event(verb: 'customer.set_role')
      record_event(verb: 'customer.purge')
      record_event(verb: 'session.delete')

      data = list('verb' => 'customer')

      expect(data[:details][:events].map { |e| e[:verb] })
        .to contain_exactly('customer.set_role', 'customer.purge')
      expect(data[:details][:pagination][:verb]).to eq('customer')
    end

    it 'paginates filtered results with a filtered total_count' do
      3.times { |i| record_event(verb: "customer.v#{i}") }
      record_event(verb: 'session.delete')

      data = list('verb' => 'customer', 'page' => 2, 'per_page' => 2)

      expect(data[:details][:events].length).to eq(1)
      expect(data[:details][:pagination]).to include(total_count: 3, total_pages: 2)
    end

    # CONTRACT 4, as it now reads (#4335): "reads never write the OPERATOR
    # trail; curated sensitive reads write their own budgeted stream." The
    # first half is the invariant that protects the mutation trail from
    # read-volume eviction, and it is unchanged.
    it 'reading the log writes NO event to the OPERATOR trail (CONTRACT 4)' do
      record_event
      before_count = Onetime::ColonelAuditEvent.count

      list
      list('actor' => 'someone', 'verb' => 'customer')

      expect(Onetime::ColonelAuditEvent.count).to eq(before_count)
    end

    # The second half. Reading the flight recorder is itself an operator action
    # — "who has been reading the audit log" was the one question this log
    # could not answer.
    it 'records ONE observation per read on the access trail' do
      list
      list('actor' => 'someone', 'verb' => 'customer')

      expect(Onetime::ColonelAuditEvent.access_count).to eq(2)
      event = Onetime::ColonelAuditEvent.recent_access(1).first
      expect(event['verb']).to eq('audit.list')
      expect(event['target']).to eq('colonel_audit')
      expect(event['actor']).to eq(colonel.extid)
      expect(event['detail']).to include('actor_filter' => 'someone', 'verb_filter' => 'customer')
    end

    # Recorded AFTER the read, so an operator never sees the event describing
    # the request they just made — and, more importantly, the reader itself
    # never re-enters record_access while enumerating (ColonelAuditReader
    # writes nothing; only its callers do).
    it 'does not include its own observation in the page it returns' do
      data = list

      expect(data[:details][:events]).to be_empty
      expect(Onetime::ColonelAuditEvent.access_count).to eq(1)
    end

    it 'merges the observation trail into the same feed on the NEXT read' do
      record_event(verb: 'customer.purge')
      list

      verbs = list[:details][:events].map { |event| event[:verb] }
      expect(verbs).to contain_exactly('audit.list', 'customer.purge')
    end

    # A row's retention depends on which trail it came from, so the wire says
    # which one that was.
    it 'tags every row with the trail it came from' do
      record_event(verb: 'customer.purge')
      record_security_event(verb: 'auth.reset_request_throttled')
      list

      rows = list[:details][:events].to_h { |event| [event[:verb], event[:trail]] }
      expect(rows).to eq(
        'audit.list' => 'access_events',
        'customer.purge' => 'events',
        'auth.reset_request_throttled' => 'security_events',
      )
    end

    it 'counts all three trails in the unfiltered total, so pagination is honest' do
      record_event(verb: 'customer.purge')
      record_security_event(verb: 'auth.throttled')
      list # writes the first observation; its own total predates it

      expect(list[:details][:pagination][:total_count]).to eq(3)
    end

    it 'rejects non-colonel actors (defense-in-depth below the router role gate)' do
      staff = create_customer(email: "staff-#{SecureRandom.hex(4)}@example.com", role: 'staff')

      logic = ColonelAPI::Logic::Colonel::ListColonelAuditEvents.new(strategy_result_for(staff), {})
      expect { logic.raise_concerns }.to raise_error(Onetime::Forbidden)
    end
  end

  # ---------------------------------------------------------------------------
  # 1b. Audit export (ExportColonelAuditEvents) — #4334
  #
  # Same trails, same merge, same filters and the SAME FIELD ALLOWLIST as the
  # list endpoint above; only the serialisation differs. These pin that the two
  # cannot drift, and that the download is still read-only.
  # ---------------------------------------------------------------------------
  describe 'ExportColonelAuditEvents' do
    def export(params = {})
      logic = ColonelAPI::Logic::Colonel::ExportColonelAuditEvents.new(
        strategy_result_for(colonel), params,
      )
      logic.raise_concerns
      logic.process
      logic
    end

    it 'defaults to CSV with the allowlisted header row' do
      record_event(verb: 'customer.purge', target: 'ur_victim', detail: { 'reason' => 'gdpr' })

      logic = export
      rows  = CSV.parse(logic.body)

      expect(logic.content_type).to eq('text/csv; charset=utf-8')
      expect(logic.filename).to match(/\Acolonel-audit-\d{8}T\d{6}Z\.csv\z/)
      expect(rows.first).to eq(%w[id actor verb target result detail created trail])
      expect(rows[1][2]).to eq('customer.purge')
      expect(rows[1][3]).to eq('ur_victim')
      # detail is JSON-encoded into the one cell, so a consumer parses it back
      # to exactly what the JSON list endpoint returns.
      expect(JSON.parse(rows[1][5])).to eq('reason' => 'gdpr')
    end

    it 'emits NDJSON, one allowlisted object per line, newest first' do
      record_event(verb: 'customer.set_role')
      record_event(verb: 'banner.set')

      logic = export('format' => 'ndjson')
      lines = logic.body.lines.map { |line| JSON.parse(line) }

      expect(logic.content_type).to eq('application/x-ndjson; charset=utf-8')
      expect(lines.map { |e| e['verb'] }).to eq(%w[banner.set customer.set_role])
      expect(lines.first.keys).to contain_exactly(*%w[id actor verb target result detail created trail])
    end

    it 'exports BOTH trails merged, like the list endpoint' do
      record_event(verb: 'customer.set_role')
      record_security_event(verb: 'auth.reset_request_throttled')

      lines = export('format' => 'ndjson').body.lines.map { |line| JSON.parse(line) }

      expect(lines.map { |e| e['verb'] })
        .to contain_exactly('customer.set_role', 'auth.reset_request_throttled')
    end

    it 'honours the same actor / verb filters as the list endpoint' do
      record_event(actor: 'ur_alice123', verb: 'customer.purge')
      record_event(actor: 'ur_bob456', verb: 'session.delete')

      by_verb  = export('format' => 'ndjson', 'verb' => 'customer').body.lines
      by_actor = export('format' => 'ndjson', 'actor' => 'ALICE').body.lines

      expect(by_verb.map { |l| JSON.parse(l)['verb'] }).to eq(%w[customer.purge])
      expect(by_actor.map { |l| JSON.parse(l)['actor'] }).to eq(%w[ur_alice123])
    end

    it 'caps limit at the whole store and takes the newest when narrowed' do
      3.times { |i| record_event(verb: "v#{i}") }

      expect(export('limit' => '1').events.map { |e| e['verb'] }).to eq(%w[v2])
      expect(export('limit' => '99999').limit)
        .to eq(ColonelAPI::Logic::Colonel::ExportColonelAuditEvents::MAX_LIMIT)
    end

    it 'serialises an empty trail as a header-only CSV, not an error' do
      expect(export.body).to eq("id,actor,verb,target,result,detail,created,trail\n")
      # The FIRST export sees an empty store; it records its own observation on
      # the way out, which is why this asserts on a fresh export rather than
      # re-running the same one.
      expect(Onetime::ColonelAuditEvent.access_count).to eq(1)
    end

    it 'serialises an empty trail as an empty NDJSON body, not a broken line' do
      expect(export('format' => 'ndjson').body).to eq('')
    end

    # process_params runs inside Logic::Base#initialize, so this is raised
    # before the instance exists — an unknown format never reaches a read.
    it 'rejects an unknown format instead of silently defaulting' do
      expect do
        ColonelAPI::Logic::Colonel::ExportColonelAuditEvents.new(
          strategy_result_for(colonel), { 'format' => 'xlsx' },
        )
      end.to raise_error(Onetime::FormError, /Unsupported export format/)
    end

    it 'exporting the log writes NO event to the OPERATOR trail (CONTRACT 4)' do
      record_event
      before_count = Onetime::ColonelAuditEvent.count

      export
      export('format' => 'ndjson', 'verb' => 'customer')

      expect(Onetime::ColonelAuditEvent.count).to eq(before_count)
    end

    # A download is a BULK EXTRACTION and gets its own verb, so an operator
    # hunting for exfiltration does not have to parse `detail` to tell it from
    # a page view.
    it 'records ONE observation per export, under its own verb' do
      record_event(verb: 'customer.purge')

      export
      export('format' => 'ndjson', 'verb' => 'customer')

      expect(Onetime::ColonelAuditEvent.access_count).to eq(2)
      verbs = Onetime::ColonelAuditEvent.recent_access(2).map { |event| event['verb'] }
      expect(verbs).to all(eq('audit.export'))

      newest = Onetime::ColonelAuditEvent.recent_access(1).first
      expect(newest['target']).to eq('colonel_audit')
      expect(newest['detail']).to include('format' => 'ndjson', 'exported' => 1, 'verb_filter' => 'customer')
    end

    it 'rejects non-colonel actors (defense-in-depth below the router role gate)' do
      staff = create_customer(email: "staff-#{SecureRandom.hex(4)}@example.com", role: 'staff')

      logic = ColonelAPI::Logic::Colonel::ExportColonelAuditEvents.new(strategy_result_for(staff), {})
      expect { logic.raise_concerns }.to raise_error(Onetime::Forbidden)
    end

    # The `Klass.method` adapter. Nothing else covers it: the colonel app's
    # other routes are Logic-class routes whose response Otto builds, and this
    # one has to write the bytes and the download headers itself.
    describe '.render (the download adapter)' do
      def render(query, user: colonel)
        env                         = Rack::MockRequest.env_for("/api/colonel/audit/export?#{query}")
        env['otto.strategy_result'] = strategy_result_for(user)
        res                         = Rack::Response.new

        ColonelAPI::Logic::Colonel::ExportColonelAuditEvents.render(Rack::Request.new(env), res)
        res
      end

      def body_of(res)
        buffer = +''
        res.body.each { |chunk| buffer << chunk }
        buffer
      end

      it 'writes the serialised body with download headers' do
        record_event(verb: 'customer.purge')

        res = render('format=ndjson')

        expect(res['content-type']).to eq('application/x-ndjson; charset=utf-8')
        expect(res['content-disposition']).to match(/\Aattachment; filename="colonel-audit-.+\.ndjson"\z/)
        # A point-in-time snapshot of a mutable, operator-only trail.
        expect(res['cache-control']).to eq('no-store')
        expect(JSON.parse(body_of(res).lines.first)['verb']).to eq('customer.purge')
      end

      it 'passes the query filters through to the read' do
        record_event(verb: 'customer.purge')
        record_event(verb: 'session.delete')

        res = render('format=ndjson&verb=customer')

        expect(body_of(res).lines.map { |l| JSON.parse(l)['verb'] }).to eq(%w[customer.purge])
      end

      it 'runs raise_concerns: a non-colonel never reaches the body' do
        staff = create_customer(email: "staff-#{SecureRandom.hex(4)}@example.com", role: 'staff')

        expect { render('format=csv', user: staff) }.to raise_error(Onetime::Forbidden)
      end
    end

    # The two surfaces must describe the same record. If one grows a field the
    # other does not, this fails.
    it 'emits exactly the fields the JSON list endpoint emits' do
      record_event(verb: 'customer.purge', detail: { 'reason' => 'gdpr' })

      listed   = ColonelAPI::Logic::Colonel::ListColonelAuditEvents.new(strategy_result_for(colonel), {})
      listed.raise_concerns
      json_row = listed.process[:details][:events].first
      csv_row  = CSV.parse(export.body).first

      expect(csv_row.map(&:to_sym)).to eq(json_row.keys)
    end
  end

  # ---------------------------------------------------------------------------
  # 2. Trends (GetTrends)
  # ---------------------------------------------------------------------------
  describe 'GetTrends' do
    def trends
      logic = ColonelAPI::Logic::Colonel::GetTrends.new(strategy_result_for(colonel), {})
      logic.raise_concerns
      logic.process
    end

    def clear_daily_metrics
      keys = Familia.dbclient.keys("#{Onetime::DailyMetric::KEY_PREFIX}:*")
      Familia.dbclient.del(*keys) unless keys.empty?
    end

    # Materialize the colonel FIRST — Customer.create! itself ticks the
    # signups metric (the instrumentation under test) — then zero the slate.
    before do
      colonel
      clear_daily_metrics
    end

    it 'counts a customer signup into the signups series (chokepoint wiring)' do
      create_customer(email: "signup-#{SecureRandom.hex(4)}@example.com")

      data = trends

      expect(data[:details][:series][:signups].last[:count]).to eq(1)
    end

    it 'returns 30 zero-filled days per series when nothing was collected' do
      data = trends

      expect(data[:details][:days]).to eq(30)
      %i[signups secrets_created].each do |metric|
        series = data[:details][:series][metric]
        expect(series.length).to eq(30)
        expect(series.map { |p| p[:count] }).to all(eq(0))
        expect(series.last[:date]).to eq(Time.now.utc.to_date.iso8601)
      end
    end

    it "reflects DailyMetric increments in today's bucket" do
      2.times { Onetime::DailyMetric.increment(:signups) }
      Onetime::DailyMetric.increment(:secrets_created)

      data = trends

      expect(data[:details][:series][:signups].last[:count]).to eq(2)
      expect(data[:details][:series][:secrets_created].last[:count]).to eq(1)
    end

    # NOT on the curated list, and this pins that the curation is real rather
    # than "audit every GET". Trends is aggregate counters: it exposes no
    # customer material and extracts nothing in bulk, so it writes to NEITHER
    # trail (CONTRACT 4).
    it 'reading trends writes NO audit event on any trail (CONTRACT 4)' do
      before_count = Onetime::ColonelAuditEvent.count

      trends

      expect(Onetime::ColonelAuditEvent.count).to eq(before_count)
      expect(Onetime::ColonelAuditEvent.access_count).to eq(0)
    end

    it 'rejects non-colonel actors' do
      staff = create_customer(email: "staff-#{SecureRandom.hex(4)}@example.com", role: 'staff')

      logic = ColonelAPI::Logic::Colonel::GetTrends.new(strategy_result_for(staff), {})
      expect { logic.raise_concerns }.to raise_error(Onetime::Forbidden)
    end
  end
end

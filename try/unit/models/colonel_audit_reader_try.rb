# try/unit/models/colonel_audit_reader_try.rb
#
# frozen_string_literal: true

#
# Unit tests for Onetime::ColonelAuditReader — the single READ projection of
# the operator audit trail (#4334), shared by three readers that must not
# drift: GET /api/colonel/audit, GET /api/colonel/audit/export, and
# `bin/ots audit list`.
#
# Covers:
# - the merged, newest-first view over both trails
# - the actor / verb filter semantics (substring vs exact-or-category-prefix)
# - the FIELD ALLOWLIST (what a reader is allowed to see)
# - CSV and NDJSON serialisation, including how free-form `detail` is encoded
# - format normalisation and the download filename

require_relative '../../support/test_models'
require 'csv'
require 'onetime/colonel_audit_reader'

OT.boot! :test

Reader = Onetime::ColonelAuditReader

ColonelAuditEvent.events.clear
ColonelAuditEvent.security_events.clear
ColonelAuditEvent.access_events.clear

# TRYOUTS

## the allowlist is exactly the fields the wire contract types
Reader::FIELDS
#=> [:id, :actor, :verb, :target, :result, :detail, :created, :trail]

## MAX_COMBINED is the whole store: all three caps summed, never a traffic function
Reader::MAX_COMBINED
#=> ColonelAuditEvent::MAX_EVENTS + ColonelAuditEvent::MAX_SECURITY_EVENTS + ColonelAuditEvent::MAX_ACCESS_EVENTS

## merged() reads BOTH trails, newest-first
ColonelAuditEvent.events.clear
ColonelAuditEvent.security_events.clear
ColonelAuditEvent.access_events.clear
ColonelAuditEvent.record(actor: 'ur_col', verb: 'customer.purge', target: 'ur_v', result: :success)
ColonelAuditEvent.record_security(actor: 'anonymous', verb: 'auth.throttled', target: 'ip', result: :failure)
ColonelAuditEvent.record(actor: 'ur_col', verb: 'banner.set', target: 'banner', result: :success)
Reader.merged(10).map { |e| e['verb'] }
#=> ["banner.set", "auth.throttled", "customer.purge"]

## merged() truncates to the requested limit, keeping the newest
Reader.merged(2).map { |e| e['verb'] }
#=> ["banner.set", "auth.throttled"]

## a non-positive limit reads nothing
Reader.merged(0)
#=> []

## recent() with no filters is merged()
Reader.recent(limit: 2).map { |e| e['verb'] }
#=> ["banner.set", "auth.throttled"]

## the verb filter matches an exact verb
Reader.recent(verb: 'customer.purge').map { |e| e['verb'] }
#=> ["customer.purge"]

## …and a dotted CATEGORY prefix reaches the whole family
Reader.recent(verb: 'customer').map { |e| e['verb'] }
#=> ["customer.purge"]

## a prefix must be dotted: 'custom' is not a category of 'customer.purge'
Reader.recent(verb: 'custom')
#=> []

## the actor filter is a case-insensitive SUBSTRING (the sessions-search idiom)
Reader.recent(actor: 'UR_COL').map { |e| e['verb'] }
#=> ["banner.set", "customer.purge"]

## filters compose
Reader.recent(actor: 'ur_col', verb: 'banner').map { |e| e['verb'] }
#=> ["banner.set"]

## a filtered read still honours the limit, keeping the newest match
Reader.recent(limit: 1, actor: 'ur_col').map { |e| e['verb'] }
#=> ["banner.set"]

## format_event emits the allowlist and nothing else
@event = Reader.merged(1).first
Reader.format_event(@event).keys
#=> [:id, :actor, :verb, :target, :result, :detail, :created, :trail]

## an event formatted OUTSIDE the merge (a raw model read) falls back to the
## operator trail — where every untagged event came from before #4335
Reader.format_event(ColonelAuditEvent.recent(1).first)[:trail]
#=> "events"

## created stays the stored epoch float — one timestamp representation, not two
Reader.format_event(@event)[:created].is_a?(Float)
#=> true

## -- Serialisation --------------------------------------------------------

## NDJSON is one allowlisted JSON object per line, newline-terminated
@ndjson = Reader.serialize(Reader.merged(3), format: 'ndjson')
[@ndjson.lines.size, @ndjson.end_with?("\n"), JSON.parse(@ndjson.lines.first)['verb']]
#=> [3, true, "banner.set"]

## an empty trail serialises to an empty NDJSON body, not a broken line
Reader.serialize([], format: 'ndjson')
#=> ""

## CSV leads with the allowlist as its header row
CSV.parse(Reader.serialize(Reader.merged(3), format: 'csv')).first
#=> ["id", "actor", "verb", "target", "result", "detail", "created", "trail"]

## an empty trail still serialises a header-only CSV
Reader.serialize([], format: 'csv')
#=> "id,actor,verb,target,result,detail,created,trail\n"

## `trail` is APPENDED, so every incumbent column keeps its index
Reader::FIELDS.index(:detail)
#=> 5

## a CSV detail cell is JSON, so a consumer parses it back to the JSON surface's value
ColonelAuditEvent.events.clear
ColonelAuditEvent.security_events.clear
ColonelAuditEvent.record(actor: 'a', verb: 'v', target: 't', result: :success,
                         detail: { 'reason' => 'gdpr, urgent', 'quoted' => 'say "hi"' })
@row = CSV.parse(Reader.serialize(Reader.merged(1), format: 'csv'))[1]
JSON.parse(@row[5])
#=> { "reason" => "gdpr, urgent", "quoted" => 'say "hi"' }

## a nil detail is an empty cell, never the string "null"
ColonelAuditEvent.events.clear
ColonelAuditEvent.record(actor: 'a', verb: 'v', target: 't', result: :success)
CSV.parse(Reader.serialize(Reader.merged(1), format: 'csv'))[1][5]
#=> ""

## a cell a spreadsheet would EVALUATE is prefixed with the text guard
ColonelAuditEvent.events.clear
ColonelAuditEvent.record(actor: 'a', verb: 'v', target: '=HYPERLINK("http://evil.test","click")',
                         result: :success)
CSV.parse(Reader.serialize(Reader.merged(1), format: 'csv'))[1][3]
#=> "'=HYPERLINK(\"http://evil.test\",\"click\")"

## every formula opener is covered, including the tab/CR the importer strips first
ColonelAuditEvent.events.clear
['=cmd', '+1+1', '-2+3', '@SUM(A1)', "\tcmd", "\rcmd"].each do |payload|
  ColonelAuditEvent.record(actor: 'a', verb: 'v', target: payload, result: :success)
end
CSV.parse(Reader.serialize(Reader.merged(6), format: 'csv'))[1..].map { |row| row[3][0] }
#=> ["'", "'", "'", "'", "'", "'"]

## the guard reaches the JSON-encoded detail cell too — serialisation is not a way past it
ColonelAuditEvent.events.clear
ColonelAuditEvent.record(actor: 'a', verb: 'v', target: 't', result: :success, detail: '=cmd|calc')
CSV.parse(Reader.serialize(Reader.merged(1), format: 'csv'))[1][5]
#=> "'=cmd|calc"

## an ordinary cell is untouched — no stray apostrophes in a normal export
ColonelAuditEvent.events.clear
ColonelAuditEvent.record(actor: 'ur_col', verb: 'customer.purge', target: 'ur_victim', result: :success)
@ordinary = CSV.parse(Reader.serialize(Reader.merged(1), format: 'csv'))[1]
[@ordinary[1], @ordinary[2], @ordinary[3]]
#=> ["ur_col", "customer.purge", "ur_victim"]

## NDJSON is UNTOUCHED: it has no formula problem and its consumers parse JSON
ColonelAuditEvent.events.clear
ColonelAuditEvent.record(actor: 'a', verb: 'v', target: '=cmd', result: :success)
JSON.parse(Reader.to_ndjson(Reader.merged(1)).lines.first)['target']
#=> "=cmd"

## an unsupported format raises rather than guessing
begin
  Reader.serialize([], format: 'xlsx')
rescue ArgumentError => ex
  ex.message.include?('xlsx')
end
#=> true

## -- Format normalisation --------------------------------------------------

## a blank format means the default
[Reader.normalize_format(nil), Reader.normalize_format('')]
#=> ["csv", "csv"]

## recognised formats normalise case and whitespace
[Reader.normalize_format(' CSV '), Reader.normalize_format(:ndjson)]
#=> ["csv", "ndjson"]

## an unrecognised format is nil — the caller decides whether that is an error
Reader.normalize_format('xlsx')
#=> nil

## content types are download types, not JSON
[Reader.content_type('csv'), Reader.content_type('ndjson')]
#=> ["text/csv; charset=utf-8", "application/x-ndjson; charset=utf-8"]

## the filename is timestamped so repeated exports do not collide
Reader.filename('csv', now: Time.utc(2026, 9, 1, 12, 30, 45))
#=> "colonel-audit-20260901T123045Z.csv"

## -- The OBSERVATION trail (#4335) -----------------------------------------

## all THREE trails merge into one chronological feed
ColonelAuditEvent.events.clear
ColonelAuditEvent.security_events.clear
ColonelAuditEvent.access_events.clear
ColonelAuditEvent.record(actor: 'ur_col', verb: 'customer.purge', target: 'ur_v', result: :success)
ColonelAuditEvent.record_security(actor: 'anonymous', verb: 'auth.throttled', target: 'ip', result: :failure)
ColonelAuditEvent.record_access(actor: 'ur_col', verb: 'audit.list', target: 'colonel_audit',
                                result: :success)
Reader.merged(10).map { |e| e['verb'] }
#=> ["audit.list", "auth.throttled", "customer.purge"]

## every row is TAGGED with the trail it came from — retention differs per trail,
## so "nothing older than X" means something different in each
Reader.merged(10).map { |e| e['trail'] }
#=> ["access_events", "security_events", "events"]

## tagging is non-destructive: the stored member never grows a `trail` field
ColonelAuditEvent.recent(1).first.key?('trail')
#=> false

## observations answer the same verb filters as everything else
Reader.recent(verb: 'audit').map { |e| e['verb'] }
#=> ["audit.list"]

## …and the same actor filter, so one operator's whole session reads together
Reader.recent(actor: 'ur_col').map { |e| e['verb'] }
#=> ["audit.list", "customer.purge"]

## the trail tag survives serialisation to both export formats
JSON.parse(Reader.to_ndjson(Reader.merged(1)).lines.first)['trail']
#=> "access_events"

## and lands in the CSV's last column
CSV.parse(Reader.serialize(Reader.merged(1), format: 'csv'))[1].last
#=> "access_events"

# Cleanup
ColonelAuditEvent.events.clear
ColonelAuditEvent.security_events.clear
ColonelAuditEvent.access_events.clear

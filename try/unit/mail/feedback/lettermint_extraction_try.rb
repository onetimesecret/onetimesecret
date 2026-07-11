# try/unit/mail/feedback/lettermint_extraction_try.rb
#
# frozen_string_literal: true

# Unit tryouts for the REAL Lettermint feedback extraction:
#   Onetime::Mail::Feedback::Lettermint#stats / #messages / #lookup
#
# The provider_status op tryouts inject a fake FETCHER, so they never exercise
# extract_totals / metric / message_record / next_cursor — the one layer whose
# inputs are the provider's actual wire shape. This file injects a fake
# team_api (the gem client) into the REAL fetcher and asserts the mapping
# against payloads CAPTURED VERBATIM from the lettermint-ruby gem's own spec
# fixtures (spec/lettermint/resources/{stats,messages}_spec.rb):
#
#   /stats    -> {"totals":{"sent":1000,"delivered":950,"bounced":5},"daily":[]}
#   /messages -> {"data":[{"id":"msg_1","subject":"Hello","status":"delivered"}],
#                 "meta":{"next_cursor":"cursor_def"}}
#
# The point: prove that the real /stats shape (totals NESTED, bounce field named
# `bounced`, NO complaint field) maps to sent/delivered/hard_bounced correctly
# and to spam_complaints=nil (NOT 0 — "not reported", so the UI never shows a
# fake 0.00% complaint rate), and that the minimal /messages row maps without
# rejecting the wire schema.
#
# Run: try --agent try/unit/mail/feedback/lettermint_extraction_try.rb

require_relative '../../../support/test_helpers'

OT.boot! :test

require 'onetime/mail/feedback/lettermint'

F = Onetime::Mail::Feedback::Lettermint

# --- fake gem client returning the CAPTURED wire shapes ------------------

class FakeStatsResource
  # Verbatim from stats_spec.rb: totals nested, `bounced` (not hard_bounced),
  # no complaint field of any spelling.
  def get(from:, to:, **)
    { 'totals' => { 'sent' => 1000, 'delivered' => 950, 'bounced' => 5 }, 'daily' => [] }
  end
end

class FakeMessagesResource
  # Verbatim from messages_spec.rb: rows under `data`, only id/subject/status
  # present, next cursor under meta.next_cursor.
  def list(page_size: nil, page_cursor: nil, **)
    {
      'data' => [{ 'id' => 'msg_1', 'subject' => 'Hello', 'status' => 'delivered' }],
      'meta' => { 'next_cursor' => 'cursor_def' },
    }
  end
end

class FakeSuppressionsResource
  # Echoes the queried value, so an exact post-filter always matches.
  def list(value:, **)
    { 'data' => [{ 'value' => value, 'reason' => 'hard_bounce' }] }
  end
end

# A suppressions resource whose stored row does NOT carry the queried address —
# the provider returned a loose (domain/fuzzy) match. The fetcher's exact
# post-filter must reject it (contract §4 rule 9: never trust the provider
# filter for a single-address lookup).
class FakeLooseSuppressionsResource
  def list(value:, **)
    { 'data' => [{ 'value' => 'other@example.com', 'reason' => 'hard_bounce' }] }
  end
end

class FakeTeamAPI
  def initialize(suppressions: FakeSuppressionsResource.new)
    @suppressions = suppressions
  end

  def stats; FakeStatsResource.new; end
  def messages; FakeMessagesResource.new; end
  def suppressions; @suppressions; end
end

def build_fetcher(team_api: FakeTeamAPI.new)
  fetcher = F.new({})
  fetcher.instance_variable_set(:@team_api, team_api)
  fetcher
end

# --- /stats: the real shape maps correctly ------------------------------

## sent/delivered map from the nested totals block
@s = build_fetcher.stats(from: '2024-01-01', to: '2024-01-31')
[@s[:sent], @s[:delivered]]
#=> [1000, 950]

## bounce maps via the `bounced` alias (real field name, not hard_bounced)
@s = build_fetcher.stats(from: '2024-01-01', to: '2024-01-31')
@s[:hard_bounced]
#=> 5

## complaints ABSENT from /stats -> nil (NOT 0): "not reported", never a fake 0%
@s = build_fetcher.stats(from: '2024-01-01', to: '2024-01-31')
@s[:spam_complaints]
#=> nil

# --- /messages: minimal real row maps without schema-rejecting --------

## rows read from `data`, cursor from meta.next_cursor
@m = build_fetcher.messages(page_size: 30)
[@m[:messages].size, @m[:cursor]]
#=> [1, "cursor_def"]

## id/status/subject map; absent to/from_email/created_at default to schema-valid empties
@rec = build_fetcher.messages(page_size: 30)[:messages].first
[@rec[:id], @rec[:status], @rec[:subject], @rec[:to], @rec[:from_email], @rec[:created_at]]
#=> ["msg_1", "delivered", "Hello", [], "", nil]

# --- /suppressions lookup: exact post-filter + raw reason ----------------

## lookup matches on exact value and returns the RAW Lettermint reason
@l = build_fetcher.lookup('user@example.com')
[@l[:suppressed], @l[:reason]]
#=> [true, "hard_bounce"]

## exact post-filter rejects a loose provider match (row value != queried address)
@loose = build_fetcher(team_api: FakeTeamAPI.new(suppressions: FakeLooseSuppressionsResource.new))
@r = @loose.lookup('someone-else@example.com')
[@r[:suppressed], @r[:reason]]
#=> [false, nil]

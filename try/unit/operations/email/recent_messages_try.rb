# try/unit/operations/email/recent_messages_try.rb
#
# frozen_string_literal: true

# Unit tryouts for the Track B recent-messages op (item 9):
#   Onetime::Operations::Email::RecentMessages
#
# Only Lettermint has a message API; SES + non-live transports surface
# capability=false. Provider fetcher is INJECTED. Covers:
# - Lettermint: message mapping + cursor pagination (null totals)
# - SES: capability false, empty page, zero totals, per_page echoed
# - degraded (fetcher raises) -> capability true, available false, per_page echoed
# - NO-CREDS scan (§9)
#
# Run: try --agent try/unit/operations/email/recent_messages_try.rb

require_relative '../../../support/test_helpers'

OT.boot! :test

require 'onetime/operations/email/recent_messages'

RM = Onetime::Operations::Email::RecentMessages

class FakeMessages
  def messages(page_size:, page_cursor: nil)
    {
      messages: [
        {
          id: 'msg_abc123', status: 'hard_bounced', subject: 'Your secret link',
          to: ['recipient@example.com'], from_email: 'noreply@onetimesecret.com',
          created_at: 1_720_000_000
        },
      ],
      cursor: 'eyJnext',
    }
  end
end

class FakeBoomMessages
  def messages(page_size:, page_cursor: nil); raise 'lettermint list timed out'; end
end

def deep_string_values(obj)
  case obj
  when Hash  then obj.values.flat_map { |v| deep_string_values(v) }
  when Array then obj.flat_map { |v| deep_string_values(v) }
  when nil   then []
  else [obj.to_s]
  end
end

def deep_keys(obj)
  case obj
  when Hash  then obj.keys.map(&:to_s) + obj.values.flat_map { |v| deep_keys(v) }
  when Array then obj.flat_map { |v| deep_keys(v) }
  else []
  end
end

# --- Lettermint: mapping + cursor pagination ----------------------------

## lettermint is live; the message maps to the wire shape
@r = RM.new(provider: 'lettermint', page: 1, per_page: 30, fetcher: FakeMessages.new).call
[@r.capability, @r.available, @r.messages.first[:id], @r.messages.first[:status], @r.messages.first[:to]]
#=> [true, true, 'msg_abc123', 'hard_bounced', ['recipient@example.com']]

## cursor-paginated: totals are null, cursor carries "next"
@r = RM.new(provider: 'lettermint', page: 1, per_page: 30, fetcher: FakeMessages.new).call
[@r.pagination[:total_count], @r.pagination[:total_pages], @r.pagination[:cursor]]
#=> [nil, nil, 'eyJnext']

# --- SES: capability false ----------------------------------------------

## ses has no message API -> capability false, empty, zero totals, per_page echoed
@r = RM.new(provider: 'ses', page: 1, per_page: 30).call
[@r.capability, @r.available, @r.messages, @r.pagination[:total_count], @r.pagination[:per_page]]
#=> [false, false, [], 0, 30]

# --- degraded: fetcher raises -------------------------------------------

## a raising fetcher degrades: capability true, available false, per_page echoed
@r = RM.new(provider: 'lettermint', page: 2, per_page: 15, fetcher: FakeBoomMessages.new).call
[@r.capability, @r.available, @r.messages, @r.pagination[:per_page], @r.error.include?('timed out')]
#=> [true, false, [], 15, true]

# --- NO-CREDS scan (§9) --------------------------------------------------

## no secret sentinel value in the payload
@r      = RM.new(provider: 'lettermint', page: 1, per_page: 30, fetcher: FakeMessages.new).call
@leaves = deep_string_values(@r.to_h)
%w[super-secret-pw aws-secret-key lm_team_].any? { |s| @leaves.any? { |v| v.include?(s) } }
#=> false

## no secret-named key
@r    = RM.new(provider: 'lettermint', page: 1, per_page: 30, fetcher: FakeMessages.new).call
@keys = deep_keys(@r.to_h)
@keys.any? { |k| k.match?(/user|pass|secret|token/i) || k == 'api_key' }
#=> false

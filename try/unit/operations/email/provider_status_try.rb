# try/unit/operations/email/provider_status_try.rb
#
# frozen_string_literal: true

# Unit tryouts for the Track B provider-status op (item "status + rates"):
#   Onetime::Operations::Email::ProviderStatus
#
# The op is the fail-soft boundary. Test env resolves determine_provider ->
# 'logger', so we INJECT a fake fetcher (`fetcher:`) to reach the real SES /
# Lettermint mapping — otherwise the risky code (rate math, note, degraded
# path) is never exercised. Covers:
# - Lettermint: counts + rates computed in Ruby (float division, sent==0 guard)
# - SES: quota passthrough + rate_bounce/complaint null + rate_note present
# - degraded path (fetcher raises) -> capability true, available false, error
# - non-live provider -> capability false
# - NO-CREDS scan (§9): no secret sentinel value, no secret-named key
#
# Run: try --agent try/unit/operations/email/provider_status_try.rb

require_relative '../../../support/test_helpers'

OT.boot! :test

require 'onetime/operations/email/provider_status'

PS = Onetime::Operations::Email::ProviderStatus

# --- injectable fakes (plain objects, no mocking framework) --------------

class FakeLettermintStats
  def stats(from:, to:)
    { sent: 1000, delivered: 950, hard_bounced: 20, spam_complaints: 5, opened: 600, clicked: 200 }
  end
end

class FakeZeroStats
  def stats(from:, to:)
    { sent: 0, delivered: 0, hard_bounced: 0, spam_complaints: 0, opened: 0, clicked: 0 }
  end
end

class FakeSesAccount
  def account_status
    {
      enforcement_status: 'HEALTHY', production_access_enabled: true, sending_enabled: true,
      max_24_hour_send: 50_000.0, sent_last_24_hours: 1234.0, max_send_rate: 14.0
    }
  end
end

class FakeBoomFetcher
  def stats(*); raise 'stats timed out after 5s'; end
  def account_status; raise 'get_account timed out after 5s'; end
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

# --- Lettermint: rate math ----------------------------------------------

## lettermint status is live + computes bounce/complaint rates in Ruby
@r = PS.new(provider: 'lettermint', fetcher: FakeLettermintStats.new).call
[@r.capability, @r.available, @r.error, @r.ses]
#=> [true, true, nil, nil]

## rate_bounce = 20/1000, rate_complaint = 5/1000 (float division, not integer)
@r = PS.new(provider: 'lettermint', fetcher: FakeLettermintStats.new).call
[@r.lettermint[:rate_bounce], @r.lettermint[:rate_complaint], @r.lettermint[:window_days]]
#=> [0.02, 0.005, 30]

## sent==0 guards each rate to nil (never NaN / integer-division 0)
@r = PS.new(provider: 'lettermint', fetcher: FakeZeroStats.new).call
[@r.lettermint[:sent], @r.lettermint[:rate_bounce], @r.lettermint[:rate_complaint]]
#=> [0, nil, nil]

# --- SES: quota + null rate + note --------------------------------------

## ses status passes quota through, nulls the numeric rates, sets rate_note
@r = PS.new(provider: 'ses', fetcher: FakeSesAccount.new).call
[@r.capability, @r.available, @r.ses[:enforcement_status], @r.ses[:max_24_hour_send]]
#=> [true, true, 'HEALTHY', 50000.0]

## ses numeric rates are null with an explanatory rate_note (deferred gem)
@r = PS.new(provider: 'ses', fetcher: FakeSesAccount.new).call
[@r.ses[:rate_bounce], @r.ses[:rate_complaint], @r.ses[:rate_note].nil?]
#=> [nil, nil, false]

# --- fail-soft: fetcher raises ------------------------------------------

## a raising fetcher degrades: capability true, available false, error captured
@r = PS.new(provider: 'lettermint', fetcher: FakeBoomFetcher.new).call
[@r.capability, @r.available, @r.error.include?('timed out'), @r.lettermint]
#=> [true, false, true, nil]

# --- non-live provider ---------------------------------------------------

## logger (non-live) -> capability false, available false, both blocks nil
@r = PS.new(provider: 'logger').call
[@r.capability, @r.available, @r.ses, @r.lettermint]
#=> [false, false, nil, nil]

# --- NO-CREDS scan (§9) --------------------------------------------------

## no secret sentinel value appears anywhere in the payload
@r      = PS.new(provider: 'lettermint', fetcher: FakeLettermintStats.new).call
@leaves = deep_string_values(@r.to_h)
%w[super-secret-pw aws-secret-key lm_team_].any? { |s| @leaves.any? { |v| v.include?(s) } }
#=> false

## no key whose NAME implies a secret (user/pass/secret/token/api_key)
@r    = PS.new(provider: 'ses', fetcher: FakeSesAccount.new).call
@keys = deep_keys(@r.to_h)
@keys.any? { |k| k.match?(/user|pass|secret|token/i) || k == 'api_key' }
#=> false

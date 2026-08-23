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
# - SMTP2GO: cycle passthrough + percent->ratio conversion (nil preserved) +
#   cycle rate_note present
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

class FakeSmtp2goStats
  # The documented /stats/email_summary shape as the fetcher hands it over
  # (symbol keys, counts as Integers, percents as provider-reported Floats).
  def stats
    {
      cycle_start: '2021-04-01T00:00:00', cycle_end: '2021-05-01T00:00:00',
      cycle_used: 550, cycle_remaining: 450, cycle_max: 1000, email_count: 550,
      bounce_rejects: 10, softbounces: 10, hardbounces: 10, spam_rejects: 10,
      unsubscribes: 10, bounce_percent: 5.5, spam_percent: 1.8
    }
  end
end

class FakeSmtp2goNoPercents
  # Percents omitted by the provider arrive as nil (not 0.0) — the ratio
  # conversion must preserve the "not reported" distinction.
  def stats
    {
      cycle_start: nil, cycle_end: nil, cycle_used: 0, cycle_remaining: 1000,
      cycle_max: 1000, email_count: 0, bounce_rejects: 0, softbounces: 0,
      hardbounces: 0, spam_rejects: 0, unsubscribes: 0,
      bounce_percent: nil, spam_percent: nil
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

# --- SMTP2GO: cycle passthrough + percent -> ratio -----------------------

## smtp2go status is live; the ses/lettermint blocks stay nil
@r = PS.new(provider: 'smtp2go', fetcher: FakeSmtp2goStats.new).call
[@r.capability, @r.available, @r.error, @r.ses, @r.lettermint]
#=> [true, true, nil, nil, nil]

## cycle quota and counts pass through from /stats/email_summary
@r = PS.new(provider: 'smtp2go', fetcher: FakeSmtp2goStats.new).call
[@r.smtp2go[:cycle_used], @r.smtp2go[:cycle_remaining], @r.smtp2go[:cycle_max],
 @r.smtp2go[:hardbounces], @r.smtp2go[:spam_rejects]]
#=> [550, 450, 1000, 10, 10]

## provider percentages convert to ratios (5.5% -> 0.055), cycle rate_note present
@r = PS.new(provider: 'smtp2go', fetcher: FakeSmtp2goStats.new).call
[@r.smtp2go[:rate_bounce], @r.smtp2go[:rate_complaint].round(6), @r.smtp2go[:rate_note].nil?]
#=> [0.055, 0.018, false]

## unreported percentages stay nil (not 0.0) through the ratio conversion
@r = PS.new(provider: 'smtp2go', fetcher: FakeSmtp2goNoPercents.new).call
[@r.smtp2go[:rate_bounce], @r.smtp2go[:rate_complaint]]
#=> [nil, nil]

## a raising smtp2go fetcher degrades: capability true, available false, block nil
@r = PS.new(provider: 'smtp2go', fetcher: FakeBoomFetcher.new).call
[@r.capability, @r.available, @r.error.include?('timed out'), @r.smtp2go]
#=> [true, false, true, nil]

# --- fail-soft: fetcher raises ------------------------------------------

## a raising fetcher degrades: capability true, available false, error captured
@r = PS.new(provider: 'lettermint', fetcher: FakeBoomFetcher.new).call
[@r.capability, @r.available, @r.error.include?('timed out'), @r.lettermint]
#=> [true, false, true, nil]

# --- non-live provider ---------------------------------------------------

## logger (non-live) -> capability false, available false, all provider blocks nil
@r = PS.new(provider: 'logger').call
[@r.capability, @r.available, @r.ses, @r.lettermint, @r.smtp2go]
#=> [false, false, nil, nil, nil]

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

# try/unit/operations/email/recipient_lookup_try.rb
#
# frozen_string_literal: true

# Unit tryouts for the Track B recipient-lookup op (item 10):
#   Onetime::Operations::Email::RecipientLookup
#
# Local store is real (test Valkey); the provider fetcher is INJECTED. Covers:
# - local status is ALWAYS present (authority), even when provider is non-live
# - EmailSuppression.normalize keys the lookup (uppercase input matches store)
# - provider_result carries the RAW provider reason (not REASON_MAP'd)
# - a "not found" on the provider is available=true + suppressed=false
# - provider read failure is fail-soft: available=false, local still authoritative
# - non-live provider -> capability false, provider_result nil
# - NO-CREDS scan (§9)
#
# Run: try --agent try/unit/operations/email/recipient_lookup_try.rb

require_relative '../../../support/test_helpers'

OT.boot! :test

require 'onetime/models/email_suppression'
require 'onetime/operations/email/recipient_lookup'

RL  = Onetime::Operations::Email::RecipientLookup
SUP = Onetime::EmailSuppression

@ts   = Familia.now.to_i
@addr = "lookup_#{@ts}@example.com"
SUP.remove!(@addr)

class FakeSuppressed
  def lookup(address); { suppressed: true, reason: 'BOUNCE', last_update_time: 1_719_990_000 }; end
end

class FakeClean
  def lookup(address); { suppressed: false, reason: nil, last_update_time: nil }; end
end

class FakeBoomLookup
  def lookup(address); raise 'SES get_suppressed_destination failed'; end
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

# --- local always present; provider raw reason -------------------------

## not-in-store locally, but the provider reports suppressed with a RAW reason
@r = RL.new(address: @addr, provider: 'ses', fetcher: FakeSuppressed.new).call
[@r.local[:suppressed], @r.available, @r.provider_result[:suppressed], @r.provider_result[:reason]]
#=> [false, true, true, 'BOUNCE']

## provider last_update_time passes through untouched
@r = RL.new(address: @addr, provider: 'ses', fetcher: FakeSuppressed.new).call
@r.provider_result[:last_update_time]
#=> 1_719_990_000

# --- normalization keys the lookup --------------------------------------

## an UPPERCASE input normalizes to the stored (lowercase) key and finds it
SUP.suppress!(address: @addr, reason: 'bounce', source: 'manual')
@r = RL.new(address: @addr.upcase, provider: 'lettermint', fetcher: FakeClean.new).call
[@r.address, @r.local[:suppressed], @r.local[:reason], @r.local[:source]]
#=> [@addr, true, 'bounce', 'manual']

## provider reports clean -> available true, suppressed false (not an error)
@r = RL.new(address: @addr, provider: 'lettermint', fetcher: FakeClean.new).call
[@r.available, @r.provider_result[:suppressed], @r.provider_result[:reason]]
#=> [true, false, nil]

# --- provider fail-soft: local stays authoritative ----------------------

## a raising provider lookup degrades but local (suppressed) remains
@r = RL.new(address: @addr, provider: 'ses', fetcher: FakeBoomLookup.new).call
[@r.available, @r.error.include?('failed'), @r.provider_result, @r.local[:suppressed]]
#=> [false, true, nil, true]

# --- non-live provider ---------------------------------------------------

## logger -> capability false, provider_result nil, local still present
@r = RL.new(address: @addr, provider: 'logger').call
[@r.capability, @r.provider_result, @r.local[:suppressed]]
#=> [false, nil, true]

# --- NO-CREDS scan (§9) --------------------------------------------------

## no secret sentinel value in the payload
@r      = RL.new(address: @addr, provider: 'ses', fetcher: FakeSuppressed.new).call
@leaves = deep_string_values(@r.to_h)
%w[super-secret-pw aws-secret-key lm_team_].any? { |s| @leaves.any? { |v| v.include?(s) } }
#=> false

## no secret-named key
@r    = RL.new(address: @addr, provider: 'ses', fetcher: FakeSuppressed.new).call
@keys = deep_keys(@r.to_h)
@keys.any? { |k| k.match?(/user|pass|secret|token/i) || k == 'api_key' }
#=> false

# --- teardown ------------------------------------------------------------
SUP.remove!(@addr) rescue nil

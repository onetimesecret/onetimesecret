# try/unit/operations/verify_domain_confirmation_window_try.rb
#
# frozen_string_literal: true

# Operations::VerifyDomain::ConfirmationWindow: the bound on how long an
# indeterminate TXT check may hold `verified`.
#
#   1. A domain with no clock (every domain at deploy) starts one on its first
#      indeterminate check and is not demoted by it, however old it is.
#   2. Inside the window an indeterminate check changes nothing.
#   3. Past the window an indeterminate check withdraws `verified`, reported
#      as :confirmation_expired (not :indeterminate, not :failed).
#   4. A passing check records verified_confirmed_at and clears the clock, so
#      one resolver failure long after the last pass never demotes. A pass
#      from a strategy that does not check the record records nothing.
#   5. A definitive failure clears the clock too.
#   6. An operator override exempts the domain; unverified domains are
#      untouched.
#   7. A dry run reports the expiry and writes nothing.
#   8. BulkResult counts expiries.

require_relative '../../support/test_helpers'
require 'securerandom'

OT.boot! :test

require 'onetime/operations/verify_domain'

# Strategy stand-in whose TXT answer the cases script.
class WindowTryStrategy
  INDETERMINATE = {
    validated: nil, indeterminate: true,
    message: 'DNS lookup failed (indeterminate)',
    data: [{ 'actual_values' => false, 'match' => false }]
  }.freeze
  PASS          = { validated: true, message: 'TXT record validated', data: [{ 'match' => true }] }.freeze
  FAIL          = { validated: false, message: 'TXT record not found', data: [{ 'actual_values' => [] }] }.freeze

  attr_accessor :ownership_result, :proves_ownership

  def initialize
    @ownership_result = INDETERMINATE
    @proves_ownership = true
  end

  def proves_ownership?           = proves_ownership
  def validate_ownership(_domain) = ownership_result
  def check_status(_domain)       = { ready: true, has_ssl: true, is_resolving: true, mode: 'window_try' }
  def request_certificate(_domain) = { status: 'success' }
  def bulk_rate_limit             = 0
end

WINDOW_TRY_MAX_AGE = Onetime::Operations::VerifyDomain::ConfirmationWindow::MAX_AGE

@strategy = WindowTryStrategy.new
@suffix   = "#{Familia.now.to_i}-#{SecureRandom.hex(3)}"
@owner    = Onetime::Customer.create!(email: "window_try_#{@suffix}@test.com")
@org      = Onetime::Organization.create!('WindowTry Corp', @owner, "window_try_#{@suffix}@corp.com")
@org.define_singleton_method(:billing_enabled?) { false }
@domain   = Onetime::CustomDomain.create!("window-#{@suffix}.example.com", @org.objid)
@other    = Onetime::CustomDomain.create!("window-other-#{@suffix}.example.com", @org.objid)

def window_try_verify(domain, persist: true)
  Onetime::Operations::VerifyDomain.new(domain: domain, strategy: @strategy, persist: persist).call
end

def window_try_reload(domain)
  Onetime::CustomDomain.find_by_identifier(domain.identifier)
end

# Put a domain in a known stored state.
def window_try_set(domain, verified:, since: nil, confirmed_at: nil, override: false)
  domain.verified                   = verified
  domain.resolving                  = true
  domain.verified_by_override       = override
  domain.verified_unconfirmed_since = since
  domain.verified_confirmed_at      = confirmed_at
  domain.save
end

## The default window is 7 days
WINDOW_TRY_MAX_AGE
#=> 604_800

## A new domain has neither timestamp
[@domain.verified_confirmed_at, @domain.verified_unconfirmed_since]
#=> [nil, nil]

## No clock yet - the first indeterminate check of a verified domain holds it
window_try_set(@domain, verified: true)
@strategy.ownership_result = WindowTryStrategy::INDETERMINATE
@first = window_try_verify(@domain)
[@first.current_state, @first.demoted?, @first.confirmation_expired, @first.dns_outcome]
#=> [:verified, false, false, :indeterminate]

## No clock yet - that check started the clock
@started_at = window_try_reload(@domain).verified_unconfirmed_since
(Familia.now.to_i - @started_at).between?(0, 5)
#=> true

## No clock yet - an old last confirmation does not demote either
window_try_set(@domain, verified: true, confirmed_at: Familia.now.to_i - (WINDOW_TRY_MAX_AGE * 10))
@old_pass = window_try_verify(@domain)
[@old_pass.current_state, @old_pass.confirmation_expired, window_try_reload(@domain).verified]
#=> [:verified, false, true]

## Inside the window - an indeterminate check changes nothing and keeps the clock
@inside_since = Familia.now.to_i - WINDOW_TRY_MAX_AGE + 3600
window_try_set(@domain, verified: true, since: @inside_since)
@inside = window_try_verify(@domain)
@inside_reloaded = window_try_reload(@domain)
[@inside.current_state, @inside.confirmation_expired, @inside_reloaded.verified, @inside_reloaded.verified_unconfirmed_since == @inside_since]
#=> [:verified, false, true, true]

## Past the window - a dry run reports the expiry and writes nothing
@expired_since = Familia.now.to_i - WINDOW_TRY_MAX_AGE - 60
window_try_set(@domain, verified: true, since: @expired_since)
@dry = window_try_verify(@domain, persist: false)
@dry_reloaded = window_try_reload(@domain)
[@dry.dns_outcome, @dry.demoted?, @dry.persisted, @dry_reloaded.verified, @dry_reloaded.verified_unconfirmed_since == @expired_since]
#=> [:confirmation_expired, false, false, true, true]

## Past the window - an indeterminate check withdraws verified
@expired = window_try_verify(@domain)
[@expired.previous_state, @expired.current_state, @expired.demoted?, @expired.confirmation_expired]
#=> [:verified, :resolving, true, true]

## Past the window - the outcome is distinct and the check still counts as indeterminate
[@expired.dns_outcome, @expired.dns_indeterminate, @expired.dns_validated, @expired.to_h[:confirmation_expired]]
#=> [:confirmation_expired, true, false, true]

## Past the window - the demotion is stored and the clock is cleared
@expired_reloaded = window_try_reload(@domain)
[@expired_reloaded.verified, @expired_reloaded.verified_unconfirmed_since]
#=> [false, nil]

## Unverified - a further indeterminate check starts no clock and reports plain indeterminate
@after = window_try_verify(@domain)
[@after.dns_outcome, @after.demoted?, window_try_reload(@domain).verified_unconfirmed_since]
#=> [:indeterminate, false, nil]

## A passing check records the confirmation and clears the clock
window_try_set(@domain, verified: true, since: @expired_since)
@strategy.ownership_result = WindowTryStrategy::PASS
@pass = window_try_verify(@domain)
@pass_reloaded = window_try_reload(@domain)
[@pass.dns_outcome, @pass_reloaded.verified, @pass_reloaded.verified_unconfirmed_since, (Familia.now.to_i - @pass_reloaded.verified_confirmed_at).between?(0, 5)]
#=> [:validated, true, nil, true]

## A passing check promotes an unverified domain and records the confirmation
window_try_set(@other, verified: false)
@promoted = window_try_verify(@other)
[@promoted.current_state, window_try_reload(@other).verified_confirmed_at.nil?]
#=> [:verified, false]

## A pass from a strategy that does not check the record (Passthrough) verifies and clears the clock, but is not a confirmation
window_try_set(@other, verified: false, since: @inside_since)
@strategy.proves_ownership = false
@unproven = window_try_verify(@other)
@strategy.proves_ownership = true
@unproven_reloaded = window_try_reload(@other)
[@unproven.current_state, @unproven_reloaded.verified_unconfirmed_since, @unproven_reloaded.verified_confirmed_at]
#=> [:verified, nil, nil]

## The real PassthroughStrategy leaves verified_confirmed_at nil
window_try_set(@other, verified: false)
@passthrough = Onetime::Operations::VerifyDomain.new(
  domain: @other, strategy: Onetime::DomainValidation::PassthroughStrategy.new({}), persist: true
).call
@passthrough_reloaded = window_try_reload(@other)
[@passthrough.current_state, @passthrough_reloaded.verified, @passthrough_reloaded.verified_confirmed_at]
#=> [:verified, true, nil]

## A definitive failure demotes as before and clears the clock
window_try_set(@domain, verified: true, since: @inside_since, confirmed_at: @inside_since - 60)
@strategy.ownership_result = WindowTryStrategy::FAIL
@failed = window_try_verify(@domain)
@failed_reloaded = window_try_reload(@domain)
[@failed.dns_outcome, @failed.confirmation_expired, @failed_reloaded.verified, @failed_reloaded.verified_unconfirmed_since, @failed_reloaded.verified_confirmed_at == @inside_since - 60]
#=> [:failed, false, false, nil, true]

## Operator override - an expired clock does not demote, and no clock is started
window_try_set(@domain, verified: true, since: @expired_since, override: true)
@strategy.ownership_result = WindowTryStrategy::INDETERMINATE
@held = window_try_verify(@domain)
@held_reloaded = window_try_reload(@domain)
[@held.dns_outcome, @held.demoted?, @held_reloaded.verified, @held_reloaded.verified_by_override]
#=> [:indeterminate, false, true, true]

## Operator override - a domain with no clock gets none while the override holds
window_try_set(@domain, verified: true, override: true)
window_try_verify(@domain)
window_try_reload(@domain).verified_unconfirmed_since
#=> nil

## Bulk - expiries are counted, and also count as indeterminate and demoted
window_try_set(@domain, verified: true, since: @expired_since)
window_try_set(@other, verified: true, since: @inside_since)
@bulk = Onetime::Operations::VerifyDomain.new(domains: [@domain, @other], strategy: @strategy, persist: true).call
[@bulk.confirmation_expired_count, @bulk.indeterminate_count, @bulk.demoted_count, @bulk.to_h[:confirmation_expired_count]]
#=> [1, 2, 1, 1]

## The window itself - max_age and now are injectable
@window_domain = window_try_reload(@other)
@window = Onetime::Operations::VerifyDomain::ConfirmationWindow.new(
  @window_domain, WindowTryStrategy::INDETERMINATE, now: @inside_since + 120, max_age: 60
)
[@window.expired?, @window.unconfirmed_since == @inside_since, @window.max_age]
#=> [true, true, 60]

## The window itself - exactly max_age is not yet expired
Onetime::Operations::VerifyDomain::ConfirmationWindow.new(
  @window_domain, WindowTryStrategy::INDETERMINATE, now: @inside_since + 60, max_age: 60
).expired?
#=> false

# Teardown
@domain.destroy!
@other.destroy!
@org.destroy!
@owner.destroy!

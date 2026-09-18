# try/unit/operations/verify_domain_approximated_unavailable_try.rb
#
# frozen_string_literal: true

# Operations::VerifyDomain driven by the real ApproximatedStrategy when the
# upstream checker cannot be asked at all: no API key, a non-200 response, a
# client exception. None of those is evidence about the customer's DNS, so the
# native TXT lookup decides, the same as for an indeterminate upstream answer:
#
#   - native match: the domain is confirmed (verified_confirmed_at stamped,
#     unconfirmed clock cleared). A deployment whose API key is missing or
#     revoked keeps confirming natively and is not demoted once the
#     confirmation window runs out.
#   - native definitive negative: a verified domain is demoted.
#   - native indeterminate: reported :indeterminate (not :failed) and bounded
#     by the confirmation window.
#   - a strategy that raises is :indeterminate too.
#
# The Approximated client and the resolver are scripted; nothing leaves the
# process.

require_relative '../../support/test_helpers'
require 'securerandom'

OT.boot! :test

require 'onetime/operations/verify_domain'
require 'onetime/domain_validation/strategy'

# Approximated client whose TXT check is scripted per case. The vhost lookup
# always answers, so only the ownership check is under test.
module ApproxUnavailableTryClient
  Response = Struct.new(:code, :parsed_response)

  class << self
    attr_accessor :mode, :txt_calls

    def check_records_match_exactly(_api_key, _records)
      self.txt_calls += 1
      raise StandardError, 'connection reset' if mode == :raise

      Response.new(503, { 'error' => 'unavailable' })
    end

    def get_vhost_by_incoming_address(_api_key, _domain)
      Response.new(200, { 'data' => { 'status' => 'ACTIVE_SSL', 'has_ssl' => true, 'is_resolving' => true } })
    end
  end
end
ApproxUnavailableTryClient.txt_calls = 0

# Scripted stand-in for DomainValidation::TxtResolver.
class ApproxUnavailableTryResolver
  attr_accessor :rcode, :values

  def lookup(_hostname)
    Onetime::DomainValidation::TxtResolver::Answer.new(rcode: rcode, values: values || [])
  end

  def close; end
end

# Strategy whose ownership check raises out of the strategy itself.
class ApproxUnavailableTryRaisingStrategy
  def validate_ownership(_domain)  = raise(StandardError, 'strategy failed')
  def check_status(_domain)        = { ready: true, has_ssl: true, is_resolving: true, mode: 'raising_try' }
  def request_certificate(_domain) = { status: 'success' }
  def proves_ownership?            = true
  def bulk_rate_limit              = 0
end

APPROX_UNAVAILABLE_MAX_AGE = Onetime::Operations::VerifyDomain::ConfirmationWindow::MAX_AGE

@previous_api_key = Onetime::DomainValidation::Features.api_key

@resolver = ApproxUnavailableTryResolver.new
@verifier = Onetime::DomainValidation::TxtVerifier.new(resolver_factory: -> { @resolver })
@strategy = Onetime::DomainValidation::ApproximatedStrategy.new(
  {}, client: ApproxUnavailableTryClient, txt_verifier: @verifier
)

@suffix = "#{Familia.now.to_i}-#{SecureRandom.hex(3)}"
@owner  = Onetime::Customer.create!(email: "approx_unavail_#{@suffix}@test.com")
@org    = Onetime::Organization.create!('ApproxUnavail Corp', @owner, "approx_unavail_#{@suffix}@corp.com")
@org.define_singleton_method(:billing_enabled?) { false }
@domain = Onetime::CustomDomain.create!("approx-unavail-#{@suffix}.example.com", @org.objid)

def approx_unavailable_verify(domain, strategy: @strategy)
  Onetime::Operations::VerifyDomain.new(domain: domain, strategy: strategy, persist: true).call
end

def approx_unavailable_reload(domain)
  Onetime::CustomDomain.find_by_identifier(domain.identifier)
end

# A verified domain whose checks have been indeterminate for `since_age`
# seconds (nil: no clock running).
def approx_unavailable_set(domain, since_age: nil, confirmed_at: nil)
  domain.verified                   = true
  domain.resolving                  = true
  domain.verified_by_override       = false
  domain.verified_unconfirmed_since = since_age && (Familia.now.to_i - since_age)
  domain.verified_confirmed_at      = confirmed_at
  domain.save
end

def approx_unavailable_native(rcode, values = [])
  @resolver.rcode  = rcode
  @resolver.values = values
end

## No API key, native match - past the window the domain is confirmed, not demoted
Onetime::DomainValidation::Features.api_key = nil
approx_unavailable_native(Resolv::DNS::RCode::NoError, [@domain.txt_validation_value])
approx_unavailable_set(@domain, since_age: APPROX_UNAVAILABLE_MAX_AGE + 3600)
@keyless = approx_unavailable_verify(@domain)
[@keyless.dns_outcome, @keyless.demoted?, @keyless.confirmation_expired, @keyless.current_state]
#=> [:validated, false, false, :verified]

## No API key, native match - the confirmation is stamped and the clock cleared
@keyless_stored = approx_unavailable_reload(@domain)
[(Familia.now.to_i - @keyless_stored.verified_confirmed_at).between?(0, 5), @keyless_stored.verified_unconfirmed_since]
#=> [true, nil]

## No API key - the upstream client was never called
ApproxUnavailableTryClient.txt_calls
#=> 0

## No API key, native match - an unverified domain is promoted
@domain.verified = false
@domain.save
@promoted = approx_unavailable_verify(@domain)
[@promoted.previous_state, @promoted.current_state, @promoted.dns_outcome]
#=> [:resolving, :verified, :validated]

## No API key, native NXDOMAIN - a verified domain is demoted
approx_unavailable_native(Resolv::DNS::RCode::NXDomain)
approx_unavailable_set(@domain)
@keyless_gone = approx_unavailable_verify(@domain)
[@keyless_gone.dns_outcome, @keyless_gone.demoted?, approx_unavailable_reload(@domain).verified]
#=> [:failed, true, false]

## No API key, native NXDOMAIN - the message names both checkers
@keyless_gone.dns_message
#=> 'TXT record not found (native lookup; upstream checker unavailable: Approximated API key not configured)'

## No API key, native SERVFAIL - indeterminate, not failed; verified held and the clock started
approx_unavailable_native(Resolv::DNS::RCode::ServFail)
approx_unavailable_set(@domain)
@keyless_servfail = approx_unavailable_verify(@domain)
@keyless_servfail_stored = approx_unavailable_reload(@domain)
[@keyless_servfail.dns_outcome, @keyless_servfail.demoted?, @keyless_servfail_stored.verified, @keyless_servfail_stored.verified_unconfirmed_since.nil?]
#=> [:indeterminate, false, true, false]

## No API key, native SERVFAIL past the window - the confirmation window applies
approx_unavailable_set(@domain, since_age: APPROX_UNAVAILABLE_MAX_AGE + 60)
@keyless_expired = approx_unavailable_verify(@domain)
[@keyless_expired.dns_outcome, @keyless_expired.demoted?, approx_unavailable_reload(@domain).verified]
#=> [:confirmation_expired, true, false]

## Non-200, native SERVFAIL - indeterminate, verified held
Onetime::DomainValidation::Features.api_key = 'approx-unavail-try-key'
ApproxUnavailableTryClient.mode             = :status
approx_unavailable_set(@domain)
@non200 = approx_unavailable_verify(@domain)
[@non200.dns_outcome, @non200.demoted?, approx_unavailable_reload(@domain).verified]
#=> [:indeterminate, false, true]

## Non-200 - one upstream call, no NXDOMAIN probe
ApproxUnavailableTryClient.txt_calls
#=> 1

## Non-200, native match - validated
approx_unavailable_native(Resolv::DNS::RCode::NoError, [@domain.txt_validation_value])
approx_unavailable_verify(@domain).dns_outcome
#=> :validated

## Client exception, native SERVFAIL - indeterminate, verified held
ApproxUnavailableTryClient.mode = :raise
approx_unavailable_native(Resolv::DNS::RCode::ServFail)
approx_unavailable_set(@domain)
@raised = approx_unavailable_verify(@domain)
[@raised.dns_outcome, @raised.demoted?, approx_unavailable_reload(@domain).verified]
#=> [:indeterminate, false, true]

## Client exception, native NXDOMAIN - demoted on the native answer
approx_unavailable_native(Resolv::DNS::RCode::NXDomain)
@raised_gone = approx_unavailable_verify(@domain)
[@raised_gone.dns_outcome, @raised_gone.demoted?]
#=> [:failed, true]

## A strategy that raises - indeterminate, verified held and the clock started
approx_unavailable_set(@domain)
@strategy_raised = approx_unavailable_verify(@domain, strategy: ApproxUnavailableTryRaisingStrategy.new)
@strategy_raised_stored = approx_unavailable_reload(@domain)
[@strategy_raised.dns_outcome, @strategy_raised.success?, @strategy_raised_stored.verified, @strategy_raised_stored.verified_unconfirmed_since.nil?]
#=> [:indeterminate, true, true, false]

## A strategy that raises, past the window - the confirmation window applies
approx_unavailable_set(@domain, since_age: APPROX_UNAVAILABLE_MAX_AGE + 60)
approx_unavailable_verify(@domain, strategy: ApproxUnavailableTryRaisingStrategy.new).dns_outcome
#=> :confirmation_expired

# Teardown
Onetime::DomainValidation::Features.api_key = @previous_api_key
@domain.destroy! if @domain&.exists?
@org.destroy! if @org&.exists?
@owner.destroy! if @owner&.exists?

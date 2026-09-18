# try/unit/operations/verify_domain_caddy_on_demand_try.rb
#
# frozen_string_literal: true

# Operations::VerifyDomain driven by the real CaddyOnDemandStrategy.
#
# The internal ACME ask endpoint (apps/internal/acme) authorises a certificate
# only when CustomDomain#ready? is true, and ready? requires `verified`. These
# cases run the real strategy and the real TxtVerifier over a scripted resolver
# (no sockets) and check what ends up stored:
#
#   1. No TXT record: the domain does not become verified; ready? stays false.
#   2. A matching TXT record promotes.
#   3. An indeterminate lookup leaves a verified domain verified, provided a
#      TXT check has confirmed it before (verified_confirmed_at).
#   4. A definitive negative demotes a verified domain ...
#   5. ... unless an operator override holds it.
#   6. A newly created domain starts unverified.
#   6a. A domain the Passthrough strategy verified has no confirmation on
#       record, so after a move to this strategy case 3 does not apply to it.
#
# The status half (check_status) runs over a scripted TlsProbe:
#
#   7. A definite probe answer is stored: `resolving`, and has_ssl inside vhost.
#   8. A probe that could not tell leaves `resolving` and vhost as they were
#      and marks the check as failed (vhost_fetch_failed_at).
#   9. A probe that knows only that the name resolves stores `resolving` and
#      refreshes the vhost blob, carrying the stored has_ssl forward.
#  10. A vhost blob written under the Approximated strategy is not replaced.
#
# The scripted probe reports resolving + valid certificate until case 7, so
# `verified` is the only thing between the domain and ready? in cases 1-6.

require_relative '../../support/test_helpers'
require 'securerandom'

OT.boot! :test

require 'onetime/operations/verify_domain'
require 'onetime/domain_validation/strategy'

# Scripted stand-in for DomainValidation::TxtResolver.
class CaddyTryScriptedResolver
  Answer = Onetime::DomainValidation::TxtResolver::Answer

  attr_accessor :rcode, :values, :error
  attr_reader :lookups

  def initialize
    @rcode   = Resolv::DNS::RCode::NXDomain
    @values  = []
    @lookups = []
  end

  def lookup(hostname)
    @lookups << hostname
    raise error if error

    Answer.new(rcode: rcode, values: values)
  end

  def close; end
end

# Scripted stand-in for DomainValidation::TlsProbe. Returns the real Result.
class CaddyTryScriptedProbe
  Result = Onetime::DomainValidation::TlsProbe::Result

  attr_accessor :is_resolving, :has_ssl
  attr_reader :probed

  def initialize
    @is_resolving = true
    @has_ssl      = true
    @probed       = []
  end

  def probe(hostname)
    @probed << hostname
    Result.new(is_resolving: is_resolving, has_ssl: has_ssl, addresses: ['93.184.216.34'], message: 'scripted')
  end
end

@resolver = CaddyTryScriptedResolver.new
@verifier = Onetime::DomainValidation::TxtVerifier.new(resolver_factory: -> { @resolver })
@probe    = CaddyTryScriptedProbe.new
@strategy = Onetime::DomainValidation::CaddyOnDemandStrategy.new({}, txt_verifier: @verifier, tls_probe: @probe)

@suffix = "#{Familia.now.to_i}-#{SecureRandom.hex(3)}"
@owner  = Onetime::Customer.create!(email: "caddy_verify_#{@suffix}@test.com")
@org    = Onetime::Organization.create!('CaddyVerify Corp', @owner, "caddy_verify_#{@suffix}@corp.com")
@org.define_singleton_method(:billing_enabled?) { false }

@domain = Onetime::CustomDomain.create!("caddy-#{@suffix}.example.com", @org.objid)

def caddy_try_verify(domain)
  Onetime::Operations::VerifyDomain.new(domain: domain, strategy: @strategy, persist: true).call
end

def caddy_try_reload(domain)
  Onetime::CustomDomain.find_by_identifier(domain.identifier)
end

## A newly created domain has a challenge and starts unverified
[@domain.txt_validation_value.to_s.empty?, @domain.verified == true, @domain.ready?]
#=> [false, false, false]

## No TXT record (NXDOMAIN) - the check fails definitively
@domain.resolving = true
@domain.save
@resolver.rcode  = Resolv::DNS::RCode::NXDomain
@resolver.values = []
@missing         = caddy_try_verify(@domain)
[@missing.dns_validated, @missing.dns_indeterminate, @missing.dns_outcome, @missing.dns_message]
#=> [false, false, :failed, 'TXT record not found']

## No TXT record - the lookup went to the domain's validation record
@resolver.lookups.last
#=> @domain.validation_record

## No TXT record - the stored domain is not verified and not ready (ask endpoint refuses)
@stored = caddy_try_reload(@domain)
[@stored.verified == true, @stored.verification_state, @stored.ready?]
#=> [false, :resolving, false]

## NOERROR without TXT data - also not verified
@resolver.rcode = Resolv::DNS::RCode::NoError
caddy_try_verify(@domain)
caddy_try_reload(@domain).ready?
#=> false

## A different TXT value - not verified
@resolver.values = ['not-the-challenge']
@mismatch        = caddy_try_verify(@domain)
[@mismatch.dns_validated, caddy_try_reload(@domain).ready?]
#=> [false, false]

## An indeterminate lookup does not promote an unverified domain
@resolver.rcode  = Resolv::DNS::RCode::ServFail
@resolver.values = []
@unverified_indeterminate = caddy_try_verify(@domain)
[@unverified_indeterminate.dns_outcome, caddy_try_reload(@domain).ready?]
#=> [:indeterminate, false]

## The matching TXT record promotes
@resolver.rcode  = Resolv::DNS::RCode::NoError
@resolver.values = [@domain.txt_validation_value]
@promoted        = caddy_try_verify(@domain)
[@promoted.dns_validated, @promoted.previous_state, @promoted.current_state]
#=> [true, :resolving, :verified]

## The matching TXT record - stored domain is ready
@stored = caddy_try_reload(@domain)
[@stored.verified, @stored.ready?]
#=> [true, true]

## SERVFAIL leaves a verified domain verified
@resolver.rcode  = Resolv::DNS::RCode::ServFail
@resolver.values = []
@servfail        = caddy_try_verify(@domain)
[@servfail.dns_outcome, @servfail.demoted?, @servfail.current_state]
#=> [:indeterminate, false, :verified]

## SERVFAIL - stored flag is still true
caddy_try_reload(@domain).ready?
#=> true

## A lookup timeout leaves a verified domain verified
@resolver.error = Onetime::DomainValidation::TxtResolver::NoReplyError.new('no reply')
@timeout        = caddy_try_verify(@domain)
@resolver.error = nil
[@timeout.dns_outcome, @timeout.demoted?, caddy_try_reload(@domain).ready?]
#=> [:indeterminate, false, true]

## A definitive negative demotes a verified domain
@resolver.rcode  = Resolv::DNS::RCode::NXDomain
@resolver.values = []
@demoted         = caddy_try_verify(@domain)
[@demoted.dns_outcome, @demoted.demoted?, @demoted.previous_state, @demoted.current_state]
#=> [:failed, true, :verified, :resolving]

## A definitive negative - stored domain is no longer ready
@stored = caddy_try_reload(@domain)
[@stored.verified == true, @stored.ready?]
#=> [false, false]

## An operator override holds verified through a definitive negative
@domain.verified             = true
@domain.verified_by_override = true
@domain.save
@held = caddy_try_verify(@domain)
[@held.dns_outcome, @held.override_held, @held.demoted?, caddy_try_reload(@domain).ready?]
#=> [:override_held, true, false, true]

## A passing check clears the override marker; the next negative demotes
@resolver.rcode  = Resolv::DNS::RCode::NoError
@resolver.values = [@domain.txt_validation_value]
caddy_try_verify(@domain)
@marker_after_pass = caddy_try_reload(@domain).verified_by_override == true
@resolver.rcode    = Resolv::DNS::RCode::NXDomain
@resolver.values   = []
@after_clear       = caddy_try_verify(@domain)
[@marker_after_pass, @after_clear.demoted?, caddy_try_reload(@domain).ready?]
#=> [false, true, false]

## Verified with no confirmation on record (the flag as stored before this strategy checked TXT) - an indeterminate lookup does not hold it
@legacy           = Onetime::CustomDomain.create!("caddy-legacy-#{@suffix}.example.com", @org.objid)
@legacy.verified  = true
@legacy.resolving = true
@legacy.save
@resolver.rcode  = Resolv::DNS::RCode::ServFail
@resolver.values = []
@legacy_result   = caddy_try_verify(@legacy)
@stored          = caddy_try_reload(@legacy)
[@stored.verified_confirmed_at, @legacy_result.dns_outcome, @legacy_result.demoted?, @stored.verified == true, @stored.ready?]
#=> [nil, :failed, true, false, false]

## Verified with no confirmation on record - an operator override still holds it
@legacy.verified             = true
@legacy.verified_by_override = true
@legacy.save
@legacy_held = caddy_try_verify(@legacy)
[@legacy_held.dns_outcome, @legacy_held.demoted?, caddy_try_reload(@legacy).ready?]
#=> [:override_held, false, true]

## Verified under Passthrough, then checked here - the passthrough pass is no confirmation, so an indeterminate lookup does not hold it
@cutover = Onetime::CustomDomain.create!("caddy-cutover-#{@suffix}.example.com", @org.objid)
Onetime::Operations::VerifyDomain.new(
  domain: @cutover, strategy: Onetime::DomainValidation::PassthroughStrategy.new({}), persist: true
).call
@before_cutover  = caddy_try_reload(@cutover)
@before_state    = [@before_cutover.ready?, @before_cutover.verified_confirmed_at]
@resolver.rcode  = Resolv::DNS::RCode::ServFail
@resolver.values = []
@cutover_result  = caddy_try_verify(@before_cutover)
@stored          = caddy_try_reload(@cutover)
[*@before_state, @cutover_result.dns_outcome, @cutover_result.demoted?, @stored.ready?]
#=> [true, nil, :failed, true, false]

## Status: a definite probe answer is stored (resolving, and has_ssl inside vhost)
@probe.is_resolving = true
@probe.has_ssl      = true
@status_ok          = caddy_try_verify(@domain)
@stored             = caddy_try_reload(@domain)
[@status_ok.is_resolving, @status_ok.ssl_ready, @stored.resolving == true, @stored.parse_vhost.values_at('has_ssl', 'status', 'incoming_address')]
#=> [true, true, true, [true, 'ACTIVE_SSL', @domain.display_domain]]

## Status: the probe was asked about the display domain
@probe.probed.last
#=> @domain.display_domain

## Status: a probe that could not tell leaves resolving and vhost untouched
@vhost_before       = caddy_try_reload(@domain).vhost
@probe.is_resolving = nil
@probe.has_ssl      = nil
caddy_try_verify(@domain)
@stored = caddy_try_reload(@domain)
[@stored.resolving == true, @stored.vhost == @vhost_before, @stored.parse_vhost['has_ssl']]
#=> [true, true, true]

## Status: a probe that could not tell marks the check as failed for the UI
caddy_try_reload(@domain).vhost_fetch_failed_at.to_i.positive?
#=> true

## Status: resolving known, certificate unknown - resolving stored, stored has_ssl carried forward
@probe.is_resolving = true
@probe.has_ssl      = nil
caddy_try_verify(@domain)
@stored = caddy_try_reload(@domain)
[@stored.resolving == true, @stored.parse_vhost.values_at('has_ssl', 'status'), @stored.vhost_fetch_failed_at.to_s.empty?]
#=> [true, [true, 'ACTIVE_SSL'], true]

## Status: resolves without a valid certificate - has_ssl false is stored
@probe.is_resolving = true
@probe.has_ssl      = false
caddy_try_verify(@domain)
@stored = caddy_try_reload(@domain)
[@stored.resolving == true, @stored.parse_vhost.values_at('has_ssl', 'status')]
#=> [true, [false, 'PENDING_SSL']]

## Status: the name stopped resolving - resolving false is stored and the domain is not ready
@resolver.rcode     = Resolv::DNS::RCode::NoError
@resolver.values    = [@domain.txt_validation_value]
@probe.is_resolving = false
@probe.has_ssl      = false
caddy_try_verify(@domain)
@stored = caddy_try_reload(@domain)
[@stored.verified, @stored.resolving == true, @stored.ready?, @stored.parse_vhost.values_at('is_resolving', 'status')]
#=> [true, false, false, [false, 'DNS_INCORRECT']]

## Status: a probe that could not tell does not flip resolving back either
@probe.is_resolving = nil
@probe.has_ssl      = nil
caddy_try_verify(@domain)
@stored = caddy_try_reload(@domain)
[@stored.resolving == true, @stored.parse_vhost['status']]
#=> [false, 'DNS_INCORRECT']

## Status: the name resolves again but port 443 cannot be reached - the blob follows `resolving`, has_ssl stays as stored
@probe.is_resolving = true
@probe.has_ssl      = nil
caddy_try_verify(@domain)
@stored = caddy_try_reload(@domain)
[@stored.resolving == true, @stored.parse_vhost.values_at('is_resolving', 'status', 'has_ssl')]
#=> [true, [true, 'PENDING_SSL', false]]

## Status: an Approximated-era vhost blob is left for the cleanup chore; resolving is still stored
@domain.vhost       = { 'id' => 42, 'incoming_address' => @domain.display_domain, 'status' => 'ACTIVE_SSL' }.to_json
@domain.save
@probe.is_resolving = true
@probe.has_ssl      = false
caddy_try_verify(@domain)
@stored = caddy_try_reload(@domain)
[@stored.resolving == true, @stored.parse_vhost['id'], @stored.parse_vhost.key?('source')]
#=> [true, 42, false]

# Teardown
@domain.destroy! if @domain&.exists?
@legacy.destroy! if @legacy&.exists?
@cutover.destroy! if @cutover&.exists?
@org.destroy! if @org&.exists?
@owner.destroy! if @owner&.exists?

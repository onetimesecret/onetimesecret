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
#   3. An indeterminate lookup leaves a verified domain verified.
#   4. A definitive negative demotes a verified domain ...
#   5. ... unless an operator override holds it.
#   6. A newly created domain starts unverified.
#
# `resolving` is set true on the fixtures so `verified` is the only thing
# between the domain and ready?.

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

@resolver = CaddyTryScriptedResolver.new
@verifier = Onetime::DomainValidation::TxtVerifier.new(resolver_factory: -> { @resolver })
@strategy = Onetime::DomainValidation::CaddyOnDemandStrategy.new({}, txt_verifier: @verifier)

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

# Teardown
@domain.destroy! if @domain&.exists?
@org.destroy! if @org&.exists?
@owner.destroy! if @owner&.exists?

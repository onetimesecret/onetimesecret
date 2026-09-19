# try/unit/operations/verify_domain_approximated_native_try.rb
#
# frozen_string_literal: true

# Operations::VerifyDomain driven by the real ApproximatedStrategy when the
# upstream checker is indeterminate ('actual_values' => false) and our own TXT
# lookup has to decide. Both directions matter:
#
#   - native lookup indeterminate (SERVFAIL, timeout): a verified domain stays
#     verified. Reading a failed lookup as a mismatch is what used to demote
#     correctly-configured domains.
#   - native lookup definitive negative (NXDOMAIN): a verified domain is
#     demoted, unless an operator override holds it.
#
# The Approximated client and the resolver are scripted; nothing leaves the
# process.

require_relative '../../support/test_helpers'
require 'securerandom'

OT.boot! :test

require 'onetime/operations/verify_domain'
require 'onetime/domain_validation/strategy'

# Approximated client whose DNS checker never produces an answer.
module ApproxTryIndeterminateClient
  Response = Struct.new(:code, :parsed_response)

  def self.check_records_match_exactly(_api_key, records)
    Response.new(200, { 'records' => records.map do |r|
      { 'type' => 'TXT', 'address' => r[:address], 'match_against' => r[:match_against],
        'match' => false, 'actual_values' => false }
    end })
  end

  def self.get_vhost_by_incoming_address(_api_key, _domain)
    data = { 'status' => 'ACTIVE_SSL', 'has_ssl' => true, 'is_resolving' => true }
    Response.new(200, { 'data' => data })
  end
end

# Approximated client whose DNS checker finds the record.
module ApproxTryMatchingClient
  Response = ApproxTryIndeterminateClient::Response

  def self.check_records_match_exactly(_api_key, records)
    Response.new(200, { 'records' => records.map do |r|
      { 'type' => 'TXT', 'address' => r[:address], 'match_against' => r[:match_against],
        'match' => true, 'actual_values' => [r[:match_against]] }
    end })
  end

  def self.get_vhost_by_incoming_address(api_key, domain)
    ApproxTryIndeterminateClient.get_vhost_by_incoming_address(api_key, domain)
  end
end

# Scripted stand-in for DomainValidation::TxtResolver.
class ApproxTryScriptedResolver
  attr_accessor :rcode, :values, :error

  def lookup(_hostname)
    raise error if error

    Onetime::DomainValidation::TxtResolver::Answer.new(rcode: rcode, values: values || [])
  end

  def close; end
end

@previous_api_key = Onetime::DomainValidation::Features.api_key
Onetime::DomainValidation::Features.api_key = 'approx-try-key'

@resolver = ApproxTryScriptedResolver.new
@verifier = Onetime::DomainValidation::TxtVerifier.new(resolver_factory: -> { @resolver })
@strategy = Onetime::DomainValidation::ApproximatedStrategy.new(
  {}, client: ApproxTryIndeterminateClient, txt_verifier: @verifier
)

@suffix = "#{Familia.now.to_i}-#{SecureRandom.hex(3)}"
@owner  = Onetime::Customer.create!(email: "approx_native_#{@suffix}@test.com")
@org    = Onetime::Organization.create!('ApproxNative Corp', @owner, "approx_native_#{@suffix}@corp.com")
@org.define_singleton_method(:billing_enabled?) { false }

@domain = Onetime::CustomDomain.create!("approx-native-#{@suffix}.example.com", @org.objid)
@domain.verified  = true
@domain.resolving = true
@domain.save

def approx_try_verify(domain)
  Onetime::Operations::VerifyDomain.new(domain: domain, strategy: @strategy, persist: true).call
end

def approx_try_reload(domain)
  Onetime::CustomDomain.find_by_identifier(domain.identifier)
end

## Native SERVFAIL - a verified domain is not demoted
@resolver.rcode = Resolv::DNS::RCode::ServFail
@servfail       = approx_try_verify(@domain)
[@servfail.dns_outcome, @servfail.demoted?, approx_try_reload(@domain).ready?]
#=> [:indeterminate, false, true]

## Native timeout - a verified domain is not demoted
@resolver.error = Onetime::DomainValidation::TxtResolver::NoReplyError.new('no reply')
@timeout        = approx_try_verify(@domain)
@resolver.error = nil
[@timeout.dns_outcome, @timeout.demoted?, approx_try_reload(@domain).ready?]
#=> [:indeterminate, false, true]

## Native NXDOMAIN - a verified domain is demoted
@resolver.rcode = Resolv::DNS::RCode::NXDomain
@nxdomain       = approx_try_verify(@domain)
[@nxdomain.dns_outcome, @nxdomain.demoted?, approx_try_reload(@domain).ready?]
#=> [:failed, true, false]

## Native NXDOMAIN - the message names both checkers
@nxdomain.dns_message
#=> 'TXT record not found (native lookup; upstream checker indeterminate)'

## Native NXDOMAIN - an operator override holds verified
@domain.verified             = true
@domain.verified_by_override = true
@domain.save
@held = approx_try_verify(@domain)
[@held.dns_outcome, @held.demoted?, approx_try_reload(@domain).ready?]
#=> [:override_held, false, true]

## Native match - promotes and clears the override marker
@resolver.rcode  = Resolv::DNS::RCode::NoError
@resolver.values = [@domain.txt_validation_value]
@matched         = approx_try_verify(@domain)
@stored          = approx_try_reload(@domain)
[@matched.dns_outcome, @stored.verified, @stored.verified_by_override == true]
#=> [:validated, true, false]

## Native match - the confirmation is recorded (the strategy proves ownership)
(Familia.now.to_i - @stored.verified_confirmed_at).between?(0, 5)
#=> true

## Upstream match - a pass answered by Approximated records the confirmation too
# What a cutover to caddy_on_demand relies on: one verify pass on this version
# while still on approximated stamps verified_confirmed_at for every proven domain.
@domain.verified_confirmed_at      = nil
@domain.verified_unconfirmed_since = Familia.now.to_i - 3600
@domain.save
@upstream_strategy = Onetime::DomainValidation::ApproximatedStrategy.new(
  {}, client: ApproxTryMatchingClient, txt_verifier: @verifier
)
@upstream = Onetime::Operations::VerifyDomain.new(domain: @domain, strategy: @upstream_strategy, persist: true).call
@stored   = approx_try_reload(@domain)
[@upstream.dns_outcome, @upstream_strategy.proves_ownership?, (Familia.now.to_i - @stored.verified_confirmed_at.to_i).between?(0, 5), @stored.verified_unconfirmed_since]
#=> [:validated, true, true, nil]

## Upstream match - a dry run records nothing
@domain.verified_confirmed_at = nil
@domain.save
Onetime::Operations::VerifyDomain.new(domain: @domain, strategy: @upstream_strategy, persist: false).call
approx_try_reload(@domain).verified_confirmed_at
#=> nil

# Teardown
Onetime::DomainValidation::Features.api_key = @previous_api_key
@domain.destroy! if @domain&.exists?
@org.destroy! if @org&.exists?
@owner.destroy! if @owner&.exists?

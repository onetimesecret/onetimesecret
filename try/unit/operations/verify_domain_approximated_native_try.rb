# try/unit/operations/verify_domain_approximated_native_try.rb
#
# frozen_string_literal: true

# Operations::VerifyDomain driven by the real ApproximatedStrategy when the
# upstream checker is indeterminate ('actual_values' => false) and our own TXT
# lookup has to decide. Three distinctions matter:
#
#   - native lookup indeterminate (SERVFAIL, timeout): a verified domain stays
#     verified. Reading a failed lookup as a mismatch is what used to demote
#     correctly-configured domains.
#   - one native negative (NXDOMAIN) cannot revoke an existing verification
#     while the upstream checker is indeterminate, but a never-confirmed domain
#     still fails closed.
#   - a definitive upstream negative still demotes, unless an operator override
#     holds it.
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

  class << self
    attr_accessor :actual_values
  end
  self.actual_values = false

  def self.check_records_match_exactly(_api_key, records)
    Response.new(
      200,
      {
        'records' => records.map do |r|
              {
                'type' => 'TXT',
                'address' => r[:address],
                'match_against' => r[:match_against],
                'match' => false,
                'actual_values' => actual_values,
              }
        end,
      },
    )
  end

  def self.get_vhost_by_incoming_address(_api_key, _domain)
    data = { 'status' => 'ACTIVE_SSL', 'has_ssl' => true, 'is_resolving' => true }
    Response.new(200, { 'data' => data })
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

@previous_api_key                           = Onetime::DomainValidation::Features.api_key
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

@domain           = Onetime::CustomDomain.create!("approx-native-#{@suffix}.example.com", @org.objid)
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

## Native NXDOMAIN - one local negative does not demote a verified domain while upstream is indeterminate
@resolver.rcode = Resolv::DNS::RCode::NXDomain
@nxdomain       = approx_try_verify(@domain)
[@nxdomain.dns_outcome, @nxdomain.demoted?, approx_try_reload(@domain).ready?]
#=> [:indeterminate, false, true]

## Native NXDOMAIN - the message explains why verification is held
@nxdomain.dns_message
#=> 'TXT record not found (native lookup negative; upstream checker indeterminate; previously verified domain left unchanged)'

## Native NXDOMAIN - a never-confirmed domain still fails closed
@never_confirmed           = Onetime::CustomDomain.create!("approx-new-#{@suffix}.example.com", @org.objid)
@never_confirmed.resolving = true
@never_confirmed.save
@first_negative            = approx_try_verify(@never_confirmed)
[@first_negative.dns_outcome, @first_negative.demoted?, approx_try_reload(@never_confirmed).ready?]
#=> [:failed, false, false]

## Definitive upstream negative - a verified domain is still demoted
ApproxTryIndeterminateClient.actual_values = []
@upstream_negative                         = approx_try_verify(@domain)
[@upstream_negative.dns_outcome, @upstream_negative.demoted?, approx_try_reload(@domain).ready?]
#=> [:failed, true, false]

## Definitive upstream negative - an operator override holds verified
@domain.verified             = true
@domain.verified_by_override = true
@domain.save
@held                        = approx_try_verify(@domain)
[@held.dns_outcome, @held.demoted?, approx_try_reload(@domain).ready?]
#=> [:override_held, false, true]

## Native match - promotes and clears the override marker
ApproxTryIndeterminateClient.actual_values = false
@resolver.rcode                            = Resolv::DNS::RCode::NoError
@resolver.values                           = [@domain.txt_validation_value]
@matched                                   = approx_try_verify(@domain)
@stored                                    = approx_try_reload(@domain)
[@matched.dns_outcome, @stored.verified, @stored.verified_by_override == true]
#=> [:validated, true, false]

# Teardown
Onetime::DomainValidation::Features.api_key = @previous_api_key
@never_confirmed.destroy! if @never_confirmed&.exists?
@domain.destroy! if @domain&.exists?
@org.destroy! if @org&.exists?
@owner.destroy! if @owner&.exists?

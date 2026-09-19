# try/unit/models/custom_domain_idn_lookup_try.rb
#
# frozen_string_literal: true

# CustomDomain display-domain lookups for internationalised hostnames.
#
# CustomDomain stores display_domain as the customer typed it, so an IDN may be
# stored in Unicode ("bücher-….com") or in A-label form ("xn--….com"). Everything that arrives over the wire uses A-labels:
# the SNI name Caddy passes to the internal ACME ask endpoint, and the Host
# header. The lookup therefore has to find the record from either form,
# whichever form is stored, without rewriting stored data.
#
# Covers load_by_display_domain (ACME ask, CLI, signup), from_display_domain
# (request host resolution), resolve_domain_id, and the ask endpoint's
# domain_allowed? for a verified + resolving IDN domain. Names that cannot be
# converted are a miss (the ask endpoint answers 403), never an exception.

require_relative '../../support/test_helpers'
require 'securerandom'
require 'simpleidn'

OT.boot! :test

require_relative '../../../apps/internal/acme/application'

@suffix = "#{Familia.now.to_i}#{SecureRandom.hex(3)}"
@owner  = Onetime::Customer.create!(email: "idn_lookup_#{@suffix}@test.com")
@org    = Onetime::Organization.create!('IdnLookup Corp', @owner, "idn_lookup_#{@suffix}@corp.com")
@org.define_singleton_method(:billing_enabled?) { false }

# The Unicode label has to be in the registrable domain: a Unicode subdomain
# label is refused at creation (it would end up in the TXT record host, which
# validate_txt_record! keeps ASCII).
@unicode_name = "bücher-#{@suffix}.com"
@ascii_name   = SimpleIDN.to_ascii(@unicode_name)

# Stored as typed, in Unicode; verified and resolving, so ready?.
@unicode_domain           = Onetime::CustomDomain.create!(@unicode_name, @org.objid)
@unicode_domain.verified  = true
@unicode_domain.resolving = true
@unicode_domain.save

# A second domain typed in A-label form.
@typed_ascii_name   = SimpleIDN.to_ascii("café-#{@suffix}.com")
@typed_unicode_name = "café-#{@suffix}.com"
@ascii_domain       = Onetime::CustomDomain.create!(@typed_ascii_name, @org.objid)

def idn_try_acme_allowed?(name)
  Internal::ACME::Application.domain_allowed?(name)
end

## The fixture really is stored in Unicode and the A-label form differs
[@unicode_domain.display_domain == @unicode_name, @ascii_name.start_with?('xn--'), @unicode_domain.ready?]
#=> [true, true, true]

## Stored in Unicode - found by its U-label
Onetime::CustomDomain.load_by_display_domain(@unicode_name)&.identifier
#=> @unicode_domain.identifier

## Stored in Unicode - found by its A-label (what Caddy sends)
Onetime::CustomDomain.load_by_display_domain(@ascii_name)&.identifier
#=> @unicode_domain.identifier

## Stored in Unicode - the A-label is matched case-insensitively
Onetime::CustomDomain.load_by_display_domain(@ascii_name.upcase)&.identifier
#=> @unicode_domain.identifier

## Stored in Unicode - the ACME ask check allows the A-label and the U-label
[idn_try_acme_allowed?(@ascii_name), idn_try_acme_allowed?(@unicode_name)]
#=> [true, true]

## Stored in Unicode - request host resolution finds it by the A-label Host header
Onetime::CustomDomain.from_display_domain(@ascii_name)&.identifier
#=> @unicode_domain.identifier

## Stored in Unicode - resolve_domain_id finds it by either form
[Onetime::CustomDomain.resolve_domain_id(@ascii_name), Onetime::CustomDomain.resolve_domain_id(@unicode_name)]
#=> [@unicode_domain.identifier, @unicode_domain.identifier]

## Stored in A-label form - found by either form
[@typed_ascii_name, @typed_unicode_name].map { |name| Onetime::CustomDomain.load_by_display_domain(name)&.identifier }
#=> [@ascii_domain.identifier, @ascii_domain.identifier]

## Stored data is not rewritten by a lookup
[Onetime::CustomDomain.find_by_identifier(@unicode_domain.identifier).display_domain, Onetime::CustomDomain.display_domain_index.get(@unicode_name)]
#=> [@unicode_name, @unicode_domain.identifier]

## The other form of a registered name cannot be registered a second time
begin
  @duplicate = Onetime::CustomDomain.create!(@ascii_name, @org.objid)
rescue Onetime::Problem => ex
  ex.message
end
#=> 'Domain already registered in your organization'

## An unverified IDN domain is found but not allowed by the ask check
idn_try_acme_allowed?(@typed_unicode_name)
#=> false

## An unknown IDN name is a miss in both forms
[Onetime::CustomDomain.load_by_display_domain("xn--nnx-#{@suffix}.example.com"), idn_try_acme_allowed?("ünknown-#{@suffix}.example.com")]
#=> [nil, false]

## An A-label that is not the encoding of the stored name is a miss: the decomposed spelling decodes and normalises to the same characters, but it is a different DNS name
@decomposed_ascii = "xn--#{SimpleIDN::Punycode.encode("bu\u0308cher-#{@suffix}")}.com"
[@decomposed_ascii == @ascii_name, SimpleIDN.to_unicode(@decomposed_ascii).unicode_normalize(:nfc) == @unicode_name, Onetime::CustomDomain.load_by_display_domain(@decomposed_ascii), Onetime::CustomDomain.resolve_domain_id(@decomposed_ascii), idn_try_acme_allowed?(@decomposed_ascii)]
#=> [false, true, nil, nil, false]

## Such an A-label has no Unicode key, while the canonical A-label still has one
[Onetime::CustomDomain.display_domain_lookup_keys(@decomposed_ascii), Onetime::CustomDomain.display_domain_lookup_keys(@ascii_name)]
#=> [[@decomposed_ascii], [@ascii_name, @unicode_name]]

## An overlong label is a miss, not an exception
@overlong = "#{'ü' * 70}.example.com"
[Onetime::CustomDomain.load_by_display_domain(@overlong), Onetime::CustomDomain.from_display_domain(@overlong), idn_try_acme_allowed?(@overlong)]
#=> [nil, nil, false]

## Malformed punycode is a miss, not an exception
@malformed = 'xn--a-ecp.xn--@@.example.com'
[Onetime::CustomDomain.load_by_display_domain(@malformed), Onetime::CustomDomain.from_display_domain(@malformed), idn_try_acme_allowed?(@malformed)]
#=> [nil, nil, false]

## Invalid bytes are a miss, not an exception
@invalid_bytes = "b\xFCcher.example.com".dup.force_encoding('UTF-8')
[Onetime::CustomDomain.load_by_display_domain(@invalid_bytes), idn_try_acme_allowed?(@invalid_bytes)]
#=> [nil, false]

## A plain ASCII name has one index key, so the common lookup costs one read
Onetime::CustomDomain.display_domain_lookup_keys("Plain-#{@suffix}.Example.com")
#=> ["plain-#{@suffix}.example.com"]

## An IDN has its typed, A-label and Unicode forms as keys
Onetime::CustomDomain.display_domain_lookup_keys(@ascii_name.upcase)
#=> [@ascii_name, @unicode_name]

## A blank name has no keys
[Onetime::CustomDomain.display_domain_lookup_keys(nil), Onetime::CustomDomain.from_display_domain('')]
#=> [[], nil]

# Teardown
[@unicode_domain, @ascii_domain, @duplicate].each { |domain| domain.destroy! if domain&.exists? }
@org.destroy! if @org&.exists?
@owner.destroy! if @owner&.exists?

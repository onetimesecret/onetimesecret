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

# A decomposed Unicode registration whose exact index key is not NFC.
@nfd_name   = "bu\u0308cher-nfd-#{@suffix}.com"
@nfd_ascii  = Onetime::CustomDomain.canonical_display_domain(@nfd_name)
@nfd_domain = Onetime::CustomDomain.create!(@nfd_name, @org.objid)
@nfd_domain.verified  = true
@nfd_domain.resolving = true
@nfd_domain.save

# A second domain typed in A-label form.
@typed_ascii_name   = SimpleIDN.to_ascii("café-#{@suffix}.com")
@typed_unicode_name = "café-#{@suffix}.com"
@ascii_domain       = Onetime::CustomDomain.create!(@typed_ascii_name, @org.objid)

# A plain ASCII domain, the target of a punycode label that decodes to ASCII.
@plain_name   = "plain-#{@suffix}.com"
@plain_domain = Onetime::CustomDomain.create!(@plain_name, @org.objid)

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

## Decomposed Unicode is stored unchanged but found by A-label and NFC spellings
[@nfd_domain.display_domain == @nfd_name,
 Onetime::CustomDomain.load_by_display_domain(@nfd_ascii)&.identifier,
 Onetime::CustomDomain.load_by_display_domain(@nfd_name.unicode_normalize(:nfc))&.identifier]
#=> [true, @nfd_domain.identifier, @nfd_domain.identifier]

## Decomposed Unicode resolves through the Host header and domain ID lookup
[Onetime::CustomDomain.from_display_domain(@nfd_ascii)&.identifier,
 Onetime::CustomDomain.resolve_domain_id(@nfd_ascii)]
#=> [@nfd_domain.identifier, @nfd_domain.identifier]

## The ACME ask check permits the A-label of a verified decomposed registration
idn_try_acme_allowed?(@nfd_ascii)
#=> true

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

## A crafted A-label that only decodes to a registered name is not an alias for it.
## Punycode of the decomposed spelling (u + combining diaeresis) NFC-folds to
## the stored Unicode name, but it is a different DNS name.
@decomposed_ascii = "xn--#{SimpleIDN::Punycode.encode("bu\u0308cher-#{@suffix}")}.com"
[@decomposed_ascii != @ascii_name,
 Onetime::CustomDomain.display_domain_lookup_keys(@decomposed_ascii),
 Onetime::CustomDomain.load_by_display_domain(@decomposed_ascii),
 idn_try_acme_allowed?(@decomposed_ascii)]
#=> [true, [@decomposed_ascii], nil, false]

## An A-label whose punycode decodes to a registered A-label is not an alias for it either
@ascii_decoding = "xn--#{@typed_ascii_name.split('.').first}-.com"
[Onetime::CustomDomain.display_domain_lookup_keys(@ascii_decoding),
 Onetime::CustomDomain.load_by_display_domain(@ascii_decoding),
 idn_try_acme_allowed?(@ascii_decoding)]
#=> [[@ascii_decoding], nil, false]

## Every crafted spelling of the registered Unicode name misses in every lookup path:
## the decomposed A-label, an A-label encoding an upper-case letter, and the
## punycode of the real A-label. Each decodes towards the registered name but
## does not encode back to itself.
@crafted_spellings = [
  @decomposed_ascii,
  "xn--#{SimpleIDN::Punycode.encode("b#{0xDC.chr(Encoding::UTF_8)}cher-#{@suffix}")}.com",
  "xn--#{@ascii_name.split('.').first}-.com",
]
@crafted_spellings.map do |name|
  [Onetime::CustomDomain.load_by_display_domain(name),
   Onetime::CustomDomain.from_display_domain(name),
   Onetime::CustomDomain.resolve_domain_id(name),
   idn_try_acme_allowed?(name)]
end.uniq
#=> [[nil, nil, nil, false]]

## The crafted spellings are distinct names from each other and from the real A-label
(@crafted_spellings + [@ascii_name]).uniq.size
#=> 4

## A punycode label that decodes to a plain ASCII name does not find that record
@plain_as_punycode = "xn--plain-#{@suffix}-.com"
[Onetime::CustomDomain.display_domain_lookup_keys(@plain_as_punycode),
 Onetime::CustomDomain.load_by_display_domain(@plain_as_punycode),
 Onetime::CustomDomain.from_display_domain(@plain_as_punycode),
 idn_try_acme_allowed?(@plain_as_punycode)]
#=> [[@plain_as_punycode], nil, nil, false]

## The plain record itself is still found by its own name
Onetime::CustomDomain.load_by_display_domain(@plain_name.upcase)&.identifier
#=> @plain_domain.identifier

## A crafted A-label is its own DNS name: registering it makes a separate record
## with its own canonical claim, and the existing record's verification does not
## carry over to it. (Before the round-trip guard the preflight aliased it onto the
## Unicode record and refused it as a duplicate.)
@decomposed_domain = Onetime::CustomDomain.create!(@decomposed_ascii, @org.objid)
[@decomposed_domain.identifier != @unicode_domain.identifier,
 Onetime::CustomDomain.canonical_display_domain_index.get(@decomposed_ascii),
 Onetime::CustomDomain.load_by_display_domain(@ascii_name)&.identifier,
 @decomposed_domain.ready?,
 idn_try_acme_allowed?(@decomposed_ascii)]
#=> [true, @decomposed_domain.identifier, @unicode_domain.identifier, false, false]

## Verifying the crafted record authorizes only its own name: each name still
## resolves to its own record, in both directions
@decomposed_domain.verified  = true
@decomposed_domain.resolving = true
@decomposed_domain.save
[Onetime::CustomDomain.load_by_display_domain(@decomposed_ascii)&.identifier == @decomposed_domain.identifier,
 Onetime::CustomDomain.load_by_display_domain(@ascii_name)&.identifier == @unicode_domain.identifier,
 Onetime::CustomDomain.load_by_display_domain(@unicode_name)&.identifier == @unicode_domain.identifier,
 idn_try_acme_allowed?(@decomposed_ascii)]
#=> [true, true, true, true]

## The crafted record cannot be renamed onto the real name in either spelling
[@unicode_name, @ascii_name].map do |name|
  @decomposed_domain.update_display_domain(name)
  :renamed
rescue Onetime::Problem => ex
  ex.message
end
#=> ['Domain already registered', 'Domain already registered']

## Nor can the real record be renamed onto the crafted spelling
begin
  @unicode_domain.update_display_domain(@decomposed_ascii)
  :renamed
rescue Onetime::Problem => ex
  ex.message
end
#=> 'Domain already registered'

## After the refused renames both records keep their names and canonical claims
[Onetime::CustomDomain.find_by_identifier(@unicode_domain.identifier).display_domain,
 Onetime::CustomDomain.find_by_identifier(@decomposed_domain.identifier).display_domain,
 Onetime::CustomDomain.canonical_display_domain_index.get(@ascii_name),
 Onetime::CustomDomain.canonical_display_domain_index.get(@decomposed_ascii)]
#=> [@unicode_name, @decomposed_ascii, @unicode_domain.identifier, @decomposed_domain.identifier]

## A blank name has no keys
[Onetime::CustomDomain.display_domain_lookup_keys(nil), Onetime::CustomDomain.from_display_domain('')]
#=> [[], nil]

# Teardown
[@unicode_domain, @nfd_domain, @ascii_domain, @plain_domain, @duplicate, @decomposed_domain].each { |domain| domain.destroy! if domain&.exists? }
@org.destroy! if @org&.exists?
@owner.destroy! if @owner&.exists?

# try/unit/utils/diagnostics_ref_try.rb
#
# frozen_string_literal: true

# Tests for Onetime::Utils::DiagnosticsRef - opaque actor and organization
# references for the third-party diagnostics backend (Sentry).
#
# Companion to try/unit/utils/email_hash_try.rb, and deliberately in the same
# lane: EmailHash is FEDERATION reference (a queryable Redis index, and a field
# in Stripe customer metadata), DiagnosticsRef is DIAGNOSTICS reference. The two
# must never produce the same value, or Sentry would hold a live join key into
# billing and the datastore.
#
# Security model (see docs/specs/diagnostics/actor-ref-preimage-debate-decision.md):
# - The correlation subject is the customer RECORD, not the human: the actor
#   pre-image is the server-minted EXTID, never the email. An email pre-image
#   would split one account on email change, conflate two people on address
#   reassignment, re-link a deleted-and-recreated subject, and be re-identifiable
#   offline against public address lists under key compromise
# - One-way, keyed by ACCOUNT_ID_SECRET alone. Rotating that secret rotates every
#   ref; under Sentry's retention window the discontinuity ages out
# - Domain separated: versioned purpose prefixes ("onetime:sentry:v2:actor",
#   "onetime:sentry:v2:organization"). The prefix is the ONLY separation between
#   the two namespaces, so the same string must digest differently in each -
#   pinned by executing both entry points, not by reading the constants
# - No residency element and no scope label: extids and objids are minted per
#   install, so separately provisioned regional records do not correlate by
#   default. There is nothing to mix in and nothing to label
# - NOT normalized: no case folding, no unicode normalization. Folding could
#   collapse two distinct records onto one ref
# - Fail-soft: nil, never an exception, for an unconfigured secret or an
#   unusable pre-image (this runs on every authenticated render, so a raise here
#   is a 500 page plus a self-inflicted Sentry event)
#
# Run: pnpm run test:tryouts:agent try/unit/utils/diagnostics_ref_try.rb

require_relative '../../support/test_helpers'

# Only filled in when the lane did not export one (tests/lanes/base.env does).
ENV['ACCOUNT_ID_SECRET'] ||= 'test-account-id-secret-for-diagnostics-ref'

# DiagnosticsRef does NOT use this - it is here solely so EmailHash.compute can
# answer in the domain-separation cases below. That the two modules key off
# different secrets entirely is now part of the separation.
ENV['FEDERATION_SECRET'] ||= 'test-federation-secret-for-email-hash-only'

require 'onetime/utils/diagnostics_ref'
require 'onetime/utils/email_hash'

TR = Onetime::Utils::DiagnosticsRef

# Set several env vars for the duration of a block and restore all of them,
# so case ordering can never matter. Assigning nil deletes.
def with_env_vars(pairs)
  original = pairs.keys.to_h { |key| [key, ENV.fetch(key, nil)] }
  pairs.each { |key, value| ENV[key] = value }
  yield
ensure
  original.each { |key, value| ENV[key] = value }
end

# Shaped like a real Customer extid: Familia's external_identifier feature under
# `format: 'ur%<id>s'` emits `ur` plus 25 base36 characters.
@extid = 'ur00fedcba9876543210zyxwvu'
@other_extid = 'ur00abcdef0123456789vwxyzu'
@deployment_key = 'account-id-secret-for-diagnostics-ref-try'

## actor_ref returns a String
TR.actor_ref(@extid).is_a?(String)
#=> true

## actor_ref is REF_LENGTH hex characters
TR.actor_ref(@extid).length
#=> 16

## actor_ref contains only lowercase hex
TR.actor_ref(@extid) =~ /\A[0-9a-f]{16}\z/
#=> 0

## actor_ref is deterministic
TR.actor_ref(@extid) == TR.actor_ref(@extid)
#=> true

## actor_ref distinguishes different customers
TR.actor_ref(@extid) == TR.actor_ref(@other_extid)
#=> false

## actor_ref discloses nothing of the extid it derives from
[TR.actor_ref(@extid) == @extid, @extid.include?(TR.actor_ref(@extid))]
#=> [false, false]

## NO NORMALIZATION: an extid is a server-minted token, not something a human
## types, so case is NOT folded. Folding could collapse two distinct records
## onto one ref, which is the opposite of what the ref exists to provide.
TR.actor_ref(@extid) == TR.actor_ref(@extid.upcase)
#=> false

## Surrounding whitespace is trimmed, so a padded value cannot split one
## customer into two refs
TR.actor_ref("  #{@extid}  ") == TR.actor_ref(@extid)
#=> true

## Blank, nil and whitespace-only pre-images return nil, never a digest of ''
[TR.actor_ref(''), TR.actor_ref(nil), TR.actor_ref('   ')]
#=> [nil, nil, nil]

## ENCODING: a pre-image that is not valid UTF-8 returns nil instead of raising
## ArgumentError out of String#strip, while ASCII bytes carrying the wrong
## encoding tag are recovered and still correlate with themselves
[TR.actor_ref("a\xFFur"),
 TR.actor_ref(@extid.dup.force_encoding(Encoding::ASCII_8BIT)) == TR.actor_ref(@extid)]
#=> [nil, true]

## Domain separation: an actor ref is NOT the federation email hash of the same
## string - Sentry never holds a live join key into billing or the index
TR.actor_ref(@extid) == Onetime::Utils::EmailHash.compute(@extid)
#=> false

## Domain separation: nor a prefix of it
Onetime::Utils::EmailHash.compute(@extid)[0, TR::REF_LENGTH] == TR.actor_ref(@extid)
#=> false

## Purpose prefix is versioned, so diagnostics reference can be re-keyed alone.
## v2 is the extid pre-image over a two-element message; v1 was an email
## pre-image with a residency element.
[TR::ACTOR_INFO.include?('v2'), TR::ACTOR_INFO.include?('actor')]
#=> [true, true]

## Diagnostics refs are narrower than federation email hashes
TR::REF_LENGTH < Onetime::Utils::EmailHash::HASH_LENGTH
#=> true

## The ref is the derivation an operator can reproduce from the extid and the
## key, and nothing else - two elements, no residency, recomputed independently
with_env_vars('ACCOUNT_ID_SECRET' => @deployment_key) { TR.actor_ref(@extid) } ==
  OpenSSL::HMAC.hexdigest(
    'SHA256', @deployment_key, [TR::ACTOR_INFO, @extid].join(TR::SEPARATOR)
  )[0, TR::REF_LENGTH]
#=> true

## KEYING: ACCOUNT_ID_SECRET is the only key. Two installs derive DIFFERENT refs
## for the same extid, which is what makes refs per-install by construction.
install_a = with_env_vars('ACCOUNT_ID_SECRET' => 'per-install-secret-a') { TR.actor_ref(@extid) }
install_b = with_env_vars('ACCOUNT_ID_SECRET' => 'per-install-secret-b') { TR.actor_ref(@extid) }
[install_a.nil?, install_a == install_b]
#=> [false, false]

## KEYING: FEDERATION_SECRET is NOT consulted. Setting or clearing it cannot
## change a ref - diagnostics dropped it entirely.
with_env_vars('ACCOUNT_ID_SECRET' => @deployment_key, 'FEDERATION_SECRET' => 'shared-across-regions') do
  TR.actor_ref(@extid)
end == with_env_vars('ACCOUNT_ID_SECRET' => @deployment_key, 'FEDERATION_SECRET' => nil) do
  TR.actor_ref(@extid)
end
#=> true

## KEYING: rotating ACCOUNT_ID_SECRET re-keys refs. Accepted and documented:
## under Sentry's retention window the discontinuity ages out.
with_env_vars('ACCOUNT_ID_SECRET' => 'before-rotation') { TR.actor_ref(@extid) } ==
  with_env_vars('ACCOUNT_ID_SECRET' => 'after-rotation') { TR.actor_ref(@extid) }
#=> false

## keying answers the raw secret, not a struct
with_env_vars('ACCOUNT_ID_SECRET' => @deployment_key) { TR.keying }
#=> 'account-id-secret-for-diagnostics-ref-try'

## Unconfigured deployment: every entry point returns nil instead of raising,
## even where EmailHash would raise Onetime::Problem for the same input
with_env_vars('ACCOUNT_ID_SECRET' => nil, 'FEDERATION_SECRET' => nil) do
  raised = begin
    Onetime::Utils::EmailHash.compute('user@example.com')
    false
  rescue Onetime::Problem
    true
  end
  [raised, TR.actor_ref(@extid), TR.actor(@extid), TR.available?]
end
#=> [true, nil, nil, false]

## available? is true once ACCOUNT_ID_SECRET is set
with_env_vars('ACCOUNT_ID_SECRET' => @deployment_key) { TR.available? }
#=> true

## The bundle carries EXACTLY one key. The frontend parses it as a Zod
## strictObject, so a second key makes the client discard the whole block.
TR.actor(@extid).keys
#=> ['actor_ref']

## The bundle's ref is the same value actor_ref derives
TR.actor(@extid)['actor_ref'] == TR.actor_ref(@extid)
#=> true

## The bundle is nil for a blank pre-image
TR.actor('')
#=> nil

## The emitted bundle discloses neither the extid nor the keying secret
with_env_vars('ACCOUNT_ID_SECRET' => @deployment_key) do
  serialized = TR.actor(@extid).to_json
  [serialized.include?(@extid), serialized.include?(@deployment_key)]
end
#=> [false, false]

## An email handed to the bundle entry point never escapes as an exception
## either - it digests like any other string, which is exactly why
## ErrorHandler.diagnostics_actor refuses to hand one over (see
## spec/unit/onetime/error_handler_diagnostics_actor_spec.rb)
TR.actor('someone@example.com').keys
#=> ['actor_ref']

# ---------------------------------------------------------------------------
# ORGANIZATION REFS
# ---------------------------------------------------------------------------
# Same module, same keying — a SECOND namespace, separated only by the purpose
# prefix. It exists because Sentry parameterizes the colonel route to
# /api/colonel/organizations/:org_id and never carries the real id, so an
# operator cannot otherwise tell "one org is broken" from "every org is broken".
# The cases below pin the three things that makes safe: separation from the
# actor namespace, identical fail-closed behaviour, and no normalization that
# could collapse two organizations onto one ref.

@org_objid = '01JORGABCDEFGHJKMNPQRSTVWX'
@other_org_objid = '01JOTHERABCDEFGHJKMNPQRSTV'

# A pre-image both entry points treat IDENTICALLY, so an actor/org comparison
# over it isolates the purpose prefix as the only difference.
@shared_pre_image = 'domain-separation-probe'

## organization_ref is REF_LENGTH lowercase hex
TR.organization_ref(@org_objid) =~ /\A[0-9a-f]{16}\z/
#=> 0

## organization_ref is deterministic
TR.organization_ref(@org_objid) == TR.organization_ref(@org_objid)
#=> true

## organization_ref distinguishes different organizations
TR.organization_ref(@org_objid) == TR.organization_ref(@other_org_objid)
#=> false

## organization_ref discloses nothing of the objid it derives from
[TR.organization_ref(@org_objid) == @org_objid,
 @org_objid.downcase.include?(TR.organization_ref(@org_objid))]
#=> [false, false]

## DOMAIN SEPARATION: the SAME string under the SAME keying digests differently
## in the two namespaces. Executed against both entry points rather than
## asserted from the constants.
TR.organization_ref(@shared_pre_image) == TR.actor_ref(@shared_pre_image)
#=> false

## DOMAIN SEPARATION: the org purpose prefix is versioned and distinct from the
## actor one, so either namespace can be re-keyed without touching the other
[TR::ORGANIZATION_INFO == TR::ACTOR_INFO,
 TR::ORGANIZATION_INFO.include?('v2'),
 TR::ORGANIZATION_INFO.include?('organization')]
#=> [false, true, true]

## DOMAIN SEPARATION: an org ref is not the federation email hash of the same
## string either
TR.organization_ref(@shared_pre_image) == Onetime::Utils::EmailHash.compute(@shared_pre_image)
#=> false

## NO NORMALIZATION: objid alphabets are case-sensitive, so folding could
## collapse two distinct organizations onto one ref. Neither namespace folds.
lower = '01jorgabcdefghjkmnpqrstvwx'
upper = '01JORGABCDEFGHJKMNPQRSTVWX'
[TR.organization_ref(lower) == TR.organization_ref(upper),
 TR.actor_ref(lower) == TR.actor_ref(upper)]
#=> [false, false]

## Surrounding whitespace is trimmed, so a padded value cannot split one
## organization into two refs
TR.organization_ref("  #{@org_objid}  ") == TR.organization_ref(@org_objid)
#=> true

## Blank, nil and whitespace-only identifiers return nil, never a digest of ''
[TR.organization_ref(''), TR.organization_ref(nil), TR.organization_ref('   ')]
#=> [nil, nil, nil]

## ENCODING: an identifier that is not valid UTF-8 returns nil instead of
## raising ArgumentError out of String#strip, while ASCII bytes carrying the
## wrong encoding tag are recovered and still correlate with themselves
[TR.organization_ref("a\xFForg"),
 TR.organization_ref('01JORG'.dup.force_encoding(Encoding::ASCII_8BIT)) == TR.organization_ref('01JORG')]
#=> [nil, true]

## FAIL-CLOSED PARITY: organization_ref returns nil under EXACTLY the keying
## conditions actor_ref does. Executed as a table so the two cannot drift: each
## row is [actor_ref.nil?, organization_ref.nil?] and every row must agree.
usable = with_env_vars('ACCOUNT_ID_SECRET' => @deployment_key) do
  [TR.actor_ref(@extid).nil?, TR.organization_ref(@org_objid).nil?]
end
no_secret = with_env_vars('ACCOUNT_ID_SECRET' => nil) do
  [TR.actor_ref(@extid).nil?, TR.organization_ref(@org_objid).nil?]
end
blank_pre_image = with_env_vars('ACCOUNT_ID_SECRET' => @deployment_key) do
  [TR.actor_ref('  ').nil?, TR.organization_ref('  ').nil?]
end
[usable, no_secret, blank_pre_image]
#=> [[false, false], [true, true], [true, true]]

## The org ref is the derivation an operator can reproduce from the objid and
## the key, and nothing else - recomputed independently here
with_env_vars('ACCOUNT_ID_SECRET' => @deployment_key) { TR.organization_ref(@org_objid) } ==
  OpenSSL::HMAC.hexdigest(
    'SHA256', @deployment_key, [TR::ORGANIZATION_INFO, @org_objid].join(TR::SEPARATOR)
  )[0, TR::REF_LENGTH]
#=> true

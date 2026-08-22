# try/unit/utils/diagnostics_ref_try.rb
#
# frozen_string_literal: true

# Tests for Onetime::Utils::DiagnosticsRef - opaque actor and organization
# references for the third-party diagnostics backend (Sentry).
#
# Companion to try/unit/utils/email_hash_try.rb, and deliberately in the same
# lane: EmailHash is FEDERATION identity (a queryable Redis index, and a field
# in Stripe customer metadata), DiagnosticsRef is DIAGNOSTICS identity. They may
# be keyed by the same FEDERATION_SECRET but must never produce the same value,
# or Sentry would hold a live join key into billing and the datastore.
#
# Security model:
# - One-way, keyed: the email pre-image is never recoverable
# - Domain separated: versioned purpose prefix ("onetime:sentry:v1:actor",
#   "onetime:sentry:v1:organization"). The prefix is the ONLY separation
#   between the two namespaces, so the same string must digest differently in
#   each - pinned by executing both entry points, not by reading the constants
# - Residency separated: refs do NOT correlate across jurisdictions, so two
#   regional instances sharing FEDERATION_SECRET cannot be joined on user.id
# - Residency FAIL-CLOSED: with no residency declared, the shared
#   FEDERATION_SECRET is refused outright and keying drops to the
#   per-deployment secret. The safe state is the one an operator gets for free.
# - Fail-soft: nil, never an exception, for an unconfigured secret OR for a
#   stored email that is not valid UTF-8 (this runs on every authenticated
#   render, so a raise here is a 500 page plus a self-inflicted Sentry event)
# - Fail-soft is not fail-open: a failure that could change WHICH identity a
#   human gets answers nil (a gap) rather than a second, different ref
# - ONE residency resolution per derivation, threaded through the Keying value:
#   the residency mixed into a ref and the scope label emitted beside it always
#   come from the same read, so a config that changes mid-derivation cannot
#   split one actor in two, collide two jurisdictions, or invert the label
#
# Run: pnpm run test:tryouts:agent try/unit/utils/diagnostics_ref_try.rb

require_relative '../../support/test_helpers'

ENV['FEDERATION_SECRET'] ||= 'test-hmac-secret-for-diagnostics-ref-32c'

# FEDERATION_SECRET only keys the ref when a residency scope resolves, so the
# federated cases below need one declared for the file. The cases that pin the
# undeclared default clear this explicitly.
ENV['DIAGNOSTICS_REF_REGION'] ||= 'try-region'

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

# Replace OT.conf for the duration of a block. Needed because the residency
# scope reads features.regions.current_jurisdiction, and the tryouts lane shares
# one process across files - whether OT has been booted by the time this file
# runs depends on which other files ran first. Pin it rather than inherit it.
def with_conf(conf)
  original = OT.method(:conf)
  OT.define_singleton_method(:conf) { conf }
  yield
ensure
  OT.define_singleton_method(:conf, original)
end

# Simulate a transient config-read failure on the residency path, which is the
# fault that used to fork one human into two Sentry actors.
def with_failing_conf
  original = OT.method(:conf)
  OT.define_singleton_method(:conf) { raise 'transient config failure' }
  yield
ensure
  OT.define_singleton_method(:conf, original)
end

# The fault window that used to fork one Sentry actor in two: OT.conf answers a
# healthy jurisdiction for the FIRST residency resolution of a derivation and
# then goes FALSY. Nothing raises, so the raise-based guard never engages -
# which is exactly why residency must be resolved once and threaded rather than
# re-read and defaulted. Degradation is triggered BY the resolution rather than
# by counting OT.conf reads, so these cases do not depend on how many times the
# implementation happens to touch OT.conf.
def with_conf_falsy_after_first_resolution(jurisdiction)
  original = OT.method(:conf)
  resolved = false
  conf     = Object.new
  conf.define_singleton_method(:dig) do |*path|
    next nil unless path == %w[features regions current_jurisdiction]

    resolved = true
    jurisdiction
  end
  OT.define_singleton_method(:conf) { resolved ? nil : conf }
  yield
ensure
  OT.define_singleton_method(:conf, original)
end

# The same window with no nil anywhere: the DECLARED jurisdiction simply changes
# between resolutions (an operator edit, a config reload). Each resolution takes
# the next value in the sequence; the last value repeats forever.
def with_drifting_jurisdiction(*sequence)
  original = OT.method(:conf)
  queue    = sequence.dup
  conf     = Object.new
  conf.define_singleton_method(:dig) do |*path|
    next nil unless path == %w[features regions current_jurisdiction]

    queue.length > 1 ? queue.shift : queue.first
  end
  OT.define_singleton_method(:conf) { conf }
  yield
ensure
  OT.define_singleton_method(:conf, original)
end

def jurisdiction_conf(label)
  { 'features' => { 'regions' => { 'current_jurisdiction' => label } } }
end

REPO_ROOT = File.expand_path('../../..', __dir__)

@email = 'user@example.com'
@email_upper = 'USER@EXAMPLE.COM'
@email_whitespace = '  user@example.com  '
@other_email = 'other@example.com'
@deployment_key = 'account-id-secret-for-diagnostics-ref-try'

# Two regional installs SHARE this by design - that is what makes a
# residency-independent ref a cross-region join rather than a convenience.
@shared_secret = 'shared-federation-secret-across-two-regions'

# The environment the fault-window cases run under: the shared federation
# secret, no operator pin (so residency comes from the jurisdiction config the
# helpers drive), and a per-install fallback secret available.
@fault_env = { 'FEDERATION_SECRET' => @shared_secret,
               'DIAGNOSTICS_REF_REGION' => nil,
               'ACCOUNT_ID_SECRET' => @deployment_key }

# The value the pre-fix code emitted during the fault window: the shared
# federation secret over a RESIDENCY_UNSCOPED pre-image. Every install sharing
# the secret derives exactly this, whatever jurisdiction it serves, which is the
# collision the cases below assert never appears.
@unscoped_collision = OpenSSL::HMAC.hexdigest(
  'SHA256', @shared_secret,
  [TR::ACTOR_INFO, TR::RESIDENCY_UNSCOPED, @email].join(TR::SEPARATOR)
)[0, TR::REF_LENGTH]

## actor_ref returns a String
TR.actor_ref(@email).is_a?(String)
#=> true

## actor_ref is REF_LENGTH hex characters
TR.actor_ref(@email).length
#=> 16

## actor_ref contains only lowercase hex
TR.actor_ref(@email) =~ /\A[0-9a-f]{16}\z/
#=> 0

## actor_ref is deterministic
TR.actor_ref(@email) == TR.actor_ref(@email)
#=> true

## actor_ref distinguishes different emails
TR.actor_ref(@email) == TR.actor_ref(@other_email)
#=> false

## Email normalization: case-insensitive
TR.actor_ref(@email) == TR.actor_ref(@email_upper)
#=> true

## Email normalization: whitespace trimmed
TR.actor_ref(@email) == TR.actor_ref(@email_whitespace)
#=> true

## Email normalization: NFD and NFC forms of the same address agree
## (built rather than typed - an editor would silently normalize a literal)
composed = "jos\u{e9}@example.com".unicode_normalize(:nfc)
decomposed = composed.unicode_normalize(:nfd)
[decomposed.bytes == composed.bytes, TR.actor_ref(decomposed) == TR.actor_ref(composed)]
#=> [false, true]

## Email normalization agrees with the canonical OT::Utils normalizer
TR.actor_ref(@email_upper) == TR.actor_ref(OT::Utils.normalize_email(@email_upper))
#=> true

## Blank email returns nil
TR.actor_ref('')
#=> nil

## Nil email returns nil
TR.actor_ref(nil)
#=> nil

## Whitespace-only email returns nil
TR.actor_ref('   ')
#=> nil

## Domain separation: actor ref is NOT the federation email hash
TR.actor_ref(@email) == Onetime::Utils::EmailHash.compute(@email)
#=> false

## Domain separation: actor ref is not a prefix of the federation email hash
Onetime::Utils::EmailHash.compute(@email)[0, TR::REF_LENGTH] == TR.actor_ref(@email)
#=> false

## Purpose prefix is versioned, so diagnostics identity can be re-keyed alone
[TR::ACTOR_INFO.include?('v1'), TR::ACTOR_INFO.include?('actor')]
#=> [true, true]

## Diagnostics refs are narrower than federation email hashes
TR::REF_LENGTH < Onetime::Utils::EmailHash::HASH_LENGTH
#=> true

## FEDERATION_SECRET produces the federated correlation scope
TR.scope
#=> 'federated'

## actor bundle carries exactly the ref and its scope
TR.actor(@email).keys.sort
#=> ['actor_ref', 'actor_scope']

## actor bundle is nil for a blank email
TR.actor('')
#=> nil

## Emitted bundle discloses no part of the address
TR.actor(@email).to_json.include?('example.com')
#=> false

## Emitted bundle discloses neither keying secret
with_env_vars('ACCOUNT_ID_SECRET' => @deployment_key) do
  serialized = TR.actor(@email).to_json
  [serialized.include?(ENV.fetch('FEDERATION_SECRET')), serialized.include?(@deployment_key)]
end
#=> [false, false]

## ACCOUNT_ID_SECRET alone produces the deployment scope and a well-formed ref
with_env_vars('FEDERATION_SECRET' => nil, 'ACCOUNT_ID_SECRET' => @deployment_key) do
  [TR.scope, TR.available?, TR.actor_ref(@email) =~ /\A[0-9a-f]{16}\z/]
end
#=> ['deployment', true, 0]

## FEDERATION_SECRET is preferred over ACCOUNT_ID_SECRET, so the refs differ
federated = with_env_vars('ACCOUNT_ID_SECRET' => @deployment_key) { TR.actor_ref(@email) }
deployment = with_env_vars('FEDERATION_SECRET' => nil, 'ACCOUNT_ID_SECRET' => @deployment_key) do
  TR.actor_ref(@email)
end
federated == deployment
#=> false

## RESIDENCY: the same person in two jurisdictions gets DIFFERENT refs even
## though both instances share one FEDERATION_SECRET. This is the cross-region
## re-identification join we refuse to hand the diagnostics backend.
eu = with_env_vars('DIAGNOSTICS_REF_REGION' => 'eu') { TR.actor_ref(@email) }
us = with_env_vars('DIAGNOSTICS_REF_REGION' => 'us') { TR.actor_ref(@email) }
eu == us
#=> false

## RESIDENCY: refs remain deterministic within one jurisdiction
with_env_vars('DIAGNOSTICS_REF_REGION' => 'eu') { TR.actor_ref(@email) } ==
  with_env_vars('DIAGNOSTICS_REF_REGION' => 'EU  ') { TR.actor_ref(@email) }
#=> true

## RESIDENCY: an undeclared residency is not a wildcard that matches every
## declared one - it is not a residency scope at all, and its ref is keyed by
## a different (per-deployment) secret entirely
with_conf({}) do
  unscoped = with_env_vars('DIAGNOSTICS_REF_REGION' => nil,
                           'ACCOUNT_ID_SECRET' => @deployment_key) { TR.actor_ref(@email) }
  unscoped == with_env_vars('DIAGNOSTICS_REF_REGION' => 'eu') { TR.actor_ref(@email) }
end
#=> false

## RESIDENCY: the explicit pin wins over a declared jurisdiction, and is never blank
with_conf({ 'features' => { 'regions' => { 'current_jurisdiction' => 'EU' } } }) do
  with_env_vars('DIAGNOSTICS_REF_REGION' => 'ca-central') { TR.residency_scope }
end
#=> 'ca-central'

## RESIDENCY: a blank pin and no declared jurisdiction resolves to NO residency
## scope. nil is load-bearing here: it is what makes keying refuse the shared
## FEDERATION_SECRET. The RESIDENCY_UNSCOPED literal is only a pre-image filler
## so the element count never varies, and never reaches a federated derivation.
with_conf({}) { with_env_vars('DIAGNOSTICS_REF_REGION' => '   ') { TR.residency_scope } }
#=> nil

## RESIDENCY: with no pin, the scope comes from features.regions.current_jurisdiction
## - the same source SetupDiagnostics derives the Sentry `jurisdiction` tag from
with_conf({ 'features' => { 'regions' => { 'current_jurisdiction' => 'EU' } } }) do
  with_env_vars('DIAGNOSTICS_REF_REGION' => nil) { TR.residency_scope }
end
#=> 'eu'

## RESIDENCY: the residency label is never part of the emitted bundle
with_env_vars('DIAGNOSTICS_REF_REGION' => 'eu-central-zzz') { TR.actor(@email).to_json }.include?('eu-central-zzz')
#=> false

## ENCODING: an invalid byte in a stored email returns nil instead of raising
## Encoding::CompatibilityError out of unicode_normalize
TR.actor_ref("a\xFF@b.com")
#=> nil

## ENCODING: a truncated multibyte sequence returns nil instead of raising
## ArgumentError out of unicode_normalize
TR.actor_ref("\xC3(@b.com")
#=> nil

## ENCODING: an email carrying correct UTF-8 bytes under the wrong encoding tag
## is recovered, not dropped - it must still correlate with itself
TR.actor_ref('alice@example.com'.dup.force_encoding(Encoding::ASCII_8BIT)) ==
  TR.actor_ref('alice@example.com')
#=> true

## ENCODING: a non-UTF-8 email never escapes as an exception from the bundle
## entry point either
[TR.actor("a\xFF@b.com"), TR.actor('alice@example.com'.dup.force_encoding(Encoding::ASCII_8BIT)).nil?]
#=> [nil, false]

## Unconfigured deployment: every entry point returns nil instead of raising,
## even where EmailHash would raise Onetime::Problem for the same address
with_env_vars('FEDERATION_SECRET' => nil, 'ACCOUNT_ID_SECRET' => nil) do
  raised = begin
    Onetime::Utils::EmailHash.compute(@email)
    false
  rescue Onetime::Problem
    true
  end
  [raised, TR.actor_ref(@email), TR.actor(@email), TR.scope, TR.available?]
end
#=> [true, nil, nil, nil, false]

## DEFECT 1 (fail-open default): with NOTHING declared, a shared
## FEDERATION_SECRET must not key the ref. Keying drops to the per-deployment
## secret and the emitted label narrows with it, so an operator is never told
## the ref correlates further than it does.
with_conf({}) do
  with_env_vars('DIAGNOSTICS_REF_REGION' => nil, 'ACCOUNT_ID_SECRET' => @deployment_key) do
    [TR.scope, TR.available?]
  end
end
#=> ['deployment', true]

## DEFECT 1: the headline regression. Two installs that share FEDERATION_SECRET
## and configure NO residency - the documented default state - must derive
## DIFFERENT refs for the same person. Before the fix both derived the identical
## value, which is the cross-region re-identification join this module exists to
## prevent, available to anyone who configured nothing.
same_secret = 'shared-federation-secret-across-two-regions'
install_a = with_conf({}) do
  with_env_vars('FEDERATION_SECRET' => same_secret,
                'DIAGNOSTICS_REF_REGION' => nil,
                'ACCOUNT_ID_SECRET' => 'per-install-secret-region-a') { TR.actor_ref(@email) }
end
install_b = with_conf({}) do
  with_env_vars('FEDERATION_SECRET' => same_secret,
                'DIAGNOSTICS_REF_REGION' => nil,
                'ACCOUNT_ID_SECRET' => 'per-install-secret-region-b') { TR.actor_ref(@email) }
end
[install_a.nil?, install_b.nil?, install_a == install_b]
#=> [false, false, false]

## DEFECT 1: refusal, not degradation. With a shared FEDERATION_SECRET, no
## residency and no per-deployment secret to fall back to, there is nothing safe
## to key with - so nothing is emitted, rather than reaching for the shared key.
with_conf({}) do
  with_env_vars('DIAGNOSTICS_REF_REGION' => nil, 'ACCOUNT_ID_SECRET' => nil) do
    [TR.scope, TR.available?, TR.actor_ref(@email), TR.actor(@email)]
  end
end
#=> [nil, false, nil, nil]

## DEFECT 1: declaring a residency is what unlocks federated keying, and it is
## enough on its own - JURISDICTION alone, no diagnostics-specific env var.
with_conf({ 'features' => { 'regions' => { 'current_jurisdiction' => 'EU' } } }) do
  with_env_vars('DIAGNOSTICS_REF_REGION' => nil, 'ACCOUNT_ID_SECRET' => @deployment_key) do
    [TR.scope, TR.residency_scope]
  end
end
#=> ['federated', 'eu']

## DEFECT 1: and the residency mechanism still separates jurisdictions once on,
## so closing the default did not disable the guarantee it protects.
eu_scoped = with_conf({ 'features' => { 'regions' => { 'current_jurisdiction' => 'EU' } } }) do
  with_env_vars('DIAGNOSTICS_REF_REGION' => nil) { TR.actor_ref(@email) }
end
us_scoped = with_conf({ 'features' => { 'regions' => { 'current_jurisdiction' => 'US' } } }) do
  with_env_vars('DIAGNOSTICS_REF_REGION' => nil) { TR.actor_ref(@email) }
end
[eu_scoped.nil?, eu_scoped == us_scoped]
#=> [false, false]

## DEFECT 2 (residency rescue fail-open): a transient config failure must not
## hand the same human a SECOND, different ref. It yields no ref at all - a gap,
## which is honest and self-healing - and no scope label either.
with_failing_conf do
  with_env_vars('DIAGNOSTICS_REF_REGION' => nil) do
    [TR.actor_ref(@email), TR.actor(@email), TR.scope, TR.available?]
  end
end
#=> [nil, nil, nil, false]

## DEFECT 2: specifically, the fault does not fork one actor into two. The ref
## derived during the fault is not some other derivable value - it is absent, so
## it can never be mistaken for a different data subject.
healthy = with_conf({ 'features' => { 'regions' => { 'current_jurisdiction' => 'EU' } } }) do
  with_env_vars('DIAGNOSTICS_REF_REGION' => nil) { TR.actor_ref(@email) }
end
faulted = with_failing_conf do
  with_env_vars('DIAGNOSTICS_REF_REGION' => nil) { TR.actor_ref(@email) }
end
[healthy.nil?, faulted.nil?]
#=> [false, true]

## DEFECT 2: and the failure still never escapes as an exception - this runs on
## every authenticated render, where a raise is a 500 plus a self-inflicted
## Sentry event. residency_scope stays raise-free for boot checks too.
with_failing_conf do
  with_env_vars('DIAGNOSTICS_REF_REGION' => nil) do
    [TR.residency_scope, TR.actor(@email)]
  rescue StandardError => ex
    ex.class
  end
end
#=> [nil, nil]

## DEFECT 3 (false operator-facing comment): DIAGNOSTICS_REF_REGION is documented
## in both operator env files, so the knob that decides residency keying is
## discoverable without reading the source.
[File.read(File.join(REPO_ROOT, '.env.example')).include?('DIAGNOSTICS_REF_REGION'),
 File.read(File.join(REPO_ROOT, '.env.reference')).include?('DIAGNOSTICS_REF_REGION')]
#=> [true, true]

## DEFECT 3: and .env.example no longer advertises the property the code
## deliberately does not deliver ("one identity per person across regions").
File.read(File.join(REPO_ROOT, '.env.example')).include?('identity per person across regions')
#=> false

## DEFECT 4 (residency resolved three times per derivation): the emitted bundle
## must come from ONE resolution. keying resolves the secret, the label that
## secret implies, and the residency that SELECTED it, together, as one value -
## so nothing downstream can pair a ref with a label from a different read.
with_conf(jurisdiction_conf('EU')) do
  with_env_vars('DIAGNOSTICS_REF_REGION' => nil, 'ACCOUNT_ID_SECRET' => @deployment_key) do
    key = TR.keying
    [key.is_a?(TR::Keying), key.scope, key.residency]
  end
end
#=> [true, 'federated', 'eu']

## DEFECT 4 (fault window, falsy-conf variant): ONE human in ONE process gets
## ONE ref. Before the fix, keying resolved 'eu' and chose FEDERATION_SECRET,
## then digest_ref re-resolved into the falsy window, substituted
## RESIDENCY_UNSCOPED, and derived a SECOND ref for the same person.
healthy_eu = with_conf(jurisdiction_conf('eu')) do
  with_env_vars(@fault_env) { TR.actor(@email) }
end
faulted_eu = with_conf_falsy_after_first_resolution('eu') do
  with_env_vars(@fault_env) { TR.actor(@email) }
end
[faulted_eu.nil?, faulted_eu == healthy_eu]
#=> [false, true]

## DEFECT 4 (fault window): NO COLLISION. Two installs in DIFFERENT
## jurisdictions sharing one FEDERATION_SECRET must not derive the same ref
## during the window. Before the fix both fell back to RESIDENCY_UNSCOPED while
## still keyed with the shared secret, which IS the cross-region join.
faulted_a = with_conf_falsy_after_first_resolution('eu') do
  with_env_vars(@fault_env) { TR.actor_ref(@email) }
end
faulted_b = with_conf_falsy_after_first_resolution('us') do
  with_env_vars(@fault_env) { TR.actor_ref(@email) }
end
[faulted_a == faulted_b, faulted_a == @unscoped_collision, faulted_b == @unscoped_collision]
#=> [false, false, false]

## DEFECT 4 (fault window): NO LABEL INVERSION. The emitted label must describe
## the key that actually derived the ref. Recomputed independently here from the
## shared secret and the DECLARED residency: the ref matches that derivation and
## the label says 'federated'. Before the fix the ref was federation-keyed while
## the label read 'deployment' - told narrower than it actually correlated.
faulted = with_conf_falsy_after_first_resolution('eu') do
  with_env_vars(@fault_env) { TR.actor(@email) }
end
expected = OpenSSL::HMAC.hexdigest(
  'SHA256', @shared_secret, [TR::ACTOR_INFO, 'eu', @email].join(TR::SEPARATOR)
)[0, TR::REF_LENGTH]
[faulted['actor_ref'] == expected, faulted['actor_scope']]
#=> [true, 'federated']

## DEFECT 4 (jurisdiction-changed-between-reads variant, no nil involved): a
## jurisdiction that drifts eu -> us mid-derivation yields the EU ref, because
## EU is the read that chose the key. It is not the US ref, and it is not some
## third value only the fault can produce.
drifted = with_drifting_jurisdiction('eu', 'us') do
  with_env_vars(@fault_env) { TR.actor(@email) }
end
stable_us = with_conf(jurisdiction_conf('us')) do
  with_env_vars(@fault_env) { TR.actor(@email) }
end
[drifted == healthy_eu, drifted['actor_ref'] == stable_us['actor_ref']]
#=> [true, false]

## DEFECT 4: the honesty invariant is now ENFORCED, not just asserted. Handed
## FEDERATION_SECRET keying with no residency - the pairing that would put
## RESIDENCY_UNSCOPED under the shared key - digest_ref emits nothing at all.
TR.send(:digest_ref, TR::ACTOR_INFO,
        TR::Keying.new(secret: @shared_secret, scope: TR::SCOPE_FEDERATED, residency: nil)) { @email }
#=> nil

## DEFECT 4: and that refusal is specific to the shared key. A per-deployment
## key with no residency still derives normally - RESIDENCY_UNSCOPED there
## grants no cross-install correlation, which is the whole reason it survives.
TR.send(:digest_ref, TR::ACTOR_INFO,
        TR::Keying.new(secret: @deployment_key, scope: TR::SCOPE_DEPLOYMENT, residency: nil)) { @email } =~ /\A[0-9a-f]{16}\z/
#=> 0

# ---------------------------------------------------------------------------
# ORGANIZATION REFS
# ---------------------------------------------------------------------------
# Same module, same keying, same residency threading — a SECOND namespace,
# separated only by the purpose prefix. It exists because Sentry parameterizes
# the colonel route to /api/colonel/organizations/:org_id and never carries the
# real id, so an operator cannot otherwise tell "one org is broken" from "every
# org is broken". The cases below pin the three things that makes safe:
# separation from the actor namespace, identical fail-closed behaviour, and no
# normalization that could collapse two organizations onto one ref.

@org_objid = '01JORGABCDEFGHJKMNPQRSTVWX'
@other_org_objid = '01JOTHERABCDEFGHJKMNPQRSTV'

# A pre-image both entry points treat IDENTICALLY — already lowercase,
# unpadded, NFC — so an actor/org comparison over it isolates the purpose
# prefix as the only difference.
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

## DOMAIN SEPARATION: the SAME string, the SAME keying and the SAME residency
## digest differently in the two namespaces. Executed against both entry points
## rather than asserted from the constants.
TR.organization_ref(@shared_pre_image) == TR.actor_ref(@shared_pre_image)
#=> false

## DOMAIN SEPARATION: the org purpose prefix is versioned and distinct from the
## actor one, so either namespace can be re-keyed without touching the other
[TR::ORGANIZATION_INFO == TR::ACTOR_INFO,
 TR::ORGANIZATION_INFO.include?('v1'),
 TR::ORGANIZATION_INFO.include?('organization')]
#=> [false, true, true]

## DOMAIN SEPARATION: an org ref is not the federation email hash of the same
## string either - Sentry never holds a live join key into billing or the index
TR.organization_ref(@shared_pre_image) == Onetime::Utils::EmailHash.compute(@shared_pre_image)
#=> false

## NO NORMALIZATION, by contrast with emails: an objid alphabet is
## case-sensitive, so folding it could collapse two distinct organizations onto
## one ref. actor_ref folds by design; organization_ref must not.
lower = '01jorgabcdefghjkmnpqrstvwx'
upper = '01JORGABCDEFGHJKMNPQRSTVWX'
[TR.organization_ref(lower) == TR.organization_ref(upper),
 TR.actor_ref(lower) == TR.actor_ref(upper)]
#=> [false, true]

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

## RESIDENCY: one organization in two jurisdictions gets DIFFERENT refs, even
## though both instances share one FEDERATION_SECRET - the same cross-region
## join refusal actor refs get
eu_org = with_env_vars('DIAGNOSTICS_REF_REGION' => 'eu') { TR.organization_ref(@org_objid) }
us_org = with_env_vars('DIAGNOSTICS_REF_REGION' => 'us') { TR.organization_ref(@org_objid) }
[eu_org.nil?, eu_org == us_org]
#=> [false, false]

## FAIL-CLOSED PARITY: organization_ref returns nil under EXACTLY the keying
## conditions actor_ref does. Executed as a table so the two cannot drift: each
## row is [actor_ref.nil?, organization_ref.nil?] and every row must agree.
usable = [TR.actor_ref(@email).nil?, TR.organization_ref(@org_objid).nil?]
no_secret = with_env_vars('FEDERATION_SECRET' => nil, 'ACCOUNT_ID_SECRET' => nil) do
  [TR.actor_ref(@email).nil?, TR.organization_ref(@org_objid).nil?]
end
shared_no_residency = with_conf({}) do
  with_env_vars('FEDERATION_SECRET' => @shared_secret,
                'DIAGNOSTICS_REF_REGION' => nil,
                'ACCOUNT_ID_SECRET' => nil) do
    [TR.actor_ref(@email).nil?, TR.organization_ref(@org_objid).nil?]
  end
end
failing_conf = with_failing_conf do
  with_env_vars('DIAGNOSTICS_REF_REGION' => nil) do
    [TR.actor_ref(@email).nil?, TR.organization_ref(@org_objid).nil?]
  end
end
[usable, no_secret, shared_no_residency, failing_conf]
#=> [[false, false], [true, true], [true, true], [true, true]]

## FAIL-CLOSED: two installs sharing FEDERATION_SECRET with NO residency
## declared must not derive the same org ref. They fall to the per-deployment
## key, exactly as actor refs do.
org_a = with_conf({}) do
  with_env_vars('FEDERATION_SECRET' => @shared_secret,
                'DIAGNOSTICS_REF_REGION' => nil,
                'ACCOUNT_ID_SECRET' => 'per-install-secret-region-a') { TR.organization_ref(@org_objid) }
end
org_b = with_conf({}) do
  with_env_vars('FEDERATION_SECRET' => @shared_secret,
                'DIAGNOSTICS_REF_REGION' => nil,
                'ACCOUNT_ID_SECRET' => 'per-install-secret-region-b') { TR.organization_ref(@org_objid) }
end
[org_a.nil?, org_b.nil?, org_a == org_b]
#=> [false, false, false]

## FAIL-CLOSED: the honesty invariant applies to the org namespace too. Handed
## FEDERATION_SECRET keying with no residency, digest_ref emits nothing.
TR.send(:digest_ref, TR::ORGANIZATION_INFO,
        TR::Keying.new(secret: @shared_secret, scope: TR::SCOPE_FEDERATED, residency: nil)) { @org_objid }
#=> nil

## The org ref is the derivation an operator can reproduce from the objid and
## the key, and nothing else - recomputed independently here
with_env_vars('DIAGNOSTICS_REF_REGION' => 'eu') { TR.organization_ref(@org_objid) } ==
  OpenSSL::HMAC.hexdigest(
    'SHA256', ENV.fetch('FEDERATION_SECRET'),
    [TR::ORGANIZATION_INFO, 'eu', @org_objid].join(TR::SEPARATOR)
  )[0, TR::REF_LENGTH]
#=> true

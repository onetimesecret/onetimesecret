# try/unit/domain_validation/record_normalizer_try.rb
#
# frozen_string_literal: true

# Tests for Onetime::DomainValidation::RecordNormalizer (issue #4023)
#
# Source of truth for tag-list normalization semantics (RFC 6376 Section 3.2,
# RFC 7489 Section 6.4):
# 1. Tag-list parsing: WSP tolerance, trailing ";", duplicate-tag invalidation
# 2. Subset matching: expected tags must be present, extras ignored
# 3. Per-tag case policy: DMARC keywords fold, DKIM p= base64 does not
# 4. Record-kind discriminators (dmarc?, dkim?, spf?)
# 5. BaseStrategy#record_matches? dispatch: tag-lists normalize, SPF keeps
#    include: extraction, opaque tokens require exact match after trim
# 6. Record-set selection: duplicate DMARC/SPF records are ambiguous, never
#    a pass (RFC 7489 Section 6.6.3, RFC 7208 permerror)

require_relative '../../support/test_helpers'

OT.boot! :test

require 'onetime/domain_validation/record_normalizer'
require 'onetime/domain_validation/sender_strategies/strategy'

@normalizer = Onetime::DomainValidation::RecordNormalizer
@base       = Onetime::DomainValidation::SenderStrategies::BaseStrategy.new

# --- Parsing (RFC 6376 Section 3.2 tag-list grammar) ---

## Parses a compact tag-list into name => value pairs
@normalizer.parse('v=DMARC1;p=none')
#=> {'v' => 'DMARC1', 'p' => 'none'}

## Tolerates WSP around names, "=", and values; trailing ";" allowed
@normalizer.parse(' v = DMARC1 ; p = none ; ')
#=> {'v' => 'DMARC1', 'p' => 'none'}

## Tag names fold to lowercase; values keep their case
@normalizer.parse('V=DKIM1;P=MIGfMA0')
#=> {'v' => 'DKIM1', 'p' => 'MIGfMA0'}

## Internal whitespace in a value is significant and preserved
@normalizer.parse('v=spf1 include:example.com ~all;note=a b')['note']
#=> 'a b'

## Empty tag-value is permitted by the grammar
@normalizer.parse('v=DKIM1;g=')
#=> {'v' => 'DKIM1', 'g' => ''}

## Duplicate tag names invalidate the entire record
@normalizer.parse('v=DMARC1;p=none;p=reject')
#=> nil

## Duplicate detection is case-insensitive on the tag name
@normalizer.parse('v=DMARC1;p=none;P=reject')
#=> nil

## Empty tag-spec in the middle is invalid (only trailing ";" is optional)
@normalizer.parse('v=DMARC1;;p=none')
#=> nil

## Non-tag-list input returns nil
@normalizer.parse('some-verification-token')
#=> nil

## Empty string returns nil
@normalizer.parse('')
#=> nil

# --- Subset matching: the #4023 regression ---

## Issue #4023: published "v=DMARC1; p=none;" satisfies expected
## "v=DMARC1;p=none" (real Lettermint case, eu-direct.metalbaum.dev)
@normalizer.subset_match?('v=DMARC1;p=none', 'v=DMARC1; p=none;')
#=> true

## Spacing tolerance works in the other direction too
@normalizer.subset_match?('v=DMARC1; p=none;', 'v=DMARC1;p=none')
#=> true

## Customer-added tags (rua=) do not fail verification
@normalizer.subset_match?('v=DMARC1;p=none', 'v=DMARC1; p=none; rua=mailto:dmarc@example.com')
#=> true

## Published p=reject satisfies expected p=none (hardening is not a mismatch)
@normalizer.subset_match?('v=DMARC1;p=none', 'v=DMARC1; p=reject')
#=> true

## Published sp= follows the same strength ordering (both hardened here)
@normalizer.subset_match?('v=DMARC1;p=none;sp=none', 'v=DMARC1;p=quarantine;sp=reject')
#=> true

## Policy keywords compare case-insensitively (ABNF keywords, RFC 5234 2.3)
@normalizer.subset_match?('v=DMARC1;p=none', 'v=DMARC1; p=NONE')
#=> true

## Weaker published policy fails: p=none does not satisfy expected p=quarantine
@normalizer.subset_match?('v=DMARC1;p=quarantine', 'v=DMARC1; p=none')
#=> false

## Unrecognized published policy value fails (p=bogus is not an RFC 7489 keyword)
@normalizer.subset_match?('v=DMARC1;p=none', 'v=DMARC1; p=bogus')
#=> false

## Empty published policy value fails
@normalizer.subset_match?('v=DMARC1;p=none', 'v=DMARC1; p=')
#=> false

## WSP around a policy value trims away (TAG_SPEC); strength still applies
@normalizer.subset_match?('v=DMARC1;p=quarantine', 'v=DMARC1; p= REJECT ')
#=> true

## Weaker published sp= fails even when p= is satisfied
@normalizer.subset_match?('v=DMARC1;p=none;sp=reject', 'v=DMARC1;p=none;sp=none')
#=> false

## Unrecognized EXPECTED policy falls back to case-insensitive equality
[@normalizer.subset_match?('v=DMARC1;p=custom', 'v=DMARC1;p=CUSTOM'),
 @normalizer.subset_match?('v=DMARC1;p=custom', 'v=DMARC1;p=reject')]
#=> [true, false]

## Missing expected tag fails
@normalizer.subset_match?('v=DMARC1;p=none', 'v=DMARC1')
#=> false

## Version tag compares case-insensitively
@normalizer.subset_match?('v=DMARC1;p=none', 'v=dmarc1; p=none')
#=> true

## Wrong version fails
@normalizer.subset_match?('v=DMARC1;p=none', 'v=DMARC2;p=none')
#=> false

## DMARC alignment values compare case-insensitively (adkim=r vs ADKIM=R)
@normalizer.subset_match?('v=DMARC1;p=none;adkim=r', 'v=DMARC1;p=none;ADKIM=R')
#=> true

## Published record with duplicate tags is invalid and never matches
@normalizer.subset_match?('v=DMARC1;p=none', 'v=DMARC1;p=none;p=reject')
#=> false

## Malformed expected record never matches
@normalizer.subset_match?('v=DMARC1;p=none;p=none', 'v=DMARC1;p=none')
#=> false

# --- DKIM case policy ---

## DKIM k= (key type) compares case-insensitively
@normalizer.subset_match?('v=DKIM1;k=rsa;p=MIGfMA0', 'v=DKIM1; k=RSA; p=MIGfMA0')
#=> true

## DKIM p= base64 is case-SENSITIVE: MIGfMA0 does not match migfma0
@normalizer.subset_match?('v=DKIM1;k=rsa;p=MIGfMA0', 'v=DKIM1;k=rsa;p=migfma0')
#=> false

## DKIM p= ignores internal whitespace (DNS UIs wrap long keys)
@normalizer.subset_match?('v=DKIM1;k=rsa;p=MIGfMA0GCSqGSIb3', 'v=DKIM1; k=rsa; p=MIGfMA0 GCSqG SIb3')
#=> true

# --- Discriminators ---

## dmarc? accepts WSP and trailing content
@normalizer.dmarc?(' v = DMARC1 ; p=none;')
#=> true

## dmarc? rejects non-DMARC records
[@normalizer.dmarc?('v=spf1 -all'), @normalizer.dmarc?('token'), @normalizer.dmarc?('v=DMARC10;p=none')]
#=> [false, false, false]

## spf? requires exactly v=spf1 followed by space or end (RFC 7208 4.5)
[@normalizer.spf?('v=spf1 include:x.com ~all'), @normalizer.spf?('v=spf1'), @normalizer.spf?('v=spf10 -all')]
#=> [true, true, false]

## dkim? identifies DKIM key records
[@normalizer.dkim?('v=DKIM1; k=rsa; p=ABC'), @normalizer.dkim?('v=DMARC1;p=none')]
#=> [true, false]

# --- BaseStrategy dispatch (record_matches?) ---

## The #4023 regression verifies end-to-end through record_matches?
@base.send(:record_matches?, 'TXT', 'v=DMARC1;p=none', ['v=DMARC1; p=none;'])
#=> true

## DKIM records normalize through record_matches? too
@base.send(:record_matches?, 'TXT', 'v=DKIM1;k=rsa;p=TESTKEY', ['v=DKIM1; k=rsa; p=TESTKEY'])
#=> true

## SPF matching still uses include: extraction (unchanged behavior)
@base.send(:record_matches?, 'TXT',
  'v=spf1 include:amazonses.com ~all',
  ['v=spf1 include:amazonses.com include:sendgrid.net ~all'])
#=> true

## Opaque tokens require exact match: substring is no longer enough
@base.send(:record_matches?, 'TXT', 'token-abc', ['prefix-token-abc-suffix'])
#=> false

## Opaque tokens match exactly after trimming edge whitespace
@base.send(:record_matches?, 'TXT', 'token-abc', ['  token-abc  '])
#=> true

## Opaque tokens are case-sensitive (exact means exact)
@base.send(:record_matches?, 'TXT', 'Token-ABC', ['token-abc'])
#=> false

# --- Record-set selection (evaluate_record_set) ---

## One DMARC record plus unrelated TXT junk still verifies (6.6.3 discard)
@base.send(:evaluate_record_set,
  { type: 'TXT', value: 'v=DMARC1;p=none' },
  ['v=DMARC1; p=none;', 'google-site-verification=abc123'])
#=> [true, nil]

## Two DMARC records are ambiguous: verified false, error_type set
@base.send(:evaluate_record_set,
  { type: 'TXT', value: 'v=DMARC1;p=none' },
  ['v=DMARC1; p=none;', 'v=DMARC1; p=reject'])
#=> [false, 'ambiguous_record_set']

## Duplicate identical DMARC records are still ambiguous, never a pass
@base.send(:evaluate_record_set,
  { type: 'TXT', value: 'v=DMARC1;p=none' },
  ['v=DMARC1;p=none', 'v=DMARC1;p=none'])
#=> [false, 'ambiguous_record_set']

## Two SPF records are ambiguous (RFC 7208 permerror)
@base.send(:evaluate_record_set,
  { type: 'TXT', value: 'v=spf1 include:amazonses.com ~all' },
  ['v=spf1 include:amazonses.com ~all', 'v=spf1 -all'])
#=> [false, 'ambiguous_record_set']

## Zero surviving records keeps not-found semantics (no error_type)
@base.send(:evaluate_record_set,
  { type: 'TXT', value: 'v=DMARC1;p=none' },
  ['google-site-verification=abc123'])
#=> [false, nil]

## Opaque-token expectations have no discriminator: duplicates allowed
@base.send(:evaluate_record_set,
  { type: 'TXT', value: 'token-abc' },
  ['token-abc', 'other-token'])
#=> [true, nil]

## CNAME sets pass through unfiltered
@base.send(:evaluate_record_set,
  { type: 'CNAME', value: 'target.example.com' },
  ['target.example.com.', 'other.example.com.'])
#=> [true, nil]

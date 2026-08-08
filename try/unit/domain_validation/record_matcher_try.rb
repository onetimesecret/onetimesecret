# try/unit/domain_validation/record_matcher_try.rb
#
# frozen_string_literal: true

# Tests for Onetime::DomainValidation::RecordMatcher (issue #4047)
#
# RecordMatcher is the shared DNS comparison module extracted from the #4046
# fix so that BOTH pipelines — verification (DomainValidation::SenderStrategies)
# and fact-finding (Mail::SenderStrategies) — dispatch identically. It is a
# pure module (no OT state, no I/O), so this tryout is deliberately boot-free:
# it requires the file directly instead of going through test_helpers/OT.boot!.
#
# Coverage:
# 1. record_matches? type dispatch (TXT content-aware, CNAME/MX hostname,
#    unknown types never match)
# 2. txt_record_matches? dispatch: SPF include-subset, DMARC/DKIM tag-list
#    normalization, opaque tokens exact-after-trim
# 3. spf_record_matches? include: extraction and the no-include fallback
# 4. select_txt_record_set: duplicate DMARC/SPF in the zone is ambiguous,
#    never a pass; unrelated TXT records are discarded, not failures
#
# Motivating real-world cases (#4047):
# - SES provisions advisory DMARC as 'v=DMARC1; p=none;' WITH spaces; zones
#   often store 'v=DMARC1;p=none' — must MATCH (the #4047 false negative)
# - SES required SPF vs a customer's merged record — must MATCH
# - DKIM p= base64 differing only in case — must NOT match (the old global
#   downcase made this a false positive)

require_relative '../../../lib/onetime/domain_validation/record_matcher'

@matcher = Onetime::DomainValidation::RecordMatcher

# --- record_matches?: TXT/DMARC (the #4047 false negative) ---

## SES advisory DMARC 'v=DMARC1; p=none;' (with spaces, per
## ses_sender_strategy provisioning) matches a compact zone record
@matcher.record_matches?('TXT', 'v=DMARC1; p=none;', ['v=DMARC1;p=none'])
#=> true

## Spacing tolerance works in the other direction too
@matcher.record_matches?('TXT', 'v=DMARC1;p=none', ['v=DMARC1; p=none;'])
#=> true

## Customer-added DMARC tags (rua=) do not break the match
@matcher.record_matches?('TXT', 'v=DMARC1; p=none;', ['v=DMARC1;p=none;rua=mailto:dmarc@example.com'])
#=> true

## A zone with no DMARC record does not match
@matcher.record_matches?('TXT', 'v=DMARC1; p=none;', ['google-site-verification=abc123'])
#=> false

# --- record_matches?: TXT/SPF (merged customer records) ---

## SES required SPF matches a customer record merged with another provider
@matcher.record_matches?('TXT',
  'v=spf1 include:amazonses.com ~all',
  ['v=spf1 include:amazonses.com include:_spf.google.com ~all'])
#=> true

## Exact SPF record still matches, case-insensitively
@matcher.record_matches?('TXT', 'v=spf1 include:amazonses.com ~all', ['V=SPF1 INCLUDE:AMAZONSES.COM ~ALL'])
#=> true

## SPF without the required include: mechanism does not match
@matcher.record_matches?('TXT', 'v=spf1 include:amazonses.com ~all', ['v=spf1 include:sendgrid.net ~all'])
#=> false

# --- record_matches?: TXT/DKIM (case-sensitivity restored) ---

## DKIM keys differing ONLY in p= case do NOT match (RFC 6376: base64 key
## data is case-sensitive; the old global downcase made this a false positive)
@matcher.record_matches?('TXT', 'v=DKIM1;k=rsa;p=MIGfMA0GCSqG', ['v=DKIM1;k=rsa;p=migfma0gcsqg'])
#=> false

## Identical DKIM keys match despite spacing differences in the tag list
@matcher.record_matches?('TXT', 'v=DKIM1;k=rsa;p=MIGfMA0GCSqG', ['v=DKIM1; k=rsa; p=MIGfMA0GCSqG'])
#=> true

# --- record_matches?: TXT opaque verification tokens ---

## Opaque tokens match exactly
@matcher.record_matches?('TXT', 'token-abc123', ['token-abc123'])
#=> true

## Substring containment is NOT a match
@matcher.record_matches?('TXT', 'token-abc123', ['prefix-token-abc123-suffix'])
#=> false

## Opaque tokens are case-sensitive
@matcher.record_matches?('TXT', 'Token-ABC123', ['token-abc123'])
#=> false

## Edge whitespace on either side is trimmed before the exact comparison
@matcher.record_matches?('TXT', '  token-abc123  ', ['token-abc123 '])
#=> true

## A nil expected value never matches
@matcher.record_matches?('TXT', nil, ['token-abc123'])
#=> false

# --- record_matches?: CNAME / MX hostname comparison ---

## CNAME comparison ignores the trailing dot DNS resolvers return
@matcher.record_matches?('CNAME', 'abc123.dkim.amazonses.com', ['abc123.dkim.amazonses.com.'])
#=> true

## CNAME comparison is case-insensitive
@matcher.record_matches?('CNAME', 'Bounces.LMTA.net', ['bounces.lmta.net'])
#=> true

## Trailing dot on the expected side is also tolerated
@matcher.record_matches?('CNAME', 'bounces.lmta.net.', ['bounces.lmta.net'])
#=> true

## Different CNAME targets do not match
@matcher.record_matches?('CNAME', 'bounces.lmta.net', ['other.example.com.'])
#=> false

## MX uses the same hostname comparison
@matcher.record_matches?('MX', 'feedback-smtp.us-east-1.amazonses.com', ['FEEDBACK-SMTP.us-east-1.amazonses.com.'])
#=> true

## Unknown record types never match
@matcher.record_matches?('A', '192.0.2.1', ['192.0.2.1'])
#=> false

## Dispatch is on the exact type string: callers must upcase first
@matcher.record_matches?('txt', 'token-abc123', ['token-abc123'])
#=> false

# --- txt_record_matches? / spf_record_matches? internals ---

## SPF expected without an include: requires every expected term
@matcher.txt_record_matches?('v=spf1 -all', ['v=spf1 -all'])
#=> true

## The no-include path still requires each expected term to appear
@matcher.txt_record_matches?('v=spf1 -all', ['v=spf1 mx ~all'])
#=> false

## The no-include path tolerates extra terms in the customer record, the
## same way the include: path does (PR #4051 review)
@matcher.txt_record_matches?('v=spf1 mx -all', ['v=spf1 mx include:other.com -all'])
#=> true

## spf_record_matches? only considers actual records that are SPF: an
## include: mechanism embedded in a non-SPF TXT record does not count
@matcher.spf_record_matches?('v=spf1 include:amazonses.com ~all', ['some-token include:amazonses.com'])
#=> false

## spf_record_matches? finds the include among other mechanisms, any case
@matcher.spf_record_matches?('v=spf1 include:amazonses.com ~all', ['v=spf1 a mx INCLUDE:AMAZONSES.COM -all'])
#=> true

## Mechanisms match as whole terms: a longer domain that merely starts
## with the expected one is a different include (PR #4051 review)
@matcher.spf_record_matches?('v=spf1 include:amazonses.com ~all', ['v=spf1 include:amazonses.com.evil ~all'])
#=> false

## The same term discipline applies to the no-include path
@matcher.spf_record_matches?('v=spf1 mx -all', ['v=spf1 mxtra -all'])
#=> false

## An expected value that is SPF-flagged but carries no terms never matches
@matcher.spf_record_matches?('', ['v=spf1 -all'])
#=> false

# --- select_txt_record_set: ambiguity detection ---

## Two DMARC records in the zone survive selection and flag ambiguous
@matcher.select_txt_record_set('TXT', 'v=DMARC1;p=none', ['v=DMARC1; p=none;', 'v=DMARC1; p=reject'])
#=> [['v=DMARC1; p=none;', 'v=DMARC1; p=reject'], true]

## Duplicate identical DMARC records are still ambiguous, never a pass
@matcher.select_txt_record_set('TXT', 'v=DMARC1;p=none', ['v=DMARC1;p=none', 'v=DMARC1;p=none'])
#=> [['v=DMARC1;p=none', 'v=DMARC1;p=none'], true]

## Two SPF records are ambiguous (RFC 7208 permerror)
@matcher.select_txt_record_set('TXT',
  'v=spf1 include:amazonses.com ~all',
  ['v=spf1 include:amazonses.com ~all', 'v=spf1 -all'])
#=> [['v=spf1 include:amazonses.com ~all', 'v=spf1 -all'], true]

## One DMARC record plus unrelated TXT junk: junk is discarded, not ambiguous
@matcher.select_txt_record_set('TXT', 'v=DMARC1;p=none', ['v=DMARC1; p=none;', 'google-site-verification=abc123'])
#=> [['v=DMARC1; p=none;'], false]

## Zero survivors keeps not-found semantics (no candidates, not ambiguous)
@matcher.select_txt_record_set('TXT', 'v=DMARC1;p=none', ['google-site-verification=abc123'])
#=> [[], false]

## Opaque-token expectations have no discriminator: full set passes through
@matcher.select_txt_record_set('TXT', 'token-abc', ['token-abc', 'other-token'])
#=> [['token-abc', 'other-token'], false]

## Non-TXT types pass through unfiltered, never ambiguous
@matcher.select_txt_record_set('CNAME', 'target.example.com', ['a.example.com.', 'b.example.com.'])
#=> [['a.example.com.', 'b.example.com.'], false]

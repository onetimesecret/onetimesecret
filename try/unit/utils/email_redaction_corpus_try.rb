# try/unit/utils/email_redaction_corpus_try.rb
#
# frozen_string_literal: true

# EMAIL REDACTION INVARIANT — the shared-corpus suite (Ruby half).
#
# THE INVARIANT
#   Every address the VALIDATOR accepts must be redacted by EVERY redactor.
#   The validator (Truemail's REGEX_EMAIL_PATTERN) defines what is STORABLE.
#   A redactor narrower than the validator prints stored data in the clear —
#   that is not a cosmetic gap, it is a leak by construction.
#
# THE LEAK THIS SUITE EXISTS TO CATCH
#   `josé@example.com` is accepted by Truemail (storable) and was matched by
#   NONE of the redactors, so it printed in the clear on operator terminals and
#   rode out to Sentry. Both redactors below are now Unicode-widened. If either
#   is ever narrowed again, THIS FILE goes red and names the address.
#
# THE THREE IMPLEMENTATIONS (two are Ruby and live here; the third is TS)
#   A  Onetime::Utils.obscure_email                — lib/onetime/utils/strings.rb
#      PARTIAL, shape-preserving mask for operator output
#      (`user@example.com` -> `us***@e***.com`). Must stay human-correlatable.
#   B  Onetime::Initializers::SetupDiagnostics     — lib/onetime/initializers/setup_diagnostics.rb
#      FULL sentinel replacement for Sentry payloads. Must leak nothing.
#   TS src/plugins/core/diagnostics/scrubbers.ts   — deliberate mirror of B.
#      Its own contract assertions live in
#      src/tests/plugins/core/diagnostics/emailRedactionCorpus.spec.ts, which
#      reads THE SAME corpus file. This file asserts the literal parity from
#      the Ruby side too, so a Ruby-only CI lane still catches a one-sided edit.
#
# ONE SPECIFICATION, THREE OUTPUT CONTRACTS. A and B are deliberately NOT
# expected to produce the same output — only B and its TS twin are. Do not
# "unify" them.
#
# THE CORPUS
#   tests/fixtures/email_redaction_corpus.json — language-neutral DATA ONLY, no
#   expected output strings. Each entry carries `kind` and `contains`; each
#   language derives its own expectations from those. Add a shape there and
#   both languages pick it up automatically.
#
# WHY TRYOUTS AND NOT RSPEC
#   These are pure functions with no datastore, no boot and no fixtures — the
#   shape try/unit/utils/utils_try.rb already covers for strings.rb. Redactor B
#   also has an rspec home (spec/unit/onetime/initializers/setup_diagnostics_spec.rb)
#   covering the initializer's Sentry wiring; the corpus invariant is deliberately
#   kept in ONE file across both redactors so the specification cannot drift
#   between two suites.
#
# HOW FAILURES READ
#   Each case returns an array of violation strings and expects []. A failure
#   prints the array, and every string names the entry id, the exact address,
#   the redactor, and the observed output. `expected [] got [...]` on a 30-entry
#   corpus with no detail is what this format exists to avoid.

require 'json'
require_relative '../../support/test_helpers'

# Redaction contracts derived from the shared corpus.
#
# Namespaced in a module rather than defined as bare top-level methods so the
# helpers cannot collide with tryouts' shared context or with another try file.
module EmailRedactionCorpus
  module_function

  CORPUS_PATH = File.join(Onetime::HOME, 'tests', 'fixtures', 'email_redaction_corpus.json')

  # Redactor A: partial mask. Pattern is asserted directly (not just the
  # public method) because a MATCH is the invariant; the mask is the contract.
  A_PATTERN = Onetime::Utils::Strings::EMAIL_PATTERN

  # Redactor B: full sentinel. EMAIL_PATTERN is defined inside `class << self`,
  # so it is a constant on the singleton class.
  B_MODULE  = Onetime::Initializers::SetupDiagnostics
  B_PATTERN = B_MODULE.singleton_class::EMAIL_PATTERN

  # Mirror sources, read from disk rather than re-typed, so these assertions
  # test what actually ships.
  RUBY_B_SOURCE_FILE = File.join(Onetime::HOME, 'lib', 'onetime', 'initializers', 'setup_diagnostics.rb')
  TS_TWIN_SOURCE_FILE = File.join(Onetime::HOME, 'src', 'plugins', 'core', 'diagnostics', 'scrubbers.ts')

  # The addresses that actually leaked. Pinned by literal so that deleting them
  # from the corpus turns this suite RED instead of quietly green — an eroded
  # corpus is the one failure mode a corpus-driven suite cannot self-detect.
  HISTORICAL_LEAKS = [
    'josé@example.com',
    'JOSÉ@EXAMPLE.COM',
    '用户@example.com',
    'пользователь@example.com',
    'user@пример.рф',
    'user@example.онлайн',
    'user@mail.пример.рф',
  ].freeze

  def corpus
    @corpus ||= JSON.parse(File.read(CORPUS_PATH))
  end

  def entries
    corpus['entries']
  end

  # Entries whose addresses MUST be redacted: the validator accepts them
  # (kind=accepted), or accepts addresses inside them (kind=embedded).
  def must_redact
    entries.select { |e| !e['contains'].nil? && !e['contains'].empty? }
  end

  # Entries the validator REJECTS. Not storable, so redacting them costs
  # operators signal for no privacy gain: they must pass through UNCHANGED.
  # kind=informational is deliberately excluded — the corpus states those are
  # unasserted, and over-redacting them would be harmless.
  def must_not_redact
    entries.select { |e| e['kind'] == 'rejected' }
  end

  # Derived, not hardcoded: whatever redactor B actually substitutes today.
  # Changing the sentinel in setup_diagnostics.rb changes this, and the
  # cross-language sentinel assertion below then goes red.
  def sentinel
    @sentinel ||= B_MODULE.scrub_text('user@example.com')
  end

  def redact_a(text) = Onetime::Utils.obscure_email(text)
  def redact_b(text) = text.gsub(B_PATTERN, sentinel)

  def local_part(address)  = address.rpartition('@').first
  def first_domain_label(address) = address.rpartition('@').last.split('.').first

  # The head exemption, read off the corpus entry — NEVER inferred from the
  # length of whatever we happened to get back. `mask_string_head` (strings.rb)
  # returns its input unchanged when length <= keep_head (2 for the local part,
  # 1 for the domain host), so some addresses are DELIBERATELY left in the clear
  # by redactor A. An "or it was too short" escape hatch would swallow a real
  # regression the moment a mask stopped applying; keying off the corpus flag
  # means the exemption only ever applies where a human wrote it down.
  def exempt?(entry, part)
    entry.fetch('partial_mask_head_exempt', {})[part] == true
  end

  def violation(redactor, entry, address, detail)
    "LEAK/[#{redactor}] entry=#{entry['id']} address=#{address.inspect} — #{detail}"
  end

  # Collapses a violation list into ONE front-loaded string, and that shape is
  # load-bearing, not cosmetic.
  #
  # Tryouts' `--agent` formatter (the default mode here per TESTING.md) renders
  # an Array actual as `got [, ...7 more]` — it drops the elements. A 30-entry
  # corpus failing with `expected [], got [, ...7 more]` tells the next person
  # nothing at 2am, which is exactly the failure mode this suite exists to
  # avoid. A String actual is printed head-first, so the redactor and the
  # offending addresses are put in the first ~120 characters and survive any
  # truncation; the per-violation detail follows for `try -vf`.
  #
  # @return [String] '' when there are no violations
  def report(label, violations)
    return '' if violations.empty?

    addresses = violations.filter_map { |v| v[/address=("[^"]*")/, 1] }.uniq
    head      = "#{violations.size} FAILURE(S) — #{label}"
    head     += " — addresses: #{addresses.join(', ')}" unless addresses.empty?
    ([head] + violations).join("\n  ")
  end

  # ---------------------------------------------------------------- corpus

  def corpus_integrity_violations
    v = []
    v << "corpus has no entries at #{CORPUS_PATH}" if entries.nil? || entries.empty?
    entries.each do |e|
      %w[id input kind truemail_accepts contains].each do |key|
        v << "entry #{e['id'].inspect} is missing required key #{key.inspect}" unless e.key?(key)
      end
    end
    HISTORICAL_LEAKS.each do |address|
      hit = entries.find { |e| e['input'] == address && e['kind'] == 'accepted' }
      next if hit

      v << "CORPUS EROSION: #{address.inspect} is one of the addresses that actually leaked, " \
           'and it is no longer in the corpus as kind=accepted. Restore it — deleting a shape ' \
           'from the corpus silences every assertion in both languages.'
    end
    # kind=informational may only ever hold validator-REJECTED, contains-empty
    # shapes. It exists to record don't-care over-redaction; a storable address
    # downgraded to informational (with contains emptied) would be unasserted in
    # BOTH languages — the one route by which this category could swallow a leak.
    entries.select { |e| e['kind'] == 'informational' }.each do |e|
      if e['truemail_accepts'] != false
        v << "entry #{e['id'].inspect} is kind=informational but truemail_accepts=" \
             "#{e['truemail_accepts'].inspect} — a storable address must be kind=accepted " \
             'so its redaction is asserted; informational is only for validator-rejected shapes.'
      end
      unless e['contains'].nil? || e['contains'].empty?
        v << "entry #{e['id'].inspect} is kind=informational but lists contains=" \
             "#{e['contains'].inspect} — must_redact keys off contains, so this entry " \
             'would be asserted by the leak suites while every kind-filtered suite skips ' \
             'it. Make it accepted/embedded, or empty contains.'
      end
    end
    v
  end

  # ------------------------------------------------- redactor A (partial mask)

  # The invariant proper: redactor A's pattern must MATCH every storable
  # address. Asserted separately from the mask because for a head-exempt
  # address the mask is a documented no-op — matching is the only observable
  # that distinguishes "matched, mask declined" from "never matched at all".
  def a_match_violations
    must_redact.flat_map do |entry|
      found = entry['input'].scan(A_PATTERN)
      entry['contains'].reject { |addr| found.include?(addr) }.map do |addr|
        violation('A obscure_email', entry, addr,
                  'NOT MATCHED by Onetime::Utils::Strings::EMAIL_PATTERN. The validator accepts ' \
                  'this address, so it is storable, and an unmatched address is printed in full. ' \
                  "scan returned #{found.inspect} for input #{entry['input'].inspect}")
      end
    end
  end

  # Nothing beyond the corpus addresses may be swallowed.
  def a_no_over_match_violations
    entries.flat_map do |entry|
      next [] unless %w[accepted embedded rejected].include?(entry['kind'])

      found = entry['input'].scan(A_PATTERN)
      extra = found - entry['contains']
      next [] if extra.empty?

      [violation('A obscure_email', entry, entry['input'],
                 "matched #{extra.inspect}, which the validator does NOT accept. Over-redaction " \
                 'blinds operators to ops-useful text (hostnames, version strings, at-rules).')]
    end
  end

  def a_mask_shape_violations
    must_redact.flat_map do |entry|
      entry['contains'].flat_map do |addr|
        masked        = redact_a(addr)
        local         = local_part(addr)
        label         = first_domain_label(addr)
        local_exempt  = exempt?(entry, 'local')
        host_exempt   = exempt?(entry, 'host')
        v             = []

        if local_exempt
          # Pin the exemption exactly rather than skipping: if mask_string_head
          # ever starts masking a 1-2 char local part, the corpus flag is stale
          # and must be updated deliberately, not silently tolerated.
          unless masked.start_with?("#{local}@")
            v << violation('A obscure_email', entry, addr,
                           "corpus marks the LOCAL part head-exempt (<= #{Onetime::Utils::Strings::EMAIL_MASK_MIN_LOCAL} chars, " \
                           "left in the clear by mask_string_head) but obscure_email returned #{masked.inspect}, " \
                           "which does not start with #{local.inspect}. The exemption in the corpus is now stale.")
          end
        elsif masked.include?(local)
          v << violation('A obscure_email', entry, addr,
                         "the LOCAL part #{local.inspect} survived verbatim in #{masked.inspect}")
        end

        if host_exempt
          unless masked.include?("@#{label}.")
            v << violation('A obscure_email', entry, addr,
                           'corpus marks the HOST head-exempt (<= 1 char, left in the clear by ' \
                           "mask_string_head) but obscure_email returned #{masked.inspect}, which does " \
                           "not carry #{label.inspect} unmasked. The exemption in the corpus is now stale.")
          end
        elsif masked.include?(label)
          v << violation('A obscure_email', entry, addr,
                         "the HOST label #{label.inspect} survived verbatim in #{masked.inspect}")
        end

        if local_exempt && host_exempt
          # Documented no-op. Asserted as an EQUALITY so this entry can never be
          # mistaken for evidence that matching occurred (it is the corpus's own
          # trap for a test that conflates "unmasked" with "unmatched").
          unless masked == addr
            v << violation('A obscure_email', entry, addr,
                           'corpus marks BOTH parts head-exempt, so obscure_email is a documented ' \
                           "no-op here, but it returned #{masked.inspect}. Update the corpus flag deliberately.")
          end
        else
          unless masked.include?(Onetime::Utils::Strings::EMAIL_MASK_CHAR * Onetime::Utils::Strings::EMAIL_MASK_LENGTH)
            v << violation('A obscure_email', entry, addr,
                           "no mask characters in #{masked.inspect} — the shape-preserving mask did not apply")
          end
          if masked == addr
            v << violation('A obscure_email', entry, addr,
                           'returned BYTE-IDENTICAL to the input address and the corpus marks no head ' \
                           'exemption for it — the address printed in the clear')
          end
        end

        v
      end
    end
  end

  # Whole-input behaviour: masking each address in isolation and substituting it
  # back must reproduce what obscure_email does to the full string. This is what
  # pins the embedded/free-text cases — surrounding text must survive intact.
  def a_whole_input_violations
    must_redact.filter_map do |entry|
      expected = entry['contains'].reduce(entry['input']) { |acc, addr| acc.gsub(addr, redact_a(addr)) }
      actual   = redact_a(entry['input'])
      next if actual == expected

      violation('A obscure_email', entry, entry['input'],
                "expected #{expected.inspect} (each contained address replaced by its own mask, " \
                "surrounding text untouched) but got #{actual.inspect}")
    end
  end

  def a_negative_violations
    must_not_redact.filter_map do |entry|
      actual = redact_a(entry['input'])
      next if actual == entry['input']

      violation('A obscure_email', entry, entry['input'],
                "OVER-REDACTED: the validator REJECTS this, so it is not storable and must pass " \
                "through unchanged, but obscure_email returned #{actual.inspect}. #{entry['probes']}")
    end
  end

  # ------------------------------------------------ redactor B (full sentinel)

  def b_violations
    must_redact.flat_map do |entry|
      actual   = redact_b(entry['input'])
      expected = entry['contains'].reduce(entry['input']) { |acc, addr| acc.gsub(addr, sentinel) }
      v        = []

      entry['contains'].each do |addr|
        next unless actual.include?(addr)

        v << violation('B setup_diagnostics', entry, addr,
                       "survived VERBATIM in the Sentry-bound output #{actual.inspect}. Redactor B has " \
                       'no head exemption: it must leak nothing.')
      end

      unless actual.include?(sentinel)
        v << violation('B setup_diagnostics', entry, entry['input'],
                       "no #{sentinel} sentinel in #{actual.inspect} — nothing was redacted at all")
      end

      if actual != expected
        v << violation('B setup_diagnostics', entry, entry['input'],
                       "expected #{expected.inspect} (each contained address replaced by the sentinel, " \
                       "surrounding text untouched) but got #{actual.inspect}")
      end

      v
    end
  end

  def b_negative_violations
    must_not_redact.filter_map do |entry|
      actual = redact_b(entry['input'])
      next if actual == entry['input']

      violation('B setup_diagnostics', entry, entry['input'],
                "OVER-REDACTED: the validator REJECTS this, so it is not storable and must pass " \
                "through unchanged, but redactor B returned #{actual.inspect}. #{entry['probes']}")
    end
  end

  # End-to-end through the public entry point, not just the pattern. scrub_text
  # runs the path and named-param passes too, so this proves no earlier pass
  # eats an address's '@' and leaves the rest readable.
  def b_public_entrypoint_violations
    must_redact.flat_map do |entry|
      actual = B_MODULE.scrub_text(entry['input'])
      entry['contains'].filter_map do |addr|
        next unless actual.include?(addr)

        violation('B setup_diagnostics.scrub_text', entry, addr,
                  "survived VERBATIM through the public entry point: #{actual.inspect}")
      end
    end
  end

  # ------------------------------------------------------- cross-language mirror

  def ts_twin_literal
    line = File.readlines(TS_TWIN_SOURCE_FILE).find { |l| l.start_with?('export const EMAIL_PATTERN') }
    return nil if line.nil?

    line.match(%r{=\s*/(?<source>.*)/(?<flags>[a-z]*);\s*\z})
  end

  # Every sentinel the TS twin substitutes for EMAIL_PATTERN. scrubbers.ts has
  # THREE substitution sites (free text, query values, URLs); renaming one and
  # not the others is drift that a single `include?` check would miss, so this
  # returns them de-duplicated and the assertion demands exactly one value.
  def ts_twin_sentinels
    File.read(TS_TWIN_SOURCE_FILE).scan(/replace\(EMAIL_PATTERN,\s*'([^']*)'\)/).flatten.uniq
  end

  def ruby_b_literal
    line = File.readlines(RUBY_B_SOURCE_FILE).find { |l| l =~ /^\s*EMAIL_PATTERN\s*=\s*%?r?/ }
    return nil if line.nil?

    line.match(%r{=\s*/(?<source>.*)/\s*\z})
  end
end

## CORPUS: loads, carries the keys both languages read, and still holds every address that leaked
EmailRedactionCorpus.report('corpus integrity', EmailRedactionCorpus.corpus_integrity_violations)
#=> ''

## CORPUS: every entry lands in exactly one direction, and neither direction is empty
## (deliberately NOT a hardcoded count — adding a shape to the corpus must extend both
## languages' suites automatically, not turn this file red for growing)
[
  EmailRedactionCorpus.must_redact.size.positive?,
  EmailRedactionCorpus.must_not_redact.size.positive?,
  EmailRedactionCorpus.must_redact.size +
    EmailRedactionCorpus.must_not_redact.size +
    EmailRedactionCorpus.entries.count { |e| e['kind'] == 'informational' } ==
    EmailRedactionCorpus.entries.size,
]
#=> [true, true, true]

## REDACTOR B: its sentinel is derived from the shipped code, not hardcoded in this file
EmailRedactionCorpus.sentinel
#=> '[EMAIL_REDACTED]'

## INVARIANT / REDACTOR A: matches every address the validator accepts (goes red on the josé@example.com leak)
EmailRedactionCorpus.report('redactor A (obscure_email) did not MATCH a storable address',
                            EmailRedactionCorpus.a_match_violations)
#=> ''

## REDACTOR A: masks the non-exempt parts, and the corpus-flagged head exemptions hold exactly
EmailRedactionCorpus.report('redactor A (obscure_email) mask shape',
                            EmailRedactionCorpus.a_mask_shape_violations)
#=> ''

## REDACTOR A: masks each address in place and leaves the surrounding free text intact
EmailRedactionCorpus.report('redactor A (obscure_email) whole-input rendering',
                            EmailRedactionCorpus.a_whole_input_violations)
#=> ''

## NEGATIVE / REDACTOR A: passes through unchanged everything the validator rejects
EmailRedactionCorpus.report('redactor A (obscure_email) over-redacted a validator-rejected shape',
                            EmailRedactionCorpus.a_negative_violations)
#=> ''

## NEGATIVE / REDACTOR A: matches nothing beyond the addresses the corpus lists
EmailRedactionCorpus.report('redactor A (obscure_email) matched more than the corpus lists',
                            EmailRedactionCorpus.a_no_over_match_violations)
#=> ''

## INVARIANT / REDACTOR B: fully replaces every address the validator accepts (goes red on the josé@example.com leak)
EmailRedactionCorpus.report('redactor B (setup_diagnostics) leaked a storable address',
                            EmailRedactionCorpus.b_violations)
#=> ''

## REDACTOR B: leaks nothing through its public entry point (scrub_text) either
EmailRedactionCorpus.report('redactor B (setup_diagnostics.scrub_text) leaked a storable address',
                            EmailRedactionCorpus.b_public_entrypoint_violations)
#=> ''

## NEGATIVE / REDACTOR B: passes through unchanged everything the validator rejects
EmailRedactionCorpus.report('redactor B (setup_diagnostics) over-redacted a validator-rejected shape',
                            EmailRedactionCorpus.b_negative_violations)
#=> ''

## MIRROR: redactor B's pattern is byte-identical to its TS twin in scrubbers.ts (flags are the only difference)
[
  EmailRedactionCorpus.ts_twin_literal&.[](:source),
  EmailRedactionCorpus.ts_twin_literal&.[](:flags),
]
#=> [EmailRedactionCorpus::B_PATTERN.source, 'gu']

## MIRROR: the Ruby literal this suite exercised is the one that ships in setup_diagnostics.rb
EmailRedactionCorpus.ruby_b_literal&.[](:source)
#=> EmailRedactionCorpus::B_PATTERN.source

## MIRROR: EVERY TS substitution site uses redactor B's sentinel (scrubbers.ts has three; a partial rename is drift)
EmailRedactionCorpus.ts_twin_sentinels
#=> [EmailRedactionCorpus.sentinel]

# spec/unit/onetime/models/customer_verified_predicate_guard_spec.rb
#
# frozen_string_literal: true

# =============================================================================
# TEST TYPE: Static guard: no new calls to the deprecated Customer predicates
# =============================================================================
#
# Customer#verified? was renamed to #account_verified?, and #email_verified?
# to #verified_by_email_link?. Both old names stay as deprecated aliases
# (lib/onetime/models/customer/features/status.rb). "verified?" alone reads
# as mailbox proof, which it is not: any verified_by provenance satisfies it
# (see Customer#mailbox_verified? for the stricter rule).
#
# CustomDomain::MailerConfig, BulkAuditContext and SsoProvider issuer
# validation also define verified?, so the scan cannot refuse every
# `.verified?`. It flags:
#
#   1. `.verified?` / `.email_verified?` on a receiver whose name ends in a
#      customer word (cust, customer, owner, user, principal, member,
#      colonel), with or without @ or a prefix (`invitee_customer`).
#   2. `.email_verified?` on any receiver, and the symbol `:email_verified?`.
#      No other model defines it (oidc_email_verified? is a different name).
#   3. Dynamic forms of `:verified?`: `&:verified?`, send/public_send,
#      method, respond_to?.
#   4. Implicit-self `verified?` / `email_verified?` inside
#      lib/onetime/models/customer/, where self is a Customer.
#
# Limits: a Customer held in a variable with another name (`record`,
# `account`, `target`) passes, as does an implicit-self call from a module
# mixed into Customer outside lib/onetime/models/customer/. Comment lines
# are skipped. A line that is not about a customer can carry the marker
# `# verified-predicate: not a customer` to be skipped.
#
# =============================================================================

require 'spec_helper'

RSpec.describe 'Customer deprecated verification predicate guard' do
  GUARD_ROOT     = File.expand_path('../../../..', __dir__)
  GUARD_GLOBS    = %w[apps/**/*.rb lib/**/*.rb].freeze
  GUARD_EXCLUDED = %r{/(spec|try)/}
  GUARD_MARKER   = '# verified-predicate: not a customer'
  CUSTOMER_DIR   = 'lib/onetime/models/customer/'

  RECEIVER_CALL = /
    (?: \b | @ ) \w*? (?:cust|customer|owner|user|principal|member|colonel)
    (?: \)? &? \. ) (?:email_)?verified\? (?![\w?])
  /xi

  ANY_EMAIL_VERIFIED = /(?:\.|:)email_verified\?(?![\w?])/

  DYNAMIC_VERIFIED = /
    &:verified\? (?![\w?])
    | \b(?:send|public_send|__send__|method|respond_to\?)\s*\(?\s*:verified\? (?![\w?])
  /x

  IMPLICIT_SELF = /(?<![\w.:&@])(?:email_)?verified\?(?![\w?:])/

  def guard_source_files
    # Matched on the repo-relative path, so a checkout under a directory
    # named spec/ or try/ is still scanned.
    GUARD_GLOBS.flat_map { |glob| Dir.glob(File.join(GUARD_ROOT, glob)) }
               .reject { |path| "/#{path.delete_prefix("#{GUARD_ROOT}/")}".match?(GUARD_EXCLUDED) }
  end

  def offending?(line, in_customer_dir:)
    stripped = line.strip
    return false if stripped.start_with?('#')
    return false if line.include?(GUARD_MARKER)
    # The definitions themselves.
    return false if in_customer_dir && stripped.match?(/\A(?:def|alias|alias_method)\s/)
    return true if line.match?(RECEIVER_CALL) || line.match?(ANY_EMAIL_VERIFIED) || line.match?(DYNAMIC_VERIFIED)

    in_customer_dir && line.match?(IMPLICIT_SELF)
  end

  it 'scans the customer model and the call sites (non-empty file set)' do
    relatives = guard_source_files.map { |path| path.delete_prefix("#{GUARD_ROOT}/") }
    expect(relatives).to include('lib/onetime/models/customer/features/status.rb',
                                 'lib/onetime/jobs/scheduled/expiration_warning_job.rb')
  end

  it 'finds no calls to Customer#verified? or #email_verified? in lib/ and apps/' do
    offenses = guard_source_files.flat_map do |path|
      relative        = path.delete_prefix("#{GUARD_ROOT}/")
      in_customer_dir = relative.start_with?(CUSTOMER_DIR)
      File.read(path, encoding: 'UTF-8').each_line.with_index(1).filter_map do |line, lineno|
        "#{relative}:#{lineno}: #{line.strip}" if offending?(line, in_customer_dir: in_customer_dir)
      end
    end

    expect(offenses).to be_empty, <<~MSG
      Customer#verified? and #email_verified? are deprecated aliases. Call
      #account_verified? (any provenance) or #mailbox_verified? (proof of
      mailbox control), and #verified_by_email_link? for the 'email' stamp.
      If the receiver is not a Customer, add the marker
      `#{GUARD_MARKER}` to the line.

      #{offenses.join("\n")}
    MSG
  end

  it 'flags the deprecated forms and leaves other receivers alone (pattern self-test)' do
    flagged_anywhere = [
      'cust.verified?',
      'return unless @customer.verified?',
      'verified: this_cust.verified?,',
      'owner&.verified?',
      'invitee_customer.verified?',
      'user.email_verified?',
      'record.email_verified?',
      'customers.select(&:verified?)',
      'cust.send(:verified?)',
      'cust.public_send(:verified?)',
      'cust.respond_to?(:verified?)',
      'base.safe_dump_field :verified, ->(cust) { cust.verified? }',
    ]
    not_flagged_anywhere = [
      'cust.account_verified?',
      'cust.mailbox_verified?',
      'cust.stored_verified?',
      'cust.verified_by_email_link?',
      'sender_config&.enabled? && sender_config.verified?',
      'verified: config.verified?,',
      'Onetime::Operations::BulkAuditContext.verified?(',
      'oidc_email_verified?(account)',
      'unless password_verified?',
      'domain_record.verified?',
      "cust.verified == 'true'",
      "cust.verified? # #{GUARD_MARKER}",
      '# cust.verified? in a comment',
    ]
    in_customer_dir_only = [
      'verified? && verified_by.to_s == "email"',
      '!anonymous? && !verified? && role?("customer")',
    ]
    customer_dir_definitions = [
      'def verified?',
      'alias verified? account_verified?',
      'alias_method :verified?, :account_verified?',
      'alias_method :email_verified?, :verified_by_email_link?',
      'def stored_verified?',
      '!anonymous? && account_verified?',
    ]

    misses = (flagged_anywhere.reject { |l| offending?(l, in_customer_dir: false) } +
              in_customer_dir_only.reject { |l| offending?(l, in_customer_dir: true) })
    expect(misses).to be_empty, "guard failed to flag: #{misses.inspect}"

    false_positives = not_flagged_anywhere.select { |l| offending?(l, in_customer_dir: false) } +
                      in_customer_dir_only.select { |l| offending?(l, in_customer_dir: false) } +
                      customer_dir_definitions.select { |l| offending?(l, in_customer_dir: true) }
    expect(false_positives).to be_empty, "guard wrongly flagged: #{false_positives.inspect}"
  end
end

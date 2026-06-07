# spec/unit/onetime/locales/api_error_keys_spec.rb
#
# frozen_string_literal: true

require 'spec_helper'
require 'json'
require 'set'

# Lockdown spec for the api.organizations.* and api.invite.* error_key
# namespaces — the equivalent of entitlement_keys_spec.rb but for the
# explicitly-hardcoded keys at form/invite call sites rather than
# auto-derived ones.
#
# The HTTP-edge resolver falls back to the pre-set English message when
# I18n.t can't find a key, so a typo like
#   raise_form_error(error_key: 'api.organizations.errors.display_naem_required')
# wouldn't break the response — it would silently render the English
# fallback instead of the localized text. This spec catches that drift
# by asserting the locale file and the call sites stay in sync in both
# directions.
#
# Code references are extracted from apps/ and lib/ at test time via a
# line-by-line regex. Pure-comment lines are skipped so docstring
# examples (e.g. the FormError shape comment in lib/onetime/errors.rb
# and the helper docstring in authorization_policies.rb) don't show up
# as references.

RSpec.describe 'API error_key locale coverage' do
  CODE_REFERENCE_RE = /error_key:\s*['"]([a-zA-Z0-9._]+)['"]/.freeze

  # Walk apps/ and lib/ once per example group, collect every error_key
  # literal that appears outside a pure-comment line. Downstream describes
  # filter this by namespace prefix.
  let(:all_code_keys) do
    keys = Set.new
    Dir.glob(File.join(Onetime::HOME, '{apps,lib}', '**', '*.rb')).each do |file|
      File.readlines(file, chomp: true).each do |line|
        next if line.lstrip.start_with?('#')
        line.scan(CODE_REFERENCE_RE) { |match| keys << match[0] }
      end
    end
    keys
  end

  def locale_keys(filename)
    path = File.join(Onetime::HOME, 'locales', 'content', 'en', filename)
    Set.new(JSON.parse(File.read(path)).keys)
  end

  shared_examples 'a locale file in sync with code' do |prefix:, locale_filename:|
    let(:code_keys)        { all_code_keys.select { |k| k.start_with?(prefix) }.to_set }
    let(:locale_file_keys) { locale_keys(locale_filename) }

    it "has a locale entry for every #{prefix}* error_key referenced in code" do
      missing = code_keys - locale_file_keys
      expect(missing).to be_empty,
        "Missing locale entries in #{locale_filename} for: #{missing.to_a.sort.inspect}. " \
        "Add them or fix the typo at the call site."
    end

    it "has no orphaned #{prefix}* entries (every locale key has a call site)" do
      orphaned = locale_file_keys - code_keys
      expect(orphaned).to be_empty,
        "Locale entries in #{locale_filename} with no matching call site: " \
        "#{orphaned.to_a.sort.inspect}. Remove them or restore the call site."
    end
  end

  describe 'api.organizations.* (api-organizations-errors.json)' do
    include_examples 'a locale file in sync with code',
      prefix: 'api.organizations.', locale_filename: 'api-organizations-errors.json'
  end

  describe 'api.invite.* (api-invite-errors.json)' do
    include_examples 'a locale file in sync with code',
      prefix: 'api.invite.', locale_filename: 'api-invite-errors.json'
  end

  describe 'api.account.* (api-account-errors.json)' do
    include_examples 'a locale file in sync with code',
      prefix: 'api.account.', locale_filename: 'api-account-errors.json'
  end
end

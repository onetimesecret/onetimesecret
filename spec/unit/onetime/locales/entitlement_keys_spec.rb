# spec/unit/onetime/locales/entitlement_keys_spec.rb
#
# frozen_string_literal: true

require 'spec_helper'
require 'json'
require 'onetime/models/features/with_entitlements'

# Lockdown spec for the auto-derivation convention.
#
# `Onetime::Logic::Base#require_entitlement!` and
# `Onetime::Incoming::RecipientResolver#require_domain_entitlement!` derive
# their I18n error_key as "api.entitlements.errors.#{entitlement}_required".
# Renaming an entitlement (e.g. :custom_domains -> :custom_domain) or adding
# a new one without updating locales would silently break the lookup and
# fall back to the legacy English message.
#
# This spec enforces that the locale file stays in sync with the canonical
# entitlement list in WithEntitlements::STANDALONE_ENTITLEMENTS. It uses the
# constant directly (rather than a hardcoded list) so that any change to the
# entitlement set forces a corresponding locale update.
RSpec.describe 'api.entitlements.errors locale keys' do
  locale_path = File.join(
    Onetime::HOME, 'locales', 'content', 'en', 'api-entitlements-errors.json',
  )

  let(:locale_keys) { JSON.parse(File.read(locale_path)).keys }
  let(:entitlements) do
    Onetime::Models::Features::WithEntitlements::STANDALONE_ENTITLEMENTS
  end

  it 'has a context_unavailable system-error key' do
    expect(locale_keys).to include('api.entitlements.errors.context_unavailable')
  end

  it 'has a <name>_required key for every STANDALONE_ENTITLEMENTS entry' do
    missing = entitlements.reject do |entitlement|
      locale_keys.include?("api.entitlements.errors.#{entitlement}_required")
    end

    expect(missing).to be_empty,
      "Missing api.entitlements.errors.<name>_required keys for: #{missing.inspect}. " \
      "Add them to locales/content/en/api-entitlements-errors.json."
  end

  it 'contains no stale api.entitlements.errors.* keys' do
    expected = entitlements.map { |e| "api.entitlements.errors.#{e}_required" }
    expected << 'api.entitlements.errors.context_unavailable'

    extras = locale_keys.select { |k| k.start_with?('api.entitlements.errors.') } - expected

    expect(extras).to be_empty,
      "Unexpected api.entitlements.errors.* keys (entitlement removed but key not cleaned up?): " \
      "#{extras.inspect}"
  end
end

# spec/unit/onetime/errors_spec.rb
#
# frozen_string_literal: true

require 'spec_helper'

# Unit tests for the i18n shape on Forbidden subclasses.
#
# Both LimitExceeded and GuestRoutesDisabled inherit error_key/args storage
# from Forbidden so that Onetime::Application::ErrorResolver can localize
# their messages at the HTTP edge. These tests are constructor-only — they
# don't exercise the resolver, only that the carriers propagate through
# initialize/to_h correctly.
#
# Mirrors the pattern used for EntitlementRequired (see
# spec/unit/onetime/logic/require_entitlement_spec.rb for context).

RSpec.describe Onetime::LimitExceeded do
  describe '#initialize' do
    it 'defaults to legacy message when none provided' do
      error = described_class.new
      expect(error.message).to eq('Rate limit exceeded')
    end

    it 'defaults error_key to nil so legacy callers stay untouched' do
      error = described_class.new
      expect(error.error_key).to be_nil
    end

    it 'defaults args to an empty hash' do
      error = described_class.new
      expect(error.args).to eq({})
    end

    it 'stores error_key when supplied' do
      error = described_class.new(error_key: 'api.limits.errors.too_many_attempts')
      expect(error.error_key).to eq('api.limits.errors.too_many_attempts')
    end

    it 'stores args when supplied' do
      error = described_class.new(args: { max: 5 })
      expect(error.args).to eq({ max: 5 })
    end

    it 'still accepts and stores rate-limit metadata' do
      error = described_class.new('blocked', retry_after: 60, attempts: 6, max_attempts: 5)
      expect(error.retry_after).to eq(60)
      expect(error.attempts).to eq(6)
      expect(error.max_attempts).to eq(5)
    end
  end

  describe '#to_h' do
    it 'includes error_key when present' do
      error = described_class.new(error_key: 'api.limits.errors.too_many_attempts')
      expect(error.to_h).to include(error_key: 'api.limits.errors.too_many_attempts')
    end

    it 'omits error_key when nil' do
      error = described_class.new
      expect(error.to_h).not_to have_key(:error_key)
    end

    it 'preserves pre-existing fields alongside error_key' do
      error = described_class.new(
        'blocked',
        retry_after: 60, attempts: 6, max_attempts: 5,
        error_key: 'api.limits.errors.too_many_attempts',
      )
      hash = error.to_h
      expect(hash[:error]).to eq('LimitExceeded')
      expect(hash[:message]).to eq('blocked')
      expect(hash[:retry_after]).to eq(60)
      expect(hash[:attempts]).to eq(6)
      expect(hash[:max_attempts]).to eq(5)
    end
  end
end

RSpec.describe Onetime::GuestRoutesDisabled do
  describe '#initialize' do
    it 'defaults to legacy message when none provided' do
      error = described_class.new
      expect(error.message).to eq('Guest API access is disabled')
    end

    it 'defaults error_key to nil so legacy callers stay untouched' do
      error = described_class.new
      expect(error.error_key).to be_nil
    end

    it 'defaults args to an empty hash' do
      error = described_class.new
      expect(error.args).to eq({})
    end

    it 'stores error_key when supplied' do
      error = described_class.new(error_key: 'api.guest.errors.routes_disabled')
      expect(error.error_key).to eq('api.guest.errors.routes_disabled')
    end

    it 'stores args when supplied' do
      error = described_class.new(args: { feature: 'create' })
      expect(error.args).to eq({ feature: 'create' })
    end

    it 'still accepts and stores the error code' do
      error = described_class.new('nope', code: 'CUSTOM_CODE')
      expect(error.code).to eq('CUSTOM_CODE')
    end
  end

  describe '#to_h' do
    it 'includes error_key when present' do
      error = described_class.new(error_key: 'api.guest.errors.routes_disabled')
      expect(error.to_h).to include(error_key: 'api.guest.errors.routes_disabled')
    end

    it 'omits error_key when nil' do
      error = described_class.new
      expect(error.to_h).not_to have_key(:error_key)
    end

    it 'preserves pre-existing fields alongside error_key' do
      error = described_class.new(
        'nope',
        code: 'CUSTOM_CODE',
        error_key: 'api.guest.errors.routes_disabled',
      )
      hash = error.to_h
      expect(hash[:message]).to eq('nope')
      expect(hash[:code]).to eq('CUSTOM_CODE')
    end
  end
end

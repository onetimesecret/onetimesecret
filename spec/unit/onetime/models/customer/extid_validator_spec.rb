# spec/unit/onetime/models/customer/extid_validator_spec.rb
#
# frozen_string_literal: true

# Pins Customer.extid? (Familia's external_identifier shape validator)
# against the extids the same feature actually mints.
#
# Why this exists: the validator extracts its prefix by splitting the
# declared format on the literal '%{id}'. The model used to declare the
# format in sprintf's '%<id>s' spelling — which interpolates identically,
# so minting worked, but the validator answered false for EVERY customer
# extid and did so silently. A format edit can reintroduce that skew
# without failing any minting test, so the round-trip is pinned here.
#
# Run with:
#   tests/lanes/run unit --only spec/unit/onetime/models/customer/extid_validator_spec.rb
require 'spec_helper'

RSpec.describe Onetime::Customer do
  describe '.extid?' do
    it 'accepts an extid the feature itself derives' do
      customer = described_class.new(email: 'extid-validator@example.com')

      extid = customer.extid

      expect(extid).to start_with('ur')
      expect(described_class.extid?(extid)).to be(true)
    end

    it 'refuses an email' do
      expect(described_class.extid?('someone@example.com')).to be(false)
    end

    it 'refuses a foreign-prefix extid' do
      expect(described_class.extid?('cd00fedcba9876543210zyxwvu')).to be(false)
    end

    it 'refuses nil and empty' do
      expect(described_class.extid?(nil)).to be(false)
      expect(described_class.extid?('')).to be(false)
    end
  end
end

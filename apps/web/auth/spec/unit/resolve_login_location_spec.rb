# apps/web/auth/spec/unit/resolve_login_location_spec.rb
#
# frozen_string_literal: true

# Unit tests for Auth::Operations::ResolveLoginLocation — the privacy-safe
# "location" resolver for new-login / MFA alert emails (#3989). Pure function:
# it must NEVER return a raw IP, only a country code, an already-masked IP, or
# the fallback string.
#
# Run:
#   bundle exec rspec apps/web/auth/spec/unit/resolve_login_location_spec.rb

require_relative '../spec_helper'
require_relative '../../operations/resolve_login_location'

RSpec.describe Auth::Operations::ResolveLoginLocation do
  describe '.call' do
    it 'returns the ISO alpha-2 country code when one is resolved' do
      expect(described_class.call(geo_country: 'US', masked_ip: '203.0.113.0')).to eq('US')
    end

    it 'upcases nothing but accepts a well-formed code as-is' do
      expect(described_class.call(geo_country: 'FR', masked_ip: '198.51.100.0')).to eq('FR')
    end

    it "falls back to the masked IP when the country is the '**' unknown sentinel" do
      expect(described_class.call(geo_country: '**', masked_ip: '203.0.113.0')).to eq('203.0.113.0')
    end

    it 'falls back to the masked IP when the country is nil' do
      expect(described_class.call(geo_country: nil, masked_ip: '203.0.113.0')).to eq('203.0.113.0')
    end

    it 'rejects a malformed country code and falls back to the masked IP' do
      expect(described_class.call(geo_country: 'USA', masked_ip: '203.0.113.0')).to eq('203.0.113.0')
      expect(described_class.call(geo_country: '12', masked_ip: '203.0.113.0')).to eq('203.0.113.0')
    end

    it 'returns the fallback string when neither a country nor a masked IP is available' do
      expect(described_class.call(geo_country: '**', masked_ip: nil)).to eq('Unknown location')
      expect(described_class.call(geo_country: nil, masked_ip: '')).to eq('Unknown location')
      expect(described_class.call(geo_country: nil, masked_ip: '   ')).to eq('Unknown location')
    end

    it 'prefers the country over the masked IP when both are present' do
      expect(described_class.call(geo_country: 'DE', masked_ip: '203.0.113.0')).to eq('DE')
    end
  end
end

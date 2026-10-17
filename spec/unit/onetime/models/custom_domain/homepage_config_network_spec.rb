# spec/unit/onetime/models/custom_domain/homepage_config_network_spec.rb
#
# frozen_string_literal: true

require 'spec_helper'

# HomepageConfig network rules — the allowed_cidrs / denied_cidrs lists and
# the per-visitor verdict (#network_allowed?) that the bootstrap serializer
# and CustomDomain#allow_public_secret_creation? both consume.
#
# The decision table itself (deny wins, empty allow = everyone not denied,
# no resolvable IP fails closed) belongs to Onetime::Utils::CidrList and is
# pinned in spec/unit/onetime/utils/cidr_list_spec.rb. This file covers what
# the MODEL adds around it: storage round-trip through the validating
# setters, typed refusals, the no-rules fast path, and every fail-closed
# case the stored record can get itself into (unreadable JSON, an entry
# that no longer parses, a request with no matcher). Pure in-memory
# records; Redis is never touched.
RSpec.describe Onetime::CustomDomain::HomepageConfig do
  subject(:config) { described_class.new(domain_id: 'domain123', enabled: 'true') }

  # A stand-in for env['otto.ip_match']: membership of ONE client IP.
  def matcher_for(ip)
    addr = IPAddr.new(ip)
    ->(ranges) { ranges.any? { |range| range.family == addr.family && range.include?(addr) } }
  end

  before { allow(OT).to receive(:le) }

  describe 'allowed_cidrs / denied_cidrs storage' do
    it 'reads an unset field as an empty list and is unrestricted' do
      expect(config.allowed_cidrs).to eq([])
      expect(config.denied_cidrs).to eq([])
      expect(config.network_restricted?).to be(false)
    end

    it 'normalizes and de-duplicates entries on write' do
      config.allowed_cidrs = ['10.1.2.3/8', ' 10.0.0.0/8 ', '2001:DB8::1']
      expect(config.allowed_cidrs).to eq(['10.0.0.0/8', '2001:db8::1/128'])
      expect(config.allowed_cidrs_json).to eq('["10.0.0.0/8","2001:db8::1/128"]')
      expect(config.network_restricted?).to be(true)
    end

    it 'stores an empty or nil list as nil (the cleared state)' do
      config.denied_cidrs = ['10.0.0.0/8']
      config.denied_cidrs = []
      expect(config.denied_cidrs_json).to be_nil
      config.denied_cidrs = ['10.0.0.0/8']
      config.denied_cidrs = nil
      expect(config.denied_cidrs_json).to be_nil
      expect(config.network_restricted?).to be(false)
    end

    it 'refuses an unparseable entry with a typed, field-tagged error' do
      expect { config.allowed_cidrs = ['10.0.0.0/8', 'example.com'] }
        .to raise_error(described_class::InvalidCidr) do |ex|
          expect(ex).to be_a(Onetime::Problem)
          expect(ex.field).to eq('allowed_cidrs')
          expect(ex.cidr).to eq('example.com')
          expect(ex.error_key).to eq('api.domains.errors.homepage_cidr_invalid')
          expect(ex.args).to eq({ cidr: 'example.com' })
        end
      # Nothing landed.
      expect(config.allowed_cidrs_json).to be_nil
    end

    it 'refuses more than MAX_CIDRS distinct ranges with a typed, field-tagged error' do
      too_many = (0..described_class::MAX_CIDRS).map { |i| "10.#{i / 256}.#{i % 256}.0/24" }
      expect { config.denied_cidrs = too_many }
        .to raise_error(described_class::TooManyCidrs) do |ex|
          expect(ex.field).to eq('denied_cidrs')
          expect(ex.max).to eq(described_class::MAX_CIDRS)
          expect(ex.error_key).to eq('api.domains.errors.homepage_cidrs_max_exceeded')
          expect(ex.args).to eq({ max: described_class::MAX_CIDRS })
        end
    end

    it 'declares both lists as colonel-writable string arrays' do
      expect(described_class::FIELD_SPECS['allowed_cidrs']).to eq({ type: :string_array })
      expect(described_class::FIELD_SPECS['denied_cidrs']).to eq({ type: :string_array })
    end
  end

  describe 'corrupt stored lists' do
    it 'reads unparseable JSON as [] for display but reports it corrupt and restricted' do
      config.allowed_cidrs_json = '{not json'
      expect(config.allowed_cidrs).to eq([])
      expect(config.allowed_cidrs_corrupt?).to be(true)
      expect(config.network_restricted?).to be(true)
      expect(config.validation_errors).to include('allowed_cidrs is unreadable')
    end

    it 'treats a JSON non-array as corrupt' do
      config.denied_cidrs_json = '{"cidr":"10.0.0.0/8"}'
      expect(config.denied_cidrs).to eq([])
      expect(config.denied_cidrs_corrupt?).to be(true)
      expect(config.validation_errors).to include('denied_cidrs is unreadable')
    end

    it 'does not call a well-formed empty array corrupt' do
      config.allowed_cidrs_json = '[]'
      expect(config.allowed_cidrs_corrupt?).to be(false)
      expect(config.network_restricted?).to be(false)
    end
  end

  describe '#network_allowed?' do
    context 'with no rules' do
      it 'admits everyone without a matcher and without logging' do
        expect(config.network_allowed?(nil)).to be(true)
        expect(config.network_allowed?('not callable')).to be(true)
        expect(OT).not_to have_received(:le)
      end
    end

    context 'with rules' do
      before { config.allowed_cidrs = ['10.0.0.0/8'] }

      it 'admits a client inside an allowed range' do
        expect(config.network_allowed?(matcher_for('10.1.2.3'))).to be(true)
      end

      it 'refuses a client outside every allowed range' do
        expect(config.network_allowed?(matcher_for('192.168.1.1'))).to be(false)
      end

      it 'lets a deny match win over the allow list' do
        config.denied_cidrs = ['10.1.0.0/16']
        expect(config.network_allowed?(matcher_for('10.1.2.3'))).to be(false)
        expect(config.network_allowed?(matcher_for('10.2.2.3'))).to be(true)
      end

      it 'fails closed, loudly, when the request carries no matcher' do
        expect(config.network_allowed?(nil)).to be(false)
        expect(OT).to have_received(:le).with(/no otto.ip_match closure; denying/)
      end

      it 'fails closed when the matcher itself raises, logging only the error class' do
        exploding = ->(_ranges) { raise ArgumentError, 'contains 203.0.113.9' }
        expect(config.network_allowed?(exploding)).to be(false)
        expect(OT).to have_received(:le).with(a_string_including('ArgumentError').and(satisfy { |m| !m.include?('203.0.113.9') }))
      end

      it 'fails closed when a stored entry no longer parses' do
        config.allowed_cidrs_json = '["10.0.0.0/8","junk"]'
        expect(config.network_allowed?(matcher_for('10.1.2.3'))).to be(false)
        expect(OT).to have_received(:le).with(/network match failed/)
      end

      it 'fails closed when a stored list is unreadable, even for a client the other list admits' do
        config.denied_cidrs_json = '{not json'
        expect(config.network_allowed?(matcher_for('10.1.2.3'))).to be(false)
        expect(OT).to have_received(:le).with(/unreadable/)
      end
    end
  end
end

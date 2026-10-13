# spec/unit/onetime/models/custom_domain/txt_validation_record_spec.rb
#
# frozen_string_literal: true

# The TXT ownership challenge: the record host and value from
# generate_txt_validation_record, and the full record name from
# validation_record, which every validation strategy queries.
#
# display_domain, trd and base_domain are stored as the customer typed them,
# so an internationalised name keeps its Unicode spelling. The challenge
# record name goes into the customer's DNS and to Approximated's
# check_records API, so it is built from A-labels.

require 'spec_helper'
require 'securerandom'

RSpec.describe Onetime::CustomDomain, 'TXT validation record' do
  let(:org_id) { 'org-txt-record' }

  def shortid(domain)
    domain.identifier.to_s[0..6]
  end

  describe '#generate_txt_validation_record' do
    context 'with a Unicode subdomain' do
      subject(:domain) { described_class.parse('bücher.example.com', org_id) }

      it 'builds the record host from the A-label form of the subdomain' do
        host, value = domain.generate_txt_validation_record

        expect([host, value]).to match(["_onetime-challenge-#{shortid(domain)}.xn--bcher-kva", /\A\h{32}\z/])
      end

      it 'keeps the display spelling of the domain parts' do
        domain.generate_txt_validation_record

        expect([domain.display_domain, domain.trd, domain.base_domain])
          .to eq(['bücher.example.com', 'bücher', 'example.com'])
      end

      it 'names the full record in A-labels' do
        domain.generate_txt_validation_record

        expect(domain.validation_record).to eq("_onetime-challenge-#{shortid(domain)}.xn--bcher-kva.example.com")
      end
    end

    context 'with a Unicode registrable domain' do
      subject(:domain) { described_class.parse('secrets.bücher.de', org_id) }

      it 'keeps the host relative to the base domain and names the full record in A-labels' do
        host, = domain.generate_txt_validation_record

        expect([host, domain.base_domain, domain.validation_record]).to eq(
          [
            "_onetime-challenge-#{shortid(domain)}.secrets",
            'bücher.de',
            "_onetime-challenge-#{shortid(domain)}.secrets.xn--bcher-kva.de",
          ],
        )
      end
    end

    context 'with an ASCII subdomain' do
      subject(:domain) { described_class.parse('status.www.example.com', org_id) }

      it 'is unchanged' do
        host, = domain.generate_txt_validation_record

        expect([host, domain.validation_record]).to eq(
          [
            "_onetime-challenge-#{shortid(domain)}.status.www",
            "_onetime-challenge-#{shortid(domain)}.status.www.example.com",
          ],
        )
      end
    end

    context 'with an apex domain' do
      subject(:domain) { described_class.parse('example.com', org_id) }

      it 'has no subdomain part' do
        host, = domain.generate_txt_validation_record

        expect([host, domain.validation_record])
          .to eq(["_onetime-challenge-#{shortid(domain)}", "_onetime-challenge-#{shortid(domain)}.example.com"])
      end
    end

    context 'when the challenge record name would not fit in 253 bytes' do
      # 232 bytes as a display domain, 259 as a challenge record name. Built
      # with new, not parse, so the generator's own check is what refuses it.
      subject(:domain) do
        described_class.new(display_domain: "#{(['a' * 63] * 3).join('.')}.#{'b' * 36}.com", org_id: org_id)
      end

      it 'refuses with a user-facing message and leaves no challenge behind' do
        expect { domain.generate_txt_validation_record }
          .to raise_error(Onetime::Problem, 'Domain too long for its TXT validation record')
        expect([domain.txt_validation_host, domain.txt_validation_value]).to eq([nil, nil])
      end
    end
  end

  describe '#validation_record' do
    subject(:domain) { described_class.new(display_domain: 'bücher.example.com', org_id: org_id) }

    it 'converts a record host stored with a Unicode subdomain label' do
      domain.txt_validation_host = '_onetime-challenge-abc1234.bücher'

      expect(domain.validation_record).to eq('_onetime-challenge-abc1234.xn--bcher-kva.example.com')
    end

    it 'is nil before a challenge is generated' do
      expect(domain.validation_record).to be_nil
    end

    it 'raises ConversionError for a stored name with no A-label form' do
      domain.txt_validation_host = "_onetime-challenge-abc1234.#{'ü' * 70}"

      expect { domain.validation_record }
        .to raise_error(Onetime::DomainValidation::AsciiHostname::ConversionError)
    end
  end

  describe '#validation_record_display' do
    it 'spells the record name like the display domain' do
      domain = described_class.parse('bücher.example.com', org_id)
      domain.generate_txt_validation_record

      expect(domain.validation_record_display).to eq("_onetime-challenge-#{shortid(domain)}.bücher.example.com")
    end

    it 'is nil before a challenge is generated' do
      expect(described_class.new(display_domain: 'bücher.example.com', org_id: org_id).validation_record_display).to be_nil
    end
  end

  # The fields the UI shows for the TXT record. txt_validation_host stays
  # relative to base_domain, which keeps its typed spelling, so the full
  # name comes from the backend in both spellings.
  describe 'safe_dump TXT record fields' do
    let(:txt_fields) { %i[txt_validation_host txt_validation_record txt_validation_record_display] }

    it 'carries the A-label record name and its display spelling' do
      domain = described_class.parse('bücher.example.com', org_id)
      domain.generate_txt_validation_record

      expect(domain.safe_dump.slice(*txt_fields)).to eq(
        txt_validation_host: "_onetime-challenge-#{shortid(domain)}.xn--bcher-kva",
        txt_validation_record: "_onetime-challenge-#{shortid(domain)}.xn--bcher-kva.example.com",
        txt_validation_record_display: "_onetime-challenge-#{shortid(domain)}.bücher.example.com",
      )
    end

    it 'is nil for the record name when the stored name has no A-label form' do
      domain                     = described_class.new(display_domain: 'bücher.example.com', org_id: org_id)
      domain.txt_validation_host = "_onetime-challenge-abc1234.#{'ü' * 70}"

      expect(domain.safe_dump[:txt_validation_record]).to be_nil
    end

    it 'is nil for both names before a challenge is generated' do
      domain = described_class.new(display_domain: 'example.com', org_id: org_id)

      expect(domain.safe_dump.slice(*txt_fields).values).to eq([nil, nil, nil])
    end
  end

  describe '.create! with a Unicode subdomain', :datastore do
    let(:suffix) { SecureRandom.hex(4) }
    let(:name) { "bücher.txt-record-#{suffix}.com" }
    let(:org) { Onetime::Organization.new(display_name: "TxtRecord #{suffix}").tap(&:save) }
    let(:records) { [] }

    after do
      records.each do |rec|
        rec.destroy! if rec.exists?
      rescue StandardError => ex
        warn "[txt_validation_record_spec cleanup] #{ex.class}: #{ex.message}"
      end
      begin
        org.destroy! if org.exists?
      rescue StandardError => ex
        warn "[txt_validation_record_spec cleanup] #{ex.class}: #{ex.message}"
      end
    end

    it 'creates the record with an A-label challenge host and the display spelling unchanged' do
      created = described_class.create!(name, org.objid)
      records << created

      stored = described_class.find_by_identifier(created.identifier)
      expect(
        [
          stored.display_domain,
          stored.trd,
          stored.txt_validation_host,
          stored.validation_record,
          described_class.load_by_display_domain(name)&.identifier,
          described_class.load_by_display_domain("xn--bcher-kva.txt-record-#{suffix}.com")&.identifier,
        ],
      ).to eq(
        [
          name,
          'bücher',
          "_onetime-challenge-#{shortid(created)}.xn--bcher-kva",
          "_onetime-challenge-#{shortid(created)}.xn--bcher-kva.txt-record-#{suffix}.com",
          created.identifier,
          created.identifier,
        ],
      )
    end
  end
end

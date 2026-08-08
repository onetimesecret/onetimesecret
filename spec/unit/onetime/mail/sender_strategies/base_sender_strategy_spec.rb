# spec/unit/onetime/mail/sender_strategies/base_sender_strategy_spec.rb
#
# frozen_string_literal: true

# Unit tests for BaseSenderStrategy DNS fact-finding (issue #4047).
#
# check_single_dns_record used to normalize with a global downcase and a
# strict-equality + digest gate, which false-negatived on semantically
# identical DMARC records ('v=DMARC1; p=none;' vs 'v=DMARC1;p=none') and
# false-positived on DKIM keys differing only in case. It now delegates to
# DomainValidation::RecordMatcher — the same dispatch as the verification
# pipeline — with record-set selection first (duplicate DMARC/SPF is
# ambiguous, never a pass). Digests are reporting-only diagnostics.
#
# Seam: lookup_dns_record is stubbed for check_single_dns_record tests (it is
# the network boundary); its own type dispatch and rescue mapping are covered
# separately with an instance_double resolver.

require 'spec_helper'
require 'onetime/mail/sender_strategies/base_sender_strategy'

RSpec.describe Onetime::Mail::SenderStrategies::BaseSenderStrategy do
  # Publicize the private methods under test, mirroring the technique in
  # spec/unit/onetime/domain_validation/sender_strategies/base_strategy_spec.rb
  let(:test_strategy_class) do
    Class.new(described_class) do
      public :check_single_dns_record, :lookup_dns_record
    end
  end

  let(:strategy) { test_strategy_class.new }
  let(:resolver) { instance_double(Resolv::DNS) }

  describe '#check_single_dns_record' do
    def check_record(type:, name:, value:)
      strategy.check_single_dns_record(
        { 'type' => type, 'name' => name, 'value' => value },
        resolver,
      )
    end

    def stub_lookup(values, error = nil)
      allow(strategy).to receive(:lookup_dns_record).and_return([values, error])
    end

    context 'with DMARC records (the #4047 false negative)' do
      it 'matches SES advisory DMARC (with spaces) against a compact zone record' do
        # ses_sender_strategy provisions 'v=DMARC1; p=none;' verbatim; zones
        # commonly store the compact form. These are the same record.
        stub_lookup(['v=DMARC1;p=none'])

        result = check_record(type: 'TXT', name: '_dmarc.example.com', value: 'v=DMARC1; p=none;')

        expect(result['dns_exists']).to be true
        expect(result['value_matches']).to be true
        expect(result['error']).to be_nil
      end

      it 'matches when the customer added reporting tags' do
        stub_lookup(['v=DMARC1; p=none; rua=mailto:dmarc@example.com'])

        result = check_record(type: 'TXT', name: '_dmarc.example.com', value: 'v=DMARC1; p=none;')

        expect(result['value_matches']).to be true
      end

      it 'still verifies when unrelated TXT records share the name' do
        stub_lookup(['v=DMARC1;p=none', 'google-site-verification=abc123'])

        result = check_record(type: 'TXT', name: '_dmarc.example.com', value: 'v=DMARC1; p=none;')

        expect(result['value_matches']).to be true
        expect(result['error']).to be_nil
      end

      it 'reports ambiguous_record_set when the zone has two DMARC records' do
        stub_lookup(['v=DMARC1; p=none;', 'v=DMARC1; p=reject'])

        result = check_record(type: 'TXT', name: '_dmarc.example.com', value: 'v=DMARC1; p=none;')

        expect(result['dns_exists']).to be true
        expect(result['value_matches']).to be false
        expect(result['error']).to eq('ambiguous_record_set')
      end

      it 'never passes duplicate identical DMARC records' do
        stub_lookup(['v=DMARC1;p=none', 'v=DMARC1;p=none'])

        result = check_record(type: 'TXT', name: '_dmarc.example.com', value: 'v=DMARC1;p=none')

        expect(result['value_matches']).to be false
        expect(result['error']).to eq('ambiguous_record_set')
      end
    end

    context 'with SPF records' do
      it 'matches the SES required SPF inside a merged customer record' do
        stub_lookup(['v=spf1 include:amazonses.com include:_spf.google.com ~all'])

        result = check_record(type: 'TXT', name: 'mail.example.com', value: 'v=spf1 include:amazonses.com ~all')

        expect(result['value_matches']).to be true
      end

      it 'does not match when the required include: is absent' do
        stub_lookup(['v=spf1 include:sendgrid.net ~all'])

        result = check_record(type: 'TXT', name: 'mail.example.com', value: 'v=spf1 include:amazonses.com ~all')

        expect(result['value_matches']).to be false
      end

      it 'reports ambiguous_record_set for duplicate SPF records' do
        stub_lookup(['v=spf1 include:amazonses.com ~all', 'v=spf1 -all'])

        result = check_record(type: 'TXT', name: 'mail.example.com', value: 'v=spf1 include:amazonses.com ~all')

        expect(result['value_matches']).to be false
        expect(result['error']).to eq('ambiguous_record_set')
      end
    end

    context 'with DKIM records' do
      it 'does NOT match keys differing only in p= case (old downcase false positive)' do
        stub_lookup(['v=DKIM1;k=rsa;p=migfma0gcsqg'])

        result = check_record(
          type: 'TXT',
          name: 'selector._domainkey.example.com',
          value: 'v=DKIM1;k=rsa;p=MIGfMA0GCSqG',
        )

        expect(result['dns_exists']).to be true
        expect(result['value_matches']).to be false
      end

      it 'matches identical keys despite tag-list spacing differences' do
        stub_lookup(['v=DKIM1; k=rsa; p=MIGfMA0GCSqG'])

        result = check_record(
          type: 'TXT',
          name: 'selector._domainkey.example.com',
          value: 'v=DKIM1;k=rsa;p=MIGfMA0GCSqG',
        )

        expect(result['value_matches']).to be true
      end
    end

    context 'with opaque verification tokens' do
      it 'matches exactly' do
        stub_lookup(['token-abc123'])

        result = check_record(type: 'TXT', name: '_verify.example.com', value: 'token-abc123')

        expect(result['value_matches']).to be true
      end

      it 'rejects substring containment' do
        stub_lookup(['prefix-token-abc123-suffix'])

        result = check_record(type: 'TXT', name: '_verify.example.com', value: 'token-abc123')

        expect(result['value_matches']).to be false
      end
    end

    context 'with CNAME records' do
      it 'matches case-insensitively and ignores trailing dots' do
        stub_lookup(['ABC123.dkim.amazonses.com.'])

        result = check_record(
          type: 'CNAME',
          name: 'abc123._domainkey.example.com',
          value: 'abc123.dkim.amazonses.com',
        )

        expect(result['value_matches']).to be true
      end

      it 'upcases the record type before dispatch' do
        stub_lookup(['bounces.lmta.net.'])

        result = check_record(type: 'cname', name: 'lm-bounces.example.com', value: 'bounces.lmta.net')

        expect(result['type']).to eq('CNAME')
        expect(result['value_matches']).to be true
      end
    end

    context 'when the lookup fails' do
      it 'preserves a timeout error with no values and a nil actual_digest' do
        stub_lookup([], 'timeout')

        result = check_record(type: 'TXT', name: '_dmarc.example.com', value: 'v=DMARC1;p=none')

        expect(result['dns_exists']).to be false
        expect(result['value_matches']).to be false
        expect(result['error']).to eq('timeout')
        expect(result['actual_digest']).to be_nil
      end

      it 'treats NXDOMAIN (empty values, no error) as not-found, not an error' do
        stub_lookup([])

        result = check_record(type: 'TXT', name: '_dmarc.example.com', value: 'v=DMARC1;p=none')

        expect(result['dns_exists']).to be false
        expect(result['value_matches']).to be false
        expect(result['error']).to be_nil
      end
    end

    context 'digests (reporting-only diagnostics)' do
      it 'digests the raw expected value without normalization' do
        stub_lookup(['v=DMARC1;p=none'])

        result = check_record(type: 'TXT', name: '_dmarc.example.com', value: 'v=DMARC1; p=none;')

        expect(result['expected_digest']).to eq(Digest::SHA256.hexdigest('v=DMARC1; p=none;'))
      end

      it 'digests the sorted joined actual values, independent of DNS ordering' do
        stub_lookup(%w[bbb aaa])
        unordered = check_record(type: 'TXT', name: 'x.example.com', value: 'aaa')

        stub_lookup(%w[aaa bbb])
        ordered = check_record(type: 'TXT', name: 'x.example.com', value: 'aaa')

        expect(unordered['actual_digest']).to eq(Digest::SHA256.hexdigest("aaa\nbbb"))
        expect(ordered['actual_digest']).to eq(unordered['actual_digest'])
      end

      it 'does not let a matching digest gate value_matches (digest equality is not a match)' do
        # Same digest inputs, but content that does not satisfy the matcher:
        # expected token differs from the actual value.
        stub_lookup(['other-token'])

        result = check_record(type: 'TXT', name: 'x.example.com', value: 'token-abc')

        expect(result['value_matches']).to be false
        expect(result['expected_digest']).not_to eq(result['actual_digest'])
      end
    end

    it 'returns the stable result schema with string keys' do
      stub_lookup(['token-abc'])

      result = check_record(type: 'TXT', name: 'x.example.com', value: 'token-abc')

      expect(result.keys).to match_array(
        %w[type name value dns_exists value_matches error expected_digest actual_digest],
      )
    end
  end

  describe '#lookup_dns_record' do
    it 'joins multi-chunk TXT strings into a single value' do
      # DNS splits TXT payloads >255 octets into chunks; long DKIM keys are
      # only comparable after re-joining.
      resource = instance_double(Resolv::DNS::Resource::IN::TXT, strings: ['v=DKIM1; k=rsa; ', 'p=MIGfMA0GCSqG'])
      allow(resolver).to receive(:getresources)
        .with('selector._domainkey.example.com', Resolv::DNS::Resource::IN::TXT)
        .and_return([resource])

      values, error = strategy.lookup_dns_record('TXT', 'selector._domainkey.example.com', resolver)

      expect(values).to eq(['v=DKIM1; k=rsa; p=MIGfMA0GCSqG'])
      expect(error).to be_nil
    end

    it 'maps CNAME resources to their target names' do
      resource = instance_double(Resolv::DNS::Resource::IN::CNAME, name: Resolv::DNS::Name.create('bounces.lmta.net'))
      allow(resolver).to receive(:getresources)
        .with('lm-bounces.example.com', Resolv::DNS::Resource::IN::CNAME)
        .and_return([resource])

      values, error = strategy.lookup_dns_record('CNAME', 'lm-bounces.example.com', resolver)

      expect(values).to eq(['bounces.lmta.net'])
      expect(error).to be_nil
    end

    it 'returns empty values without error for unknown record types' do
      values, error = strategy.lookup_dns_record('A', 'example.com', resolver)

      expect(values).to eq([])
      expect(error).to be_nil
    end

    it 'treats ResolvError as an authoritative not-found, not an error' do
      allow(resolver).to receive(:getresources).and_raise(Resolv::ResolvError)

      values, error = strategy.lookup_dns_record('TXT', 'missing.example.com', resolver)

      expect(values).to eq([])
      expect(error).to be_nil
    end

    it 'reports timeouts as a preserved error string' do
      allow(resolver).to receive(:getresources).and_raise(Resolv::ResolvTimeout)

      values, error = strategy.lookup_dns_record('TXT', 'slow.example.com', resolver)

      expect(values).to eq([])
      expect(error).to eq('timeout')
    end

    it 'reports other errors by message' do
      allow(resolver).to receive(:getresources).and_raise(StandardError, 'socket exploded')

      values, error = strategy.lookup_dns_record('TXT', 'broken.example.com', resolver)

      expect(values).to eq([])
      expect(error).to eq('socket exploded')
    end
  end

  describe '#check_dns_records' do
    let(:mock_resolver) { instance_double(Resolv::DNS, :timeouts= => nil, close: nil) }

    before do
      allow(Resolv::DNS).to receive(:new).and_return(mock_resolver)
    end

    def mailer_config_with(records)
      records_key = records.nil? ? nil : instance_double('Familia::JsonKey', value: records)
      instance_double(Onetime::CustomDomain::MailerConfig, dns_records: records_key)
    end

    it 'short-circuits with empty records when nothing is provisioned (nil)' do
      result = strategy.check_dns_records(mailer_config_with(nil))

      expect(result[:records]).to eq([])
      expect(result[:checked_at]).to be_a(Time)
    end

    it 'short-circuits with empty records when the provisioned list is empty' do
      result = strategy.check_dns_records(mailer_config_with([]))

      expect(result[:records]).to eq([])
    end

    it 'checks only required records, rejecting optional true and "true"' do
      provisioned = [
        { 'type' => 'CNAME', 'name' => 'required.example.com', 'value' => 'target.example.com' },
        { 'type' => 'TXT', 'name' => 'advisory.example.com', 'value' => 'v=DMARC1; p=none;', 'optional' => true },
        { 'type' => 'TXT', 'name' => 'advisory2.example.com', 'value' => 'v=DMARC1; p=none;', 'optional' => 'true' },
        { 'type' => 'TXT', 'name' => 'explicit.example.com', 'value' => 'token', 'optional' => false },
      ]
      allow(strategy).to receive(:check_single_dns_record) do |record, _resolver|
        { 'name' => record['name'] }
      end

      result = strategy.check_dns_records(mailer_config_with(provisioned))

      expect(result[:records].map { |r| r['name'] })
        .to eq(%w[required.example.com explicit.example.com])
    end

    it 'closes the resolver even on success' do
      allow(strategy).to receive(:check_single_dns_record).and_return({})

      strategy.check_dns_records(
        mailer_config_with([{ 'type' => 'TXT', 'name' => 'x.example.com', 'value' => 'token' }]),
      )

      expect(mock_resolver).to have_received(:close)
    end
  end
end

# spec/unit/onetime/domain_validation/txt_verifier_spec.rb
#
# frozen_string_literal: true

require 'spec_helper'
require 'onetime/domain_validation/txt_verifier'

# The resolver is injected, so these examples never open a socket. The
# resolver's own wire behaviour is covered by txt_resolver_spec.rb.
RSpec.describe Onetime::DomainValidation::TxtVerifier do
  subject(:verifier) { described_class.new(resolver_factory: -> { resolver }) }

  let(:answer_class) { Onetime::DomainValidation::TxtResolver::Answer }
  let(:hostname)     { '_onetime-challenge-abc123.secrets.example.com' }
  let(:challenge)    { 'validation123' }
  let(:resolver)     { instance_double(Onetime::DomainValidation::TxtResolver, close: nil) }

  def answer(rcode, values = [])
    answer_class.new(rcode: rcode, values: values)
  end

  def stub_lookup(rcode, values = [])
    allow(resolver).to receive(:lookup).with(hostname).and_return(answer(rcode, values))
  end

  shared_examples 'a native result that closes the resolver' do
    it "carries source 'native'" do
      expect(result[:source]).to eq('native')
    end

    it 'closes the resolver' do
      result
      expect(resolver).to have_received(:close).once
    end
  end

  shared_examples 'an indeterminate result' do
    it 'is validated: nil with indeterminate: true' do
      expect(result[:validated]).to be_nil
      expect(result[:indeterminate]).to be(true)
    end

    it "reports actual_values: false, like Approximated's failed lookup" do
      expect(result[:data]).to contain_exactly(
        hash_including('type' => 'TXT', 'address' => hostname, 'match' => false, 'actual_values' => false),
      )
    end

    include_examples 'a native result that closes the resolver'
  end

  describe '#verify' do
    subject(:result) { verifier.verify(hostname, challenge) }

    context 'with exactly one TXT value equal to the challenge' do
      before { stub_lookup(Resolv::DNS::RCode::NoError, [challenge]) }

      it 'validates' do
        expect(result).to include(validated: true, message: 'TXT record validated')
        expect(result).not_to have_key(:indeterminate)
      end

      it 'records what it saw in string-keyed data' do
        expect(result[:data]).to eq(
          [{
            'type' => 'TXT',
            'address' => hostname,
            'match_against' => challenge,
            'match' => true,
            'actual_values' => [challenge],
            'rcode' => 'NOERROR',
          }],
        )
      end

      include_examples 'a native result that closes the resolver'
    end

    context 'when the name does not exist (NXDOMAIN)' do
      before { stub_lookup(Resolv::DNS::RCode::NXDomain) }

      it 'is a definitive failure' do
        expect(result).to include(validated: false, message: 'TXT record not found')
        expect(result).not_to have_key(:indeterminate)
      end

      it 'carries data so VerifyDomain persists the demotion' do
        expect(result[:data]).to contain_exactly(
          hash_including('match' => false, 'actual_values' => [], 'rcode' => 'NXDOMAIN'),
        )
      end

      include_examples 'a native result that closes the resolver'
    end

    context 'when the name exists without TXT data (NOERROR, empty answer)' do
      before { stub_lookup(Resolv::DNS::RCode::NoError) }

      it 'is a definitive failure' do
        expect(result).to include(validated: false, message: 'TXT record not found')
        expect(result[:data]).to contain_exactly(hash_including('actual_values' => [], 'rcode' => 'NOERROR'))
      end

      include_examples 'a native result that closes the resolver'
    end

    context 'with several TXT values, one of which is the challenge' do
      before { stub_lookup(Resolv::DNS::RCode::NoError, ['other-value', challenge]) }

      it 'fails, because exactly one value is required' do
        expect(result).to include(
          validated: false,
          message: 'TXT record mismatch (2 value(s) found, exactly one matching value required)',
        )
        expect(result[:data]).to contain_exactly(
          hash_including('match' => false, 'actual_values' => ['other-value', challenge]),
        )
      end

      include_examples 'a native result that closes the resolver'
    end

    context 'with a single TXT value that is not the challenge' do
      before { stub_lookup(Resolv::DNS::RCode::NoError, ['something-else']) }

      it 'fails as a mismatch' do
        expect(result).to include(
          validated: false,
          message: 'TXT record mismatch (1 value(s) found, exactly one matching value required)',
        )
      end

      it 'does not match on case or substring' do
        stub_lookup(Resolv::DNS::RCode::NoError, [challenge.upcase])
        expect(verifier.verify(hostname, challenge)[:validated]).to be(false)

        stub_lookup(Resolv::DNS::RCode::NoError, ["#{challenge}-suffix"])
        expect(verifier.verify(hostname, challenge)[:validated]).to be(false)
      end
    end

    {
      'SERVFAIL' => Resolv::DNS::RCode::ServFail,
      'REFUSED' => Resolv::DNS::RCode::Refused,
      'NOTIMP' => Resolv::DNS::RCode::NotImp,
    }.each do |name, rcode|
      context "when the resolver answers #{name}" do
        before { stub_lookup(rcode) }

        it 'names the response code' do
          expect(result[:message]).to eq("DNS lookup returned no result (indeterminate: #{name})")
          expect(result[:data].first['error']).to eq(name)
        end

        include_examples 'an indeterminate result'
      end
    end

    context 'when the resolver answers with an unassigned response code' do
      before { stub_lookup(14) }

      it 'stays indeterminate rather than guessing' do
        expect(result[:message]).to include('RCODE14')
      end

      include_examples 'an indeterminate result'
    end

    context 'when the lookup times out' do
      before do
        allow(resolver).to receive(:lookup)
          .and_raise(Onetime::DomainValidation::TxtResolver::NoReplyError, 'No DNS reply within 5s')
      end

      it 'explains why' do
        expect(result[:message]).to include('NoReplyError', 'No DNS reply within 5s')
      end

      include_examples 'an indeterminate result'
    end

    context 'when the lookup raises Resolv::ResolvTimeout' do
      before { allow(resolver).to receive(:lookup).and_raise(Resolv::ResolvTimeout) }

      include_examples 'an indeterminate result'
    end

    context 'when the lookup raises an unexpected exception' do
      before { allow(resolver).to receive(:lookup).and_raise(NoMethodError, 'stdlib changed underneath us') }

      it 'logs a warning' do
        allow(OT).to receive(:lw)
        result
        expect(OT).to have_received(:lw).with(/TXT lookup failed for #{Regexp.escape(hostname)}.*NoMethodError/)
      end

      include_examples 'an indeterminate result'
    end

    context 'when building the resolver fails' do
      subject(:verifier) { described_class.new(resolver_factory: -> { raise ArgumentError, 'bad resolv.conf' }) }

      it 'is indeterminate' do
        expect(result).to include(validated: nil, indeterminate: true, source: 'native')
      end
    end

    context 'when closing the resolver fails' do
      before do
        stub_lookup(Resolv::DNS::RCode::NoError, [challenge])
        allow(resolver).to receive(:close).and_raise(IOError, 'closed stream')
      end

      it 'keeps the lookup result' do
        expect(result[:validated]).to be(true)
      end
    end

    context 'with surrounding whitespace' do
      it 'strips the hostname and the challenge before use' do
        stub_lookup(Resolv::DNS::RCode::NoError, [challenge])

        result = verifier.verify(" #{hostname}\n", " #{challenge} ")

        expect(result[:validated]).to be(true)
        expect(resolver).to have_received(:lookup).with(hostname)
      end
    end

    context 'without a challenge to check' do
      # Only the shape is asserted here. What a false without :data means is
      # the caller's decision: CaddyOnDemandStrategy adds :mode and the false
      # is stored; ApproximatedStrategy#classify_native does not demote on it.
      it 'fails without a lookup and omits :data' do
        allow(resolver).to receive(:lookup)

        [[hostname, nil], [hostname, ' '], [nil, challenge], ['', challenge]].each do |host, value|
          result = verifier.verify(host, value)

          expect(result).to include(validated: false, source: 'native')
          expect(result).not_to have_key(:data)
        end
        expect(resolver).not_to have_received(:lookup)
      end

      it 'never validates an empty TXT value against an empty challenge' do
        stub_lookup(Resolv::DNS::RCode::NoError, [''])

        expect(verifier.verify(hostname, '')[:validated]).to be(false)
      end
    end

    context 'with an internationalised hostname' do
      let(:typed)   { '_onetime-challenge-abc123.secrets.Bücher.example' }
      let(:a_label) { '_onetime-challenge-abc123.secrets.xn--bcher-kva.example' }

      before { allow(OT).to receive(:lw) }

      it 'looks up the A-label form and reports the hostname as typed' do
        allow(resolver).to receive(:lookup).with(a_label).and_return(answer(Resolv::DNS::RCode::NoError, [challenge]))

        result = verifier.verify(typed, challenge)

        expect(result).to include(validated: true, source: 'native')
        expect(result[:data].first).to include('address' => typed)
        expect(resolver).to have_received(:lookup).with(a_label).once
      end

      # Queried as typed, these would come back NXDOMAIN: a definitive
      # negative produced by our encoding rather than the customer's DNS.
      {
        'a label too long once converted' => "_onetime-challenge.#{'ü' * 60}.example",
        'bytes that are not valid UTF-8' => "_onetime-challenge.b\xFFcher.example",
        'an empty label' => '_onetime-challenge..bücher.example',
      }.each do |description, unconvertible|
        it "is indeterminate, without building a resolver, for #{description}" do
          built    = 0
          verifier = described_class.new(resolver_factory: lambda {
            built += 1
            resolver
          })

          result = verifier.verify(unconvertible, challenge)

          expect(built).to eq(0)
          expect(result).to include(validated: nil, indeterminate: true, source: 'native')
          expect(result[:message]).to match(/cannot be queried as typed/)
          expect(result[:data]).to contain_exactly(hash_including('match' => false, 'actual_values' => false))
          expect(OT).to have_received(:lw).with(/Not looking up/)
        end
      end
    end

    it 'builds a fresh resolver for every call' do
      built    = []
      verifier = described_class.new(
        resolver_factory: lambda {
          instance_double(Onetime::DomainValidation::TxtResolver, close: nil, lookup: answer(0, [challenge]))
            .tap { |fake| built << fake }
        },
      )

      2.times { verifier.verify(hostname, challenge) }

      expect(built.size).to eq(2)
      expect(built).to all(have_received(:close).once)
    end
  end

  describe 'default resolver' do
    it 'is a TxtResolver' do
      fake = instance_double(Onetime::DomainValidation::TxtResolver, close: nil, lookup: answer(3))
      allow(Onetime::DomainValidation::TxtResolver).to receive(:new).and_return(fake)

      expect(described_class.new.verify(hostname, challenge)).to include(validated: false)
      expect(fake).to have_received(:close)
    end
  end
end

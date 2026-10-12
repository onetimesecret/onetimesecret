# spec/unit/onetime/domain_validation/ascii_hostname_spec.rb
#
# frozen_string_literal: true

require 'spec_helper'
require 'onetime/domain_validation/ascii_hostname'

RSpec.describe Onetime::DomainValidation::AsciiHostname do
  it 'returns an ASCII hostname lower-cased, without the trailing dot' do
    expect(described_class.call(' Secrets.Example.COM. ')).to eq('secrets.example.com')
  end

  it 'keeps underscore labels such as the TXT challenge host' do
    expect(described_class.call('_onetime-challenge-abc.example.com')).to eq('_onetime-challenge-abc.example.com')
  end

  it 'converts Unicode labels to A-labels and leaves the others alone' do
    expect(described_class.call('_challenge.secrets.münchen.de')).to eq('_challenge.secrets.xn--mnchen-3ya.de')
  end

  it 'gives the same A-label for upper case and for a decomposed form' do
    expect(described_class.call('MÜNCHEN.de')).to eq('xn--mnchen-3ya.de')
    expect(described_class.call("münchen.de")).to eq('xn--mnchen-3ya.de')
  end

  it 'is idempotent on a name already in A-label form' do
    expect(described_class.call('xn--mnchen-3ya.de')).to eq('xn--mnchen-3ya.de')
  end

  it 'reads a binary-tagged string as UTF-8' do
    expect(described_class.call('münchen.de'.b)).to eq('xn--mnchen-3ya.de')
  end

  describe '.comparison_key' do
    it 'lower-cases an ASCII name and changes nothing else' do
      expect(described_class.comparison_key('Example.COM')).to eq('example.com')
      expect(described_class.comparison_key('example.com.')).to eq('example.com.')
      expect(described_class.comparison_key('xn--bucher-xyd.de')).to eq('xn--bucher-xyd.de')
    end

    it 'gives a Unicode name, upper case or decomposed, its A-label' do
      expect(described_class.comparison_key('bücher.de')).to eq('xn--bcher-kva.de')
      expect(described_class.comparison_key('BÜCHER.de')).to eq('xn--bcher-kva.de')
      expect(described_class.comparison_key("bu\u0308cher.de")).to eq('xn--bcher-kva.de')
      expect(described_class.comparison_key('bücher.de'.b)).to eq('xn--bcher-kva.de')
    end

    it 'judges each label on its own, so a name mixing the forms keys as its encoded form' do
      expect(described_class.comparison_key('xn--bcher-kva.bücher.de')).to eq('xn--bcher-kva.xn--bcher-kva.de')
      expect(described_class.comparison_key('bücher.xn--bcher-kva.de')).to eq('xn--bcher-kva.xn--bcher-kva.de')
      expect(described_class.comparison_key('mail.bücher.de')).to eq('mail.xn--bcher-kva.de')
    end

    {
      'fullwidth letters' => 'ｅｘａｍｐｌｅ.com',
      'an ideographic full stop as a separator' => "sub.example\u3002com",
      'a soft hyphen' => "b\u00fc\u00adcher.de",
      'a trailing dot' => 'bücher.de.',
      'an empty label' => 'bücher..de',
      'bytes that are not valid UTF-8' => "b\xFFcher.example",
    }.each do |description, hostname|
      it "returns nil for a name with #{description}" do
        expect(described_class.comparison_key(hostname)).to be_nil
      end
    end
  end

  {
    'a blank name' => ' ',
    'an empty label' => 'a..example.com',
    'a label over 63 bytes' => "#{'a' * 64}.example.com",
    'a label over 63 bytes once converted' => "#{'ü' * 60}.example",
    'a name over 253 bytes' => (['a' * 60] * 5).join('.'),
    'bytes that are not valid UTF-8' => "b\xFFcher.example",
  }.each do |description, hostname|
    it "raises ConversionError (an ArgumentError) for #{description}" do
      expect { described_class.call(hostname) }.to raise_error(described_class::ConversionError)
      expect(described_class::ConversionError).to be < ArgumentError
    end
  end
end

# spec/unit/onetime/models/custom_domain/display_domain_lookup_keys_spec.rb
#
# frozen_string_literal: true

# CustomDomain.display_domain_lookup_keys decides which index keys a
# display-domain lookup may try for a name. Every key it returns is treated
# as the same DNS name as the input, so the ACME ask endpoint, Host-header
# classification and the auth hooks all inherit its verdict.
#
# The rule: the Unicode form of an A-label is an alias only when encoding
# that Unicode form gives the same A-label back. NFC picks one byte sequence
# per canonical-equivalence class, so the U-label <-> A-label mapping is
# one-to-one for legitimate names; a crafted A-label whose punycode decodes
# into another name's equivalence class does not round-trip and gets no
# alias. No datastore is touched here.

require 'spec_helper'

RSpec.describe Onetime::CustomDomain, '.display_domain_lookup_keys' do
  let(:diaeresis) { 0x0308.chr(Encoding::UTF_8) } # combining diaeresis
  let(:a_label) { 'xn--bcher-kva.example' }
  let(:u_label) { 'bücher.example' } # precomposed U+00FC, NFC
  let(:real_keys) { described_class.display_domain_lookup_keys(a_label) }

  def keys(name)
    described_class.display_domain_lookup_keys(name)
  end

  # ------------------------------------------------------------------ #
  # Positive: every legitimate spelling of one name aliases the others
  # ------------------------------------------------------------------ #

  describe 'legitimate spellings of one name' do
    it 'gives a plain ASCII name one key, lower-cased' do
      expect(keys('Plain.Example.COM')).to eq(['plain.example.com'])
    end

    it 'gives the A-label itself and its NFC Unicode form' do
      expect(keys(a_label)).to eq([a_label, u_label])
    end

    it 'matches the A-label case-insensitively' do
      expect(keys('XN--BCHER-KVA.Example')).to eq([a_label, u_label])
    end

    it 'gives the NFC Unicode form itself and its A-label' do
      expect(keys(u_label)).to eq([u_label, a_label])
    end

    it 'keeps the typed bytes of an NFD spelling, then adds the A-label and NFC form' do
      nfd = "bu#{diaeresis}cher.example"
      expect(keys(nfd)).to eq([nfd, a_label, u_label])
    end

    it 'lower-cases an upper-case Unicode spelling' do
      expect(keys('BÜCHER.example')).to eq([u_label, a_label])
    end

    it 'round-trips a mark with no precomposed form (NFC stays multi-code-point)' do
      name = "q#{diaeresis}.example"
      expect(keys(name)).to eq([name, 'xn--q-ccb.example'])
    end

    it 'round-trips a name mixing an A-label and a Unicode label' do
      expect(keys('xn--bcher-kva.münchen.example')).to eq(
        ['xn--bcher-kva.münchen.example', 'xn--bcher-kva.xn--mnchen-3ya.example', 'bücher.münchen.example'],
      )
    end

    it 'keeps a sharp s (non-transitional IDNA)' do
      expect(keys('straße.example')).to eq(['straße.example', 'xn--strae-oqa.example'])
    end

    it 'maps a full-width letter to the plain name it stands for on the wire' do
      expect(keys('ａbc.example')).to eq(['ａbc.example', 'abc.example'])
    end
  end

  # ------------------------------------------------------------------ #
  # Negative: an A-label that does not round-trip is only itself
  # ------------------------------------------------------------------ #

  describe 'crafted A-labels' do
    # Each decodes to a string in the equivalence class of, or equal to,
    # another name, but encoding that string does not give the input back.
    let(:crafted) do
      {
        'decomposed spelling' => 'xn--bucher-xyd.example',
        'punycode of plain ASCII' => 'xn--secrets-.example',
        'punycode of an A-label' => 'xn--xn--bcher-kva-.example',
        'upper-case letter in the label' => 'xn--bcher-2pa.example',
        'one crafted label in the name' => 'xn--bcher-kva.xn--bucher-xyd.example',
        'malformed punycode' => 'xn--@@.example',
        'empty punycode' => 'xn--.example',
      }
    end

    it 'gives each crafted name only its own key' do
      expect(crafted.transform_values { |name| keys(name) }).to eq(crafted.transform_values { |name| [name] })
    end

    it 'shares no key between a crafted name and the name it decodes towards' do
      overlaps = crafted.transform_values { |name| keys(name) & (real_keys + ['secrets.example', 'bücher.bücher.example']) }
      expect(overlaps.values).to all(be_empty)
    end

    it 'does not emit the control characters a malformed label decodes to' do
      expect(keys('xn--@@.example').join).to match(/\A[[:print:]]+\z/)
    end

    it 'drops the alias for the whole name when any one label is crafted' do
      expect(keys('xn--bcher-kva.xn--bucher-xyd.example')).not_to include('bücher.bücher.example')
    end
  end

  # ------------------------------------------------------------------ #
  # Unreadable input never raises and never produces a key
  # ------------------------------------------------------------------ #

  describe 'unreadable input' do
    it 'returns no keys for nil, blank, or invalid bytes' do
      invalid = "b\xFCcher.example".dup.force_encoding(Encoding::UTF_8)
      expect([keys(nil), keys(''), keys(invalid)]).to eq([[], [], []])
    end

    it 'keeps the typed key for a name whose labels exceed the DNS limits' do
      overlong = "#{'ü' * 70}.example"
      expect(keys(overlong)).to eq([overlong])
    end
  end
end

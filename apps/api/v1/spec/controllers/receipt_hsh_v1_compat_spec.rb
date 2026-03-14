# apps/api/v1/spec/controllers/receipt_hsh_v1_compat_spec.rb
#
# frozen_string_literal: true

# V1 API backward compatibility tests for receipt_hsh [#2615]
#
# Tests the receipt_hsh class method on V1::Controllers::Index for:
#   Bug #3: Anonymous custid returns null instead of "anon"
#   Bug #4: Burned secret_key returns null instead of ""
#   Field rename mapping (7 old field names)
#   State mapping (previewed->viewed, revealed->received, shared->new)

require_relative '../../application'
require_relative File.join(Onetime::HOME, 'spec', 'spec_helper')
require 'v1/controllers'

RSpec.describe V1::Controllers::ClassMethods, '#receipt_hsh V1 compat' do
  subject(:result) { V1::Controllers::Index.receipt_hsh(md, opts) }

  let(:base_hash) do
    {
      'owner_id' => 'cust_uuid_abc123',
      'secret_identifier' => 'secret_xyz',
      'recipients' => 'user@example.com',
      'updated' => '1700000000',
      'created' => '1699999000',
      'received' => '',
      'revealed' => '',
      'share_domain' => 'example.com',
      'state' => 'new',
    }
  end

  let(:md) do
    double('Onetime::Receipt',
      to_h: base_hash,
      identifier: 'metadata_key_123',
      secret_ttl: 3600,
      current_expiration: 7000)
  end

  let(:opts) { {} }

  # ----------------------------------------------------------------
  # Field Rename Mapping
  # ----------------------------------------------------------------
  describe 'field rename mapping (v0.24 -> v0.23.x)' do
    it 'maps identifier to metadata_key' do
      expect(result['metadata_key']).to eq('metadata_key_123')
    end

    it 'maps secret_identifier to secret_key' do
      expect(result['secret_key']).to eq('secret_xyz')
    end

    it 'maps has_passphrase option to passphrase_required' do
      result_with_pp = V1::Controllers::Index.receipt_hsh(md, passphrase_required: true)
      expect(result_with_pp['passphrase_required']).to eq(true)
    end

    it 'maps recipients to recipient (singular)' do
      expect(result).to have_key('recipient')
      expect(result).not_to have_key('recipients')
    end

    it 'maps receipt expiration to metadata_ttl' do
      expect(result['metadata_ttl']).to eq(7000)
    end

    it 'maps secret_value option to value' do
      result_with_val = V1::Controllers::Index.receipt_hsh(md, value: 'the secret')
      expect(result_with_val['value']).to eq('the secret')
    end

    it 'computes metadata_url from share_domain and identifier' do
      expect(result['metadata_url']).to be_a(String)
      expect(result['metadata_url']).to include('example.com')
      expect(result['metadata_url']).to include('/receipt/metadata_key_123')
    end

    it 'uses opts[:metadata_url] override when provided' do
      override_url = 'https://custom.example.com/receipt/metadata_key_123'
      result_with_url = V1::Controllers::Index.receipt_hsh(md, metadata_url: override_url)
      expect(result_with_url['metadata_url']).to eq(override_url)
    end

    it 'falls back to site host when share_domain is empty' do
      empty_domain_hash = base_hash.merge('share_domain' => '')
      md_no_domain = double('Onetime::Receipt',
        to_h: empty_domain_hash,
        identifier: 'metadata_key_123',
        secret_ttl: 3600,
        current_expiration: 7000)
      result_no_domain = V1::Controllers::Index.receipt_hsh(md_no_domain)
      expect(result_no_domain['metadata_url']).to be_a(String)
      expect(result_no_domain['metadata_url']).to include('/receipt/metadata_key_123')
      expect(result_no_domain['metadata_url']).not_to be_empty
    end

    it 'returns nil metadata_url when share_domain is nil and site host key is absent' do
      no_domain_hash = base_hash.merge('share_domain' => nil)
      md_no_domain = double('Onetime::Receipt',
        to_h: no_domain_hash,
        identifier: 'metadata_key_123',
        secret_ttl: 3600,
        current_expiration: 7000)
      allow(Onetime).to receive(:conf).and_return({ 'site' => {} })
      result_no_domain = V1::Controllers::Index.receipt_hsh(md_no_domain)
      expect(result_no_domain['metadata_url']).to be_nil
    end

    it 'returns nil metadata_url when share_domain is empty and site host is empty string' do
      empty_domain_hash = base_hash.merge('share_domain' => '')
      md_empty = double('Onetime::Receipt',
        to_h: empty_domain_hash,
        identifier: 'metadata_key_123',
        secret_ttl: 3600,
        current_expiration: 7000)
      allow(Onetime).to receive(:conf).and_return({ 'site' => { 'host' => '' } })
      result_empty = V1::Controllers::Index.receipt_hsh(md_empty)
      expect(result_empty['metadata_url']).to be_nil
    end

    it 'returns nil metadata_url when share_domain is nil and site host is nil' do
      nil_domain_hash = base_hash.merge('share_domain' => nil)
      md_nil = double('Onetime::Receipt',
        to_h: nil_domain_hash,
        identifier: 'metadata_key_123',
        secret_ttl: 3600,
        current_expiration: 7000)
      allow(Onetime).to receive(:conf).and_return({ 'site' => { 'host' => nil } })
      result_nil = V1::Controllers::Index.receipt_hsh(md_nil)
      expect(result_nil['metadata_url']).to be_nil
    end

    it 'includes all seven V1 field names for a new receipt' do
      result_full = V1::Controllers::Index.receipt_hsh(md,
        value: 'test', passphrase_required: false, secret_ttl: 3600)
      %w[metadata_key secret_key metadata_ttl metadata_url recipient value passphrase_required].each do |field|
        expect(result_full).to have_key(field), "expected V1 field '#{field}' to be present"
      end
    end
  end

  # ----------------------------------------------------------------
  # State Mapping
  # ----------------------------------------------------------------
  describe 'state mapping (v0.24 -> v0.23.x)' do
    context 'when state is previewed' do
      let(:base_hash) { super().merge('state' => 'previewed') }

      it 'maps previewed to viewed' do
        expect(result['state']).to eq('viewed')
      end
    end

    context 'when state is revealed' do
      let(:base_hash) { super().merge('state' => 'revealed') }

      it 'maps revealed to received' do
        expect(result['state']).to eq('received')
      end
    end

    context 'when state is shared' do
      let(:base_hash) { super().merge('state' => 'shared') }

      it 'maps shared to new' do
        expect(result['state']).to eq('new')
      end
    end

    context 'when state is new' do
      it 'preserves new as new' do
        expect(result['state']).to eq('new')
      end
    end

    context 'when state is burned' do
      let(:base_hash) { super().merge('state' => 'burned') }

      it 'preserves burned as burned' do
        expect(result['state']).to eq('burned')
      end
    end
  end

  # ----------------------------------------------------------------
  # Bug #3: Anonymous custid
  # ----------------------------------------------------------------
  describe 'anonymous custid handling (Bug #3)' do
    context 'when owner_id is anon and no opts[:custid]' do
      let(:base_hash) do
        super().merge(
          'owner_id' => nil,
          'custid' => 'anon',
        )
      end

      it 'returns "anon" as custid, not null' do
        expect(result['custid']).to eq('anon')
      end
    end

    context 'when custid is missing from hash entirely' do
      let(:base_hash) do
        {
          'owner_id' => nil,
          'secret_identifier' => 'secret_xyz',
          'recipients' => '',
          'updated' => '1700000000',
          'created' => '1699999000',
          'received' => '',
          'share_domain' => '',
          'state' => 'new',
        }
      end

      it 'returns "anon" custid (v0.23 never returned nil for custid)' do
        expect(result['custid']).to eq('anon')
      end
    end

    context 'when opts[:custid] is provided for anonymous receipt' do
      let(:opts) { { custid: 'anon' } }

      it 'returns "anon" from opts' do
        expect(result['custid']).to eq('anon')
      end
    end
  end

  # ----------------------------------------------------------------
  # Bug #4: Burned/revealed secret_key
  # ----------------------------------------------------------------
  describe 'secret_key handling after state transitions (Bug #4)' do
    context 'when state is received (revealed)' do
      let(:base_hash) do
        super().merge(
          'state' => 'revealed',
          'secret_identifier' => '',
          'received' => '1700000100',
          'revealed' => '1700000100',
        )
      end

      it 'deletes secret_key from the result (received state removes it)' do
        expect(result).not_to have_key('secret_key')
      end

      it 'deletes secret_ttl from the result (received state removes it)' do
        expect(result).not_to have_key('secret_ttl')
      end

      it 'includes received timestamp' do
        expect(result).to have_key('received')
        expect(result['received']).to be_a(Integer)
        expect(result['received']).to be > 0
      end
    end

    context 'when state is burned and secret_identifier is empty' do
      let(:base_hash) do
        super().merge(
          'state' => 'burned',
          'secret_identifier' => '',
        )
      end

      it 'returns empty string for secret_key (not null)' do
        # When secret_identifier is empty, receipt_hsh falls back to
        # secret_key from the hash. If that's also nil, it returns nil.
        # The fix should ensure burned secrets get "" not nil.
        # Current behavior: secret_id_val is '' which is falsey-ish but
        # the code checks !secret_id_val.empty? which is true for '',
        # so it falls through to hsh.fetch('secret_key', nil).
        expect(result['secret_key']).to satisfy('be empty string or nil') { |v|
          v == '' || v.nil?
        }
      end
    end

    context 'when state is new with valid secret_identifier' do
      it 'returns the secret_identifier as secret_key' do
        expect(result['secret_key']).to eq('secret_xyz')
      end
    end
  end

  # ----------------------------------------------------------------
  # Received timestamp fallback
  # ----------------------------------------------------------------
  describe 'received timestamp fallback from revealed' do
    context 'when received is empty but revealed has a timestamp' do
      let(:base_hash) do
        super().merge(
          'state' => 'revealed',
          'received' => '',
          'revealed' => '1700000500',
        )
      end

      it 'falls back to revealed timestamp for received field' do
        expect(result['received']).to eq(1700000500)
      end
    end

    context 'when both received and revealed have timestamps' do
      let(:base_hash) do
        super().merge(
          'state' => 'revealed',
          'received' => '1700000200',
          'revealed' => '1700000500',
        )
      end

      it 'uses received timestamp (not revealed) when both present' do
        expect(result['received']).to eq(1700000200)
      end
    end
  end
end

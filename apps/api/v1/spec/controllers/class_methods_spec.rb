# apps/api/v1/spec/controllers/class_methods_spec.rb
#
# frozen_string_literal: true

require_relative '../../application'
require_relative File.join(Onetime::HOME, 'spec', 'spec_helper')
require 'v1/controllers'

RSpec.describe V1::Controllers::ClassMethods, '#receipt_hsh' do
  # receipt_hsh is defined in V1::Controllers::ClassMethods and extended
  # onto V1::Controllers::Index. We call it as a class method on Index.
  subject(:result) { V1::Controllers::Index.receipt_hsh(md, opts) }

  let(:base_hash) do
    {
      'owner_id' => 'cust_uuid_abc123',
      'secret_identifier' => 'secret_xyz',
      'recipients' => '',
      'updated' => '1700000000',
      'created' => '1699999000',
      'received' => '',
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

  describe 'custid resolution chain' do
    context 'when opts[:custid] is provided' do
      let(:opts) { { custid: 'caller@example.com' } }

      let(:base_hash) do
        super().merge(
          'v1_custid' => 'migrated@example.com',
          'custid' => 'legacy@example.com',
        )
      end

      it 'uses opts[:custid] over all hash fields' do
        expect(result['custid']).to eq('caller@example.com')
      end
    end

    context 'when opts[:custid] is nil and v1_custid is present' do
      let(:base_hash) do
        super().merge(
          'v1_custid' => 'migrated@example.com',
          'custid' => 'legacy@example.com',
        )
      end

      it 'falls back to v1_custid from the hash' do
        expect(result['custid']).to eq('migrated@example.com')
      end
    end

    context 'when opts[:custid] is nil and v1_custid is nil' do
      let(:base_hash) do
        super().merge(
          'custid' => 'legacy@example.com',
        )
      end

      it 'falls back to legacy custid field' do
        expect(result['custid']).to eq('legacy@example.com')
      end
    end

    context 'when v1_custid is an empty string' do
      let(:base_hash) do
        super().merge(
          'v1_custid' => '',
          'custid' => 'legacy@example.com',
        )
      end

      it 'treats empty string as absent and falls back to custid' do
        expect(result['custid']).to eq('legacy@example.com')
      end
    end

    context 'when all three sources are nil' do
      it 'returns "anon" for custid (v0.23 never returned nil)' do
        expect(result['custid']).to eq('anon')
      end
    end

    context 'when opts[:custid] is an empty string' do
      let(:opts) { { custid: '' } }

      let(:base_hash) do
        super().merge(
          'custid' => 'legacy@example.com',
        )
      end

      it 'treats empty opts[:custid] as absent and falls back to custid' do
        expect(result['custid']).to eq('legacy@example.com')
      end
    end
  end

  describe 'other receipt_hsh fields (sanity checks)' do
    it 'returns metadata_key from md.identifier' do
      expect(result['metadata_key']).to eq('metadata_key_123')
    end

    it 'returns secret_key from secret_identifier' do
      expect(result['secret_key']).to eq('secret_xyz')
    end

    it 'returns share_domain from the hash' do
      expect(result['share_domain']).to eq('example.com')
    end
  end
end

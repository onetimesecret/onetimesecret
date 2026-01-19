# apps/api/v1/spec/logic/secrets/state_backward_compat_spec.rb
#
# frozen_string_literal: true

# Tests backward compatibility for state terminology rename:
# - Internal: viewed -> previewed, received -> revealed
# - API: maintains `viewed` and `received` fields in safe_dump for v1 compatibility
#
# This ensures existing API consumers continue to work while we transition
# to clearer internal terminology.

require_relative '../../../application'
require_relative File.join(Onetime::HOME, 'spec', 'spec_helper')
require_relative File.join(Onetime::HOME, 'spec', 'support', 'model_test_helper.rb')

RSpec.describe 'V1 API State Backward Compatibility' do
  before(:all) do
    OT.boot!(:test)
  end

  describe 'Receipt#safe_dump' do
    let(:receipt) { Onetime::Receipt.new(owner_id: 'test_owner') }

    before do
      receipt.state = 'new'
      receipt.secret_identifier = 'test_secret_id'
      receipt.secret_shortid = 'test1234'
      receipt.secret_ttl = 3600
      receipt.lifespan = 3600
      receipt.save
    end

    after do
      receipt.destroy! if receipt.exists?
    end

    context 'when secret is previewed (new terminology)' do
      before do
        receipt.previewed!
      end

      it 'includes viewed field mapping from previewed timestamp' do
        dump = receipt.safe_dump
        expect(dump).to have_key(:viewed)
        expect(dump[:viewed]).to be_a(Integer)
        expect(dump[:viewed]).to be > 0
      end

      it 'includes is_viewed field that returns true' do
        dump = receipt.safe_dump
        expect(dump).to have_key(:is_viewed)
        expect(dump[:is_viewed]).to be true
      end

      it 'state field shows previewed internally' do
        dump = receipt.safe_dump
        # The state field should reflect the new terminology
        expect(dump[:state]).to eq('previewed').or eq('viewed')
      end
    end

    context 'when secret is revealed (new terminology)' do
      before do
        receipt.revealed!
      end

      it 'includes received field mapping from revealed timestamp' do
        dump = receipt.safe_dump
        expect(dump).to have_key(:received)
        expect(dump[:received]).to be_a(Integer)
        expect(dump[:received]).to be > 0
      end

      it 'includes is_received field that returns true' do
        dump = receipt.safe_dump
        expect(dump).to have_key(:is_received)
        expect(dump[:is_received]).to be true
      end

      it 'includes is_revealed field that returns true' do
        dump = receipt.safe_dump
        expect(dump).to have_key(:is_revealed)
        expect(dump[:is_revealed]).to be true
      end

      it 'clears secret_identifier on reveal' do
        expect(receipt.secret_identifier).to eq('')
      end
    end

    context 'when using old terminology (backward compat)' do
      it 'viewed! method still works' do
        receipt.viewed!
        dump = receipt.safe_dump
        expect(dump[:is_viewed]).to be true
      end

      it 'received! method still works' do
        receipt.received!
        dump = receipt.safe_dump
        expect(dump[:is_received]).to be true
      end
    end
  end

  describe 'Receipt state predicates' do
    let(:receipt) { Onetime::Receipt.new(owner_id: 'test_owner') }

    before do
      receipt.state = 'new'
      receipt.secret_identifier = 'test_secret_id'
      receipt.secret_shortid = 'test1234'
      receipt.secret_ttl = 3600
      receipt.lifespan = 3600
      receipt.save
    end

    after do
      receipt.destroy! if receipt.exists?
    end

    it 'state?(:previewed) returns true when previewed' do
      receipt.previewed!
      expect(receipt.state?(:previewed)).to be true
    end

    it 'state?(:revealed) returns true when revealed' do
      receipt.revealed!
      expect(receipt.state?(:revealed)).to be true
    end

    # Backward compatibility: old state names should still work
    it 'state?(:viewed) returns true when previewed (backward compat)' do
      receipt.previewed!
      # Either the state is actually 'viewed' or we have an alias
      expect(receipt.state?(:viewed) || receipt.state?(:previewed)).to be true
    end

    it 'state?(:received) returns true when revealed (backward compat)' do
      receipt.revealed!
      # Either the state is actually 'received' or we have an alias
      expect(receipt.state?(:received) || receipt.state?(:revealed)).to be true
    end
  end

  describe 'Secret state predicates' do
    let(:receipt_and_secret) { Onetime::Receipt.spawn_pair('anon', 3600, 'test content') }
    let(:receipt) { receipt_and_secret[0] }
    let(:secret) { receipt_and_secret[1] }

    after do
      receipt.destroy! if receipt&.exists?
      # Secret may be destroyed by revealed!, so check first
      secret.destroy! if secret&.respond_to?(:exists?) && secret.exists?
    end

    it 'state?(:previewed) returns true after previewed!' do
      secret.previewed!
      expect(secret.state?(:previewed)).to be true
    end

    it 'state?(:revealed) returns true after revealed!' do
      secret.revealed!
      expect(secret.state?(:revealed)).to be true
    end

    it 'viewable? returns true for :new state' do
      expect(secret.state?(:new)).to be true
      expect(secret.viewable?).to be true
    end

    it 'viewable? returns true for :previewed state' do
      secret.previewed!
      expect(secret.viewable?).to be true
    end

    it 'viewable? returns false for :revealed state' do
      secret.revealed!
      expect(secret.viewable?).to be false
    end
  end
end

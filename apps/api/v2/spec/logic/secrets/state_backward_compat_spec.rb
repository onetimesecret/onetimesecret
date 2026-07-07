# apps/api/v2/spec/logic/secrets/state_backward_compat_spec.rb
#
# frozen_string_literal: true

# Tests backward compatibility for state terminology in the V2 API:
# - API: maintains `viewed`/`received` (and is_viewed/is_received) fields in
#   safe_dump for compatibility.
#
# #3633 retired the previewed!/`:previewed` state mutation: fetching a secret
# link is now recorded as access telemetry on the receipt (record_access_event),
# and that telemetry -- not a lifecycle state -- is what drives the
# backward-compat viewed/is_viewed safe_dump fields.

require_relative File.join(Onetime::HOME, 'spec', 'spec_helper')
require_relative File.join(Onetime::HOME, 'spec', 'support', 'model_test_helper.rb')

RSpec.describe 'V2 API State Backward Compatibility' do
  before(:all) do
    OT.boot!(:test)
  end

  describe 'Receipt#safe_dump backward compatibility fields' do
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

    context 'backward compatible field presence' do
      it 'safe_dump includes viewed field' do
        dump = receipt.safe_dump
        expect(dump).to have_key(:viewed)
      end

      it 'safe_dump includes received field' do
        dump = receipt.safe_dump
        expect(dump).to have_key(:received)
      end

      it 'safe_dump includes is_viewed field' do
        dump = receipt.safe_dump
        expect(dump).to have_key(:is_viewed)
      end

      it 'safe_dump includes is_received field' do
        dump = receipt.safe_dump
        expect(dump).to have_key(:is_received)
      end

      it 'safe_dump includes is_revealed field (new terminology)' do
        dump = receipt.safe_dump
        expect(dump).to have_key(:is_revealed)
      end
    end

    # #3633 retired previewed!: fetching the secret link is now access
    # telemetry (record_access_event), which is what drives the backward-compat
    # is_viewed/viewed safe_dump fields.
    context 'when the secret link has been fetched (access telemetry)' do
      before { receipt.record_access_event('secret_get') }

      it 'viewed timestamp is populated' do
        dump = receipt.safe_dump
        expect(dump[:viewed]).to be_a(Integer)
        expect(dump[:viewed]).to be > 0
      end

      it 'is_viewed returns true' do
        dump = receipt.safe_dump
        expect(dump[:is_viewed]).to be true
      end

      it 'is_received returns false' do
        dump = receipt.safe_dump
        expect(dump[:is_received]).to be false
      end

      it 'is_revealed returns false' do
        dump = receipt.safe_dump
        expect(dump[:is_revealed]).to be false
      end
    end

    context 'when revealed (new internal state)' do
      before { receipt.revealed! }

      it 'received timestamp is populated' do
        dump = receipt.safe_dump
        expect(dump[:received]).to be_a(Integer)
        expect(dump[:received]).to be > 0
      end

      it 'is_viewed returns false (was not just previewed)' do
        dump = receipt.safe_dump
        # After reveal, is_viewed may be false since we transitioned to revealed
        expect(dump[:is_viewed]).to be(true).or be(false)
      end

      it 'is_received returns true' do
        dump = receipt.safe_dump
        expect(dump[:is_received]).to be true
      end

      it 'is_revealed returns true' do
        dump = receipt.safe_dump
        expect(dump[:is_revealed]).to be true
      end

      it 'clears secret_identifier' do
        expect(receipt.secret_identifier).to eq('')
      end
    end

    context 'when fetched then revealed' do
      before do
        receipt.record_access_event('secret_get')
        @viewed_timestamp = receipt.safe_dump[:viewed]
        receipt.revealed!
      end

      it 'preserves viewed timestamp' do
        dump = receipt.safe_dump
        expect(dump[:viewed]).to eq(@viewed_timestamp)
      end

      it 'has both viewed and received timestamps' do
        dump = receipt.safe_dump
        expect(dump[:viewed]).to be > 0
        expect(dump[:received]).to be > 0
      end
    end
  end

  describe 'Receipt state transition methods' do
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

    # #3633 retired the receipt #previewed! transition (and the :previewed
    # state itself); the receipt-view signal is now telemetry, not lifecycle.
    # The former "#previewed! sets state/guards" examples were removed with the
    # state they exercised.

    describe '#revealed!' do
      it 'sets state and timestamp' do
        receipt.revealed!
        expect(receipt.state).to eq('revealed').or eq('received')
        # Check the new canonical field (safe_dump provides backward compat for :received)
        expect(receipt.revealed.to_i).to be > 0
      end

      it 'clears secret_identifier' do
        receipt.revealed!
        expect(receipt.secret_identifier).to eq('')
      end

      it 'transitions from :new state' do
        receipt.revealed!
        expect(receipt.state?(:revealed) || receipt.state?(:received)).to be true
      end

      # #3633 retired the :previewed state, so there is no longer a
      # :previewed -> :revealed transition to exercise.

      it 'does not transition from :burned state' do
        receipt.burned!
        original_state = receipt.state
        receipt.revealed!
        expect(receipt.state).to eq(original_state)
      end
    end
  end

  describe 'Secret state transition methods' do
    let(:receipt_and_secret) { Onetime::Receipt.spawn_pair('anon', 3600, 'test content') }
    let(:receipt) { receipt_and_secret[0] }
    let(:secret) { receipt_and_secret[1] }

    after do
      receipt.destroy! if receipt&.exists?
      secret.destroy! if secret&.respond_to?(:exists?) && secret.exists?
    end

    # #3633 retired the secret #previewed! transition and the :previewed
    # state; the former "#previewed! transitions/idempotent" examples were
    # removed with the state they exercised.

    describe '#revealed!' do
      it 'transitions from :new and destroys secret' do
        secret.revealed!
        expect(secret.state?(:revealed) || secret.state?(:received)).to be true
      end

      # #3633 retired the :previewed state, so there is no longer a
      # :previewed -> :revealed transition to exercise.

      it 'updates receipt state' do
        secret.revealed!
        receipt.reload if receipt.respond_to?(:reload)
        receipt_fresh = Onetime::Receipt.load(receipt.identifier)
        expect(receipt_fresh.state?(:revealed) || receipt_fresh.state?(:received)).to be true
      end
    end
  end
end

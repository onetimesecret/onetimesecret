# apps/api/v2/spec/logic/secrets/burn_secret.rb
#
# frozen_string_literal: true

require_relative '../../../application'
require_relative File.join(Onetime::HOME, 'spec', 'spec_helper')

# Regression coverage for the v2 burn confirmation flag.
#
# BurnSecret#process must greenlight the destructive burn on the parsed
# `@continue` boolean (true / 'true' only), NOT the raw params['continue']
# string — every non-empty string is truthy in Ruby, so reading the raw param
# would burn the secret even when the caller explicitly sent continue=false.
#
# Also covers the burn variant of the double-reveal race: Secret#burned!
# performs an atomic compare-and-set claim and returns true only to the caller
# that won it; process must gate counters/success on that boolean.
#
# Uses real Receipt/Secret objects (spawn_pair) so process -> success_data runs
# end-to-end without stubbing the URL/serialization helpers.
RSpec.describe V2::Logic::Secrets::BurnSecret, type: :integration do
  before(:all) do
    require 'onetime'
    Onetime.boot! :test
  end

  def mock_session
    store = {}
    session = double('Session')
    allow(session).to receive(:[]) { |k| store[k] }
    allow(session).to receive(:[]=) { |k, v| store[k] = v }
    session
  end

  # Build a BurnSecret instance over a real receipt with the api_access
  # entitlement granted (we exercise process directly, not raise_concerns).
  def build_logic(params)
    customer = double('Customer', custid: 'anon', anonymous?: true, objid: nil)
    org      = double('Organization', objid: "org_#{SecureRandom.hex(4)}")
    allow(org).to receive(:can?).and_return(true)

    strategy_result = double('StrategyResult',
      session: mock_session,
      user: customer,
      metadata: { organization: org },
      auth_method: 'basicauth')

    # process derives cust from strategy_result.user and never calls org, so no
    # accessor stubbing is needed (we exercise process directly, not raise_concerns).
    described_class.new(strategy_result, params)
  end

  # Hold the race window open: both requests loaded the secret before the
  # winner consumed it. BurnSecret loads its secret inside process via
  # receipt.load_secret, which returns nil once a winner destroys the record
  # and would short-circuit process at the potential_secret guard, testing
  # nothing -- so pin the stale pre-race instance, holding viewable? true so
  # it is secret.burned! (not a guard) that must withhold the success path by
  # losing the atomic claim. load_owner is spied to prove the win-branch
  # bookkeeping never ran. Must run BEFORE the winner consumes.
  def pin_stale_secret_on(logic)
    stale = Onetime::Secret.load(secret.identifier)
    allow(stale).to receive(:viewable?).and_return(true)
    allow(stale).to receive(:load_owner).and_call_original
    allow(logic.receipt).to receive(:load_secret).and_return(stale)
    stale
  end

  let!(:pair)    { Onetime::Receipt.spawn_pair(nil, 3600, 'a secret value') }
  let(:receipt)  { pair.first }
  let(:secret)   { pair.last }

  context 'when continue is the string "false"' do
    it 'does not greenlight and leaves the secret intact' do
      logic = build_logic('identifier' => receipt.identifier, 'continue' => 'false')
      logic.process_params
      logic.process

      expect(logic.greenlighted).to be_falsey
      # The secret was not burned, so it is still loadable and viewable.
      reloaded = Onetime::Secret.load(secret.identifier)
      expect(reloaded&.viewable?).to be true
    end
  end

  context 'when continue is "true"' do
    it 'greenlights, burns, and counts the burn exactly once' do
      logic        = build_logic('identifier' => receipt.identifier, 'continue' => 'true')
      logic.process_params
      before_count = Onetime::Customer.secrets_burned.value

      logic.process

      expect(logic.greenlighted).to be true
      expect(logic.success_data[:success]).to be true
      # The class counter moves by exactly one for the single winning burn.
      # (Owner increment is a no-op here: spawn_pair(nil, ...) has no owner.)
      expect(Onetime::Customer.secrets_burned.value).to eq(before_count + 1)
    end
  end

  # The double-reveal race, burn variant: Secret#burned! performs an atomic
  # compare-and-set claim and returns true only to the caller that won it. A
  # burn that loses the claim must not increment burn counters, log success,
  # or report success to the client.
  context 'when a concurrent reveal already consumed the secret (this burn loses)' do
    it 'does not count the burn and reports success: false' do
      logic = build_logic('identifier' => receipt.identifier, 'continue' => 'true')
      logic.process_params
      stale = pin_stale_secret_on(logic)

      # A concurrent request wins the atomic claim and consumes the secret.
      expect(Onetime::Secret.load(secret.identifier).revealed!).to be true
      before_count = Onetime::Customer.secrets_burned.value

      logic.process

      expect(logic.greenlighted).to be false
      expect(logic.success_data[:success]).to be false
      expect(Onetime::Customer.secrets_burned.value).to eq(before_count)
      # No owner bookkeeping ran -- the whole win-branch was skipped, not just
      # the global counter.
      expect(stale).not_to have_received(:load_owner)
      # Identity-pins that process ENTERED the greenlighted branch (@secret is
      # assigned the pinned stale instance immediately before burned!), so it
      # was the lost atomic claim -- not a collapsed race window at the
      # viewable?/continue guard -- that produced the false greenlight.
      expect(logic.secret).to be(stale)
    end
  end

  context 'when a concurrent burn already consumed the secret (this burn loses)' do
    it 'does not count the burn and reports success: false' do
      logic = build_logic('identifier' => receipt.identifier, 'continue' => 'true')
      logic.process_params
      stale = pin_stale_secret_on(logic)

      # A concurrent request wins the atomic claim and burns the secret. With
      # the winner case above this pins burned!'s promise: caller-side
      # bookkeeping happens exactly once across N racing burns.
      expect(Onetime::Secret.load(secret.identifier).burned!).to be true
      before_count = Onetime::Customer.secrets_burned.value

      logic.process

      expect(logic.greenlighted).to be false
      expect(logic.success_data[:success]).to be false
      expect(Onetime::Customer.secrets_burned.value).to eq(before_count)
      expect(stale).not_to have_received(:load_owner)
      # Branch-entry pin -- see the concurrent-reveal case above.
      expect(logic.secret).to be(stale)
    end
  end

  # Burn must be subject to the same passphrase rate limiting as show/reveal:
  # without it, each wrong guess is a free brute-force oracle and a correct
  # guess destroys the secret as a side effect.
  context 'when the secret is passphrase-protected' do
    before do
      secret.update_passphrase!('correct horse battery')
    end

    def attempt_burn(guess)
      logic = build_logic(
        'identifier' => receipt.identifier,
        'continue'   => 'true',
        'passphrase' => guess,
      )
      logic.process_params
      logic.process
      logic
    end

    it 'raises a form error and records the attempt on a wrong guess' do
      expect { attempt_burn('wrong') }.to raise_error(OT::FormError)

      attempts = Onetime::Secret.dbclient.get("passphrase:attempts:#{secret.identifier}")
      expect(attempts.to_i).to eq(1)

      reloaded = Onetime::Secret.load(secret.identifier)
      expect(reloaded&.viewable?).to be true
    end

    it 'locks out after MAX_ATTEMPTS wrong guesses, even for the correct passphrase' do
      max = Onetime::Security::PassphraseRateLimiter::MAX_ATTEMPTS
      max.times { expect { attempt_burn('wrong') }.to raise_error(OT::FormError) }

      expect { attempt_burn('correct horse battery') }.to raise_error(Onetime::LimitExceeded)

      # The lockout rejected the request before the burn could happen.
      reloaded = Onetime::Secret.load(secret.identifier)
      expect(reloaded&.viewable?).to be true
    end

    it 'clears rate limit state and burns on the correct passphrase' do
      expect { attempt_burn('wrong') }.to raise_error(OT::FormError)

      logic = attempt_burn('correct horse battery')

      expect(logic.greenlighted).to be true
      expect(Onetime::Secret.dbclient.get("passphrase:attempts:#{secret.identifier}")).to be_nil
    end
  end
end

# apps/api/v2/spec/logic/secrets/show_secret_spec.rb
#
# frozen_string_literal: true

require_relative '../../../application'
require_relative File.join(Onetime::HOME, 'spec', 'spec_helper')

# Security regression coverage for the double-reveal race (ShowSecret variant).
#
# ShowSecret#process reveals via its private reveal_secret/verify_owner helpers,
# both of which return the value of Secret#revealed!. The gate must withhold the
# plaintext whenever that atomic claim was lost to a concurrent reveal.
#
# See reveal_secret_spec.rb for the sibling RevealSecret coverage; the gate is
# duplicated per controller by design (v1 legacy and each v2 endpoint own their
# own copy rather than sharing a base implementation).
RSpec.describe V2::Logic::Secrets::ShowSecret, type: :integration do
  before(:all) do
    require 'onetime'
    Onetime.boot! :test
  end

  def mock_session
    store = {}
    session = double('Session')
    allow(session).to receive(:[]) { |k| store[k] }
    allow(session).to receive(:[]=) { |k, v| store[k] = v }
    allow(session).to receive(:empty?).and_return(true)
    session
  end

  # customer: overrides the default anonymous caller for the verification
  # branches that depend on who is logged in. Pass params as a braced hash --
  # the customer: kwarg would otherwise swallow a bare trailing hash.
  def build_logic(params, customer: nil)
    customer ||= double('Customer', custid: 'anon', anonymous?: true, objid: nil)
    org      = double('Organization', objid: "org_#{SecureRandom.hex(4)}")
    allow(org).to receive(:can?).and_return(true)

    strategy_result = double('StrategyResult',
      session: mock_session,
      user: customer,
      metadata: { organization: org },
      auth_method: 'basicauth')

    described_class.new(strategy_result, params)
  end

  # Mark a spawned secret as a verification secret the way production does it
  # post-creation (lib/onetime/logic/base.rb send_verification_email,
  # apps/api/account/logic/account/request_email_change.rb:119-126). Partial
  # write on purpose -- save_fields HSETs only :verification and never
  # re-serializes the already-persisted ciphertext (house convention, cf.
  # lib/onetime/models/features/passphrase_hashing.rb:23-26). Must run BEFORE
  # build_logic: process_params fires in the Base constructor and loads its
  # own instance from Redis.
  def flag_as_verification!(secret)
    secret.verification = 'true'
    secret.save_fields(:verification)
  end

  let!(:pair)   { Onetime::Receipt.spawn_pair(nil, 3600, 'a secret value') }
  let(:receipt) { pair.first }
  let(:secret)  { pair.last }

  context 'when this request wins the reveal (the normal case)' do
    it 'returns the decrypted plaintext' do
      logic = build_logic({ 'identifier' => secret.identifier, 'continue' => 'true' })
      logic.process_params
      logic.process

      expect(logic.show_secret).to be true
      expect(logic.secret_value).to eq('a secret value')
      expect(logic.success_data[:record][:secret_value]).to eq('a secret value')
    end
  end

  # Safe-method pin (#3633): a metadata fetch (GET without continue) must not
  # advance the secret's lifecycle state. The old previewed! side effect is
  # replaced by append-only telemetry on the receipt's access timeline.
  context 'when fetching metadata without continue' do
    it 'leaves the lifecycle state untouched and records the access on the receipt' do
      logic = build_logic({ 'identifier' => secret.identifier })
      logic.process_params
      logic.process

      expect(logic.show_secret).to be false

      reloaded = Onetime::Secret.load(secret.identifier)
      expect(reloaded.state).to eq('new')
      expect(reloaded.viewable?).to be true

      timeline = Onetime::Receipt.load(receipt.identifier)
      expect(timeline.access_count).to eq(1)
      expect(timeline.access_events.last).to start_with('secret_get:')
    end

    it "records the distinct 'previewed' kind when the creator opens their own link" do
      owner = Onetime::Customer.create!(email: "show-owner-#{SecureRandom.hex(6)}@example.com")
      owner_pair = Onetime::Receipt.spawn_pair(owner.objid, 3600, 'a secret value')
      as_owner = double('Customer', custid: owner.custid, objid: owner.objid, anonymous?: false)

      logic = build_logic({ 'identifier' => owner_pair.last.identifier }, customer: as_owner)
      logic.process_params
      logic.process

      # The creator opening their OWN secret link is the "previewed" event
      # (#3633) -- a distinct, non-mutating signal from a third party's
      # 'secret_get'. It is telemetry only: the secret's state is untouched.
      timeline = Onetime::Receipt.load(owner_pair.first.identifier)
      expect(timeline.access_events.last).to start_with('previewed:')
      expect(Onetime::Secret.load(owner_pair.last.identifier).state).to eq('new')
    end
  end

  context 'when a concurrent request already won the reveal (this request loses)' do
    it 'does NOT emit the plaintext' do
      logic = build_logic({ 'identifier' => secret.identifier, 'continue' => 'true' })
      logic.process_params # loads this request's own :new instance

      # Hold viewable? true so process takes the reveal path and it is
      # secret.reveal! (not the viewable? guard) that withholds the plaintext by
      # losing the atomic claim to the concurrent winner. See reveal_secret_spec.
      allow(logic.secret).to receive(:viewable?).and_return(true)
      winner = Onetime::Secret.load(secret.identifier)
      expect(winner.revealed!).to be true

      logic.process

      expect(logic.show_secret).to be false
      expect(logic.secret_value).to be_nil
      expect(logic.success_data[:record]).not_to have_key(:secret_value)
    end
  end

  # Verification-flow coverage (verify_owner). verify_owner has no nil/
  # anonymous-owner guards -- it dereferences owner unconditionally -- so
  # every ShowSecret verification spec uses a real persisted owner. The
  # owner-nil and owner-anonymous error branches exist only in RevealSecret;
  # see reveal_secret_spec.rb for those.
  context 'when the secret is a verification secret' do
    # Unverified by default. Unique email each run -- the customer email index
    # in the shared test Redis persists across runs.
    let(:owner) do
      Onetime::Customer.create!(email: "show-verify-#{SecureRandom.hex(6)}@example.com")
    end
    let!(:pair) { Onetime::Receipt.spawn_pair(owner.objid, 3600, 'a secret value') }

    before { flag_as_verification!(secret) }

    context 'when an anonymous caller verifies the unverified owner' do
      it 'verifies the owner and reveals the plaintext' do
        logic = build_logic({ 'identifier' => secret.identifier, 'continue' => 'true' })
        logic.process_params
        logic.process

        expect(logic.show_secret).to be true
        expect(logic.secret_value).to eq('a secret value')
        expect(logic.success_data[:record][:secret_value]).to eq('a secret value')

        # Unlike RevealSecret, verify_owner does not delete reset_secret.
        reloaded = Onetime::Customer.load(owner.objid)
        expect(reloaded.verified?).to be true
        expect(reloaded.verified_by).to eq('email')

        # Consumed: the won claim destroys the record; the trailing access
        # telemetry only appends to the receipt timeline and cannot
        # resurrect the secret.
        expect(Onetime::Secret.load(secret.identifier)).to be_nil
      end
    end

    context 'when logged in as the unverified owner' do
      # Second half of verify_owner's disjunction (cust.custid == owner.custid
      # && !owner.verified?). Covered here as well as in RevealSecret because
      # the reveal gate is duplicated per controller by design -- ShowSecret's
      # copy would otherwise be exercised nowhere.
      it 'verifies the owner and reveals the plaintext' do
        as_owner = double('Customer', custid: owner.custid, anonymous?: false, objid: owner.objid)
        logic    = build_logic({ 'identifier' => secret.identifier, 'continue' => 'true' }, customer: as_owner)
        logic.process_params
        logic.process

        expect(logic.show_secret).to be true
        expect(logic.success_data[:record][:secret_value]).to eq('a secret value')

        reloaded = Onetime::Customer.load(owner.objid)
        expect(reloaded.verified?).to be true
        expect(reloaded.verified_by).to eq('email')
        expect(Onetime::Secret.load(secret.identifier)).to be_nil
      end
    end

    context 'when the owner is already verified' do
      # DIVERGENCE PIN -- current behavior, candidate for alignment:
      # verify_owner has no already-verified guard (its condition passes on
      # anonymous_user? alone), so an anonymous caller RE-verifies a verified
      # owner and overwrites verified_by provenance with 'email'. RevealSecret
      # treats the same input as an anomaly and leaves the owner untouched
      # (reveal_secret_spec.rb pins 'stripe_payment' preserved there). If
      # either controller changes, one of the two pins fails and forces a
      # conscious decision instead of a silent behavior shift.
      it 'reveals the plaintext and (unlike RevealSecret) overwrites verified_by' do
        owner.verified    = true
        owner.verified_by = 'stripe_payment'
        owner.save
        logic = build_logic({ 'identifier' => secret.identifier, 'continue' => 'true' })
        logic.process_params
        logic.process

        expect(logic.show_secret).to be true
        expect(logic.secret_value).to eq('a secret value')

        reloaded = Onetime::Customer.load(owner.objid)
        expect(reloaded.verified?).to be true
        expect(reloaded.verified_by).to eq('email') # provenance rewritten
        expect(Onetime::Secret.load(secret.identifier)).to be_nil
      end
    end

    context 'when already logged in as a different user' do
      it 'raises a form error and neither consumes nor previews the secret' do
        other = double('Customer', custid: 'cust_other', anonymous?: false, objid: 'objid_other')
        logic = build_logic({ 'identifier' => secret.identifier, 'continue' => 'true' }, customer: other)
        logic.process_params

        # Hardcoded message (not i18n) -- safe to match.
        expect { logic.process }.to raise_error(Onetime::FormError, /already logged in/)

        # The raise short-circuits process, so the secret stays :new and
        # viewable (state is never advanced on a read anyway; #3633).
        reloaded = Onetime::Secret.load(secret.identifier)
        expect(reloaded.state).to eq('new')
        expect(reloaded.viewable?).to be true
        expect(Onetime::Customer.load(owner.objid).verified?).to be false
      end
    end

    context 'when a concurrent request already won the reveal (this request loses)' do
      it 'still verifies the owner but does NOT emit the plaintext' do
        logic = build_logic({ 'identifier' => secret.identifier, 'continue' => 'true' })
        logic.process_params # loads this request's own :new instance

        # Hold the race window open -- same recipe as the loser spec above: it
        # must be reveal!'s atomic claim, not the viewable? guard, that
        # withholds the plaintext.
        allow(logic.secret).to receive(:viewable?).and_return(true)
        winner = Onetime::Secret.load(secret.identifier)
        expect(winner.revealed!).to be true

        logic.process

        expect(logic.show_secret).to be false
        expect(logic.secret_value).to be_nil
        expect(logic.success_data[:record]).not_to have_key(:secret_value)

        # ASYMMETRY PIN -- intentional current behavior: verify_owner mutates
        # the owner BEFORE secret.reveal!, so a losing racer still verifies
        # the account. Verification is idempotent bookkeeping; only the
        # PLAINTEXT is single-winner. If that ordering ever changes, these
        # assertions force a conscious decision instead of a silent shift.
        reloaded = Onetime::Customer.load(owner.objid)
        expect(reloaded.verified?).to be true
        expect(reloaded.verified_by).to eq('email')

        # The lost claim marks the loser's in-memory state 'revealed'; the
        # trailing access telemetry cannot resurrect the destroyed record.
        expect(Onetime::Secret.load(secret.identifier)).to be_nil
      end
    end
  end
end

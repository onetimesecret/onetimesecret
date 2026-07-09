# apps/api/v2/spec/logic/secrets/reveal_secret_spec.rb
#
# frozen_string_literal: true

require_relative '../../../application'
require_relative File.join(Onetime::HOME, 'spec', 'spec_helper')

# Security regression coverage for the double-reveal race.
#
# Burn-after-reading requires that a secret's plaintext reach at most ONE
# caller. Secret#revealed! performs an atomic compare-and-set claim and returns
# true only to the caller that won it; RevealSecret#process must gate the
# plaintext on that return value, so a request that LOST the race to a
# concurrent reveal never emits secret_value.
#
# Uses real Receipt/Secret objects (spawn_pair) so the atomic claim runs
# against Redis exactly as it does in production. process is exercised directly
# (raise_concerns, which handles guest-gating/entitlements/rate-limits, is out
# of scope here).
RSpec.describe V2::Logic::Secrets::RevealSecret, type: :integration do
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

  # Build a RevealSecret over a real secret. process derives cust from
  # strategy_result.user and never needs org (that is a raise_concerns concern).
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

  # Persist an org on the receipt so the reveal cascade fans the 'revealed'
  # event (with its actor attribution) out to a real, inspectable trail. The
  # cascade reloads the receipt from Redis, so org_id must be saved, not just
  # set in memory.
  def link_receipt_to_org!(receipt)
    org = Onetime::Organization.new(
      display_name: 'Actor Attribution Org',
      contact_email: "actor-#{SecureRandom.hex(6)}@example.com",
    ).tap(&:save)
    receipt.org_id = org.objid
    receipt.save_fields(:org_id)
    org
  end

  # An authenticated caller who owns `owner_objid`'s secret.
  def owner_double(owner_objid)
    double('Customer', custid: owner_objid, objid: owner_objid, anonymous?: false)
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

  context 'when a concurrent request already won the reveal (this request loses)' do
    it 'does NOT emit the plaintext' do
      logic = build_logic({ 'identifier' => secret.identifier, 'continue' => 'true' })
      logic.process_params # loads this request's own :new instance

      # A concurrent request wins the atomic claim and consumes the secret
      # AFTER this request has already passed its viewability check but BEFORE
      # it reveals -- the exact race window. Hold viewable? true so process
      # takes the reveal path and it is secret.reveal! (not the viewable? guard)
      # that must withhold the plaintext by losing the atomic claim.
      allow(logic.secret).to receive(:viewable?).and_return(true)
      winner = Onetime::Secret.load(secret.identifier)
      expect(winner.revealed!).to be true

      logic.process

      expect(logic.show_secret).to be false
      expect(logic.secret_value).to be_nil
      expect(logic.success_data[:record]).not_to have_key(:secret_value)
    end
  end

  # Actor attribution on reveal (#3639). "Who revealed it" is the first
  # question an auditor asks; the revealed event must carry the actor
  # discriminator computed from the request's customer. The ownership test
  # mirrors the fetch-side telemetry EXACTLY, including the anonymous guard
  # that keeps a guest link (owner_id nil) revealed by an anonymous caller
  # (objid nil) from matching nil == nil and being misattributed to "creator".
  context 'actor attribution (#3639)' do
    it 'records actor=creator when the authenticated owner reveals' do
      owner_objid = "objid_#{SecureRandom.hex(6)}"
      owner_pair  = Onetime::Receipt.spawn_pair(owner_objid, 3600, 'a secret value')
      org         = link_receipt_to_org!(owner_pair.first)

      logic = build_logic(
        { 'identifier' => owner_pair.last.identifier, 'continue' => 'true' },
        customer: owner_double(owner_objid),
      )
      logic.process_params
      logic.process

      expect(logic.secret_value).to eq('a secret value')
      event = org.audit_events_page.first
      expect(event['kind']).to eq('revealed')
      expect(event['actor']).to eq('creator')
      expect(event['actor_id']).to eq(owner_objid.slice(0, 8))
    end

    it 'records actor=authenticated_other when an authenticated non-owner reveals' do
      owner_objid = "objid_#{SecureRandom.hex(6)}"
      other_objid = "objid_#{SecureRandom.hex(6)}"
      owner_pair  = Onetime::Receipt.spawn_pair(owner_objid, 3600, 'a secret value')
      org         = link_receipt_to_org!(owner_pair.first)

      logic = build_logic(
        { 'identifier' => owner_pair.last.identifier, 'continue' => 'true' },
        customer: owner_double(other_objid), # authenticated, but not the owner
      )
      logic.process_params
      logic.process

      expect(logic.secret_value).to eq('a secret value')
      event = org.audit_events_page.first
      expect(event['actor']).to eq('authenticated_other')
      expect(event['actor_id']).to eq(other_objid.slice(0, 8))
    end

    # THE privacy pin: an anonymous reveal of a guest link (secret owner_id nil,
    # caller objid nil) must be 'anonymous' and NEVER 'creator', even though
    # owner?(cust) would match nil == nil without the anonymous_user? guard.
    it 'records actor=anonymous for an anonymous reveal of a guest link (never creator)' do
      org = link_receipt_to_org!(receipt) # default pair is a guest secret (owner_id nil)

      logic = build_logic({ 'identifier' => secret.identifier, 'continue' => 'true' })
      logic.process_params
      logic.process

      expect(logic.secret_value).to eq('a secret value')
      event = org.audit_events_page.first
      expect(event['kind']).to eq('revealed')
      expect(event['actor']).to eq('anonymous')
      expect(event['actor']).not_to eq('creator')
      expect(event).not_to have_key('actor_id')
    end
  end

  # Verification-flow coverage. A verification secret carries the account
  # confirmation for its owner: revealing it verifies the owner's account
  # (reveal_secret.rb lines 97-165). Production sets the flag post-creation,
  # so these specs do the same via flag_as_verification! before build_logic.
  context 'when the secret is a verification secret' do
    # Unverified by default. Unique email each run -- the customer email index
    # in the shared test Redis persists across runs.
    let(:owner) do
      Onetime::Customer.create!(email: "reveal-verify-#{SecureRandom.hex(6)}@example.com")
    end
    let!(:pair) { Onetime::Receipt.spawn_pair(owner.objid, 3600, 'a secret value') }

    before { flag_as_verification!(secret) }

    context 'when an anonymous caller verifies the unverified owner' do
      it 'verifies the owner and reveals the plaintext' do
        owner.reset_secret = secret.identifier # standalone dbkey, writes immediately
        logic = build_logic({ 'identifier' => secret.identifier, 'continue' => 'true' })
        logic.process_params
        logic.process

        expect(logic.show_secret).to be true
        expect(logic.secret_value).to eq('a secret value')
        expect(logic.success_data[:record][:secret_value]).to eq('a secret value')

        reloaded = Onetime::Customer.load(owner.objid)
        expect(reloaded.verified?).to be true
        expect(reloaded.verified_by).to eq('email')
        # value (GET) rather than exists? -- StringKey#exists? stays truthy
        # after delete! on familia 2.10.1 (Integer 0 from EXISTS is truthy).
        expect(reloaded.reset_secret.value).to be_nil
        expect(Onetime::Secret.load(secret.identifier)).to be_nil # consumed
      end
    end

    context 'when logged in as the unverified owner' do
      # Second half of the disjunction that gates the verify branch:
      # cust.custid == owner.custid && !owner.verified?
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
      it 'still reveals the plaintext and leaves the owner untouched' do
        owner.verified    = true
        owner.verified_by = 'stripe_payment' # non-email provenance so a rewrite would be visible
        owner.save
        logic = build_logic({ 'identifier' => secret.identifier, 'continue' => 'true' })
        logic.process_params
        logic.process

        expect(logic.show_secret).to be true
        expect(logic.secret_value).to eq('a secret value')
        expect(logic.success_data[:record][:secret_value]).to eq('a secret value')
        expect(Onetime::Secret.load(secret.identifier)).to be_nil

        reloaded = Onetime::Customer.load(owner.objid)
        expect(reloaded.verified?).to be true
        expect(reloaded.verified_by).to eq('stripe_payment') # NOT overwritten to 'email'
      end
    end

    context 'when the secret has no owner' do
      let!(:pair) { Onetime::Receipt.spawn_pair(nil, 3600, 'a secret value') }

      it 'raises a form error and does not consume the secret' do
        logic = build_logic({ 'identifier' => secret.identifier, 'continue' => 'true' })
        logic.process_params

        # Message resolves through I18n with a default fallback ('Verification
        # not valid'); pin only the class so locale files cannot flake this.
        expect { logic.process }.to raise_error(Onetime::FormError)

        reloaded = Onetime::Secret.load(secret.identifier)
        expect(reloaded).not_to be_nil
        expect(reloaded.state).to eq('new')
        expect(reloaded.viewable?).to be true
      end
    end

    context 'when the owner is anonymous' do
      let!(:pair) { Onetime::Receipt.spawn_pair(nil, 3600, 'a secret value') }

      it 'raises a form error and does not consume the secret' do
        logic = build_logic({ 'identifier' => secret.identifier, 'continue' => 'true' })
        logic.process_params

        # The only owner double in these specs: Customer#save raises for
        # anonymous customers, so an anonymous owner can never be loaded from
        # Redis. Stub just the lookup -- viewable?/reveal! stay real so the
        # raise must come from the branch itself.
        anon_owner = double('AnonOwner', anonymous?: true)
        allow(logic.secret).to receive(:load_owner).and_return(anon_owner)

        expect { logic.process }.to raise_error(Onetime::FormError)

        reloaded = Onetime::Secret.load(secret.identifier)
        expect(reloaded).not_to be_nil
        expect(reloaded.state).to eq('new')
        expect(reloaded.viewable?).to be true
      end
    end

    context 'when already logged in as a different user' do
      it 'raises a form error, consumes nothing, and verifies no one' do
        other = double('Customer', custid: 'cust_other', anonymous?: false, objid: 'objid_other')
        logic = build_logic({ 'identifier' => secret.identifier, 'continue' => 'true' }, customer: other)
        logic.process_params

        # I18n default 'Cannot verify when logged in' -- pin only the class.
        expect { logic.process }.to raise_error(Onetime::FormError)

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

        # ASYMMETRY PIN -- intentional current behavior: the owner mutation
        # runs BEFORE reveal!, so a losing racer still verifies the account.
        # Verification is idempotent bookkeeping; only the PLAINTEXT is
        # single-winner. If that ordering ever changes, these assertions force
        # a conscious decision instead of a silent behavior shift.
        reloaded = Onetime::Customer.load(owner.objid)
        expect(reloaded.verified?).to be true
        expect(reloaded.verified_by).to eq('email')
      end
    end
  end
end

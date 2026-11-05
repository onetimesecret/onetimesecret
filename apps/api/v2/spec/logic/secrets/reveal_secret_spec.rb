# apps/api/v2/spec/logic/secrets/reveal_secret_spec.rb
#
# frozen_string_literal: true

require_relative '../../../application'
require_relative File.join(Onetime::HOME, 'spec', 'spec_helper')
require_relative '../../support/actor_attribution_helpers'

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
# of scope except where an example needs its viewability check for ordering).
RSpec.describe V2::Logic::Secrets::RevealSecret, type: :integration do
  include ActorAttributionSpecHelpers

  before(:all) do
    require 'onetime'
    Onetime.boot! :test
  end

  # Empty by default, the stateless (BasicAuth) shape. Pass entries to model a
  # browser session, which carries at least its CSRF token.
  def mock_session(entries = {})
    store = entries.dup
    session = double('Session')
    allow(session).to receive(:[]) { |k| store[k] }
    allow(session).to receive(:[]=) { |k, v| store[k] = v }
    allow(session).to receive(:empty?) { store.empty? }
    allow(session).to receive(:clear) { store.clear }
    session
  end

  # Build a RevealSecret over a real secret. process derives cust from
  # strategy_result.user and never needs org (that is a raise_concerns concern).
  # Without customer: the caller is anonymous and the user is nil, which is
  # what NoAuthStrategy returns on the auth=noauth guest reveal routes (#2733).
  # The anonymous Customer double that used to stand in here hid #4831.
  # customer: sets who is logged in for the branches that depend on it. Pass
  # params as a braced hash -- the customer: kwarg would otherwise swallow a
  # bare trailing hash.
  def build_logic(params, customer: nil, session: mock_session)
    org = double('Organization', objid: "org_#{SecureRandom.hex(4)}")
    allow(org).to receive(:can?).and_return(true)

    strategy_result = double('StrategyResult',
      session: session,
      user: customer,
      metadata: { organization: org },
      auth_method: customer ? 'basicauth' : 'noauth')

    described_class.new(strategy_result, params)
  end

  # secret_logger is an instance method (LoggerMethods), so the whole
  # SemanticLogger call is capturable: [message, payload] per emission. The
  # hash is SemanticLogger's payload argument, not part of the message.
  def capture_secret_logs(logic)
    captured = []
    logger   = double('SecretLogger')
    %i[debug info warn error].each do |level|
      allow(logger).to receive(level) { |message, payload = {}| captured << [message, payload] }
    end
    allow(logic).to receive(:secret_logger).and_return(logger)
    captured
  end

  def payload_for(captured, message)
    entry = captured.find { |logged, _| logged == message }
    expect(entry).not_to be_nil, "no #{message.inspect} log was emitted"
    entry.last
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

  # Record the address the link was emailed to, as send_verification_email
  # does (Secret#delivered_to?). Without it the secret is a link minted before
  # the digest was written. Same partial-write convention and ordering as
  # flag_as_verification!.
  def record_delivery!(secret, address)
    secret.delivery_digest = Onetime::Secret.delivery_digest_for(address)
    secret.save_fields(:delivery_digest)
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

    # The rate-limit clear is settled on the passphrase verdict, not on the
    # process-time show_secret verdict: a correct guess earns the clear whether
    # or not this caller got the plaintext. Regression for the ordering that
    # ran the clear inside the reveal branch: a concurrent consumer claiming
    # the secret after raise_concerns but before process recomputed viewability
    # left a correct verification without its corresponding clear. This race
    # window is deliberately EARLIER than the one above -- no viewable? stub,
    # because with one held true the old code entered the reveal branch and
    # cleared anyway, which is exactly what made the earlier draft of this
    # example pass against the code it was meant to catch.
    it 'still clears the passphrase rate limit on a correct guess' do
      secret.update_passphrase!('correct horse battery')
      attempts_key = "passphrase:attempts:#{secret.identifier}"

      wrong = build_logic(
        { 'identifier' => secret.identifier, 'continue' => 'true', 'passphrase' => 'nope' },
      )
      wrong.process_params
      expect { wrong.process }.to raise_error(Onetime::FormError)
      expect(Onetime::Secret.dbclient.get(attempts_key).to_i).to eq(1)

      logic = build_logic(
        { 'identifier' => secret.identifier, 'continue' => 'true', 'passphrase' => 'correct horse battery' },
      )
      logic.process_params

      # Production ordering: this request passes the raise_concerns viewability
      # check, THEN a concurrent request takes the atomic claim, so process
      # recomputes viewable? as false and show_secret never becomes true.
      logic.raise_concerns
      winner = Onetime::Secret.load(secret.identifier)
      expect(winner.revealed!).to be true

      logic.process

      expect(logic.show_secret).to be false
      expect(logic.secret_value).to be_nil
      expect(Onetime::Secret.dbclient.get(attempts_key)).to be_nil
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
      event = org.secret_activity_events_page.first
      expect(event['kind']).to eq('revealed')
      expect(event['actor']).to eq('creator')
      expect(event['actor_id']).to eq(owner_objid)
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
      event = org.secret_activity_events_page.first
      expect(event['actor']).to eq('authenticated_other')
      expect(event['actor_id']).to eq(other_objid)
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
      event = org.secret_activity_events_page.first
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

    before do
      flag_as_verification!(secret)
      # The stamp runs through SetCustomerVerification, whose #call ends in
      # the deferred federation claim (#4754 review, round 3). Observed as a
      # seam, like webauthn_verify_account_hook_spec.rb does: the real claim
      # finds no owned workspace for a bare test customer and returns false.
      allow(Auth::Operations::EnsureDefaultWorkspace).to receive(:claim_pending_federation_for).and_call_original
    end

    # The emailed link is opened on an auth=noauth route, so the caller has no
    # customer at all (build_logic's default). #4831 was this case.
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

      # In a simple-mode install run without AUTHENTICATION_MODE a standard
      # signup defers the federated subscription claim, and following this link
      # is the only self-service mailbox proof, so it must be the re-claim
      # trigger (#4754 review, round 3). The link proves the mailbox it was
      # sent to and no other, so the claim runs for a link sent to the owner's
      # current address and is held to that address.
      it "runs the deferred federation claim for the owner's own address" do
        record_delivery!(secret, owner.email)
        logic = build_logic({ 'identifier' => secret.identifier, 'continue' => 'true' })
        logic.process_params
        logic.process

        expect(logic.secret_value).to eq('a secret value')
        expect(Auth::Operations::EnsureDefaultWorkspace).to have_received(:claim_pending_federation_for)
          .with(an_object_having_attributes(extid: owner.extid), own_address_only: true)
      end

      # A link sent to another address proves that mailbox, not the owner's
      # current one, and a link minted before the delivery address was
      # recorded proves nothing about which. Both still verify the owner, as
      # the direct stamp did; neither runs the claim.
      it 'verifies the owner without the claim for a link sent to another address' do
        record_delivery!(secret, "reveal-elsewhere-#{SecureRandom.hex(6)}@example.com")
        logic = build_logic({ 'identifier' => secret.identifier, 'continue' => 'true' })
        logic.process_params
        logic.process

        expect(logic.secret_value).to eq('a secret value')
        expect(Onetime::Customer.load(owner.objid).verified_by).to eq('email')
        expect(Auth::Operations::EnsureDefaultWorkspace).not_to have_received(:claim_pending_federation_for)
      end

      it 'verifies the owner without the claim for a link that recorded no delivery address' do
        logic = build_logic({ 'identifier' => secret.identifier, 'continue' => 'true' })
        logic.process_params
        logic.process

        expect(logic.secret_value).to eq('a secret value')
        expect(Onetime::Customer.load(owner.objid).verified_by).to eq('email')
        expect(Auth::Operations::EnsureDefaultWorkspace).not_to have_received(:claim_pending_federation_for)
      end

      # The success line is written after the stamp, from its outcome, so it
      # is never logged for a reveal that recorded nothing (the full-mode
      # context below).
      it 'logs the success line once the stamp is recorded' do
        logic    = build_logic({ 'identifier' => secret.identifier, 'continue' => 'true' })
        captured = capture_secret_logs(logic)
        logic.process_params
        logic.process

        expect(payload_for(captured, 'Owner verification successful')[:result]).to eq(:verified)
        expect(Onetime::Customer.load(owner.objid).verified_by).to eq('email')
      end

      # The browser that opens the link has a guest session (its CSRF token at
      # least). Verifying clears it; CsrfResponseHeader mints a fresh token on
      # the same response (csrf_response_header_spec.rb).
      it "clears the visitor's guest session" do
        session = mock_session('csrf' => 'guest-token')
        logic   = build_logic({ 'identifier' => secret.identifier, 'continue' => 'true' }, session: session)
        logic.process_params
        logic.process

        expect(logic.secret_value).to eq('a secret value')
        expect(session).to be_empty
      end
    end

    context 'when logged in as the unverified owner' do
      # Second half of the disjunction that gates the verify branch:
      # cust.custid == owner.custid && !owner.verified?
      it 'verifies the owner and reveals the plaintext' do
        as_owner = double('Customer', custid: owner.custid, anonymous?: false, objid: owner.objid,
          extid: owner.extid)
        session  = mock_session('csrf' => 'owner-token', 'external_id' => owner.extid)
        logic    = build_logic(
          { 'identifier' => secret.identifier, 'continue' => 'true' },
          customer: as_owner,
          session: session,
        )
        logic.process_params
        logic.process

        expect(logic.show_secret).to be true
        expect(logic.success_data[:record][:secret_value]).to eq('a secret value')
        expect(session).to be_empty # signed out; the owner signs in again

        reloaded = Onetime::Customer.load(owner.objid)
        expect(reloaded.verified?).to be true
        expect(reloaded.verified_by).to eq('email')
        expect(Onetime::Secret.load(secret.identifier)).to be_nil
      end
    end

    context 'when the owner is already mailbox-verified' do
      it 'still reveals the plaintext and leaves the owner untouched' do
        owner.verified    = true
        owner.verified_by = 'colonel_admin' # mailbox proof, but not 'email', so a rewrite would be visible
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
        expect(reloaded.verified_by).to eq('colonel_admin') # NOT overwritten to 'email'
      end
    end

    # #4735: a verified stamp without mailbox proof (payment, autoverify, IdP)
    # is not "already verified" for this branch. Following the link delivered
    # to the address IS mailbox proof, so the owner acquires it here.
    context 'when the owner is verified without mailbox proof' do
      it 'reveals the plaintext and upgrades the provenance to email' do
        owner.verified    = true
        owner.verified_by = 'stripe_payment'
        owner.save
        expect(owner.mailbox_verified?).to be false

        logic = build_logic({ 'identifier' => secret.identifier, 'continue' => 'true' })
        logic.process_params
        logic.process

        expect(logic.show_secret).to be true
        expect(logic.secret_value).to eq('a secret value')
        expect(Onetime::Secret.load(secret.identifier)).to be_nil

        reloaded = Onetime::Customer.load(owner.objid)
        expect(reloaded.verified?).to be true
        expect(reloaded.verified_by).to eq('email')
        expect(reloaded.mailbox_verified?).to be true
      end
    end

    # #4735: the email-change confirmation secret is delivered to the PROPOSED
    # address. A customer without mailbox proof must not be able to turn it into
    # proof of their CURRENT address by feeding it to the reveal endpoint.
    context 'when the secret is the pending email-change confirmation' do
      it 'reveals the plaintext without stamping the owner' do
        owner.verified    = true
        owner.verified_by = 'stripe_payment'
        owner.save
        owner.pending_email_change = secret.identifier

        as_owner = double('Customer', custid: owner.custid, anonymous?: false, objid: owner.objid,
          extid: owner.extid)
        logic    = build_logic({ 'identifier' => secret.identifier, 'continue' => 'true' }, customer: as_owner)
        logic.process_params
        logic.process

        expect(logic.show_secret).to be true
        expect(Onetime::Secret.load(secret.identifier)).to be_nil

        reloaded = Onetime::Customer.load(owner.objid)
        expect(reloaded.verified_by).to eq('stripe_payment')
        expect(reloaded.mailbox_verified?).to be false
      end

      # No stamp, no claim: the confirmation link proves nothing about the
      # current address, so it must not deliver the benefit deferred on it.
      it 'does not run the federation claim' do
        owner.pending_email_change = secret.identifier

        logic = build_logic({ 'identifier' => secret.identifier, 'continue' => 'true' })
        logic.process_params
        logic.process

        expect(logic.show_secret).to be true
        expect(Auth::Operations::EnsureDefaultWorkspace).not_to have_received(:claim_pending_federation_for)
      end

      it 'is recognised by the secret kind alone, without the pending pointer' do
        owner.verified    = true
        owner.verified_by = 'autoverify'
        owner.save
        secret.kind = 'email_change'
        secret.save_fields(:kind)
        # No pending_email_change: a later request overwrote it, or it expired.

        logic = build_logic({ 'identifier' => secret.identifier, 'continue' => 'true' })
        logic.process_params
        logic.process

        expect(logic.show_secret).to be true
        reloaded = Onetime::Customer.load(owner.objid)
        expect(reloaded.verified_by).to eq('autoverify')
        expect(reloaded.mailbox_verified?).to be false
      end

      it 'does not stamp an unverified owner either' do
        owner.pending_email_change = secret.identifier

        logic = build_logic({ 'identifier' => secret.identifier, 'continue' => 'true' })
        logic.process_params
        logic.process

        expect(logic.show_secret).to be true
        reloaded = Onetime::Customer.load(owner.objid)
        expect(reloaded.verified?).to be false
      end
    end

    # #4735 review F1: a confirmation secret minted BEFORE Secret#kind was
    # recorded has no kind, and two requests left two live secrets with only
    # the second on pending_email_change. The first is still revealable; it
    # was delivered to a proposed address and must not read as proof of the
    # current one. Minted exactly as RequestEmailChange did: Secret.create!,
    # no receipt, the proposed address as the ciphertext.
    context 'when the secret is a legacy email-change confirmation no longer on the pointer' do
      let(:secret) do
        legacy              = Onetime::Secret.create!(owner_id: owner.objid)
        legacy.custid       = owner.objid
        legacy.ciphertext   = 'proposed@example.com'
        legacy.save
        legacy
      end

      it 'reveals the plaintext without stamping an SSO-only owner' do
        owner.verified    = true
        owner.verified_by = 'sso'
        owner.save

        owner.pending_email_change = "#{secret.identifier}-superseded-by-a-second-request"

        as_owner = double('Customer', custid: owner.custid, anonymous?: false, objid: owner.objid,
          extid: owner.extid)
        logic    = build_logic({ 'identifier' => secret.identifier, 'continue' => 'true' }, customer: as_owner)
        logic.process_params
        logic.process

        expect(logic.show_secret).to be true
        expect(logic.secret_value).to eq('proposed@example.com')
        expect(Onetime::Secret.load(secret.identifier)).to be_nil

        reloaded = Onetime::Customer.load(owner.objid)
        expect(reloaded.verified_by).to eq('sso')
        expect(reloaded.mailbox_verified?).to be false
      end

      it 'does not stamp an unverified owner either' do
        logic = build_logic({ 'identifier' => secret.identifier, 'continue' => 'true' })
        logic.process_params
        logic.process

        expect(logic.show_secret).to be true
        expect(Onetime::Customer.load(owner.objid).verified?).to be false
      end
    end

    # The receipt-backed verification secret predates the kind too, and its
    # reset_secret pointer (24h) outlives the link (24 days) by nothing like
    # enough: an older signup link must keep verifying after the pointer has
    # moved on to a resend, because only send_verification_email mints one.
    context 'when the secret is a legacy account-verification link whose pointer has moved on' do
      it 'still verifies the owner' do
        owner.reset_secret = 'a-newer-resend'

        logic = build_logic({ 'identifier' => secret.identifier, 'continue' => 'true' })
        logic.process_params
        logic.process

        expect(logic.show_secret).to be true
        reloaded = Onetime::Customer.load(owner.objid)
        expect(reloaded.verified_by).to eq('email')
      end

      # The pointer is shared with password recovery: when it has moved on to a
      # newer recovery token, consuming this older link must not delete it
      # (#4735 review, F7).
      it 'leaves the newer pointer in place' do
        owner.reset_secret = 'a-newer-recovery-token'

        logic = build_logic({ 'identifier' => secret.identifier, 'continue' => 'true' })
        logic.process_params
        logic.process

        expect(logic.show_secret).to be true
        expect(Onetime::Customer.load(owner.objid).reset_secret.value).to eq('a-newer-recovery-token')
      end
    end

    # An operator email change (`bin/ots customers change-email` or the
    # colonel endpoint, without --keep-verified) resets verification and
    # rewrites the default workspace's contact email, which the claim hashes,
    # to the new address, but leaves the links already sent to the earlier
    # address live. Following one still verifies the owner, as the direct
    # stamp did, but it proved the earlier mailbox only, so it must not apply
    # the new address's pending federated subscription (#4754 review, round
    # 3). Real records end to end: the workspace, the pending record, the
    # change and the claim.
    context 'when an operator changed the address after the link was sent' do
      let(:new_address) { "reveal-moved-#{SecureRandom.hex(6)}@example.com" }
      let(:cleanup) { [] }

      around do |example|
        original_secret          = ENV['FEDERATION_SECRET']
        ENV['FEDERATION_SECRET'] = 'test_federation_secret_32chars!'
        example.run
      ensure
        ENV['FEDERATION_SECRET'] = original_secret
      end

      before do
        require 'auth/operations/customers/change_email'
        require 'billing/models/pending_federated_subscription'
      end

      after do
        cleanup.each do |obj|
          obj.is_a?(Onetime::Organization) ? obj.delete! : obj.destroy!
        rescue StandardError
          nil
        end
      end

      def store_pending_for(address)
        hash    = Onetime::Utils::EmailHash.compute(address)
        pending = Billing::PendingFederatedSubscription.new(hash)
        pending.subscription_status     = 'active'
        pending.planid                  = 'pro_monthly'
        pending.subscription_period_end = (Time.now.to_i + (30 * 24 * 3600)).to_s
        pending.region                  = 'US'
        pending.received_at             = Time.now.to_i.to_s
        pending.save
        cleanup << pending
        hash
      end

      # The workspace with the claim deferred, as lazy creation leaves it in a
      # process without AUTHENTICATION_MODE (the record rule,
      # Customer#federation_claim_deferred?). The lane exports the variable,
      # so the caller flag stands in for that rule. Then the operator change.
      def move_owner_to(address)
        org = Auth::Operations::EnsureDefaultWorkspace.new(customer: owner, require_verification: true).call[:organization]
        cleanup << org
        result = Auth::Operations::Customers::ChangeEmail.new(
          customer: owner, new_email: address, actor: 'cli', dry_run: false,
          require_verification: true, revoke_sessions: false, notify: false
        ).call
        expect(result.status).to eq(:success)
        org
      end

      it 'verifies the owner but leaves the pending subscription of the new address' do
        record_delivery!(secret, owner.email) # sent before the change
        hash = store_pending_for(new_address)
        org  = move_owner_to(new_address)

        logic = build_logic({ 'identifier' => secret.identifier, 'continue' => 'true' })
        logic.process_params
        logic.process

        expect(logic.secret_value).to eq('a secret value')
        reloaded = Onetime::Customer.load(owner.objid)
        expect(reloaded.email).to eq(new_address)
        expect(reloaded.verified_by).to eq('email')
        org.refresh!
        expect(org.contact_email).to eq(new_address)
        expect(org.subscription_federated?).to be(false)
        expect(Billing::PendingFederatedSubscription.find_by_email_hash(hash)).not_to be_nil
      end

      # The control: a link sent to the new address after the change proves
      # it, so the same state applies the record.
      it 'applies it for a link sent to the new address' do
        hash = store_pending_for(new_address)
        org  = move_owner_to(new_address)
        _receipt, resent = Onetime::Receipt.spawn_pair(owner.objid, 3600, 'a secret value')
        flag_as_verification!(resent)
        record_delivery!(resent, new_address)

        logic = build_logic({ 'identifier' => resent.identifier, 'continue' => 'true' })
        logic.process_params
        logic.process

        expect(logic.secret_value).to eq('a secret value')
        org.refresh!
        expect(org.subscription_federated?).to be(true)
        expect(org.planid.to_s).to eq('pro_monthly')
        expect(Billing::PendingFederatedSubscription.find_by_email_hash(hash)).to be_nil
      end
    end

    # The verification secret is minted only by simple-mode flows (Core's
    # /auth/* routes, which the Auth app shadows in full auth mode), but the
    # reveal routes serve every mode, so a link minted before a switch to full
    # auth mode can still be followed. Rodauth owns verification there, so the
    # shared stamp (SetCustomerVerification.record_mailbox_proof) records
    # nothing: it builds no operation, so no SQL is reached, and the reveal
    # proceeds. Reconciling the accounts row from here would let an account
    # Rodauth blocks sign in; the old direct stamp wrote Redis alone and left
    # the row Unverified (#4754 review, round 3).
    context 'when the link is followed after a switch to full auth mode' do
      let(:auth_logger) { double('AuthLogger', info: nil) }

      before do
        allow(Onetime.auth_config).to receive(:mode).and_return('full')
        allow(Auth::Operations::SetCustomerVerification).to receive(:new).and_call_original
        allow(Auth::Operations::SetCustomerVerification).to receive(:auth_logger).and_return(auth_logger)
      end

      it 'reveals the plaintext and leaves the owner unverified' do
        owner.reset_secret = secret.identifier
        logic = build_logic({ 'identifier' => secret.identifier, 'continue' => 'true' })
        logic.process_params
        logic.process

        expect(logic.show_secret).to be true
        expect(logic.secret_value).to eq('a secret value')
        expect(Onetime::Secret.load(secret.identifier)).to be_nil

        expect(Auth::Operations::SetCustomerVerification).not_to have_received(:new)
        reloaded = Onetime::Customer.load(owner.objid)
        expect(reloaded.verified?).to be false
        expect(reloaded.verified_by.to_s).to eq('')
        # The order is unchanged: the pointer release follows the (skipped) stamp.
        expect(reloaded.reset_secret.value).to be_nil
        expect(Auth::Operations::EnsureDefaultWorkspace).not_to have_received(:claim_pending_federation_for)
      end

      it 'leaves a stamp without mailbox proof as it was' do
        owner.verified    = true
        owner.verified_by = 'stripe_payment'
        owner.save
        logic = build_logic({ 'identifier' => secret.identifier, 'continue' => 'true' })
        logic.process_params
        logic.process

        expect(logic.secret_value).to eq('a secret value')
        reloaded = Onetime::Customer.load(owner.objid)
        expect(reloaded.verified_by).to eq('stripe_payment')
        expect(reloaded.mailbox_verified?).to be false
      end

      it 'logs the skip at info, and no success line' do
        logic    = build_logic({ 'identifier' => secret.identifier, 'continue' => 'true' })
        captured = capture_secret_logs(logic)
        logic.process_params
        logic.process

        expect(auth_logger).to have_received(:info).with(
          /redeemed in full auth mode; Rodauth owns account verification there/,
          { customer: owner.extid },
        )
        payload = payload_for(captured, 'Verification link redeemed in full auth mode; revealing without stamping')
        expect(payload[:result]).to eq(:not_stamped_full_auth_mode)
        expect(captured.map(&:first)).not_to include('Owner verification successful')
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
        # Legacy-shaped custid (an email address) so the log assertion below
        # would catch a revert to custid in the payload.
        other   = double('Customer', custid: 'other@example.com', anonymous?: false, objid: 'objid_other',
          extid: 'urother')
        session = mock_session('csrf' => 'other-token', 'external_id' => 'urother')
        logic   = build_logic(
          { 'identifier' => secret.identifier, 'continue' => 'true' },
          customer: other,
          session: session,
        )
        captured = capture_secret_logs(logic)
        logic.process_params

        # I18n default 'Cannot verify when logged in' -- pin only the class.
        expect { logic.process }.to raise_error(Onetime::FormError)

        # PII pin (#4211 review): custid IS the email address on legacy
        # (pre-v0.22) records, so this refusal log carries the extid.
        payload = payload_for(captured, 'Invalid verification - user already logged in')
        expect(payload[:user_id]).to eq('urother')
        expect(payload.values.join(' ')).not_to include('@')

        reloaded = Onetime::Secret.load(secret.identifier)
        expect(reloaded.state).to eq('new')
        expect(reloaded.viewable?).to be true
        expect(Onetime::Customer.load(owner.objid).verified?).to be false
        expect(session).not_to be_empty # the refusal does not sign them out
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
  # The wrong-guess log is the highest-volume of the reveal logs (one per
  # brute-force attempt), so it is the worst place to carry an address.
  context 'when the passphrase is wrong' do
    let(:caller_customer) do
      # Legacy-shaped: custid is the address itself.
      double('Customer',
        custid: 'revealer@example.com',
        extid: 'urrevealer',
        objid: 'objid_revealer',
        anonymous?: false)
    end

    it 'records the failed attempt against the extid, never custid' do
      secret.update_passphrase!('correct horse battery')
      logic = build_logic(
        { 'identifier' => secret.identifier, 'continue' => 'true', 'passphrase' => 'wrong' },
        customer: caller_customer,
      )
      captured = capture_secret_logs(logic)
      logic.process_params

      expect { logic.process }.to raise_error(Onetime::FormError)

      payload = payload_for(captured, 'Incorrect passphrase attempt')
      expect(payload[:user_id]).to eq('urrevealer')
      expect(payload.values.join(' ')).not_to include('@')

      # Positive control for the continue=false context below, which asserts
      # this key stays nil: a committed wrong guess must write it.
      expect(Onetime::Secret.dbclient.get("passphrase:attempts:#{secret.identifier}").to_i).to eq(1)
    end
  end

  # Passphrase oracle regression: the guess is verified ONLY on a committed
  # reveal (continue=true). Without the gate, continue=false separated a right
  # guess (200, no reveal) from a wrong one (form error) and burned a
  # rate-limit attempt on a guess that was never acted on -- a free,
  # non-destructive brute-force oracle.
  context 'when continue is false on a passphrase-protected secret' do
    before { secret.update_passphrase!('correct horse battery') }

    def attempts_key
      "passphrase:attempts:#{secret.identifier}"
    end

    # The message expectation must be set on logic.secret: build_logic ->
    # process_params already loaded this request's own instance from Redis.
    def probe(guess)
      logic = build_logic(
        { 'identifier' => secret.identifier, 'continue' => 'false', 'passphrase' => guess },
      )
      logic.process_params
      expect(logic.secret).not_to receive(:passphrase?)
      expect { logic.process }.not_to raise_error
      logic
    end

    it 'does not raise on a wrong guess, verifies nothing, and records no attempt' do
      logic = probe('wrong')

      expect(logic.show_secret).to be false
      expect(logic.secret_value).to be_nil
      expect(logic.success_data[:details]).not_to have_key(:correct_passphrase)
      expect(logic.success_data[:record]).not_to have_key(:secret_value)
      expect(Onetime::Secret.dbclient.get(attempts_key)).to be_nil

      # Nothing was consumed either: the secret is still there to be revealed.
      expect(Onetime::Secret.load(secret.identifier)&.viewable?).to be true
    end

    it 'answers a wrong guess identically to a right one' do
      wrong   = probe('wrong').success_data[:details]
      correct = probe('correct horse battery').success_data[:details]

      expect(wrong).to eq(correct)
      expect(Onetime::Secret.dbclient.get(attempts_key)).to be_nil
      expect(Onetime::Secret.load(secret.identifier)&.viewable?).to be true
    end
  end

  # C10/QS-6: SECRET lifecycle safety.
  #
  # Fast-fail: when the boot-time verifier flagged a key mismatch, a
  # reveal-intent request must be refused in raise_concerns -- before any
  # atomic claim -- so no secret is consumed by a decrypt that cannot
  # succeed. Rollback: when a single ciphertext fails to decrypt anyway
  # (predates an adopted rotation), reveal! returns the claim and the typed
  # error propagates; the secret survives.
  context 'when the running SECRET does not match the datastore (C10)' do
    around do |example|
      previous_state = Onetime.secret_verifier_state
      example.run
    ensure
      Onetime.secret_verifier_state = previous_state
    end

    def build_gated_logic(params)
      logic = build_logic(params)
      # raise_concerns also gates guest routes / entitlements / rate limits;
      # neutralize those so the assertion isolates the verifier fast-fail.
      allow(logic).to receive(:require_guest_route_enabled!)
      allow(logic).to receive(:require_entitlement!)
      logic
    end

    it 'fast-fails a reveal-intent request in raise_concerns without taking the claim' do
      Onetime.secret_verifier_state = :mismatch
      logic = build_gated_logic({ 'identifier' => secret.identifier, 'continue' => 'true' })
      logic.process_params

      expect { logic.raise_concerns }.to raise_error(Onetime::SecretUndecryptable)

      # No CAS was taken: the secret is untouched and still viewable.
      reloaded = Onetime::Secret.load(secret.identifier)
      expect(reloaded.state).to eq('new')
      expect(reloaded.viewable?).to be true
    end

    it 'does not gate metadata-only requests (continue absent)' do
      Onetime.secret_verifier_state = :mismatch
      logic = build_gated_logic({ 'identifier' => secret.identifier })
      logic.process_params

      expect { logic.raise_concerns }.not_to raise_error
    end

    it 'does not gate reveals when the verifier matches' do
      Onetime.secret_verifier_state = :ok
      logic = build_gated_logic({ 'identifier' => secret.identifier, 'continue' => 'true' })
      logic.process_params

      expect { logic.raise_concerns }.not_to raise_error
    end

    it 'rolls the claim back when the ciphertext itself cannot be decrypted' do
      logic = build_logic({ 'identifier' => secret.identifier, 'continue' => 'true' })
      logic.process_params

      allow(logic.secret).to receive(:decrypted_secret_value)
        .and_raise(Familia::EncryptionError, 'wrong key')

      expect { logic.process }.to raise_error(Onetime::SecretUndecryptable)

      # The claim was returned: record, ciphertext, and viewability survive.
      reloaded = Onetime::Secret.load(secret.identifier)
      expect(reloaded).not_to be_nil
      expect(reloaded.state).to eq('new')
      expect(reloaded.viewable?).to be true

      # And with the key restored, a fresh request reveals exactly once.
      expect(reloaded.reveal!).to eq('a secret value')
    end
  end
end

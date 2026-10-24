# apps/api/colonel/spec/logic/colonel/reauthenticate_session_spec.rb
#
# frozen_string_literal: true

require_relative File.join(Onetime::HOME, 'spec', 'spec_helper')
require 'colonel/logic'

# POST /api/colonel/reauthenticate — password recovery for a lapsed admin
# session window (#4331).
#
# What this layer owns: the password check (the same dual-mode verifier as
# step-up, throttled before it runs), the audit split (.record on success,
# .record_security on failure), and what a success writes into the session: a
# fresh authenticated_at, no step-up window, a renewed session id. Whether the
# route is reachable past an expired window is AdminSessionLifetime's job and is
# pinned in spec/unit/onetime/application/auth_strategies/admin_session_lifetime_spec.rb.
#
# The session here is a bare Hash, which Onetime::SessionRotation.rotate!
# answers with nil (no server-side id); the rotation examples stub it.
RSpec.describe ColonelAPI::Logic::Colonel::ReauthenticateSession do
  let(:colonel) do
    instance_double(Onetime::Customer,
      objid: 'cust_colonel', extid: 'ur_colonel', email: 'colonel@example.com',
      role: 'colonel', verified?: true, anonymous?: false,
      has_passphrase?: true)
  end

  let(:customer) do
    instance_double(Onetime::Customer,
      objid: 'cust_plain', extid: 'ur_plain', email: 'plain@example.com',
      role: 'customer', verified?: true, anonymous?: false,
      has_passphrase?: true)
  end

  let(:now) { 1_800_000_000 }
  let(:signed_in_at) { now - 50_000 }

  # A lapsed window that also holds a stale step-up record, so both the re-stamp
  # and the elevation drop are observable.
  let(:session) do
    {
      'external_id' => 'ur_colonel',
      'authenticated' => true,
      'authenticated_at' => signed_in_at,
      'elevated_until' => { 'extid' => 'ur_colonel', 'exp' => now + 300 },
    }
  end

  def strategy_result_for(user = colonel, sess = session)
    double('StrategyResult', session: sess, user: user,
      auth_method: 'sessionauth', metadata: {})
  end

  def logic_for(params = {}, user: colonel, sess: session)
    described_class.new(strategy_result_for(user, sess), params)
  end

  def reauthenticate(password)
    logic_for({ 'password' => password }).tap(&:raise_concerns).process
  end

  def rotation_result(complete: true, reason: nil, renewed: complete)
    Onetime::SessionRotation::Result.new(
      old_sid: 'a' * 64, new_sid: renewed ? 'b' * 64 : 'a' * 64, complete: complete, reason: reason,
    )
  end

  # The full-mode second-factor check: the account row found by the
  # customer's extid in Auth::Database, then Auth::Operations::MfaStateChecker.
  # Stubbed by constant so the lookup code itself runs; apps/web/auth is not
  # loaded in simple mode, which is why the handler names neither constant
  # before full_enabled?.
  def stub_second_factor(enabled: false, account_id: 42, check_error: nil)
    accounts = double('accounts dataset')
    db       = double('Auth::Database.connection')
    checker  = double('MfaStateChecker')

    stub_const('Auth::Database', double('Auth::Database', connection: db))
    stub_const('Auth::Operations::MfaStateChecker', double('MfaStateChecker class', new: checker))
    allow(db).to receive(:[]).with(:accounts).and_return(accounts)
    allow(accounts).to receive(:where).with(external_id: 'ur_colonel').and_return(accounts)
    allow(accounts).to receive(:get).with(:id).and_return(account_id)

    if check_error
      allow(checker).to receive(:check).and_raise(check_error)
    else
      allow(checker).to receive(:check).with(account_id).and_return(double('MfaState', mfa_enabled?: enabled))
    end
    checker
  end

  before do
    allow(Familia).to receive(:now).and_return(now)
    allow(OT).to receive(:info)
    allow(OT).to receive(:ld)
    allow(OT).to receive(:li)
    allow(OT).to receive(:lw)
    allow(OT).to receive(:le)
    allow(Onetime::ColonelAuditEvent).to receive(:record)
    allow(Onetime::ColonelAuditEvent).to receive(:record_security)
    allow(Onetime.auth_config).to receive(:full_enabled?).and_return(false)
    allow(colonel).to receive(:passphrase?).and_return(false)
    allow(colonel).to receive(:passphrase?).with('hunter2').and_return(true)
    # The limiter has its own tryout; here it must not touch Redis.
    allow_any_instance_of(described_class).to receive(:enforce_colonel_elevation_limit!) # rubocop:disable RSpec/AnyInstance
    stub_watermark(nil)
  end

  # The fresh credential-watermark read after the re-stamp.
  def stub_watermark(last_password_update)
    allow(Onetime::Customer).to receive(:load).with('cust_colonel')
      .and_return(instance_double(Onetime::Customer, last_password_update: last_password_update))
  end

  describe 'authorization and throttling' do
    it 'refuses a non-colonel before anything else' do
      expect { logic_for({ 'password' => 'hunter2' }, user: customer).raise_concerns }
        .to raise_error(Onetime::Forbidden)
    end

    it 'charges the step-up limiter BEFORE verifying, keyed on the colonel extid' do
      logic = logic_for({ 'password' => 'hunter2' })
      expect(logic).to receive(:enforce_colonel_elevation_limit!).with('ur_colonel') # rubocop:disable RSpec/MessageSpies
      logic.raise_concerns
    end

    it 'never verifies a password once the limiter refuses' do
      logic = logic_for({ 'password' => 'hunter2' })
      allow(logic).to receive(:enforce_colonel_elevation_limit!)
        .and_raise(Onetime::LimitExceeded.new('Too many step-up attempts. Try again later.', retry_after: 900))

      expect { logic.raise_concerns }.to raise_error(Onetime::LimitExceeded)
      expect(colonel).not_to have_received(:passphrase?)
    end
  end

  describe 'a wrong password' do
    it 'answers 403 reauthentication_failed with the fixed message' do
      error = begin
        reauthenticate('nope')
      rescue Onetime::ReauthenticationFailed => ex
        ex
      end

      expect(error).to be_a(Onetime::Forbidden)
      expect(error.to_h).to eq(
        error: 'Password verification failed.',
        error_type: 'ReauthenticationFailed',
        error_code: 'reauthentication_failed',
      )
    end

    it 're-stamps nothing, keeps the step-up record and does not rotate', :aggregate_failures do
      allow(Onetime::SessionRotation).to receive(:rotate!)

      expect { reauthenticate('nope') }.to raise_error(Onetime::ReauthenticationFailed)

      expect(session['authenticated_at']).to eq(signed_in_at)
      expect(session['elevated_until']).to include('extid' => 'ur_colonel')
      expect(Onetime::SessionRotation).not_to have_received(:rotate!)
    end

    it 'treats a blank password as a failure without calling the verifier' do
      expect { reauthenticate('') }.to raise_error(Onetime::ReauthenticationFailed)
      expect(colonel).not_to have_received(:passphrase?)
    end

    # record_security, never .record: a failed attempt is drivable on demand by
    # whoever holds the cookie, and the operator trail is count-capped.
    it 'records a SECURITY event and nothing on the operator trail' do
      expect { reauthenticate('nope') }.to raise_error(Onetime::ReauthenticationFailed)

      expect(Onetime::ColonelAuditEvent).to have_received(:record_security).once.with(
        actor: 'ur_colonel', verb: 'colonel.reauthenticate', target: 'ur_colonel',
        result: :failure, detail: nil,
      )
      expect(Onetime::ColonelAuditEvent).not_to have_received(:record)
    end

    it 'never puts the submitted password in any audit call' do
      expect { reauthenticate('s3cr3t-value') }.to raise_error(Onetime::ReauthenticationFailed)

      recorded = nil
      expect(Onetime::ColonelAuditEvent).to have_received(:record_security) { |args| recorded = args }
      expect(recorded.to_s).not_to include('s3cr3t-value')
    end
  end

  describe 'a correct password' do
    before do
      allow(Onetime::SessionRotation).to receive(:rotate!).and_return(rotation_result)
      allow(Onetime::Operations::Sessions::TrackMetadata).to receive(:new)
        .and_return(instance_double(Onetime::Operations::Sessions::TrackMetadata, call: nil))
    end

    it 're-stamps authenticated_at to now' do
      reauthenticate('hunter2')

      expect(session['authenticated_at']).to eq(now)
    end

    it 'removes the step-up record: re-authentication grants no elevation' do
      reauthenticate('hunter2')

      expect(session).not_to have_key('elevated_until')
    end

    it 'answers the contract shape' do
      data = reauthenticate('hunter2')

      expect(data).to eq(
        record: { reauthenticated: true, authenticated_at: now },
        details: { session_rotated: true },
      )
    end

    it 'records exactly one colonel.reauthenticate success on the operator trail' do
      reauthenticate('hunter2')

      expect(Onetime::ColonelAuditEvent).to have_received(:record).once.with(
        actor: 'ur_colonel', verb: 'colonel.reauthenticate', target: 'ur_colonel', result: :success,
      )
      expect(Onetime::ColonelAuditEvent).not_to have_received(:record_security)
    end

    it 'rotates before it re-stamps' do
      stamp_at_rotation = :not_called
      allow(Onetime::SessionRotation).to receive(:rotate!) do |sess|
        stamp_at_rotation = sess['authenticated_at']
        rotation_result
      end

      reauthenticate('hunter2')

      expect(Onetime::SessionRotation).to have_received(:rotate!).with(session).once
      expect(stamp_at_rotation).to eq(signed_in_at)
    end

    # The commit skips TrackMetadata on a request that arrived past a tripped
    # bound (AdminSessionLifetime stamps EXPIRED_ENV_KEY), so the handler
    # restarts the idle clock for the NEW id itself.
    it 'writes the new session id\'s activity record' do
      reauthenticate('hunter2')

      expect(Onetime::Operations::Sessions::TrackMetadata).to have_received(:new).with(
        session_id: 'b' * 64,
        session_data: hash_including('authenticated_at' => now, 'external_id' => 'ur_colonel'),
      )
    end

    it 'continues on a session with no server-side id (rotate! answers nil)' do
      allow(Onetime::SessionRotation).to receive(:rotate!).and_return(nil)

      data = reauthenticate('hunter2')

      expect(data[:details]).to eq(session_rotated: false)
      expect(session['authenticated_at']).to eq(now)
      expect(Onetime::Operations::Sessions::TrackMetadata).not_to have_received(:new)
    end
  end

  # A password change that lands after the auth strategy's stale_credentials
  # check and before the re-stamp must still retire the session.
  describe 'a password change during the request' do
    before do
      allow(Onetime::SessionRotation).to receive(:rotate!).and_return(nil)
      stub_watermark(signed_in_at + 10)
    end

    it 'puts the old stamp back and answers ReauthenticationFailed', :aggregate_failures do
      expect { reauthenticate('hunter2') }.to raise_error(Onetime::ReauthenticationFailed)

      expect(session['authenticated_at']).to eq(signed_in_at)
      expect(Onetime::ColonelAuditEvent).to have_received(:record_security).once.with(
        hash_including(verb: 'colonel.reauthenticate', result: :failure, detail: { reason: 'credentials_changed' }),
      )
      expect(Onetime::ColonelAuditEvent).not_to have_received(:record)
    end

    it 'is not tripped by a change that predates the sign-in' do
      stub_watermark(signed_in_at - 10)

      expect(reauthenticate('hunter2')[:record][:authenticated_at]).to eq(now)
    end

    it 'fails closed when the customer record is gone by the recheck', :aggregate_failures do
      allow(Onetime::Customer).to receive(:load).with('cust_colonel').and_return(nil)

      expect { reauthenticate('hunter2') }.to raise_error(Onetime::ReauthenticationFailed)
      expect(session['authenticated_at']).to eq(signed_in_at)
    end
  end

  describe 'the password factor in FULL mode' do
    let(:auth_config_class) do
      Class.new do
        def self.valid_login_and_password?(login:, password:)
          raise NotImplementedError, "stand-in only (#{login}/#{password})"
        end
      end
    end

    before do
      allow(Onetime.auth_config).to receive(:full_enabled?).and_return(true)
      stub_const('Auth::Config', class_double(auth_config_class))
      stub_const('Rodauth::InternalRequestError', Class.new(StandardError))
      stub_second_factor(enabled: false)
      allow(Onetime::SessionRotation).to receive(:rotate!).and_return(nil)
    end

    it 'verifies through the Rodauth internal request, not the Redis passphrase' do
      allow(Auth::Config).to receive(:valid_login_and_password?).and_return(true)

      reauthenticate('hunter2')

      expect(Auth::Config).to have_received(:valid_login_and_password?)
        .with(login: 'colonel@example.com', password: 'hunter2')
      expect(colonel).not_to have_received(:passphrase?)
      expect(session['authenticated_at']).to eq(now)
    end

    it 'treats a verifier error as a failure rather than an admit' do
      allow(Auth::Config).to receive(:valid_login_and_password?).and_raise(StandardError, 'authdb down')

      expect { reauthenticate('hunter2') }.to raise_error(Onetime::ReauthenticationFailed)
      expect(session['authenticated_at']).to eq(signed_in_at)
    end
  end

  # Sign-in and the app's own POST /auth/reauth ask for the second factor when
  # the account has one; a password alone must not bring back an admin
  # session that lapsed. Checked before the password, so the answer for an
  # MFA account does not depend on it.
  describe 'a second factor in FULL mode' do
    let(:auth_config_class) do
      Class.new do
        def self.valid_login_and_password?(login:, password:)
          raise NotImplementedError, "stand-in only (#{login}/#{password})"
        end
      end
    end

    before do
      allow(Onetime.auth_config).to receive(:full_enabled?).and_return(true)
      stub_const('Auth::Config', class_double(auth_config_class))
      stub_const('Rodauth::InternalRequestError', Class.new(StandardError))
      allow(Auth::Config).to receive(:valid_login_and_password?).and_return(true)
      allow(Onetime::SessionRotation).to receive(:rotate!).and_return(rotation_result)
      allow(Onetime::Operations::Sessions::TrackMetadata).to receive(:new)
        .and_return(instance_double(Onetime::Operations::Sessions::TrackMetadata, call: nil))
    end

    def attempt(password = 'hunter2')
      reauthenticate(password)
      :admitted
    rescue Onetime::Forbidden => ex
      ex
    end

    shared_examples 'a refusal that grants nothing' do
      it 'is refused: no re-stamp, no rotation, no activity, step-up record kept', :aggregate_failures do
        outcome = attempt

        expect(outcome).to be_a(Onetime::ReauthenticationUnavailable)
        expect(session['authenticated_at']).to eq(signed_in_at)
        expect(session['elevated_until']).to include('extid' => 'ur_colonel')
        expect(Onetime::SessionRotation).not_to have_received(:rotate!)
        expect(Onetime::Operations::Sessions::TrackMetadata).not_to have_received(:new)
      end

      it 'never verifies the password (no oracle for MFA accounts)' do
        attempt('nope')

        expect(Auth::Config).not_to have_received(:valid_login_and_password?)
      end

      it 'records a SECURITY event with reason mfa_required, and no success event' do
        attempt

        expect(Onetime::ColonelAuditEvent).to have_received(:record_security).once.with(
          actor: 'ur_colonel', verb: 'colonel.reauthenticate', target: 'ur_colonel',
          result: :failure, detail: { reason: 'mfa_required' },
        )
        expect(Onetime::ColonelAuditEvent).not_to have_received(:record)
      end
    end

    context 'when the account has a second factor' do
      before { stub_second_factor(enabled: true) }

      include_examples 'a refusal that grants nothing'

      it 'answers 403 reauthentication_unavailable' do
        error = attempt

        expect(error).to be_a(Onetime::Forbidden)
        expect(error.to_h).to eq(
          error: Onetime::ReauthenticationUnavailable.new.message,
          error_type: 'ReauthenticationUnavailable',
          error_code: 'reauthentication_unavailable',
        )
      end
    end

    context 'when the second-factor check raises (fail closed)' do
      before { stub_second_factor(check_error: RuntimeError.new('authdb down')) }

      include_examples 'a refusal that grants nothing'
    end

    context 'when no account row carries the customer extid (fail closed)' do
      before { stub_second_factor(account_id: nil) }

      include_examples 'a refusal that grants nothing'
    end

    context 'when the account has no second factor' do
      it 'proceeds to the password and re-authenticates' do
        checker = stub_second_factor(enabled: false)

        expect(attempt).to eq(:admitted)
        expect(checker).to have_received(:check).with(42)
        expect(session['authenticated_at']).to eq(now)
      end
    end
  end

  describe 'the second-factor check in SIMPLE mode' do
    before do
      allow(Onetime::SessionRotation).to receive(:rotate!).and_return(nil)
    end

    it 'is never consulted: simple mode has no second factor' do
      stub_second_factor(enabled: true)

      expect(reauthenticate('hunter2')[:record][:authenticated_at]).to eq(now)
      expect(Auth::Operations::MfaStateChecker).not_to have_received(:new)
      expect(Auth::Database).not_to have_received(:connection)
    end
  end

  describe 'session id rotation refused' do
    shared_examples 'a re-authentication refused for an unrotated session' do
      it 'answers ReauthenticationFailed and re-stamps nothing', :aggregate_failures do
        error = begin
          reauthenticate('hunter2')
        rescue Onetime::ReauthenticationFailed => ex
          ex
        end

        expect(error).to be_a(Onetime::ReauthenticationFailed)
        expect(error.to_h).to include(error_code: 'reauthentication_failed')
        expect(error.message).to eq(described_class::ROTATION_FAILED_MESSAGE)
        expect(session['authenticated_at']).to eq(signed_in_at)
      end

      it 'records a security failure with the reason, and no success event' do
        expect { reauthenticate('hunter2') }.to raise_error(Onetime::ReauthenticationFailed)

        expect(Onetime::ColonelAuditEvent).to have_received(:record_security).once.with(
          hash_including(
            actor: 'ur_colonel', verb: 'colonel.reauthenticate', result: :failure,
            detail: { reason: 'session_not_rotated' },
          ),
        )
        expect(Onetime::ColonelAuditEvent).not_to have_received(:record)
      end
    end

    context 'when the rotation reports itself incomplete' do
      before do
        allow(Onetime::SessionRotation).to receive(:rotate!)
          .and_return(rotation_result(complete: false, reason: :marker_not_written))
      end

      include_examples 'a re-authentication refused for an unrotated session'
    end

    context 'when the rotation raises' do
      before do
        allow(Onetime::SessionRotation).to receive(:rotate!).and_raise(Redis::CannotConnectError, 'down')
      end

      include_examples 'a re-authentication refused for an unrotated session'
    end
  end

  # An incomplete rotation can still have moved the session to a new id
  # (:marker_not_confirmed, :blob_survived, or a raise after the re-key). The
  # commit saves the session under that id and skips TrackMetadata (the
  # request arrived past a tripped bound), so without a record for the new id
  # the next request finds no last_activity_at, skips the idle check, and the
  # admin surface is open again. The refusal carries the old record over.
  describe 'a refused rotation that renewed the id' do
    let(:old_sid) { 'a' * 64 }
    let(:new_sid) { 'b' * 64 }
    let(:last_activity) { now - 7_200 }

    let(:rack_session) do
      Class.new(Hash) { attr_accessor :id }.new.merge!(session).tap { |s| s.id = old_sid }
    end

    let(:previous_record) do
      instance_double(Onetime::SessionMetadata,
        user_id: 'ur_colonel', org_id: nil, created_at: signed_in_at, last_activity_at: last_activity,
        ip_address: nil, user_agent: nil, auth_method: 'password', mfa_used: nil,
        active_session_id_hmac: 'hmac-value', geo_country: nil)
    end

    let(:carried) { instance_double(Onetime::SessionMetadata, save: true) }
    let(:index) { double('active_sessions', add: true) }

    def reauthenticate_rack(password)
      logic_for({ 'password' => password }, sess: rack_session).tap(&:raise_concerns).process
    end

    def renew_then(reason: nil, error: nil)
      allow(Onetime::SessionRotation).to receive(:rotate!) do |sess|
        sess.id = new_sid
        raise error if error

        rotation_result(complete: false, reason: reason, renewed: true)
      end
    end

    before do
      allow(Onetime::SessionMetadata).to receive(:load).with(old_sid).and_return(previous_record)
      allow(Onetime::SessionMetadata).to receive(:new).and_return(carried)
      allow(colonel).to receive(:active_sessions).and_return(index)
      allow(Onetime::Operations::Sessions::TrackMetadata).to receive(:new)
    end

    shared_examples 'the idle clock carried to the new id' do
      it 'answers ReauthenticationFailed and re-stamps nothing', :aggregate_failures do
        expect { reauthenticate_rack('hunter2') }.to raise_error(
          Onetime::ReauthenticationFailed, described_class::ROTATION_FAILED_MESSAGE
        )
        expect(rack_session['authenticated_at']).to eq(signed_in_at)
        expect(Onetime::Operations::Sessions::TrackMetadata).not_to have_received(:new)
      end

      it "writes the new id's record with the ORIGINAL last_activity_at, and indexes it", :aggregate_failures do
        expect { reauthenticate_rack('hunter2') }.to raise_error(Onetime::ReauthenticationFailed)

        expect(Onetime::SessionMetadata).to have_received(:new).once.with(
          hash_including(session_id: new_sid, last_activity_at: last_activity,
            created_at: signed_in_at, user_id: 'ur_colonel', active_session_id_hmac: 'hmac-value'),
        )
        expect(carried).to have_received(:save)
        expect(index).to have_received(:add).with(new_sid, last_activity)
      end
    end

    context 'when the rotation reports :blob_survived' do
      before { renew_then(reason: :blob_survived) }

      include_examples 'the idle clock carried to the new id'
    end

    context 'when the rotation reports :marker_not_confirmed' do
      before { renew_then(reason: :marker_not_confirmed) }

      include_examples 'the idle clock carried to the new id'
    end

    context 'when the rotation raises after the re-key' do
      before { renew_then(error: Redis::CannotConnectError.new('down')) }

      include_examples 'the idle clock carried to the new id'
    end

    # Its idle check was already skipped before this request (a missing
    # record skips, never fails), so not writing one widens nothing.
    it 'writes nothing when the original id had no record' do
      allow(Onetime::SessionMetadata).to receive(:load).with(old_sid).and_return(nil)
      renew_then(reason: :blob_survived)

      expect { reauthenticate_rack('hunter2') }.to raise_error(Onetime::ReauthenticationFailed)
      expect(Onetime::SessionMetadata).not_to have_received(:new)
    end

    it 'writes nothing when the id did not change' do
      allow(Onetime::SessionRotation).to receive(:rotate!)
        .and_return(rotation_result(complete: false, reason: :marker_not_written))

      expect { reauthenticate_rack('hunter2') }.to raise_error(Onetime::ReauthenticationFailed)
      expect(Onetime::SessionMetadata).not_to have_received(:new)
    end

    # The same path against the real record store, read back the way the next
    # admin request reads it: only the idle bound has lapsed, and it still
    # refuses the renewed id.
    context 'with real SessionMetadata records' do
      let(:old_sid) { SecureRandom.hex(32) }
      let(:new_sid) { SecureRandom.hex(32) }

      before do
        allow(Onetime::SessionMetadata).to receive(:load).and_call_original
        allow(Onetime::SessionMetadata).to receive(:new).and_call_original
        Onetime::SessionMetadata.new(
          session_id: old_sid, user_id: 'ur_colonel', created_at: signed_in_at, last_activity_at: last_activity,
        ).save
        rack_session['authenticated_at'] = now - 100 # absolute bound still open
        renew_then(reason: :blob_survived)

        # The shipped bounds, whatever the test config sets.
        conf = YAML.load(YAML.dump(OT.conf))
        ((conf['site'] ||= {})['admin'] ||= {})['session'] =
          { 'enabled' => true, 'idle_timeout' => 3_600, 'absolute_timeout' => 43_200 }
        allow(OT).to receive(:conf).and_return(conf)
      end

      after do
        [old_sid, new_sid].each { |sid| Onetime::SessionMetadata.load(sid)&.destroy! }
      end

      it 'leaves the next admin request refused on the idle bound', :aggregate_failures do
        expect { reauthenticate_rack('hunter2') }.to raise_error(Onetime::ReauthenticationFailed)

        expect(rack_session.id).to eq(new_sid)
        expect(Onetime::SessionMetadata.load(new_sid)&.last_activity_at.to_i).to eq(last_activity)

        bounds = Object.new.extend(Onetime::Application::AuthStrategies::AdminSessionLifetime)
        env    = { 'REQUEST_METHOD' => 'GET', 'SCRIPT_NAME' => '', 'PATH_INFO' => '/api/colonel/users' }
        expect(bounds.admin_session_expiry_reason(rack_session, colonel, env)).to eq(:idle)
      end
    end
  end
end

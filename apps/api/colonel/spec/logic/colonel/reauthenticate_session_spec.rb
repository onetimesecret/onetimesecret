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

  def rotation_result(complete: true, reason: nil)
    Onetime::SessionRotation::Result.new(
      old_sid: 'a' * 64, new_sid: complete ? 'b' * 64 : 'a' * 64, complete: complete, reason: reason,
    )
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
end

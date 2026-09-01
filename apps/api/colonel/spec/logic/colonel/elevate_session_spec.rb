# apps/api/colonel/spec/logic/colonel/elevate_session_spec.rb
#
# frozen_string_literal: true

require_relative File.join(Onetime::HOME, 'spec', 'spec_helper')
require 'colonel/logic'

# POST /api/colonel/elevation — minting the step-up (sudo) window (#4327).
#
# What this layer owns, and what these examples pin:
#
#   - the DUAL-MODE branch. `Auth::Config` does not exist in simple mode
#     (registry.rb drops the whole apps/web/auth tree), so the password check
#     MUST test Onetime.auth_config.full_enabled? before naming it. The
#     simple-mode examples assert the constant is never touched, which is the
#     regression this design exists to prevent;
#   - the audit split: .record on success carrying the FACTOR, .record_security
#     on failure, and nothing at all on an unelevated tier-1 refusal (that last
#     one is asserted by the 'an elevated colonel action' shared example);
#   - the shape of what lands in the session: an identity-bound {extid, exp}
#     object, never a bare epoch;
#   - the throttle running BEFORE verification, because the Rodauth internal
#     request behind the password check does not increment Rodauth's lockout.
#
# It deliberately does NOT test the window arithmetic (elevation_spec covers the
# mixin) or the tier-1 gate (the shared example covers every TIER 1 class).
RSpec.describe ColonelAPI::Logic::Colonel::ElevateSession do
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

  # The Rack session hash the auth strategy hands the logic class. A real one is
  # mutable, which is the whole point here: grant_elevation! writes into it.
  let(:session) { {} }

  # Stand-in for the full-mode password verifier, declaring the exact signature
  # Elevation#verify_elevation_password_full_mode calls.
  #
  # `class_double('Auth::Config')` (by NAME) cannot be used, and neither can a
  # `defined?(Auth::Config)` guard. This spec runs in a SIMPLE-mode process where
  # the constant is normally absent — but `spec:apps_fast` merges every app spec
  # into one process, and any spec there that loads apps/web/auth/config.rb
  # leaves `Auth::Config` defined as a bare Rodauth::Auth subclass. The
  # `valid_login_and_password?` class method is installed by Rodauth's
  # :internal_request feature, which only runs inside `Auth::Config.configure`
  # during a full-mode boot, so rspec would verify the stub against a half-built
  # class and reject it — making these examples pass or fail on the load order of
  # the whole merged process (seed 35522 reproduces the failure).
  #
  # Doubling this stand-in is deterministic in both processes AND stricter than
  # the unverified double a name-based `class_double` degrades to when the
  # constant is absent: a call with the wrong keywords fails here.
  let(:auth_config_class) do
    Class.new do
      def self.valid_login_and_password?(login:, password:)
        raise NotImplementedError, "stand-in only (#{login}/#{password})"
      end
    end
  end

  def strategy_result_for(user = colonel, sess = session)
    double('StrategyResult', session: sess, user: user,
      auth_method: 'sessionauth', metadata: {})
  end

  def logic_for(params = {}, user: colonel, sess: session)
    described_class.new(strategy_result_for(user, sess), { 'factor' => 'password' }.merge(params))
  end

  before do
    allow(OT).to receive(:info)
    allow(OT).to receive(:ld)
    allow(OT).to receive(:li)
    allow(OT).to receive(:le)
    allow(Onetime::ColonelAuditEvent).to receive(:record)
    allow(Onetime::ColonelAuditEvent).to receive(:record_security)
    stub_colonel_elevation(enabled: true, window: 600)
    # The limiter has its own tryout; here it must not touch Redis.
    allow_any_instance_of(described_class).to receive(:enforce_colonel_elevation_limit!) # rubocop:disable RSpec/AnyInstance
  end

  describe 'authorization and shape' do
    it 'refuses a non-colonel before anything else' do
      expect { logic_for(user: customer).raise_concerns }.to raise_error(Onetime::Forbidden)
    end

    it 'defaults an absent factor to password' do
      expect(logic_for({ 'factor' => '' }).factor).to eq('password')
    end

    it 'rejects an unknown factor with a 422' do
      expect { logic_for({ 'factor' => 'telepathy' }).raise_concerns }
        .to raise_error(Onetime::FormError, /Unknown step-up factor/)
    end

    it 'rejects every factor with a 422 when elevation is disabled by config' do
      stub_colonel_elevation(enabled: false)
      expect { logic_for.raise_concerns }
        .to raise_error(Onetime::FormError, /Step-up authentication is disabled/)
    end

    it 'throttles BEFORE verifying — the internal-request check bypasses Rodauth lockout' do
      logic = logic_for
      expect(logic).to receive(:enforce_colonel_elevation_limit!).with('ur_colonel') # rubocop:disable RSpec/MessageSpies
      logic.raise_concerns
    end
  end

  describe 'the password factor in SIMPLE mode' do
    before do
      allow(Onetime.auth_config).to receive(:full_enabled?).and_return(false)
    end

    it 'verifies against the Redis passphrase and NEVER names Auth::Config' do
      allow(colonel).to receive(:passphrase?).with('hunter2').and_return(true)
      # If the class reached for Auth::Config here it would NameError in simple
      # mode, where apps/web/auth is not loaded at all. Stubbed unconditionally:
      # the old `if defined?(Auth::Config)` guard SKIPPED this assertion outright
      # in a standalone colonel run (where the constant is absent — i.e. exactly
      # the run this file is normally executed in) and blew up in the merged
      # spec:apps_fast process. The stand-in is present either way.
      auth_config = class_double(auth_config_class)
      stub_const('Auth::Config', auth_config)
      expect(auth_config).not_to receive(:valid_login_and_password?) # rubocop:disable RSpec/MessageSpies

      logic = logic_for({ 'password' => 'hunter2' })
      logic.raise_concerns
      logic.process

      expect(colonel).to have_received(:passphrase?).with('hunter2')
    end

    it 'stores an identity-bound {extid, exp} object, never a bare epoch' do
      allow(colonel).to receive(:passphrase?).and_return(true)

      logic = logic_for({ 'password' => 'hunter2' })
      logic.raise_concerns
      logic.process

      stored = session['elevated_until']
      expect(stored).to be_a(Hash)
      expect(stored['extid']).to eq('ur_colonel')
      expect(stored['exp']).to be_within(5).of(Familia.now.to_i + 600)
    end

    it 'returns the window in the ack' do
      allow(colonel).to receive(:passphrase?).and_return(true)

      logic = logic_for({ 'password' => 'hunter2' })
      logic.raise_concerns
      data = logic.process

      expect(data[:record][:elevated]).to be true
      expect(data[:details][:factor]).to eq('password')
      expect(data[:details][:window]).to eq(600)
    end

    it 'records exactly one colonel.elevate event carrying the factor' do
      allow(colonel).to receive(:passphrase?).and_return(true)

      logic = logic_for({ 'password' => 'hunter2' })
      logic.raise_concerns
      logic.process

      expect(Onetime::ColonelAuditEvent).to have_received(:record).once.with(
        hash_including(
          actor: 'ur_colonel', verb: 'colonel.elevate', target: 'ur_colonel',
          result: :success, detail: { factor: 'password', window: 600 },
        ),
      )
    end

    it 'treats a blank password as a failure without calling the verifier' do
      allow(colonel).to receive(:passphrase?)

      expect { logic_for({ 'password' => '' }).tap(&:raise_concerns).process }
        .to raise_error(Onetime::ElevationFailed)
      expect(colonel).not_to have_received(:passphrase?)
    end

    describe 'a wrong password' do
      before { allow(colonel).to receive(:passphrase?).and_return(false) }

      it 'raises ElevationFailed with error_code elevation_failed' do
        error = begin
          logic_for({ 'password' => 'nope' }).tap(&:raise_concerns).process
        rescue Onetime::ElevationFailed => ex
          ex
        end

        expect(error).to be_a(Onetime::Forbidden)
        expect(error.to_h).to include(
          error_type: 'ElevationFailed', error_code: 'elevation_failed', factor: 'password',
        )
      end

      it 'grants nothing' do
        expect { logic_for({ 'password' => 'nope' }).tap(&:raise_concerns).process }
          .to raise_error(Onetime::ElevationFailed)
        expect(session).not_to have_key('elevated_until')
      end

      # record_security (1k cap + 7d retention), never .record: a failed
      # elevation is drivable on demand by whoever holds the cookie, and the
      # operator trail is count-capped with NO TTL.
      it 'records the failure as a SECURITY event and not on the operator trail' do
        expect { logic_for({ 'password' => 'nope' }).tap(&:raise_concerns).process }
          .to raise_error(Onetime::ElevationFailed)

        expect(Onetime::ColonelAuditEvent).to have_received(:record_security).once.with(
          hash_including(
            actor: 'ur_colonel', verb: 'colonel.elevate', target: 'ur_colonel',
            result: :failure, detail: { factor: 'password' },
          ),
        )
        expect(Onetime::ColonelAuditEvent).not_to have_received(:record)
      end

      it 'never puts the submitted password in the audit detail' do
        expect { logic_for({ 'password' => 's3cr3t-value' }).tap(&:raise_concerns).process }
          .to raise_error(Onetime::ElevationFailed)

        detail = nil
        expect(Onetime::ColonelAuditEvent).to have_received(:record_security) { |args| detail = args[:detail] }
        expect(detail.to_s).not_to include('s3cr3t-value')
      end
    end
  end

  describe 'the password factor in FULL mode' do
    before do
      allow(Onetime.auth_config).to receive(:full_enabled?).and_return(true)
      stub_const('Auth::Config', class_double(auth_config_class))
      # Both constants only exist in a full-mode process; this spec runs in a
      # simple-mode one. Naming Rodauth::InternalRequestError in the rescue
      # clause is the in-repo idiom (update_password.rb, destroy_account.rb) and
      # is reachable only behind the same full_enabled? branch, so the stub
      # reproduces the real load order rather than papering over one.
      stub_const('Rodauth::InternalRequestError', Class.new(StandardError))
    end

    it 'verifies through the Rodauth internal request, not the Redis passphrase' do
      allow(Auth::Config).to receive(:valid_login_and_password?).and_return(true)
      allow(colonel).to receive(:passphrase?)

      logic = logic_for({ 'password' => 'hunter2' })
      logic.raise_concerns
      logic.process

      expect(Auth::Config).to have_received(:valid_login_and_password?)
        .with(login: 'colonel@example.com', password: 'hunter2')
      expect(colonel).not_to have_received(:passphrase?)
      expect(session['elevated_until']['extid']).to eq('ur_colonel')
    end

    it 'treats a verifier error as a failure rather than an admit' do
      allow(Auth::Config).to receive(:valid_login_and_password?).and_raise(StandardError, 'authdb down')

      expect { logic_for({ 'password' => 'hunter2' }).tap(&:raise_concerns).process }
        .to raise_error(Onetime::ElevationFailed)
      expect(session).not_to have_key('elevated_until')
    end
  end
end

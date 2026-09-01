# apps/api/colonel/spec/logic/colonel/elevate_session_recent_auth_spec.rb
#
# frozen_string_literal: true

require_relative File.join(Onetime::HOME, 'spec', 'spec_helper')
require 'colonel/logic'

# The `recent_auth` factor (#4327) — and the regression set for the security
# review's B-3 finding, which is the reason this factor is shaped the way it is.
#
# The rejected first draft let ANY colonel elevate with no credential inside a
# 300s post-sign-in grace, and the console called it silently before prompting.
# For five minutes after every colonel sign-in, "a colonel session alone" WAS
# sufficient for every tier-1 verb — verbatim the condition #4327 exists to
# remove — and a scripted cookie holder reached the same state in two requests.
# The objection that a stolen cookie cannot make `authenticated_at` recent is
# true and irrelevant: the attacker needs the VICTIM to have signed in recently,
# which is the ordinary case for theft that happens while the operator works.
#
# So the factor ships with two independent locks, and both are asserted here:
#
#   1. `reauth_grace` defaults to 0, i.e. the factor is OFF unless an operator
#      turns it on;
#   2. even switched on, it is offered ONLY to accounts that cannot satisfy the
#      password factor. A password holder always re-enters their password.
#
# The remaining purpose of the factor is SSO-only operator fleets, which would
# otherwise be locked out of every tier-1 verb.
RSpec.describe ColonelAPI::Logic::Colonel::ElevateSession, 'the recent_auth factor' do
  let(:signed_in_at) { Familia.now.to_i - 60 }
  let(:session) { { 'authenticated_at' => signed_in_at } }

  def colonel_with(passphrase:)
    instance_double(Onetime::Customer,
      objid: 'cust_colonel', extid: 'ur_colonel', email: 'colonel@example.com',
      role: 'colonel', verified?: true, anonymous?: false,
      has_passphrase?: passphrase)
  end

  let(:password_holder) { colonel_with(passphrase: true) }
  let(:sso_only) { colonel_with(passphrase: false) }

  def logic_for(user, sess = session)
    described_class.new(
      double('StrategyResult', session: sess, user: user, auth_method: 'sessionauth', metadata: {}),
      { 'factor' => 'recent_auth' },
    )
  end

  def elevate(user, sess = session)
    logic = logic_for(user, sess)
    logic.raise_concerns
    logic.process
  end

  before do
    allow(OT).to receive(:info)
    allow(OT).to receive(:ld)
    allow(OT).to receive(:li)
    allow(OT).to receive(:le)
    allow(Onetime::ColonelAuditEvent).to receive(:record)
    allow(Onetime::ColonelAuditEvent).to receive(:record_security)
    allow(Onetime.auth_config).to receive(:full_enabled?).and_return(false)
    allow_any_instance_of(described_class).to receive(:enforce_colonel_elevation_limit!) # rubocop:disable RSpec/AnyInstance
  end

  describe 'with the SHIPPED default (reauth_grace: 0)' do
    before { stub_colonel_elevation(enabled: true, reauth_grace: 0) }

    it 'refuses a password-less account one second after sign-in' do
      expect { elevate(sso_only, { 'authenticated_at' => Familia.now.to_i - 1 }) }
        .to raise_error(Onetime::ElevationFailed)
    end

    it 'refuses a password holder too' do
      expect { elevate(password_holder) }.to raise_error(Onetime::ElevationFailed)
    end

    it 'tells the operator which knob is missing, not that they guessed wrong' do
      error = begin
        elevate(sso_only)
      rescue Onetime::ElevationFailed => ex
        ex
      end

      expect(error.message).to include('COLONEL_ELEVATION_REAUTH_GRACE')
    end

    it 'offers password as the only factor' do
      expect(logic_for(sso_only).available_factors).to eq(['password'])
    end
  end

  describe 'with a grace configured' do
    before { stub_colonel_elevation(enabled: true, reauth_grace: 300) }

    it 'still refuses an account that HAS a password' do
      expect { elevate(password_holder) }.to raise_error(Onetime::ElevationFailed)
    end

    it 'tells a password holder to use their password' do
      error = begin
        elevate(password_holder)
      rescue Onetime::ElevationFailed => ex
        ex
      end

      expect(error.message).to include('re-enter it to elevate')
    end

    it 'does not offer recent_auth to a password holder' do
      expect(logic_for(password_holder).available_factors).to eq(['password'])
    end

    it 'elevates a password-less account inside the grace' do
      elevate(sso_only)

      expect(session['elevated_until']['extid']).to eq('ur_colonel')
    end

    it 'offers recent_auth to a password-less account' do
      expect(logic_for(sso_only).available_factors).to contain_exactly('password', 'recent_auth')
    end

    it 'records the WEAKER path in the audit detail so the trail can show it' do
      elevate(sso_only)

      expect(Onetime::ColonelAuditEvent).to have_received(:record).once.with(
        hash_including(verb: 'colonel.elevate', detail: hash_including(factor: 'recent_auth')),
      )
    end

    it 'refuses a password-less account whose sign-in is older than the grace' do
      stale = { 'authenticated_at' => Familia.now.to_i - 301 }

      expect { elevate(sso_only, stale) }.to raise_error(Onetime::ElevationFailed, /not recent enough/)
    end

    it 'refuses a session carrying no sign-in watermark at all' do
      expect { elevate(sso_only, {}) }.to raise_error(Onetime::ElevationFailed)
    end
  end

  describe 'in FULL auth mode' do
    before do
      stub_colonel_elevation(enabled: true, reauth_grace: 300)
      allow(Onetime.auth_config).to receive(:full_enabled?).and_return(true)
    end

    # Documented scoping decision, not an oversight: the Rodauth password-hash
    # probe is only reachable inside a Rodauth instance, and inventing a second
    # probe risks granting the WEAKER factor on a wrong answer. Full mode
    # therefore fails closed — every account counts as password-holding — and an
    # SSO-only full-mode fleet sets COLONEL_ELEVATION_ENABLED=false instead.
    it 'treats even a passphrase-less account as password-holding' do
      expect(logic_for(sso_only).elevation_password_available?).to be true
      expect(logic_for(sso_only).available_factors).to eq(['password'])
    end

    it 'refuses recent_auth there' do
      expect { elevate(sso_only) }.to raise_error(Onetime::ElevationFailed)
    end
  end
end

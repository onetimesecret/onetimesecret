# apps/web/auth/spec/operations/reauthenticate_spec.rb
#
# frozen_string_literal: true

require 'spec_helper'
require_relative '../../operations/reauthenticate'

RSpec.describe Auth::Operations::Reauthenticate do
  subject(:operation) do
    described_class.new(db, rodauth: rodauth, session: session, env: env)
  end

  let(:db)      { instance_double(Sequel::Database) }
  let(:session) { {} }
  let(:env)     { { 'onetime.domain_strategy' => :canonical } }
  let(:account) { { id: 42, email: 'user@example.com' } }
  let(:rodauth) { double('Rodauth', account_from_session: account) }
  let(:offer) do
    {
      surface: Onetime::SessionSurface::CANONICAL,
      methods: %w[webauthn password],
      webauthn_credentials: [{ scope: :platform }],
      related_origins: [],
    }
  end
  let(:mfa_state) do
    instance_double(
      Auth::Operations::MfaStateChecker::State,
      mfa_enabled?: false,
      has_otp_secret: false,
      has_recovery_codes: false,
      has_webauthn: false,
    )
  end

  before do
    allow(Auth::Config).to receive(:valid_login_and_password?).and_return(true)
    checker = instance_double(Auth::Operations::MfaStateChecker, check: mfa_state)
    allow(Auth::Operations::MfaStateChecker).to receive(:new).with(db).and_return(checker)
  end

  it 'rejects a method that is absent from the current offer' do
    result = operation.call(
      account_id: 42,
      offer: offer.merge(methods: %w[password]),
      params: { 'method' => 'webauthn' },
    )

    expect(result.status).to eq(400)
    expect(result.body['error_code']).to eq('invalid_method')
    expect(session).not_to have_key(Onetime::RecentReauth::KEY)
  end

  it 'records a password proof only after successful verification' do
    result = operation.call(
      account_id: 42,
      offer: offer,
      params: { 'method' => 'password', 'password' => 'correct-password' },
    )

    expect(result.status).to eq(200)
    expect(result.body).to eq('success' => 'Re-authentication complete')
    expect(session.dig(Onetime::RecentReauth::KEY, 'methods')).to eq(%w[password])
  end

  it 'does not record when the password is wrong' do
    allow(Auth::Config).to receive(:valid_login_and_password?).and_return(false)

    result = operation.call(
      account_id: 42,
      offer: offer,
      params: { 'method' => 'password', 'password' => 'wrong-password' },
    )

    expect(result.status).to eq(401)
    expect(result.body['error_code']).to eq('invalid_password')
    expect(session).not_to have_key(Onetime::RecentReauth::KEY)
  end

  describe 'WebAuthn challenge binding' do
    let(:pending) do
      {
        'account_id' => '42',
        'challenge' => 'challenge',
        'surface' => Onetime::SessionSurface::CANONICAL,
        'rp_id' => 'example.com',
        'primary' => true,
      }
    end
    let(:params) { { 'webauthn_auth_challenge' => 'challenge' } }

    it 'requires the consumed challenge to match account, surface, RP ID, and ceremony type' do
      expect(
        operation.send(
          :valid_pending_challenge?,
          pending,
          42,
          offer,
          params,
          'example.com',
          true,
        ),
      ).to be true

      expect(
        operation.send(
          :valid_pending_challenge?,
          pending,
          43,
          offer,
          params,
          'example.com',
          true,
        ),
      ).to be false
      expect(
        operation.send(
          :valid_pending_challenge?,
          pending,
          42,
          offer,
          params,
          'tenant.example.com',
          true,
        ),
      ).to be false
      expect(
        operation.send(
          :valid_pending_challenge?,
          pending,
          42,
          offer,
          params,
          'example.com',
          false,
        ),
      ).to be false
    end
  end

  context 'when password authentication requires MFA' do
    let(:mfa_state) do
      instance_double(
        Auth::Operations::MfaStateChecker::State,
        mfa_enabled?: true,
        has_otp_secret: true,
        has_recovery_codes: true,
        has_webauthn: false,
      )
    end

    it 'returns the available second factors without recording after password alone' do
      result = operation.call(
        account_id: 42,
        offer: offer,
        params: { 'method' => 'password', 'password' => 'correct-password' },
      )

      expect(result.body).to eq(
        'mfa_required' => true,
        'mfa_methods' => %w[otp recovery_codes],
      )
      expect(session).not_to have_key(Onetime::RecentReauth::KEY)
    end

    it 'records password and OTP only after a valid non-replayed code' do
      allow(rodauth).to receive_messages(
        otp_exists?: true,
        otp_locked_out?: false,
        otp_valid_code?: true,
        otp_update_last_use: true,
        otp_remove_auth_failures: nil,
      )

      result = operation.call(
        account_id: 42,
        offer: offer,
        params: {
          'method' => 'password',
          'password' => 'correct-password',
          'otp_code' => '123456',
        },
      )

      expect(result.status).to eq(200)
      expect(session.dig(Onetime::RecentReauth::KEY, 'methods')).to eq(%w[password totp])
    end

    it 'consumes a valid recovery code before recording proof' do
      allow(rodauth).to receive(:recovery_code_match?).with('recovery-code').and_return(true)

      result = operation.call(
        account_id: 42,
        offer: offer,
        params: {
          'method' => 'password',
          'password' => 'correct-password',
          'recovery_code' => 'recovery-code',
        },
      )

      expect(result.status).to eq(200)
      expect(session.dig(Onetime::RecentReauth::KEY, 'methods')).to eq(%w[password recovery_code])
    end
  end
end

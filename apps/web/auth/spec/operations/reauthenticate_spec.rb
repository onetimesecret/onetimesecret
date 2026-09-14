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
  # A full-feature install: the loaded-route predicates the operation uses
  # to mask MfaStateChecker (mirroring the login hook) all respond.
  let(:rodauth) do
    double(
      'Rodauth',
      account_from_session: account,
      otp_auth_route: 'otp-auth',
      recovery_auth_route: 'recovery-auth',
      webauthn_auth_route: 'webauthn-auth',
    )
  end
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
    stub_const(
      'Auth::Config',
      Class.new do
        def self.valid_login_and_password?(login:, password:)
          raise NotImplementedError, "stand-in only (#{login}/#{password})"
        end
      end,
    )
    allow(Auth::Config).to receive(:valid_login_and_password?).and_return(true)
    checker = instance_double(Auth::Operations::MfaStateChecker, check: mfa_state)
    allow(Auth::Operations::MfaStateChecker).to receive(:new).with(db).and_return(checker)
    allow(Onetime::RecentReauth).to receive(:record).and_return(
      'account_id' => 42,
      'at' => Time.now.to_i,
      'surface' => Onetime::SessionSurface::CANONICAL,
      'methods' => %w[password],
    )
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
    expect(Onetime::RecentReauth).to have_received(:record).with(
      session,
      env,
      account_id: 42,
      methods: %w[password],
    )
  end

  it 'fails closed when the proof cannot be persisted' do
    allow(Onetime::RecentReauth).to receive(:record).and_return(nil)

    result = operation.call(
      account_id: 42,
      offer: offer,
      params: { 'method' => 'password', 'password' => 'correct-password' },
    )

    expect(result.status).to eq(403)
    expect(result.body['error_code']).to eq('invalid_surface')
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

  describe 'WebAuthn RP selection' do
    let(:related_offer) do
      offer.merge(
        surface: { 'kind' => 'custom', 'id' => 'tenant-a' },
        current_origin: 'https://tenant.example:8443',
        related_origins: [
          {
            'origin' => 'https://example.com',
            'surface' => { 'kind' => 'canonical' },
          },
          {
            'origin' => 'https://tenant.example:8443',
            'surface' => { 'kind' => 'custom', 'id' => 'tenant-a' },
          },
        ],
      )
    end

    it 'selects a related-origin credential only under its registration RP ID' do
      row = { surface_scope: JSON.generate(kind: 'canonical'), rp_id: 'example.com' }

      expect(operation.send(:credential_eligible?, row, related_offer)).to be true
      expect(operation.send(:effective_rp_id, row)).to eq('example.com')
    end

    it 'passes the registration RP ID into challenge generation' do
      rows = [{ webauthn_id: 'credential-id', rp_id: 'example.com' }]
      options = double('WebAuthnOptions', challenge: 'challenge', as_json: { 'challenge' => 'challenge' })
      allow(rodauth).to receive_messages(
        webauthn_auth_timeout: 60_000,
        webauthn_user_verification: 'preferred',
      )
      expect(WebAuthn::Credential).to receive(:options_for_get).with(
        allow: ['credential-id'],
        timeout: 60_000,
        user_verification: 'preferred',
        rp_id: 'example.com',
      ).and_return(options)
      allow(Onetime::SessionSidecar).to receive(:write).and_return(120)
      allow(rodauth).to receive(:compute_hmac).with('challenge').and_return('hmac')

      result = operation.send(
        :webauthn_challenge,
        rows,
        account_id: 42,
        surface: related_offer[:surface],
        primary: true,
      )

      expect(result.status).to eq(200)
    end

    it 'rejects the same credential on a scheme or port mismatch' do
      row = { surface_scope: JSON.generate(kind: 'canonical'), rp_id: 'example.com' }
      mismatched = related_offer.merge(current_origin: 'https://tenant.example')

      expect(operation.send(:credential_eligible?, row, mismatched)).to be false
    end
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

  context 'when a configured factor belongs to a feature that is not loaded' do
    # Stale rows: a passkey registered before AUTH_WEBAUTHN_ENABLED was
    # switched off, or an OTP secret left behind by AUTH_MFA_ENABLED=false.
    let(:mfa_state) do
      instance_double(
        Auth::Operations::MfaStateChecker::State,
        mfa_enabled?: true,
        has_otp_secret: true,
        has_recovery_codes: true,
        has_webauthn: true,
      )
    end

    context 'with no second-factor feature loaded' do
      let(:rodauth) { double('Rodauth', account_from_session: account) }

      it 'treats the account as having no completable MFA and records password alone' do
        result = operation.call(
          account_id: 42,
          offer: offer,
          params: { 'method' => 'password', 'password' => 'correct-password' },
        )

        expect(result.status).to eq(200)
        expect(Onetime::RecentReauth).to have_received(:record).with(
          session,
          env,
          account_id: 42,
          methods: %w[password],
        )
      end

      it 'refuses a passkey primary ceremony instead of raising on the missing feature' do
        result = operation.call(
          account_id: 42,
          offer: offer,
          params: { 'method' => 'webauthn' },
        )

        expect(result.status).to eq(403)
        expect(result.body['error_code']).to eq('webauthn_unavailable')
        expect(Onetime::RecentReauth).not_to have_received(:record)
      end
    end

    context 'with only the OTP feature loaded' do
      let(:rodauth) { double('Rodauth', account_from_session: account, otp_auth_route: 'otp-auth') }

      it 'refuses a passkey second factor instead of raising on the missing feature' do
        result = operation.call(
          account_id: 42,
          offer: offer,
          params: { 'method' => 'password', 'password' => 'correct-password', 'mfa_method' => 'webauthn' },
        )

        expect(result.status).to eq(403)
        expect(result.body['error_code']).to eq('webauthn_unavailable')
        expect(result.password_verified).to be true
      end

      it 'offers only the completable second factors' do
        result = operation.call(
          account_id: 42,
          offer: offer,
          params: { 'method' => 'password', 'password' => 'correct-password' },
        )

        expect(result.status).to eq(200)
        expect(result.body).to eq('mfa_required' => true, 'mfa_methods' => %w[otp])
        expect(Onetime::RecentReauth).not_to have_received(:record)
      end
    end

    context 'with only the WebAuthn feature loaded' do
      let(:rodauth) { double('Rodauth', account_from_session: account, webauthn_auth_route: 'webauthn-auth') }

      it 'routes straight to the passkey second factor (webauthn is the only completable one)' do
        allow(db).to receive(:schema).with(:account_webauthn_keys).and_return([])
        dataset = double('Dataset')
        allow(db).to receive(:[]).with(:account_webauthn_keys).and_return(dataset)
        allow(dataset).to receive_messages(where: dataset, select: dataset, all: [])

        result = operation.call(
          account_id: 42,
          offer: offer,
          params: { 'method' => 'password', 'password' => 'correct-password' },
        )

        expect(result.status).to eq(403)
        expect(result.body['error_code']).to eq('webauthn_unavailable')
        expect(result.password_verified).to be true
      end
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
      expect(Onetime::RecentReauth).to have_received(:record).with(
        session,
        env,
        account_id: 42,
        methods: %w[password totp],
      )
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
      expect(Onetime::RecentReauth).to have_received(:record).with(
        session,
        env,
        account_id: 42,
        methods: %w[password recovery_code],
      )
    end
  end
end

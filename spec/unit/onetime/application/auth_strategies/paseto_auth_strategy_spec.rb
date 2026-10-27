# spec/unit/onetime/application/auth_strategies/paseto_auth_strategy_spec.rb
#
# frozen_string_literal: true

# PasetoAuthStrategy (#2427): which requests it claims, how it fails, and what
# it checks before handing back a customer. The customer is a double and the
# keyring is injected into Runtime, so this needs no datastore; the HTTP
# behavior on the mounted v3 app is spec/api/v3/api_v3_bearer_token_spec.rb.
#
# Run: pnpm run test:rspec spec/unit/onetime/application/auth_strategies/paseto_auth_strategy_spec.rb

require 'spec_helper'
require 'onetime/application/auth_strategies'

RSpec.describe Onetime::Application::AuthStrategies::PasetoAuthStrategy do
  # The organization lookup and the session carve-out both read the datastore
  # (OrganizationLoader, CustomerSessionEvaluator). The subclass pins them so
  # the strategy's own decisions are what is under test; `session_identity`
  # is the carve-out's answer for the example.
  subject(:strategy) { strategy_class.new }

  let(:strategy_class) do
    Class.new(described_class) do
      # Class-level, like every concrete strategy (an anonymous subclass does
      # not inherit the parent's instance variable).
      @auth_method_name = 'pasetoauth'

      attr_accessor :session_identity

      def load_organization_context(_cust, _session, _env)
        {}
      end

      private

      def valid_session_identity?(_env)
        session_identity == true
      end
    end
  end
  let(:keyring) { Onetime::Paseto::Keyring.derive('decafbad' * 8) }
  let(:issuer)  { Onetime::Paseto.issuer }
  let(:extid)   { 'ur0123456789abcdefghijklmno' }
  let(:cust) do
    instance_double(
      Onetime::Customer,
      extid: extid,
      objid: 'cust_1',
      anonymous?: false,
      suspended?: false,
      last_password_update: nil,
    )
  end

  before do
    Onetime::Runtime.update_security(paseto_keyring: keyring)
    allow(Onetime.auth_config).to receive(:paseto_enabled?).and_return(true)
    allow(Onetime::Customer).to receive(:extid?).and_call_original
    allow(Onetime::Customer).to receive(:find_by_extid).and_return(nil)
    allow(Onetime::Customer).to receive(:find_by_extid).with(extid).and_return(cust)
  end

  after { Onetime::Runtime.update_security(paseto_keyring: nil) }

  def mint(subject: extid, **overrides)
    Onetime::Paseto::AccessToken.issue(
      subject: subject, keyring: keyring, audience: Onetime::Paseto::V3_AUDIENCE, issuer: issuer, **overrides,
    ).first
  end

  def env_with(authorization, extra = {})
    env                       = { 'rack.session' => {}, 'REMOTE_ADDR' => '127.0.0.1', 'HTTP_USER_AGENT' => 'spec' }
    env['HTTP_AUTHORIZATION'] = authorization if authorization
    env.merge(extra)
  end

  def authenticate(authorization, extra = {})
    env    = env_with(authorization, extra)
    result = strategy.authenticate(env, 'pasetoauth')
    [result, env]
  end

  describe 'a valid token' do
    it 'authenticates the customer named by sub with the pasetoauth method' do
      result, env = authenticate("Bearer #{mint}")

      expect(result).to be_a(Otto::Security::Authentication::StrategyResult)
      expect(result).to be_authenticated
      expect(result.user).to be(cust)
      expect(result.auth_method).to eq('pasetoauth')
      expect(result.session).to be(env['rack.session'])
      expect(result.metadata).to include(auth_type: 'paseto', token_kid: keyring.signing_key.kid)
      expect(result.metadata[:token_jti]).to be_a(String)
      expect(result.metadata[:token_expires_at]).to be > Time.now.to_i
      expect(env).not_to have_key(Onetime::SessionFailureCode::ENV_KEY)
    end

    it 'accepts the scheme name case-insensitively and stray whitespace (RFC 9110 §11.1)' do
      expect(authenticate("bearer  #{mint} ").first).to be_authenticated
      expect(authenticate("BEARER #{mint}").first).to be_authenticated
    end

    it 'passes a nil session through for a stateless call' do
      env = env_with("Bearer #{mint}")
      env.delete('rack.session')
      expect(strategy.authenticate(env, nil).session).to be_nil
    end
  end

  describe 'requests that are not ours (plain failure, chain continues)' do
    it 'fails non-terminally without an Authorization header' do
      result, env = authenticate(nil)

      expect(result).to be_a(Otto::Security::Authentication::AuthFailure)
      expect(result).not_to be_terminal
      expect(result.failure_reason).to include('AUTH_HEADER_MISSING')
      expect(env).not_to have_key(Onetime::SessionFailureCode::ENV_KEY)
    end

    it 'fails non-terminally for another scheme, leaving the header to its own strategy' do
      result, env = authenticate("Basic #{Base64.strict_encode64('user:key')}")

      expect(result).not_to be_terminal
      expect(result.failure_reason).to include('AUTH_TYPE_MISMATCH')
      expect(env).not_to have_key(Onetime::SessionFailureCode::ENV_KEY)
    end

    it 'fails non-terminally for every Bearer header while auth.paseto.enabled is off' do
      allow(Onetime.auth_config).to receive(:paseto_enabled?).and_return(false)

      [mint, 'garbage'].each do |token|
        result, env = authenticate("Bearer #{token}")
        expect(result).to be_a(Otto::Security::Authentication::AuthFailure), token
        expect(result).not_to be_terminal
        expect(result.failure_reason).to include('PASETO_DISABLED')
        expect(env).not_to have_key(Onetime::SessionFailureCode::ENV_KEY)
      end
      expect(Onetime::Customer).not_to have_received(:find_by_extid)
    end
  end

  describe 'a presented Bearer token that is rejected (terminal failure)' do
    def expect_terminal(result, env, reason:, code:)
      expect(result).to be_a(Otto::Security::Authentication::AuthFailure)
      expect(result).to be_terminal
      expect(result.failure_reason).to include(reason)
      expect(env[Onetime::SessionFailureCode::ENV_KEY]).to eq(code)
      expect(Onetime::SessionFailureCode.scheme(env)).to eq(Onetime::SessionFailureCode::SCHEME_BEARER)
    end

    it 'rejects a token that is not PASETO' do
      result, env = authenticate('Bearer unimplemented-authentication-boundary-token')
      expect_terminal(result, env, reason: 'TOKEN_INVALID', code: :api_token_invalid)
    end

    it 'rejects an expired token with its own code' do
      token       = mint(now: Time.now - 7200, ttl: 3600)
      result, env = authenticate("Bearer #{token}")
      expect_terminal(result, env, reason: 'TOKEN_EXPIRED', code: :api_token_expired)
    end

    it 'rejects a token signed by an unknown key' do
      other       = Onetime::Paseto::Keyring.derive('deadbeef' * 8)
      result, env = authenticate("Bearer #{mint(keyring: other)}")
      expect_terminal(result, env, reason: 'TOKEN_INVALID', code: :api_token_invalid)
    end

    it 'rejects a token for another audience' do
      result, env = authenticate("Bearer #{mint(audience: 'onetimesecret:api:account')}")
      expect_terminal(result, env, reason: 'TOKEN_INVALID', code: :api_token_invalid)
    end

    it 'rejects a tampered token' do
      token       = mint
      body        = token.split('.')[2]
      flipped     = body.dup
      flipped[10] = flipped[10] == 'A' ? 'B' : 'A'
      result, env = authenticate("Bearer #{token.sub(body, flipped)}")
      expect_terminal(result, env, reason: 'TOKEN_INVALID', code: :api_token_invalid)
    end

    it 'rejects a subject that is not a customer extid without touching the datastore' do
      result, env = authenticate("Bearer #{mint(subject: 'on0123456789abcdefghijklmno')}")
      expect_terminal(result, env, reason: 'TOKEN_INVALID', code: :api_token_invalid)
      expect(Onetime::Customer).not_to have_received(:find_by_extid)
    end

    it 'rejects a subject that no longer exists with the same code' do
      result, env = authenticate("Bearer #{mint(subject: 'ur9999999999abcdefghijklmno')}")
      expect_terminal(result, env, reason: 'TOKEN_INVALID', code: :api_token_invalid)
    end

    it 'rejects a suspended account only after the signature verified' do
      allow(cust).to receive(:suspended?).and_return(true)
      result, env = authenticate("Bearer #{mint}")
      expect_terminal(result, env, reason: 'ACCOUNT_SUSPENDED', code: :suspended_credentials)
    end

    it 'rejects a token issued at or before the credential watermark' do
      issued      = Time.now - 120
      allow(cust).to receive(:last_password_update).and_return(issued.to_i)
      result, env = authenticate("Bearer #{mint(now: issued)}")
      expect_terminal(result, env, reason: 'TOKEN_INVALID', code: :api_token_invalid)

      allow(cust).to receive(:last_password_update).and_return(issued.to_i - 1)
      expect(authenticate("Bearer #{mint(now: issued)}").first).to be_authenticated
    end

    it 'rejects every token when no keyring was derived at boot' do
      Onetime::Runtime.update_security(paseto_keyring: nil)
      result, env = authenticate("Bearer #{mint}")
      expect_terminal(result, env, reason: 'TOKEN_INVALID', code: :api_token_invalid)
    end
  end

  describe 'the session carve-out shared with Basic auth' do
    it 'fails non-terminally when the same request resolves a valid session identity' do
      strategy.session_identity = true
      result, env               = authenticate('Bearer not-a-token')

      expect(result).to be_a(Otto::Security::Authentication::AuthFailure)
      expect(result).not_to be_terminal
      expect(env).not_to have_key(Onetime::SessionFailureCode::ENV_KEY)
    end
  end
end

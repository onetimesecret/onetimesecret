# frozen_string_literal: true

# before_email_auth_request_route (RISK-2026-08-14-M04): the email-login-request
# limiter runs on POST, before the origin preflight, and both run before the
# route body's account lookup. Mirrors reset_password_request_spec.rb.

require 'spec_helper'
require 'rodauth'

module Auth; end
Auth.const_set(:Config, Class.new(Rodauth::Auth)) unless defined?(Auth::Config)
Auth::Config.const_set(:Hooks, Module.new) unless Auth::Config.const_defined?(:Hooks, false)

require_relative '../../../config/hooks/email_login_request'

# rubocop:disable-next RSpec/SpecFilePathFormat -- auth config specs follow the lane-owned directory
RSpec.describe Auth::Config::Hooks::EmailLoginRequest, :aggregate_failures do
  let(:features) { [:email_auth] }
  let(:auth_class) do
    email_auth_enabled = features.include?(:email_auth)
    Class.new(Rodauth::Auth) do
      configure do
        enable :login
        enable :email_auth if email_auth_enabled
        Auth::Config::Hooks::EmailLoginRequest.configure(self)
      end
    end
  end
  let(:auth) { auth_class.allocate }
  let(:request) { instance_double(Rack::Request, post?: true, env: { 'otto.client_ip' => '203.0.113.0' }) }

  describe 'registered POST preflight' do
    before do
      allow(auth).to receive_messages(
        request: request,
        login_param: 'login',
        param_or_nil: 'target@example.org',
      )
      allow(auth).to receive(:enforce_email_login_request_rate_limit!).and_return(nil)
      allow(Auth::PublicHost).to receive(:required_base_url!).and_return('https://operator.example.org')
    end

    it 'calls the limiter before resolving the origin' do
      auth.send(:before_email_auth_request_route)

      expect(auth).to have_received(:enforce_email_login_request_rate_limit!)
        .with('203.0.113.0', 'target@example.org').ordered
      expect(Auth::PublicHost).to have_received(:required_base_url!).with(request.env).ordered
    end

    it 'charges the email_login_request scope, never the reset-request buckets' do
      allow(auth).to receive(:enforce_email_login_request_rate_limit!).and_call_original
      allow(auth).to receive(:enforce_reset_request_rate_limit!).and_return(nil)

      auth.send(:before_email_auth_request_route)

      expect(auth).to have_received(:enforce_reset_request_rate_limit!)
        .with('203.0.113.0', 'target@example.org', scope: :email_login_request)
    end

    it 'falls back to request.ip when otto.client_ip is absent' do
      allow(request).to receive_messages(env: {}, ip: '198.51.100.0')

      auth.send(:before_email_auth_request_route)

      expect(auth).to have_received(:enforce_email_login_request_rate_limit!).with('198.51.100.0', 'target@example.org')
    end

    it 'still resolves the origin when the limiter is disabled' do
      allow(auth).to receive(:enforce_email_login_request_rate_limit!).and_call_original
      allow(auth).to receive(:reset_request_rate_limit_enabled?).and_return(false)
      allow(auth).to receive(:reset_request_redis).and_call_original

      auth.send(:before_email_auth_request_route)

      expect(auth).to have_received(:reset_request_rate_limit_enabled?).with(:email_login_request)
      expect(auth).not_to have_received(:reset_request_redis)
      expect(Auth::PublicHost).to have_received(:required_base_url!).with(request.env)
    end

    it 'does not resolve the origin when rate limiting refuses' do
      allow(auth).to receive(:enforce_email_login_request_rate_limit!).and_raise(Onetime::LimitExceeded.new('throttled'))

      expect { auth.send(:before_email_auth_request_route) }.to raise_error(Onetime::LimitExceeded)
      expect(Auth::PublicHost).not_to have_received(:required_base_url!)
    end

    it 'does not run either POST check for a GET' do
      allow(request).to receive(:post?).and_return(false)

      auth.send(:before_email_auth_request_route)

      expect(auth).not_to have_received(:enforce_email_login_request_rate_limit!)
      expect(Auth::PublicHost).not_to have_received(:required_base_url!)
    end

    it 'skips internal requests, which are server-initiated' do
      allow(auth).to receive(:internal_request?).and_return(true)

      auth.send(:before_email_auth_request_route)

      expect(auth).not_to have_received(:enforce_email_login_request_rate_limit!)
      expect(Auth::PublicHost).not_to have_received(:required_base_url!)
    end
  end

  # The magic link POST /auth/login sends a passwordless account never enters
  # the route above; restrict_to.rb's before_email_auth_request calls this.
  describe '.charge_login_dispatch!' do
    before do
      allow(auth).to receive_messages(
        request: request,
        login_param: 'login',
        param_or_nil: 'target@example.org',
        current_route: :login,
      )
      allow(auth).to receive(:enforce_email_login_request_rate_limit!).and_return(nil)
    end

    it 'charges the login route dispatch to the same budget' do
      described_class.charge_login_dispatch!(auth)

      expect(auth).to have_received(:enforce_email_login_request_rate_limit!)
        .with('203.0.113.0', 'target@example.org')
    end

    it 'falls back to request.ip when otto.client_ip is absent' do
      allow(request).to receive_messages(env: {}, ip: '198.51.100.0')

      described_class.charge_login_dispatch!(auth)

      expect(auth).to have_received(:enforce_email_login_request_rate_limit!).with('198.51.100.0', 'target@example.org')
    end

    it 'propagates the refusal, so no key is created and no mail is sent' do
      allow(auth).to receive(:enforce_email_login_request_rate_limit!).and_raise(Onetime::LimitExceeded.new('throttled'))

      expect { described_class.charge_login_dispatch!(auth) }.to raise_error(Onetime::LimitExceeded)
    end

    it 'does not charge the dedicated route a second time' do
      allow(auth).to receive(:current_route).and_return(:email_auth_request)

      described_class.charge_login_dispatch!(auth)

      expect(auth).not_to have_received(:enforce_email_login_request_rate_limit!)
    end

    it 'skips internal requests, which are server-initiated' do
      allow(auth).to receive(:internal_request?).and_return(true)

      described_class.charge_login_dispatch!(auth)

      expect(auth).not_to have_received(:enforce_email_login_request_rate_limit!)
    end
  end

  context 'without the email_auth feature' do
    let(:features) { [] }

    it 'does not register a hook or include the limiter' do
      expect(auth_class.private_instance_methods + auth_class.instance_methods).not_to include(:before_email_auth_request_route)
      expect(auth_class.ancestors).not_to include(Onetime::Security::ResetRequestRateLimiter)
    end
  end
end

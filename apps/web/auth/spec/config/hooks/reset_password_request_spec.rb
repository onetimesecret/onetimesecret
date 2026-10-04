# frozen_string_literal: true

require 'spec_helper'
require 'rodauth'

module Auth; end
Auth.const_set(:Config, Class.new(Rodauth::Auth)) unless defined?(Auth::Config)
Auth::Config.const_set(:Hooks, Module.new) unless Auth::Config.const_defined?(:Hooks, false)

require_relative '../../../config/hooks/reset_password_request'

# rubocop:disable-next RSpec/SpecFilePathFormat -- auth config specs follow the lane-owned directory
RSpec.describe Auth::Config::Hooks::ResetPasswordRequest, :aggregate_failures do
  let(:features) { [:reset_password] }
  let(:auth_class) do
    reset_enabled = features.include?(:reset_password)
    Class.new(Rodauth::Auth) do
      configure do
        enable :login
        enable :reset_password if reset_enabled
        Auth::Config::Hooks::ResetPasswordRequest.configure(self)
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
        base_url: 'https://operator.example.org',
      )
      allow(auth).to receive(:enforce_reset_request_rate_limit!).and_return(nil)
    end

    it 'calls the limiter before resolving the origin' do
      auth.send(:before_reset_password_request_route)

      expect(auth).to have_received(:enforce_reset_request_rate_limit!).with('203.0.113.0', 'target@example.org').ordered
      expect(auth).to have_received(:base_url).ordered
    end

    it 'still resolves the origin when the limiter is disabled' do
      allow(auth).to receive(:enforce_reset_request_rate_limit!).and_call_original
      allow(auth).to receive(:reset_request_rate_limit_enabled?).and_return(false)
      allow(auth).to receive(:reset_request_redis).and_call_original

      auth.send(:before_reset_password_request_route)

      expect(auth).not_to have_received(:reset_request_redis)
      expect(auth).to have_received(:base_url)
    end

    it 'does not resolve the origin when rate limiting refuses' do
      allow(auth).to receive(:enforce_reset_request_rate_limit!).and_raise(Onetime::LimitExceeded.new('throttled'))

      expect { auth.send(:before_reset_password_request_route) }.to raise_error(Onetime::LimitExceeded)
      expect(auth).not_to have_received(:base_url)
    end

    it 'does not run either POST check for a GET' do
      allow(request).to receive(:post?).and_return(false)

      auth.send(:before_reset_password_request_route)

      expect(auth).not_to have_received(:enforce_reset_request_rate_limit!)
      expect(auth).not_to have_received(:base_url)
    end
  end

  context 'without the reset_password feature' do
    let(:features) { [] }

    it 'does not register a hook or include the limiter' do
      expect(auth_class.private_instance_methods + auth_class.instance_methods).not_to include(:before_reset_password_request_route)
      expect(auth_class.ancestors).not_to include(Onetime::Security::ResetRequestRateLimiter)
    end
  end
end

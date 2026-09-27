# apps/web/auth/spec/config/features/remember_me_spec.rb
#
# frozen_string_literal: true

# Auth::Config::Features::RememberMe (AUTH_REMEMBER_ME_ENABLED).
#
# The checkbox makes the session itself last a fixed 14 days
# (lib/onetime/session/remember_me.rb); Rodauth's :remember feature, whose
# cookie nothing ever consumed, is no longer enabled. This spec pins the
# configuration: no remember cookie machinery, and the two methods the login
# hooks call. The behaviour is covered end to end in
# spec/integration/full/remember_me_spec.rb and
# apps/web/auth/spec/integration/full_mfa/remember_me_mfa_spec.rb.

require_relative '../../spec_helper'
require 'rodauth'

# Auth::Config MUST be a Rodauth::Auth subclass, never a plain module or class
# (see the preamble in unit/omniauth_tenant_helpers_spec.rb).
module Auth; end
Auth.const_set(:Config, Class.new(Rodauth::Auth)) unless defined?(Auth::Config)
Auth::Config.const_set(:Features, Module.new) unless Auth::Config.const_defined?(:Features, false)
require_relative '../../../config/features/remember_me'

RSpec.describe 'Auth::Config::Features::RememberMe' do
  let(:db) { create_test_database }

  let(:app) do
    create_rodauth_app(db: db, features: [:base, :login, :logout]) do
      Auth::Config::Features::RememberMe.configure(self)
    end
  end

  it 'does not enable Rodauth\'s remember feature' do
    expect(rodauth_responds_to?(app, :remember_login)).to be false
    expect(rodauth_responds_to?(app, :load_memory)).to be false
    expect(rodauth_responds_to?(app, :remember_cookie_key)).to be false
  end

  it 'defines the methods the after_login and two-factor hooks call' do
    expect(rodauth_responds_to?(app, :remember_me_after_login)).to be true
    expect(rodauth_responds_to?(app, :remember_me_after_two_factor)).to be true
  end

  it 'leaves core login and logout in place' do
    expect(rodauth_responds_to?(app, :login_route)).to be true
    expect(rodauth_responds_to?(app, :logout_route)).to be true
  end
end

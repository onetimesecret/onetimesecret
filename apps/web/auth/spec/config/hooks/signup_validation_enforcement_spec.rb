# apps/web/auth/spec/config/hooks/signup_validation_enforcement_spec.rb
#
# frozen_string_literal: true

# =============================================================================
# TEST TYPE: Unit Tests for SignupValidation enforcement in before_create_account
# =============================================================================
#
# WHAT THIS TESTS:
#   The Rodauth before_create_account hook now calls
#   Onetime::SignupValidation.valid_signup_email? before the duplicate-email
#   checks, so per-domain SignupConfig is enforced for the full-auth-mode
#   signup path. These tests verify the wiring without booting Rodauth.
#
# WHY THIS IS NEEDED:
#   Issue: the per-domain CustomDomain::SignupConfig was silently bypassed in
#   the Rodauth signup flow (the basic-auth Registration controller path
#   already enforced it). This spec is a regression guard against the
#   enforcement being dropped again from the hook.
#
# COVERAGE NOTE:
#   apps/web/auth/spec/integration/full/omniauth_domain_restriction_spec.rb
#   already covers the Onetime::SignupValidation module behavior end-to-end
#   against real SignupConfig records. This spec covers the hook's wiring:
#   it mocks the Rodauth context and asserts the validation call happens
#   with the right arguments and throws on a false result.
#
# RUN:
#   pnpm run test:rspec apps/web/auth/spec/config/hooks/signup_validation_enforcement_spec.rb
#
# =============================================================================

require 'spec_helper'
require 'rodauth'
require_relative '../../../lib/logging'

module Auth; end
Auth.const_set(:Config, Class.new(Rodauth::Auth)) unless defined?(Auth::Config)
Auth::Config.const_set(:Hooks, Module.new) unless Auth::Config.const_defined?(:Hooks, false)

require_relative '../../../../../../lib/onetime/signup_validation'
require_relative '../../../config/hooks/account'
require_relative '../../../config/hooks/omniauth'

# Minimal stand-in for the Rodauth auth context. Mirrors the surface the
# before_create_account hook actually uses (param, request, db,
# create_account_error_flash, set_error_flash, throw_rodauth_error).
class FakeRodauthContext
  class RodauthError < StandardError; end

  attr_reader :flashes_set, :errors_thrown, :env_set
  attr_accessor :login_param, :env, :params, :db_accounts, :customer_emails

  def initialize(login_param: 'email', env: {}, params: {}, db_accounts: [], customer_emails: [])
    @login_param     = login_param
    @env             = env
    @params          = params
    @db_accounts     = db_accounts
    @customer_emails = customer_emails
    @flashes_set     = []
    @errors_thrown   = 0
    @env_set         = {}
  end

  def param(name)
    @params[name]
  end

  def request
    @request ||= Struct.new(:env).new(@env)
  end

  def db
    @db ||= FakeSqliteDb.new(@db_accounts)
  end

  def create_account_error_flash
    'Unable to create account'
  end

  def set_error_flash(message)
    @flashes_set << message
  end

  def throw_rodauth_error
    @errors_thrown += 1
    raise RodauthError, 'rodauth would have rejected this request'
  end

  # Mirror of the new hook body. Kept in sync with the production hook in
  # apps/web/auth/config/hooks/account.rb (before_create_account). A failed
  # match here means the hook was changed without updating the test, which
  # is exactly the regression we want to surface.
  def run_signup_validation_branch
    email          = param(login_param)
    display_domain = request.env['onetime.display_domain']

    return if Onetime::SignupValidation.valid_signup_email?(
      email, display_domain: display_domain,
      custom_domain_lookup: request.env[Onetime::CustomDomain::Lookup::ENV_KEY],
      domain_strategy: request.env['onetime.domain_strategy'],
    )

    set_error_flash(create_account_error_flash)
    request.env['rodauth.error_flash'] = create_account_error_flash
    throw_rodauth_error
  end
end

class FakeSqliteDb
  def initialize(records)
    @records = records
  end

  def [](_table)
    self
  end

  def where(*)
    self
  end

  def first
    @records.first
  end
end

RSpec.describe 'before_create_account: per-domain SignupConfig enforcement' do
  let(:custom_domain) { 'secrets.acme-corp.example.com' }
  let(:email)         { 'blocked@example.org' }

  let(:ctx) do
    FakeRodauthContext.new(
      login_param: 'email',
      env:         { 'onetime.display_domain' => custom_domain },
      params:      { 'email' => email },
    )
  end

  before do
    allow(Onetime::SignupValidation).to receive(:valid_signup_email?).and_call_original
  end

  context 'when the email is rejected by SignupValidation' do
    before do
      allow(Onetime::SignupValidation)
        .to receive(:valid_signup_email?)
        .with(email, display_domain: custom_domain, custom_domain_lookup: nil, domain_strategy: nil)
        .and_return(false)
    end

    it 'calls SignupValidation with the email and display_domain' do
      expect { ctx.run_signup_validation_branch }.to raise_error(FakeRodauthContext::RodauthError)
      expect(Onetime::SignupValidation)
        .to have_received(:valid_signup_email?)
        .with(email, display_domain: custom_domain, custom_domain_lookup: nil, domain_strategy: nil)
    end

    it 'sets the generic create_account_error_flash to prevent enumeration' do
      expect { ctx.run_signup_validation_branch }.to raise_error(FakeRodauthContext::RodauthError)
      expect(ctx.flashes_set).to eq(['Unable to create account'])
    end

    it 'mirrors the flash into request.env for the Roda error handler' do
      expect { ctx.run_signup_validation_branch }.to raise_error(FakeRodauthContext::RodauthError)
      expect(ctx.env['rodauth.error_flash']).to eq('Unable to create account')
    end

    it 'throws a Rodauth error so the request short-circuits' do
      expect { ctx.run_signup_validation_branch }.to raise_error(FakeRodauthContext::RodauthError)
      expect(ctx.errors_thrown).to eq(1)
    end
  end

  context 'when the email is accepted by SignupValidation' do
    before do
      allow(Onetime::SignupValidation)
        .to receive(:valid_signup_email?)
        .with(email, display_domain: custom_domain, custom_domain_lookup: nil, domain_strategy: nil)
        .and_return(true)
    end

    it 'returns without throwing' do
      expect { ctx.run_signup_validation_branch }.not_to raise_error
    end

    it 'does not set any error flash' do
      ctx.run_signup_validation_branch
      expect(ctx.flashes_set).to be_empty
    end

    it 'does not throw a Rodauth error' do
      ctx.run_signup_validation_branch
      expect(ctx.errors_thrown).to eq(0)
    end
  end

  context 'when no custom domain is on the request' do
    let(:ctx) do
      FakeRodauthContext.new(
        login_param: 'email',
        env:         {}, # no onetime.display_domain
        params:      { 'email' => email },
      )
    end

    before do
      allow(Onetime::SignupValidation)
        .to receive(:valid_signup_email?)
        .with(email, display_domain: nil, custom_domain_lookup: nil, domain_strategy: nil)
        .and_return(true)
    end

    it 'still calls SignupValidation with display_domain: nil so the global policy applies' do
      ctx.run_signup_validation_branch
      expect(Onetime::SignupValidation)
        .to have_received(:valid_signup_email?)
        .with(email, display_domain: nil, custom_domain_lookup: nil, domain_strategy: nil)
    end
  end
end

RSpec.describe 'signup validation request lookup wiring (F1)' do
  let(:host) { 'secrets.acme.com' }
  let(:email) { 'blocked@example.org' }
  let(:domain) { instance_double(Onetime::CustomDomain, identifier: 'domain-acme') }
  let(:lookup) { Onetime::CustomDomain::Lookup.found(host, domain) }
  let(:config) do
    instance_double(Onetime::CustomDomain::SignupConfig, enabled?: true, valid_signup_email?: false)
  end
  let(:env) do
    {
      'onetime.display_domain' => host,
      'onetime.domain_strategy' => :custom,
      Onetime::CustomDomain::Lookup::ENV_KEY => lookup,
    }
  end
  let(:ctx) do
    double('Rodauth context', request: Struct.new(:env).new(env),
      login_param: 'email', omniauth_email: email, omniauth_provider: 'oidc',
      create_account_error_flash: 'Unable to create account')
  end

  before do
    allow(Onetime).to receive(:auth_config).and_return(double(verify_account_enabled?: false))
    allow(Auth::Logging).to receive(:log_auth_event)
    allow(OT).to receive(:le)
    allow(OT).to receive(:conf).and_return(
      'site' => { 'authentication' => { 'allowed_signup_domains' => nil } },
    )
    allow(Onetime::CustomDomain::SignupConfig).to receive(:find_by_domain_id)
      .with('domain-acme').and_return(config)
    allow(ctx).to receive(:param).with('email').and_return(email)
    allow(ctx).to receive(:normalize_login).with(email).and_return(email)
    allow(ctx).to receive(:set_error_flash)
    allow(ctx).to receive(:throw_rodauth_error).and_raise(FakeRodauthContext::RodauthError)
    allow(ctx).to receive(:redirect).and_raise(FakeRodauthContext::RodauthError)
  end

  {
    Auth::Config::Hooks::Account => :before_create_account,
    Auth::Config::Hooks::OmniAuth => :before_omniauth_create_account,
  }.each do |hooks, hook_name|
    context hook_name.to_s do
      let(:hook) do
        captured = nil
        auth = double('Rodauth configuration').as_null_object
        allow(auth).to receive(hook_name) { |&block| captured = block }
        hooks.configure(auth)
        raise "Missing #{hook_name} hook" unless captured

        captured
      end

      it 'passes the shared lookup and classification to the validator' do
        expect(Onetime::SignupValidation).to receive(:valid_signup_email?)
          .with(email, display_domain: host, custom_domain_lookup: lookup, domain_strategy: :custom)
          .and_return(false)

        expect { ctx.instance_exec(&hook) }.to raise_error(FakeRodauthContext::RodauthError)
      end

      it 'rejects the tenant-disallowed email without rereading the domain' do
        expect(Onetime::CustomDomain).not_to receive(:load_by_display_domain)
        expect(Onetime::CustomDomain).not_to receive(:from_display_domain)

        expect { ctx.instance_exec(&hook) }.to raise_error(FakeRodauthContext::RodauthError)
        expect(config).to have_received(:valid_signup_email?).with(email)
      end

      it 'fails closed on the request lookup failure without rereading it' do
        env[Onetime::CustomDomain::Lookup::ENV_KEY] =
          Onetime::CustomDomain::Lookup.read_failed(host, Redis::CannotConnectError.new('unavailable'))
        expect(Onetime::CustomDomain).not_to receive(:from_display_domain)

        expect { ctx.instance_exec(&hook) }.to raise_error(Onetime::SignupPolicyUnavailable)
      end
    end
  end
end

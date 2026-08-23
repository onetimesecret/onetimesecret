# spec/unit/signup_policy_unavailable_spec.rb
#
# frozen_string_literal: true

# UNREADABLE TENANT SIGN-UP POLICY FAILS CLOSED (#4157).
# ADR-024#operator-defaults-require-positive-classification
#
# The classification-aware resolvers only close the widening when the app can
# actually READ the tenant's SignupConfig. Two datastore reads back that policy
# (CustomDomain.from_display_domain, then SignupConfig.find_by_domain_id) and
# both live in Onetime::Logic::SignupConfigResolution. Before this change a
# Redis::BaseError there produced an unhandled 500 at best — and the same blip
# is what makes DomainStrategy answer :invalid for a real customer domain, the
# classification that used to inherit the operator's global sign-up default.
#
# The sign-in half of this rule is pinned in apps/web/auth/spec/unit/restrict_to_gate_spec.rb
# and spec/unit/domain_strategy_classification_contract_spec.rb; this file is the
# sign-up half, and it pins the two halves as the SAME rule (same carve-out
# predicate, same 503 body shape) rather than two copies that can drift.

require 'spec_helper'
require 'onetime/logic/signup_config_resolution'
require_relative '../../apps/web/auth/error_translator'

module SignupPolicyContract
  CLASSIFICATIONS = [:canonical, :subdomain, :custom, :invalid, nil].freeze
  OPERATOR        = [:canonical, :subdomain].freeze

  # Minimal includer of the mixin: the mixin's whole contract is the three
  # hooks, so a fake that supplies them exercises the real read/rescue path
  # without booting a controller or a logic class.
  class FakeConsumer
    include Onetime::Logic::SignupConfigResolution

    def initialize(display_domain:, domain_strategy:, autoverify: 'false')
      @display_domain  = display_domain
      @domain_strategy = domain_strategy
      @autoverify      = autoverify
    end

    # public wrappers — the mixin's methods are private by design
    def config = domain_signup_config
    def autoverify = resolve_autoverify

    private

    def signup_config_display_domain = @display_domain
    def signup_config_domain_strategy = @domain_strategy
    def signup_config_auth_setting(_key) = @autoverify
  end

  # An includer that forgot the classification hook, to pin the default.
  class HooklessConsumer
    include Onetime::Logic::SignupConfigResolution

    def config = domain_signup_config

    private

    def signup_config_display_domain = 'tenant.example.com'
    def signup_config_auth_setting(_key) = 'false'
  end
end

RSpec.describe 'Sign-up policy read failure (#4157)' do
  let(:blip) { Redis::BaseError.new('connection reset') }

  describe 'SignupConfig.resolve_lookup_failure — the decision owner' do
    SignupPolicyContract::CLASSIFICATIONS.each do |strategy|
      operator = SignupPolicyContract::OPERATOR.include?(strategy)

      if operator
        it "returns nil (no per-domain config to lose) for #{strategy.inspect}" do
          expect(
            Onetime::CustomDomain::SignupConfig.resolve_lookup_failure(domain_strategy: strategy),
          ).to be_nil
        end
      else
        it "raises SignupPolicyUnavailable for #{strategy.inspect}" do
          expect {
            Onetime::CustomDomain::SignupConfig.resolve_lookup_failure(domain_strategy: strategy)
          }.to raise_error(Onetime::SignupPolicyUnavailable)
        end
      end
    end

    # The carve-out must be the SAME predicate the sign-in path uses, not a
    # second list: two gates disagreeing about which hosts survive an outage is
    # exactly the drift a single shared predicate exists to kill.
    it 'delegates the carve-out to SigninConfig.operator_host?' do
      expect(Onetime::CustomDomain::SigninConfig).to receive(:operator_host?).with(:custom).and_return(true)

      expect(
        Onetime::CustomDomain::SignupConfig.resolve_lookup_failure(domain_strategy: :custom),
      ).to be_nil
    end

    it 'accepts String classifications — StrategyResult metadata is not always a Symbol' do
      expect(
        Onetime::CustomDomain::SignupConfig.resolve_lookup_failure(domain_strategy: 'canonical'),
      ).to be_nil
      expect {
        Onetime::CustomDomain::SignupConfig.resolve_lookup_failure(domain_strategy: 'custom')
      }.to raise_error(Onetime::SignupPolicyUnavailable)
    end
  end

  describe 'the error family' do
    it 'is a sibling of the sign-in error, not a copy of its shape' do
      signup = Onetime::SignupPolicyUnavailable.new
      signin = Onetime::SigninPolicyUnavailable.new

      expect(signup).to be_a(Onetime::AuthPolicyUnavailable)
      expect(signin).to be_a(Onetime::AuthPolicyUnavailable)
      expect(signup.to_h.keys).to eq(signin.to_h.keys)
      expect(signup.to_h[:retry_after]).to eq(signin.to_h[:retry_after])
    end

    # The error_type is what routes an alert and what the frontend switches on;
    # a shared parent must not have collapsed the two surfaces into one name,
    # and the sign-in value is already pinned by existing specs.
    it 'names the surface that is actually down' do
      expect(Onetime::SignupPolicyUnavailable.new.to_h[:error_type]).to eq('SignupPolicyUnavailable')
      expect(Onetime::SigninPolicyUnavailable.new.to_h[:error_type]).to eq('SigninPolicyUnavailable')
      expect(Onetime::SignupPolicyUnavailable.new.message).to match(/Sign-up is temporarily unavailable/)
    end

    # Otto dispatches on the exact class name, so the sibling needs its own
    # registration; the Roda edge walks ancestors, so the family entry covers
    # both. This pins the Roda half (the Otto half is a boot-time registration).
    it 'translates to 503 at the Roda auth edge via the family entry' do
      status, body = Auth::ErrorTranslator.translate(Onetime::SignupPolicyUnavailable.new)

      expect(status).to eq(503)
      expect(body[:error_type]).to eq('SignupPolicyUnavailable')
      expect(Auth::ErrorTranslator.level_for(Onetime::SignupPolicyUnavailable.new)).to eq(:error)
      expect(Auth::ErrorTranslator.translate(Onetime::SigninPolicyUnavailable.new).first).to eq(503)
    end
  end

  describe 'Onetime::Logic::SignupConfigResolution' do
    # Both reads are guarded, because either one can be the one that fails.
    {
      'the CustomDomain identity read' => :identity,
      'the SignupConfig read' => :config,
    }.each do |label, failing_read|
      context "when #{label} raises" do
        before do
          case failing_read
          when :identity
            # Exercise from_display_domain's production behavior: unlike the
            # fail-open load_by_display_domain helper, it lets primary-database
            # failures escape so policy resolution can answer 503.
            index = instance_double(Familia::HashKey)
            allow(index).to receive(:get).and_raise(blip)
            allow(Onetime::CustomDomain).to receive(:display_domain_index).and_return(index)
          when :config
            allow(Onetime::CustomDomain).to receive(:from_display_domain)
              .and_return(instance_double(Onetime::CustomDomain, identifier: 'domain-1'))
            allow(Onetime::CustomDomain::SignupConfig).to receive(:find_by_domain_id).and_raise(blip)
          end
          allow(OT).to receive(:le)
        end

        SignupPolicyContract::CLASSIFICATIONS.each do |strategy|
          operator = SignupPolicyContract::OPERATOR.include?(strategy)

          if operator
            it "resolves to nil on #{strategy.inspect} — the only answer that host could have had" do
              consumer = SignupPolicyContract::FakeConsumer.new(
                display_domain: 'www.example.com', domain_strategy: strategy,
              )

              expect(consumer.config).to be_nil
            end
          else
            it "raises SignupPolicyUnavailable on #{strategy.inspect}" do
              consumer = SignupPolicyContract::FakeConsumer.new(
                display_domain: 'tenant.example.com', domain_strategy: strategy,
              )

              expect { consumer.config }.to raise_error(Onetime::SignupPolicyUnavailable)
            end
          end
        end

        # AUTOVERIFY IS A POLICY READ TOO. Falling back to the global setting
        # on an unreadable tenant policy auto-verifies accounts on a domain
        # whose owner never opted into that — the same widen as the gate's, so
        # it takes the same rule.
        it 'does not let autoverify fall back to the global setting on a tenant host' do
          consumer = SignupPolicyContract::FakeConsumer.new(
            display_domain: 'tenant.example.com', domain_strategy: :invalid, autoverify: 'true',
          )

          expect { consumer.autoverify }.to raise_error(Onetime::SignupPolicyUnavailable)
        end

        it 'still resolves autoverify from the global setting on an operator host' do
          consumer = SignupPolicyContract::FakeConsumer.new(
            display_domain: 'www.example.com', domain_strategy: :canonical, autoverify: 'true',
          )

          expect(consumer.autoverify).to be(true)
        end

        # An includer that supplies no classification gets nil, which
        # operator_host? rejects: over-strict, never over-permissive.
        it 'fails closed for an includer that omits the classification hook' do
          expect { SignupPolicyContract::HooklessConsumer.new.config }
            .to raise_error(Onetime::SignupPolicyUnavailable)
        end
      end
    end

    it 'is transparent when the reads succeed' do
      config = instance_double(Onetime::CustomDomain::SignupConfig)
      allow(Onetime::CustomDomain).to receive(:from_display_domain)
        .and_return(instance_double(Onetime::CustomDomain, identifier: 'domain-1'))
      allow(Onetime::CustomDomain::SignupConfig).to receive(:find_by_domain_id)
        .with('domain-1').and_return(config)

      consumer = SignupPolicyContract::FakeConsumer.new(
        display_domain: 'tenant.example.com', domain_strategy: :custom,
      )

      expect(consumer.config).to be(config)
    end
  end

  # The runtime gate is the surface that actually has to answer 503. Its hooks
  # must feed the mixin the request's real classification, or a blip would take
  # the CANONICAL sign-up page down for a read that costs it nothing.
  describe 'Core::Controllers::Base#signup_enabled?' do
    let(:controller_class) do
      Class.new do
        include Core::Controllers::Base

        def initialize(env)
          @req = Struct.new(:env).new(env)
        end
      end
    end

    def controller_for(strategy)
      controller_class.new(
        'onetime.domain_strategy' => strategy,
        'onetime.display_domain' => 'tenant.example.com',
      )
    end

    before do
      allow(OT).to receive(:conf).and_return(
        { 'site' => { 'authentication' => { 'enabled' => true, 'signup' => true } } },
      )
      allow(OT).to receive(:le)
      allow(Onetime::CustomDomain).to receive(:from_display_domain).and_raise(blip)
    end

    it 'raises SignupPolicyUnavailable on :custom' do
      expect { controller_for(:custom).send(:signup_enabled?) }
        .to raise_error(Onetime::SignupPolicyUnavailable)
    end

    # The row this file exists for: a blip's :invalid must not become "follow
    # the operator's global signup default".
    it 'raises SignupPolicyUnavailable on :invalid rather than following the global default' do
      expect { controller_for(:invalid).send(:signup_enabled?) }
        .to raise_error(Onetime::SignupPolicyUnavailable)
    end

    it 'raises SignupPolicyUnavailable when the request never passed the middleware (nil)' do
      expect { controller_for(nil).send(:signup_enabled?) }
        .to raise_error(Onetime::SignupPolicyUnavailable)
    end

    SignupPolicyContract::OPERATOR.each do |strategy|
      it "keeps following the global default on #{strategy.inspect}" do
        expect(controller_for(strategy).send(:signup_enabled?)).to be(true)
      end
    end
  end
end

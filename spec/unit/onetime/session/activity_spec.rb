# spec/unit/onetime/session/activity_spec.rb
#
# frozen_string_literal: true

require 'spec_helper'
require 'otto'
require 'onetime/session/activity'

RSpec.describe Onetime::SessionActivity do
  describe '.passive?' do
    it 'is true when the matched route declares activity=passive' do
      expect(described_class.passive?('otto.route_options' => { activity: 'passive' })).to be(true)
    end

    # Fail towards today's behaviour: anything that is not the exact
    # declaration is activity.
    [
      ['no env', nil],
      ['an env that is not a Hash', Object.new],
      ['no matched route', {}],
      ['route options that are not a Hash', { 'otto.route_options' => 'activity=passive' }],
      ['a route without the option', { 'otto.route_options' => { auth: 'noauth' } }],
      ['another value', { 'otto.route_options' => { activity: 'active' } }],
      ['a Symbol value', { 'otto.route_options' => { activity: :passive } }],
      ['a String key, which Otto never produces', { 'otto.route_options' => { 'activity' => 'passive' } }],
    ].each do |label, env|
      it "is false for #{label}" do
        expect(described_class.passive?(env)).to be(false)
      end
    end

    # The predicate depends on how Otto parses a routes-file token, which is
    # the gem's behaviour and not ours. Pin it against the real parser so an
    # Otto upgrade that changes the key type or the env key fails here, loudly,
    # instead of silently turning every poll back into activity.
    it 'reads the shape Otto really produces for the routes-file token' do
      definition = Otto::RouteDefinition.new('GET', '/bootstrap/me', 'Core::Controllers::Page#bootstrap_me auth=noauth activity=passive')

      expect(described_class.passive?(Otto::EnvKeys::ROUTE_OPTIONS => definition.options)).to be(true)
    end

    it 'agrees with Otto on the env key' do
      expect(described_class::ROUTE_OPTIONS_ENV_KEY).to eq(Otto::EnvKeys::ROUTE_OPTIONS)
    end

    it 'finds the declaration on GET /bootstrap/me, and on no other Web Core route' do
      routes  = File.readlines(File.join(Onetime::HOME, 'apps/web/core/routes.txt'), chomp: true)
      passive = routes.grep(/\bactivity=passive\b/).reject { |line| line.start_with?('#') }

      expect(passive.size).to eq(1)
      expect(passive.first).to match(%r{\AGET\s+/bootstrap/me\s})
    end
  end

  describe '.refused? and .counts?' do
    let(:evaluator) { Onetime::CustomerSessionEvaluator }
    let(:verdict_key) { evaluator::ENV_KEY }
    let(:admin_key) { Onetime::Application::AuthStrategies::AdminSessionLifetime::EXPIRED_ENV_KEY }

    def verdict(status, reason)
      evaluator::Verdict.new(status: status, reason: reason)
    end

    # Every non-success reason the evaluator can produce, with the status it is
    # raised under and whether it is a refusal. `fetch` has no default: a
    # reason added later fails here until someone decides which it is, instead
    # of silently counting as activity.
    classification = {
      session_missing: [:anonymous, false],
      not_authenticated: [:anonymous, false],
      awaiting_mfa: [:mfa_pending, false],
      identity_missing: [:rejected, true],
      surface_mismatch: [:rejected, true],
      customer_not_found: [:rejected, true],
      account_suspended: [:rejected, true],
      stale_credentials: [:rejected, true],
      admin_session_expired: [:rejected, true],
      active_session_revoked: [:rejected, true],
      active_session_unavailable: [:unavailable, true],
      customer_unavailable: [:unavailable, true],
    }.freeze

    (Onetime::CustomerSessionEvaluator::REASONS - [:authenticated]).each do |reason|
      it "classifies the #{reason} verdict" do
        status, refused = classification.fetch(reason)
        env             = { verdict_key => verdict(status, reason) }

        expect(described_class.refused?(env)).to be(refused)
        expect(described_class.counts?(env)).to be(!refused)
      end
    end

    it 'counts an authenticated verdict on an ordinary route' do
      customer = instance_double(Onetime::Customer)
      env      = {
        verdict_key => evaluator::Verdict.new(status: :authenticated, reason: :authenticated, principal: customer, customer: customer),
        'otto.route_options' => { auth: 'sessionauth' },
      }

      expect(described_class.counts?(env)).to be(true)
    end

    it 'does not count an authenticated verdict on a passive route' do
      customer = instance_double(Onetime::Customer)
      env      = {
        verdict_key => evaluator::Verdict.new(status: :authenticated, reason: :authenticated, principal: customer, customer: customer),
        'otto.route_options' => { activity: 'passive' },
      }

      expect(described_class.refused?(env)).to be(false)
      expect(described_class.counts?(env)).to be(false)
    end

    it 'treats the admin-surface bounds flag (#4331) as a refusal' do
      expect(described_class.refused?(admin_key => 'idle')).to be(true)
      expect(described_class.counts?(admin_key => 'idle')).to be(false)
    end

    it 'counts a request nobody evaluated, and one with no env' do
      expect(described_class.counts?({})).to be(true)
      expect(described_class.counts?(nil)).to be(true)
    end

    it 'ignores a verdict entry that is not a verdict' do
      expect(described_class.refused?(verdict_key => 'rejected')).to be(false)
    end
  end
end

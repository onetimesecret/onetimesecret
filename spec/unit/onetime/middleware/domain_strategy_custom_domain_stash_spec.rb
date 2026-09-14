# spec/unit/onetime/middleware/domain_strategy_custom_domain_stash_spec.rb
#
# frozen_string_literal: true

# Pins the env stashing DomainStrategy performs for :custom classifications
# (#4409): the resolved CustomDomain instance and its stable identifier land
# in env['onetime.custom_domain'] and env['onetime.custom_domain_id'] so
# downstream consumers (surface-bound sessions, tenant SSO hooks) never
# repeat the display_domain lookup and always agree on the tenant id.

require 'spec_helper'
require 'onetime/middleware/domain_strategy'

RSpec.describe Onetime::Middleware::DomainStrategy do
  describe 'env stash for :custom classifications' do
    let(:downstream) { ->(env) { [200, { 'content-type' => 'text/plain' }, ['ok']] } }
    let(:middleware) { described_class.new(downstream) }
    let(:custom_domain) { instance_double(Onetime::CustomDomain, identifier: 'domain-abc-123') }

    before do
      # Feature-flag the domains subsystem on; the class-level state is loaded
      # once from OT.conf during boot, so this stubs the instance-side readers
      # that call through to it. Reading through the middleware instance keeps
      # `#call` on its normal code path.
      allow(middleware).to receive_messages(
        domains_enabled?: true,
        canonical_domain: 'example.com',
        canonical_domains_parsed: [PublicSuffix.parse('example.com')],
        anchor_domains_parsed: [PublicSuffix.parse('example.com')],
      )
    end

    it 'stashes the CustomDomain instance and identifier when strategy resolves :custom' do
      allow(described_class::Chooserator).to receive_messages(
        choose_strategy: :custom,
        custom_domain_for: custom_domain,
      )

      env = {
        Rack::DetectHost.result_field_name => 'secrets.acme.com',
      }
      middleware.call(env)

      expect(env['onetime.domain_strategy']).to eq(:custom)
      expect(env['onetime.custom_domain']).to be(custom_domain)
      expect(env['onetime.custom_domain_id']).to eq('domain-abc-123')
    end

    it 'stashes a nil identifier when :custom classification cannot resolve the domain (blip)' do
      # choose_strategy returned :custom (its own known_custom_domain? saw the
      # row) but the follow-up load lost the race — a genuine possibility, and
      # exactly the case surface enforcement must refuse rather than crash.
      allow(described_class::Chooserator).to receive_messages(
        choose_strategy: :custom,
        custom_domain_for: nil,
      )

      env = { Rack::DetectHost.result_field_name => 'secrets.acme.com' }
      middleware.call(env)

      expect(env['onetime.domain_strategy']).to eq(:custom)
      expect(env['onetime.custom_domain']).to be_nil
      expect(env['onetime.custom_domain_id']).to be_nil
    end

    it 'does not stash a CustomDomain for non-:custom classifications' do
      allow(described_class::Chooserator).to receive(:choose_strategy).and_return(:canonical)

      env = { Rack::DetectHost.result_field_name => 'example.com' }
      middleware.call(env)

      expect(env['onetime.domain_strategy']).to eq(:canonical)
      expect(env).not_to have_key('onetime.custom_domain')
      expect(env).not_to have_key('onetime.custom_domain_id')
    end
  end

  describe described_class::Chooserator, '.custom_domain_for' do
    it 'delegates to CustomDomain.from_display_domain' do
      instance = instance_double(Onetime::CustomDomain, identifier: 'x')
      allow(Onetime::CustomDomain).to receive(:from_display_domain).with('t.example.com').and_return(instance)

      expect(described_class.custom_domain_for('t.example.com')).to be(instance)
    end

    it 'returns nil for an unknown host' do
      allow(Onetime::CustomDomain).to receive(:from_display_domain).and_return(nil)

      expect(described_class.custom_domain_for('nope.example')).to be_nil
    end
  end
end

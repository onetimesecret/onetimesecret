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
end

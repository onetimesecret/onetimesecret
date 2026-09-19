# spec/unit/onetime/helpers/session_helpers_surface_spec.rb
#
# frozen_string_literal: true

# The controller-side half of surface-bound sessions (#4409): once a session
# is stamped with the surface where its login was completed, every subsequent
# authenticated? call refuses when the request's resolved surface differs.
# Terms and the descriptor shape are defined in Onetime::SessionSurface.
#
# The classifier's own decision table is
# spec/unit/onetime/session/surface_spec.rb; what is pinned here is the
# authenticated? wiring — the four cross-surface cases the epic (#4408)
# names, plus missing marker.

require 'spec_helper'
require 'onetime/helpers/session_helpers'

RSpec.describe Onetime::Helpers::SessionHelpers do
  subject(:helper) { helper_class.new(session, instance_double(Rack::Request, env: env)) }

  let(:helper_class) do
    Class.new do
      include Onetime::Helpers::SessionHelpers

      attr_reader :session, :request

      def initialize(session, request = nil)
        @session = session
        @request = request
      end
    end
  end

  let(:customer) do
    instance_double(
      Onetime::Customer,
      suspended?: false,
      last_password_update: 0,
    )
  end

  # Customer and active-session checks are not what these surface tests exercise;
  # keep them green so a mismatch is the only refusal reason.
  before do
    allow(OT).to receive(:conf).and_return({ 'site' => { 'authentication' => { 'enabled' => true } } })
    allow(OT).to receive(:info)
    allow(Onetime::Customer).to receive(:find_by_extid).with('ur_abc').and_return(customer)
    allow(Onetime::ActiveSessionGate).to receive(:verdict).and_return(:active)
    allow(Onetime::SessionImpersonation).to receive(:resolve).and_return([customer, nil])
  end

  def session_on(descriptor)
    {
      'authenticated'               => true,
      'external_id'                 => 'ur_abc',
      Onetime::SessionSurface::KEY  => descriptor,
    }
  end

  def env_on(strategy:, host: nil, custom_id: nil)
    {
      'onetime.domain_strategy'   => strategy,
      'onetime.display_domain'    => host,
      'onetime.custom_domain_id'  => custom_id,
    }
  end

  context 'matching surfaces' do
    let(:session) { session_on({ 'kind' => 'canonical' }) }
    let(:env)     { env_on(strategy: :canonical) }

    it 'authenticates a canonical session on canonical' do
      expect(helper.authenticated?).to be(true)
    end
  end

  context 'without a request accessor' do
    subject(:helper) do
      Class.new do
        include Onetime::Helpers::SessionHelpers

        attr_reader :session

        def initialize(session)
          @session = session
        end
      end.new(session)
    end

    let(:session) { session_on({ 'kind' => 'canonical' }) }

    it 'refuses authentication instead of raising' do
      expect(helper.authenticated?).to be(false)
    end
  end

  context 'platform session on tenant surface' do
    let(:session) { session_on({ 'kind' => 'canonical' }) }
    let(:env)     { env_on(strategy: :custom, host: 'secrets.acme.com', custom_id: 'tenant-a') }

    it 'refuses' do
      expect(helper.authenticated?).to be(false)
    end
  end

  context 'tenant session on platform surface' do
    let(:session) { session_on({ 'kind' => 'custom', 'id' => 'tenant-a' }) }
    let(:env)     { env_on(strategy: :canonical) }

    it 'refuses' do
      expect(helper.authenticated?).to be(false)
    end
  end

  context 'tenant A session on tenant B surface' do
    let(:session) { session_on({ 'kind' => 'custom', 'id' => 'tenant-a' }) }
    let(:env)     { env_on(strategy: :custom, host: 'secrets.b.example', custom_id: 'tenant-b') }

    it 'refuses' do
      expect(helper.authenticated?).to be(false)
    end
  end

  context 'canonical session on canonical subdomain' do
    let(:session) { session_on({ 'kind' => 'canonical' }) }
    let(:env)     { env_on(strategy: :subdomain, host: 'eu.example.com') }

    it 'refuses (subdomain is a distinct surface class from canonical)' do
      expect(helper.authenticated?).to be(false)
    end
  end

  context 'legacy session with no marker' do
    let(:session) do
      { 'authenticated' => true, 'external_id' => 'ur_abc' }
    end
    let(:env) { env_on(strategy: :canonical) }

    it 'refuses (missing marker fails closed; user re-authenticates)' do
      expect(helper.authenticated?).to be(false)
    end
  end

  context 'stale custom domain (id no longer resolves in env)' do
    let(:session) { session_on({ 'kind' => 'custom', 'id' => 'tenant-a' }) }
    let(:env)     { env_on(strategy: :custom, host: 'secrets.acme.com', custom_id: nil) }

    it 'refuses' do
      expect(helper.authenticated?).to be(false)
    end
  end
end

# spec/unit/helpers/session_helpers_role_spec.rb
#
# frozen_string_literal: true

# Pins the principal-role invariant on has_role?/colonel? through an
# impersonation overlay. The evaluator's Verdict is constructed directly:
# the spec's job is to lock the *semantics* of the helper, not to reproduce
# a full impersonation setup — role gates answer about the acting principal,
# never about the impersonation target. current_customer, in contrast, is
# still the effective customer (the target mid-overlay).

require 'spec_helper'
require 'onetime/helpers/session_helpers'
require 'onetime/session/customer_session_evaluator'

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

  let(:principal) { instance_double(Onetime::Customer, 'principal (colonel)') }
  let(:target)    { instance_double(Onetime::Customer, 'target (customer)') }
  let(:session)   { { 'external_id' => 'ur_colonel', 'authenticated' => true } }
  let(:env)       { { 'onetime.domain_strategy' => :canonical } }

  let(:verdict) do
    Onetime::CustomerSessionEvaluator::Verdict.new(
      status:        :authenticated,
      reason:        :authenticated,
      principal:     principal,
      customer:      target,
      impersonation: { 'id' => 'imp_1' },
    )
  end

  before do
    allow(OT).to receive(:conf).and_return({ 'site' => { 'authentication' => { 'enabled' => true } } })
    allow(OT).to receive(:ld)

    # Principal is a colonel; target is a plain customer. `has_role?` MUST
    # answer about the principal so a colonel operator stays admin-capable
    # mid-overlay.
    allow(principal).to receive(:role?).with(:colonel).and_return(true)
    allow(principal).to receive(:role?).with(:customer).and_return(false)
    allow(target).to receive(:role?).with(:colonel).and_return(false)
    allow(target).to receive(:role?).with(:customer).and_return(true)

    allow(Onetime::CustomerSessionEvaluator).to receive(:evaluate).and_return(verdict)
  end

  it 'answers has_role?(:colonel) about the principal during an impersonation overlay' do
    expect(helper.has_role?(:colonel)).to be(true)
  end

  it 'does NOT report the impersonation target role from has_role?' do
    expect(helper.has_role?(:customer)).to be(false)
  end

  it 'answers colonel? about the principal' do
    expect(helper.colonel?).to be(true)
  end

  it 'still exposes the impersonation target as current_customer' do
    # Avoid load_current_customer's session-mutation branch, which is not what
    # this test is pinning.
    allow(helper).to receive(:load_current_customer).and_return(target)
    expect(helper.current_customer).to be(target)
  end

  context 'when no principal is available (unauthenticated verdict)' do
    let(:verdict) do
      Onetime::CustomerSessionEvaluator::Verdict.new(
        status: :anonymous,
        reason: :not_authenticated,
      )
    end

    it 'returns false rather than raising on missing principal' do
      expect(helper.has_role?(:colonel)).to be(false)
    end
  end

  context 'when authentication is not configured' do
    before { allow(OT).to receive(:conf).and_return({}) }

    it 'refuses role checks without touching the evaluator' do
      expect(Onetime::CustomerSessionEvaluator).not_to receive(:evaluate)
      expect(helper.has_role?(:colonel)).to be(false)
    end
  end
end

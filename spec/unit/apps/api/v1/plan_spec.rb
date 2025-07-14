# tests/unit/ruby/rspec/apps/api/v1/plan_spec.rb

require_relative '../../../../spec_helper'

require 'v1/plan'

RSpec.describe V1::Plan, type: :model do
  describe '.plans' do
    let(:mocked_plans) { double('Plans') }

    before do
      allow(V1::Plan).to receive(:plans).and_return(mocked_plans)
    end

    it 'returns the mocked plans' do
      expect(V1::Plan.plans).to eq(mocked_plans)
    end
  end

  describe '.plan' do
    let(:plan_mock) { double('Plan') }
    let(:not_authenticated_json) do
      {
        'plan' => 'not_authenticated_plan',
        'is_paid' => false
      }
    end
    let(:authenticated_json) do
      {
        'plan' => 'authenticated_plan',
        'is_paid' => true
      }
    end

    context 'for not authenticated user' do
      before do
        allow(plan_mock).to receive(:safe_dump).and_return(not_authenticated_json['plan'])
        allow(plan_mock).to receive(:paid?).and_return(not_authenticated_json['is_paid'])
        allow(V1::Plan).to receive(:plan).and_return(plan_mock)
      end

      it 'returns the not authenticated plan details' do
        expect(V1::Plan.plan.safe_dump).to eq(not_authenticated_json['plan'])
        expect(V1::Plan.plan.paid?).to eq(not_authenticated_json['is_paid'])
      end
    end

    context 'for authenticated user' do
      before do
        allow(plan_mock).to receive(:safe_dump).and_return(authenticated_json['plan'])
        allow(plan_mock).to receive(:paid?).and_return(authenticated_json['is_paid'])
        allow(V1::Plan).to receive(:plan).and_return(plan_mock)
      end

      it 'returns the authenticated plan details' do
        expect(V1::Plan.plan.safe_dump).to eq(authenticated_json['plan'])
        expect(V1::Plan.plan.paid?).to eq(authenticated_json['is_paid'])
      end
    end
  end
end

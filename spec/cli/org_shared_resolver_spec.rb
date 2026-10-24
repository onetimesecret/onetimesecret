# spec/cli/org_shared_resolver_spec.rb
#
# frozen_string_literal: true

# Org::Shared#resolve_org on the Stripe-id branches (cus_ / sub_).
#
# Organization.find_by_stripe_customer_id / find_by_stripe_subscription_id are
# Familia-generated: they HGET the unique index and load whatever org it names
# without reading the field back. A stale entry (doctor check 6) would point
# `organizations delete cus_X --yes` at an org that no longer holds cus_X. The
# resolver must refuse such an entry the way the hostname branch refuses a
# record stored under a different name.
#
# Run: tests/lanes/run unit --only spec/cli/org_shared_resolver_spec.rb

require_relative 'cli_spec_helper'
require 'onetime/cli/org/shared'

RSpec.describe 'Org::Shared#resolve_org Stripe-id branches', type: :cli do
  let(:resolver) do
    Class.new do
      include Onetime::CLI::Org::Shared
    end.new
  end

  def org_double(stripe_customer_id:, stripe_subscription_id:)
    double(
      'Organization',
      extid: 'on_named_by_index',
      display_name: 'Named By Index',
      stripe_customer_id: stripe_customer_id,
      stripe_subscription_id: stripe_subscription_id,
    )
  end

  def resolve(identifier, json: false)
    result = nil
    output = capture_output do
      result = resolver.resolve_org(identifier, json: json)
    rescue SystemExit => ex
      @last_exit_code = ex.status
    end
    [result, output]
  end

  before do
    allow(Onetime::Organization).to receive_messages(
      find_by_stripe_customer_id: nil,
      find_by_stripe_subscription_id: nil,
    )
  end

  context 'cus_ (Stripe customer id)' do
    it 'resolves the org the index names when it still holds the id' do
      org = org_double(stripe_customer_id: 'cus_HELD', stripe_subscription_id: nil)
      allow(Onetime::Organization).to receive(:find_by_stripe_customer_id).with('cus_HELD').and_return(org)

      result, = resolve('cus_HELD')

      expect(result).to be(org)
      expect(@last_exit_code).to be_nil
    end

    it 'refuses a stale index entry naming an org that now holds a different id' do
      stale = org_double(stripe_customer_id: 'cus_OTHER', stripe_subscription_id: nil)
      allow(Onetime::Organization).to receive(:find_by_stripe_customer_id).with('cus_STALE').and_return(stale)

      result, output = resolve('cus_STALE')

      expect(result).to be_nil
      expect(@last_exit_code).to eq(1)
      expect(output[:stdout]).to include('Error: Organization not found: cus_STALE')
    end

    it 'refuses an entry naming an org whose stripe_customer_id is now blank' do
      cleared = org_double(stripe_customer_id: nil, stripe_subscription_id: nil)
      allow(Onetime::Organization).to receive(:find_by_stripe_customer_id).with('cus_CLEARED').and_return(cleared)

      _, output = resolve('cus_CLEARED', json: true)

      expect(@last_exit_code).to eq(1)
      expect(JSON.parse(output[:stdout])).to eq('error' => 'Organization not found: cus_CLEARED')
    end
  end

  context 'sub_ (Stripe subscription id)' do
    it 'resolves the org the index names when it still holds the id' do
      org = org_double(stripe_customer_id: nil, stripe_subscription_id: 'sub_HELD')
      allow(Onetime::Organization).to receive(:find_by_stripe_subscription_id).with('sub_HELD').and_return(org)

      result, = resolve('sub_HELD')

      expect(result).to be(org)
      expect(@last_exit_code).to be_nil
    end

    it 'refuses a stale index entry naming an org that now holds a different id' do
      stale = org_double(stripe_customer_id: nil, stripe_subscription_id: 'sub_OTHER')
      allow(Onetime::Organization).to receive(:find_by_stripe_subscription_id).with('sub_STALE').and_return(stale)

      result, output = resolve('sub_STALE')

      expect(result).to be_nil
      expect(@last_exit_code).to eq(1)
      expect(output[:stdout]).to include('Error: Organization not found: sub_STALE')
    end
  end

  # Through a destructive verb: the stale entry must stop `delete` before it
  # reaches the org the index names.
  it 'stops `organizations delete cus_X --yes` on a stale index entry' do
    require 'onetime/cli/org/delete_command'
    stale = org_double(stripe_customer_id: 'cus_OTHER', stripe_subscription_id: nil)
    allow(Onetime::Organization).to receive(:find_by_stripe_customer_id).with('cus_STALE').and_return(stale)

    output = run_cli_command_quietly('organizations', 'delete', 'cus_STALE', '--yes')

    expect(last_exit_code).to eq(1)
    expect(output[:stdout]).to include('Organization not found: cus_STALE')
  end
end

# frozen_string_literal: true

require 'spec_helper'
require 'onetime/logic/base'

RSpec.describe Onetime::Logic::Base, 'target organization authorization' do
  let(:logic) { described_class.allocate }
  let(:org) { instance_double(Onetime::Organization, planid: 'free_v1') }
  let(:member) { instance_double(Onetime::OrganizationMembership, active?: true) }

  before do
    allow(logic).to receive(:anonymous_user?).and_return(false)
    allow(logic).to receive(:has_system_role?).with('colonel').and_return(false)
    allow(logic).to receive(:membership_in).with(org).and_return(member)
    allow(member).to receive(:has_capability?).with(:manage_domains).and_return(true)
    allow(org).to receive(:has_feature?).with(:custom_domains).and_return(true)
  end

  def require_both(org)
    logic.send(:require_feature_and_capability_in!, org, feature: :custom_domains, capability: :manage_domains)
  end

  it 'requires an active member with the capability and an organization with the feature' do
    expect(require_both(org)).to be(true)
    allow(org).to receive(:has_feature?).with(:custom_domains).and_return(false)
    expect { require_both(org) }.to raise_error(Onetime::EntitlementRequired) do |error|
      expect(error.to_h).to include(entitlement: 'custom_domains', current_plan: 'free_v1')
    end
  end

  it 'denies a missing capability before reading billing information' do
    allow(member).to receive(:has_capability?).and_return(false)
    expect { require_both(org) }.to raise_error(Onetime::CapabilityRequired) do |error|
      expect(error.to_h).to include(capability: 'manage_domains')
      expect(error.to_h.keys & %i[current_plan upgrade_to entitlement]).to be_empty
    end
    expect(org).not_to have_received(:has_feature?)
  end

  it 'requires an organization even for site operators' do
    allow(logic).to receive(:has_system_role?).with('colonel').and_return(true)
    expect { require_both(nil) }.to raise_error(Onetime::Problem, 'Organization context unavailable')
  end

  it 'checks the target plan for a site operator without a membership' do
    allow(logic).to receive(:has_system_role?).with('colonel').and_return(true)
    allow(org).to receive(:has_feature?).and_return(false)
    expect { require_both(org) }.to raise_error(Onetime::EntitlementRequired)
    expect(logic).not_to have_received(:membership_in)
  end

  it 'denies anonymous callers and inactive or absent memberships before checking the feature' do
    allow(logic).to receive(:anonymous_user?).and_return(true)
    expect { require_both(org) }.to raise_error(Onetime::Forbidden, 'Authentication required')
    allow(logic).to receive(:anonymous_user?).and_return(false)
    allow(member).to receive(:active?).and_return(false)
    expect { require_both(org) }.to raise_error(Onetime::Forbidden, /member of this organization/)
    allow(logic).to receive(:membership_in).with(org).and_return(nil)
    expect { logic.send(:require_feature_in!, org, :custom_domains) }.to raise_error(Onetime::Forbidden)
    expect(org).not_to have_received(:has_feature?)
  end

  it 'rejects a capability in the feature slot or a feature in the capability slot' do
    expect { logic.send(:require_feature_in!, org, :manage_domains) }.to raise_error(ArgumentError)
    expect { logic.send(:require_capability_in!, org, :custom_domains) }.to raise_error(ArgumentError)
  end
end

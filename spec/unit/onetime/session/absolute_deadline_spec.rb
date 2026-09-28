# spec/unit/onetime/session/absolute_deadline_spec.rb
#
# frozen_string_literal: true

# Onetime::Session.absolute_deadline: the one definition of when a session
# ends whatever it does, shared by the store's read and write paths and by
# IdentityResolution's `expires_at`. The store's use of it is exercised end
# to end in spec/integration/{simple,full}/remember_me_spec.rb.

require 'spec_helper'
require 'onetime/session'

RSpec.describe Onetime::Session, '.absolute_deadline' do
  let(:signed_in) { 1_800_000_000 }
  let(:lifetime) { Onetime::ActiveSessionGate::DEFAULT_LIFETIME_DEADLINE }

  before do
    allow(Onetime).to receive(:session_config).and_wrap_original do |original|
      original.call.merge('absolute_timeout' => lifetime)
    end
  end

  it 'is the lifetime deadline after authenticated_at for a default session' do
    expect(described_class.absolute_deadline('authenticated_at' => signed_in)).to eq(signed_in + lifetime)
  end

  it 'is the remember deadline when that is nearer' do
    stamp = signed_in + Onetime::RememberMe::DURATION
    data  = { 'authenticated_at' => signed_in, 'remember_until' => stamp }
    expect(described_class.absolute_deadline(data)).to eq(stamp)
  end

  it 'is the lifetime deadline when a remember stamp lies beyond it' do
    data = { 'authenticated_at' => signed_in, 'remember_until' => signed_in + lifetime + 1 }
    expect(described_class.absolute_deadline(data)).to eq(signed_in + lifetime)
  end

  it 'is nil for a session with no deadline', :aggregate_failures do
    expect(described_class.absolute_deadline({})).to be_nil
    expect(described_class.absolute_deadline(nil)).to be_nil
  end

  it 'ignores values that are not integer epochs' do
    data = { 'authenticated_at' => signed_in.to_s, 'remember_until' => (signed_in + 60).to_s }
    expect(described_class.absolute_deadline(data)).to be_nil
  end

  it 'is the remember stamp alone once the lifetime bound is switched off', :aggregate_failures do
    allow(Onetime).to receive(:session_config).and_wrap_original do |original|
      original.call.merge('absolute_timeout' => 0)
    end
    data = { 'authenticated_at' => signed_in, 'remember_until' => signed_in + 60 }
    expect(described_class.absolute_deadline(data)).to eq(signed_in + 60)
    expect(described_class.absolute_deadline('authenticated_at' => signed_in)).to be_nil
  end
end

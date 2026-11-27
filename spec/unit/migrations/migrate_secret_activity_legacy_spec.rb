# frozen_string_literal: true

require 'spec_helper'
require_relative '../../../migrations/2026-11-27/20261127_01_migrate_secret_activity_legacy'

RSpec.describe Onetime::Migrations::MigrateSecretActivityLegacy, type: :integration do
  before(:all) { Onetime.boot! :test }

  let(:org) do
    Onetime::Organization.new(display_name: 'Legacy trail org',
      contact_email: "legacy-#{SecureRandom.hex(6)}@example.com").tap(&:save)
  end
  let(:base) { Familia.now.to_f - 100 }

  before do
    3.times do |i|
      org.secret_activity_events.add({ 'kind' => 'revealed', 'at' => base + i, 'nonce' => "n#{i}" }, base + i)
    end
  end

  after { org.destroy! if org.exists? }

  it 'previews without changing anything' do
    described_class.run(run: false)

    expect(org.secret_activity_events.element_count).to eq(3)
    expect(org.secret_activity_member.element_count).to eq(0)
  end

  it 'moves the legacy rows into the member partition, and a rerun changes nothing' do
    described_class.run(run: true)

    expect(org.secret_activity_events.exists?).to be(false)
    expect(org.secret_activity_member.element_count).to eq(3)
    expect(org.secret_activity_events_page.map { |e| e['nonce'] }).to eq(%w[n2 n1 n0])

    expect(described_class.run(run: true)).to be_nil.or(be(true))
    expect(org.secret_activity_member.element_count).to eq(3)
  end
end

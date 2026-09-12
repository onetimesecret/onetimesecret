# apps/api/colonel/spec/logic/colonel/get_elevation_status_spec.rb
#
# frozen_string_literal: true

require_relative File.join(Onetime::HOME, 'spec', 'spec_helper')
require 'colonel/logic'

# GET /api/colonel/elevation — the status read the console fetches on mount,
# after every elevate/drop, and on a 403 elevation_required (#4327).
#
# Two properties matter beyond the obvious shape:
#
#   - it is a READ, so it audits NOTHING (CONTRACT 4). The console calls it
#     often enough that auditing here would be a self-inflicted flood of the
#     count-capped operator trail;
#   - `details.factors` and `details.password_available` are per-ACCOUNT, which
#     is what lets the console render an actionable remediation for an SSO-only
#     operator instead of looping on a prompt they cannot satisfy.
RSpec.describe ColonelAPI::Logic::Colonel::GetElevationStatus do
  let(:colonel) do
    instance_double(Onetime::Customer,
      objid: 'cust_colonel', extid: 'ur_colonel', email: 'colonel@example.com',
      role: 'colonel', verified?: true, anonymous?: false, has_passphrase?: true)
  end

  let(:customer) do
    instance_double(Onetime::Customer,
      objid: 'cust_plain', extid: 'ur_plain', email: 'plain@example.com',
      role: 'customer', verified?: true, anonymous?: false, has_passphrase?: true)
  end

  def logic_for(user = colonel, session = {})
    described_class.new(
      double('StrategyResult', session: session, user: user,
        auth_method: 'sessionauth', metadata: {}),
      {},
    )
  end

  def status_for(user = colonel, session = {})
    logic = logic_for(user, session)
    logic.raise_concerns
    logic.process
  end

  before do
    allow(OT).to receive(:info)
    allow(OT).to receive(:ld)
    allow(OT).to receive(:li)
    allow(OT).to receive(:le)
    allow(Onetime::ColonelAuditEvent).to receive(:record)
    allow(Onetime::ColonelAuditEvent).to receive(:record_security)
    allow(Onetime.auth_config).to receive(:full_enabled?).and_return(false)
    stub_colonel_elevation(enabled: true, window: 600)
  end

  it 'refuses a non-colonel' do
    expect { logic_for(customer).raise_concerns }.to raise_error(Onetime::Forbidden)
  end

  it 'audits nothing — it is a read' do
    status_for

    expect(Onetime::ColonelAuditEvent).not_to have_received(:record)
    expect(Onetime::ColonelAuditEvent).not_to have_received(:record_security)
  end

  describe 'not elevated' do
    it 'reports elevated false with a null expiry and no time remaining' do
      data = status_for

      expect(data[:record]).to eq(elevated: false, expires_at: nil, seconds_remaining: 0)
    end

    it 'still reports the configured window so the console can name it' do
      expect(status_for[:details][:window]).to eq(600)
    end
  end

  describe 'elevated' do
    it 'reports the expiry and a positive countdown seed' do
      data = status_for(colonel, elevated_session('ur_colonel', expires_in: 420))

      expect(data[:record][:elevated]).to be true
      expect(data[:record][:expires_at]).to be_within(5).of(Familia.now.to_i + 420)
      expect(data[:record][:seconds_remaining]).to be_within(5).of(420)
    end

    it 'reports NOT elevated when the window belongs to another identity' do
      data = status_for(colonel, elevated_session('ur_someone_else'))

      expect(data[:record][:elevated]).to be false
      expect(data[:record][:expires_at]).to be_nil
    end
  end

  describe 'disabled by config' do
    before { stub_colonel_elevation(enabled: false) }

    it 'says so, so the console can hide the banner and the prompt' do
      expect(status_for[:details][:enabled]).to be false
    end
  end

  describe 'per-account factors' do
    it 'offers password only for an account that has one' do
      data = status_for

      expect(data[:details][:password_available]).to be true
      expect(data[:details][:factors]).to eq(['password'])
      expect(data[:details][:grace_available]).to be false
    end

    it 'offers recent_auth to a password-less account once a grace is configured' do
      stub_colonel_elevation(enabled: true, reauth_grace: 300)
      allow(colonel).to receive(:has_passphrase?).and_return(false)

      data = status_for(colonel, { 'authenticated_at' => Familia.now.to_i - 30 })

      expect(data[:details][:password_available]).to be false
      expect(data[:details][:factors]).to contain_exactly('password', 'recent_auth')
      expect(data[:details][:grace_available]).to be true
      expect(data[:details][:reauth_grace]).to eq(300)
    end

    it 'withholds recent_auth from a password-less account when no grace is configured' do
      allow(colonel).to receive(:has_passphrase?).and_return(false)

      data = status_for(colonel, { 'authenticated_at' => Familia.now.to_i - 30 })

      expect(data[:details][:factors]).to eq(['password'])
      expect(data[:details][:grace_available]).to be false
      expect(data[:details][:reauth_grace]).to eq(0)
    end
  end
end

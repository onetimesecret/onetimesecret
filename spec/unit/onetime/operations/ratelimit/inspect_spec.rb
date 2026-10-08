# spec/unit/onetime/operations/ratelimit/inspect_spec.rb
#
# frozen_string_literal: true

# The per-IP SCAN in RateLimit::Inspect walks the whole logical database (MATCH
# only filters what comes back), and every model shares db 0 by default. The
# colonel account diagnostics request ran this walk unbounded and timed out on a
# large keyspace. These examples pin the COUNT hint and the optional deadline.

require 'spec_helper'
require 'onetime/operations/ratelimit/inspect'

RSpec.describe Onetime::Operations::RateLimit::Inspect do
  let(:email) { 'person@example.com' }
  let(:db) { double('dbclient', ttl: -2, get: nil) }

  before do
    allow(Onetime::Operations::RateLimit::Registry).to receive(:dbclient_for).with('login').and_return(db)
  end

  def call(**)
    described_class.new(kind: 'login', subject: email, **).call
  end

  it 'walks every pattern to the end when no deadline is given' do
    allow(db).to receive(:scan) do |cursor, match:, count:|
      expect(count).to eq(Onetime::Operations::RateLimit::Registry::SCAN_COUNT)
      cursor == '0' ? ['7', []] : ['0', [match.sub('*', '203.0.113.9')]]
    end

    result = call

    expect(result.scan_complete).to be(true)
    expect(db).to have_received(:scan).exactly(4).times
    expect(result.entries.map(&:key)).to include(
      "login:attempts:#{email}:203.0.113.9",
      "login:locked:#{email}:203.0.113.9",
    )
  end

  it 'stops at the deadline and reports the walk as incomplete' do
    # A cursor that never returns to '0' stands in for a keyspace too large to
    # walk inside the budget.
    allow(db).to receive(:scan).and_return(['42', []])

    result = call(scan_deadline: 0)

    expect(result.scan_complete).to be(false)
    # One SCAN per pattern: the deadline is checked after each call.
    expect(db).to have_received(:scan).twice
    # The exact keys are still read in full.
    expect(result.entries.map(&:key)).to eq(["login:attempts:#{email}", "login:locked:#{email}"])
  end

  it 'reports a complete walk that finishes inside the deadline' do
    allow(db).to receive(:scan).and_return(['0', []])

    expect(call(scan_deadline: 5).scan_complete).to be(true)
  end

  it 'defaults scan_complete to true for callers that build a Result directly' do
    result = described_class::Result.new(kind: 'login', subject: email, entries: [])

    expect(result.scan_complete).to be(true)
  end
end

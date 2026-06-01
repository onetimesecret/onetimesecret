# apps/web/billing/spec/lib/materialize_progress_renderer_spec.rb
#
# frozen_string_literal: true

# Unit tests for Billing::MaterializeProgressRenderer
#
# Tests cover verbosity modes, indent control, and event formatting.
#
# Run: pnpm run test:rspec apps/web/billing/spec/lib/materialize_progress_renderer_spec.rb

require_relative '../support/billing_spec_helper'
require_relative '../../lib/materialize_progress_renderer'
require_relative '../../operations/materialize_plans'

RSpec.describe Billing::MaterializeProgressRenderer, type: :billing do
  def capture_stdout
    old_stdout = $stdout
    $stdout = StringIO.new
    yield
    $stdout.string
  ensure
    $stdout = old_stdout
  end

  def make_event(event:, org_extid: 'org_1', planid: 'plan_v1', entitlements_count: 5, cascade: nil, reason: nil)
    Billing::Operations::MaterializePlansEvent.new(
      event: event,
      org_extid: org_extid,
      planid: planid,
      entitlements_count: entitlements_count,
      cascade: cascade,
      reason: reason,
    )
  end

  describe 'indent control' do
    it 'uses 2-space indent by default' do
      renderer = described_class.new(total: 1)
      output = capture_stdout { renderer.render(make_event(event: :materialized)) }

      expect(output).to start_with('  [')
    end

    it 'uses custom indent when specified' do
      renderer = described_class.new(total: 1, indent: 4)
      output = capture_stdout { renderer.render(make_event(event: :materialized)) }

      expect(output).to start_with('    [')
    end
  end

  describe 'progress counter' do
    it 'increments counter across calls' do
      renderer = described_class.new(total: 3)

      lines = capture_stdout do
        3.times { renderer.render(make_event(event: :materialized)) }
      end.lines

      expect(lines[0]).to include('[1/3]')
      expect(lines[1]).to include('[2/3]')
      expect(lines[2]).to include('[3/3]')
    end
  end

  describe 'verbosity modes' do
    it ':default renders per-org lines without membership detail' do
      event = make_event(
        event: :materialized,
        cascade: { success: 1, failed: 0, total: 1, details: [
          { objid: 'mem_1', role: 'owner', planid: 'p1', entitlements_count: 3, status: :ok, error: nil },
        ] },
      )
      renderer = described_class.new(total: 1, verbosity: :default)

      output = capture_stdout { renderer.render(event) }

      expect(output).to include('Materialized: org_1')
      expect(output).not_to include('mem_1')
    end

    it ':verbose adds per-membership detail lines' do
      event = make_event(
        event: :materialized,
        cascade: { success: 1, failed: 0, total: 1, details: [
          { objid: 'mem_1', role: 'owner', planid: 'p1', entitlements_count: 3, status: :ok, error: nil },
        ] },
      )
      renderer = described_class.new(total: 1, verbosity: :verbose, include_memberships: true)

      output = capture_stdout { renderer.render(event) }

      expect(output).to include('Materialized: org_1')
      expect(output).to include('mem_1')
      expect(output).to include('role=owner')
      expect(output).to include('3 entitlements')
    end

    it ':quiet suppresses all output' do
      renderer = described_class.new(total: 1, verbosity: :quiet)
      output = capture_stdout { renderer.render(make_event(event: :materialized)) }

      expect(output).to be_empty
    end
  end

  describe 'event descriptions' do
    let(:renderer) { described_class.new(total: 1) }

    it 'describes :materialized events' do
      output = capture_stdout { renderer.render(make_event(event: :materialized)) }
      expect(output).to include('Materialized: org_1 (plan_v1, 5 entitlements)')
    end

    it 'describes :would_materialize with cascade hint when enabled' do
      renderer = described_class.new(total: 1, include_memberships: true)
      output = capture_stdout { renderer.render(make_event(event: :would_materialize)) }

      expect(output).to include('Would materialize: org_1')
      expect(output).to include('(+memberships cascade)')
    end

    it 'describes :skipped_no_plan events' do
      output = capture_stdout { renderer.render(make_event(event: :skipped_no_plan)) }
      expect(output).to include('Skipping (no planid): org_1')
    end

    it 'describes :skipped_plan_filter events' do
      output = capture_stdout { renderer.render(make_event(event: :skipped_plan_filter)) }
      expect(output).to include('Skipping (plan filter): org_1')
    end

    it 'describes :failed_plan_not_found events' do
      output = capture_stdout do
        renderer.render(make_event(event: :failed_plan_not_found, reason: 'no such plan'))
      end
      expect(output).to include('Error: no such plan (org_1)')
    end

    it 'describes :failed_cascade with partial success count' do
      event = make_event(
        event: :failed_cascade,
        reason: 'partial failure',
        cascade: { success: 2, failed: 1, total: 3 },
      )
      output = capture_stdout { renderer.render(event) }

      expect(output).to include('cascade failed for org_1')
      expect(output).to include('2/3 succeeded')
    end
  end

  describe 'membership failure rendering' do
    it 'shows FAILED marker for errored memberships in verbose mode' do
      event = make_event(
        event: :materialized,
        cascade: { success: 0, failed: 1, total: 1, details: [
          { objid: 'mem_bad', role: 'member', planid: 'p1', entitlements_count: 0, status: :error, error: 'write failed' },
        ] },
      )
      renderer = described_class.new(total: 1, verbosity: :verbose, include_memberships: true)

      output = capture_stdout { renderer.render(event) }

      expect(output).to include('mem_bad')
      expect(output).to include('FAILED')
      expect(output).to include('write failed')
    end
  end
end

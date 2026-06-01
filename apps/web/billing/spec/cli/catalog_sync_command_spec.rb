# apps/web/billing/spec/cli/catalog_sync_command_spec.rb
#
# frozen_string_literal: true

# Specs for `bin/ots billing catalog sync` CLI wrapper.
#
# The command composes three operations in sequence: push, pull, materialize.
# These specs verify step orchestration, option forwarding, abort-on-failure,
# and output under success/failure/dry-run modes.
#
# Run: pnpm run test:rspec apps/web/billing/spec/cli/catalog_sync_command_spec.rb

require_relative '../support/billing_spec_helper'
require 'onetime/cli'
require_relative '../../cli/catalog_sync_command'

RSpec.describe 'Billing Catalog Sync CLI', :billing_cli do
  subject(:command) { Onetime::CLI::BillingCatalogSyncCommand.new }

  def capture_stdout
    old_stdout = $stdout
    $stdout = StringIO.new
    begin
      yield
    rescue SystemExit
      # Ignore exit calls
    end
    $stdout.string
  ensure
    $stdout = old_stdout
  end

  def push_result(success: true, no_changes: false, products_created: 0, products_updated: 0, prices_created: 0, errors: [])
    Billing::Operations::Catalog::Push::Result.new(
      success: success,
      dry_run: false,
      products_created: products_created,
      products_updated: products_updated,
      prices_created: prices_created,
      no_changes: no_changes,
      errors: errors,
    )
  end

  def pull_result(success: true, plans_synced: 3, config_plans_loaded: 0, errors: [])
    Billing::Operations::Catalog::Pull::Result.new(
      success: success,
      plans_synced: plans_synced,
      config_plans_loaded: config_plans_loaded,
      errors: errors,
    )
  end

  def materialize_result(succeeded: 1, failed: 0, scanned: 1,
                         skipped_no_plan: 0, skipped_plan_filter: 0,
                         memberships_succeeded: 0, memberships_failed: 0,
                         orgs_cascaded: 0, errors: [])
    Billing::Operations::MaterializePlansResult.new(
      scanned: scanned,
      succeeded: succeeded,
      failed: failed,
      skipped_no_plan: skipped_no_plan,
      skipped_plan_filter: skipped_plan_filter,
      memberships_succeeded: memberships_succeeded,
      memberships_failed: memberships_failed,
      orgs_cascaded: orgs_cascaded,
      errors: errors,
    )
  end

  before do
    allow(command).to receive(:boot_application!)
    allow(command).to receive(:stripe_configured?).and_return(true)
    instances = instance_double(Familia::SortedSet, element_count: 1)
    allow(Onetime::Organization).to receive(:instances).and_return(instances)
  end

  describe 'stripe configuration' do
    it 'exits early when Stripe is not configured' do
      allow(command).to receive(:stripe_configured?).and_return(false)
      expect(Billing::Operations::Catalog::Push).not_to receive(:call)

      command.call
    end
  end

  describe 'full sync (happy path)' do
    before do
      allow(Billing::Operations::Catalog::Push).to receive(:call)
        .and_return(push_result(no_changes: true))
      allow(Billing::Operations::Catalog::Pull).to receive(:call)
        .and_return(pull_result)
      allow(Billing::Operations::MaterializePlans).to receive(:call)
        .and_return(materialize_result)
    end

    it 'runs all three steps in sequence' do
      output = capture_stdout { command.call(force: true) }

      expect(output).to include('Step 1: Catalog Push')
      expect(output).to include('Step 2: Catalog Pull')
      expect(output).to include('Step 3: Plans Materialize')
    end

    it 'reports success when all steps complete without errors' do
      output = capture_stdout { command.call(force: true) }

      expect(output).to include('Catalog sync complete!')
    end
  end

  describe 'step 1: catalog push' do
    context 'when no changes needed' do
      before do
        allow(Billing::Operations::Catalog::Push).to receive(:call)
          .and_return(push_result(no_changes: true))
        allow(Billing::Operations::Catalog::Pull).to receive(:call)
          .and_return(pull_result)
        allow(Billing::Operations::MaterializePlans).to receive(:call)
          .and_return(materialize_result)
      end

      it 'continues to pull and materialize' do
        capture_stdout { command.call(force: true) }

        expect(Billing::Operations::Catalog::Pull).to have_received(:call)
        expect(Billing::Operations::MaterializePlans).to have_received(:call)
      end

      it 'reports catalog is in sync' do
        output = capture_stdout { command.call(force: true) }
        expect(output).to include('No changes needed')
      end
    end

    context 'when push preview fails' do
      before do
        allow(Billing::Operations::Catalog::Push).to receive(:call)
          .and_return(push_result(success: false, errors: ['Invalid catalog']))
      end

      it 'aborts sync and does not run pull or materialize' do
        expect(Billing::Operations::Catalog::Pull).not_to receive(:call)
        expect(Billing::Operations::MaterializePlans).not_to receive(:call)

        output = capture_stdout { command.call(force: true) }
        expect(output).to include('Aborting sync: catalog push preview failed')
      end
    end

    context 'when changes exist and --force is set' do
      before do
        # First call is preview (dry_run: true), second is actual push
        allow(Billing::Operations::Catalog::Push).to receive(:call)
          .and_return(
            push_result(products_created: 2, prices_created: 1),
            push_result(products_created: 2, prices_created: 1),
          )
        allow(Billing::Operations::Catalog::Pull).to receive(:call)
          .and_return(pull_result)
        allow(Billing::Operations::MaterializePlans).to receive(:call)
          .and_return(materialize_result)
      end

      it 'skips confirmation prompt and proceeds' do
        output = capture_stdout { command.call(force: true) }

        expect(Billing::Operations::Catalog::Push).to have_received(:call).twice
        expect(output).to include('Created 2 product(s)')
      end
    end

    context 'when user declines confirmation' do
      before do
        allow(Billing::Operations::Catalog::Push).to receive(:call)
          .and_return(push_result(products_created: 1))
        allow($stdin).to receive(:gets).and_return("n\n")
      end

      it 'aborts sync' do
        expect(Billing::Operations::Catalog::Pull).not_to receive(:call)

        output = capture_stdout { command.call }
        expect(output).to include('Aborted by user')
      end
    end
  end

  describe 'step 2: catalog pull' do
    context 'when pull fails' do
      before do
        allow(Billing::Operations::Catalog::Push).to receive(:call)
          .and_return(push_result(no_changes: true))
        allow(Billing::Operations::Catalog::Pull).to receive(:call)
          .and_return(pull_result(success: false, errors: ['Connection refused']))
      end

      it 'aborts sync and does not run materialize' do
        expect(Billing::Operations::MaterializePlans).not_to receive(:call)

        output = capture_stdout { command.call(force: true) }
        expect(output).to include('Aborting sync: catalog pull failed')
      end
    end
  end

  describe 'step 3: plans materialize' do
    before do
      allow(Billing::Operations::Catalog::Push).to receive(:call)
        .and_return(push_result(no_changes: true))
      allow(Billing::Operations::Catalog::Pull).to receive(:call)
        .and_return(pull_result)
    end

    it 'reports success statistics' do
      allow(Billing::Operations::MaterializePlans).to receive(:call)
        .and_return(materialize_result(scanned: 5, succeeded: 4, skipped_no_plan: 1))

      output = capture_stdout { command.call(force: true) }
      expect(output).to include('Scanned: 5')
      expect(output).to include('Succeeded: 4')
      expect(output).to include('Skipped (no plan): 1')
    end

    context 'with materialization errors' do
      it 'reports errors in the final banner' do
        allow(Billing::Operations::MaterializePlans).to receive(:call)
          .and_return(materialize_result(
            failed: 1,
            errors: [{ org_extid: 'org_broken', reason: 'plan not found' }],
          ))

        output = capture_stdout { command.call(force: true) }
        expect(output).to include('finished with materialization errors')
        expect(output).to include('Push and pull succeeded')
        expect(output).to include('org_broken')
      end
    end

    context 'with zero organizations' do
      before do
        empty = instance_double(Familia::SortedSet, element_count: 0)
        allow(Onetime::Organization).to receive(:instances).and_return(empty)
      end

      it 'reports nothing to materialize and still succeeds' do
        expect(Billing::Operations::MaterializePlans).not_to receive(:call)

        output = capture_stdout { command.call(force: true) }
        expect(output).to include('No organizations found')
        expect(output).to include('complete!')
      end
    end
  end

  describe 'option forwarding' do
    before do
      allow(Billing::Operations::Catalog::Push).to receive(:call)
        .and_return(push_result(no_changes: true))
      allow(Billing::Operations::Catalog::Pull).to receive(:call)
        .and_return(pull_result)
      allow(Billing::Operations::MaterializePlans).to receive(:call)
        .and_return(materialize_result)
    end

    it 'forwards --plan to push and materialize' do
      capture_stdout { command.call(force: true, plan: 'identity_plus_v1') }

      expect(Billing::Operations::Catalog::Push).to have_received(:call)
        .with(hash_including(plan_filter: 'identity_plus_v1'))
      expect(Billing::Operations::MaterializePlans).to have_received(:call)
        .with(hash_including(plan_filter: 'identity_plus_v1'))
    end

    it 'forwards --skip-prices to push' do
      capture_stdout { command.call(force: true, skip_prices: true) }

      expect(Billing::Operations::Catalog::Push).to have_received(:call)
        .with(hash_including(skip_prices: true))
    end

    it 'forwards --include-memberships to materialize' do
      capture_stdout { command.call(force: true, include_memberships: true) }

      expect(Billing::Operations::MaterializePlans).to have_received(:call)
        .with(hash_including(include_memberships: true))
    end
  end

  describe 'dry-run mode' do
    before do
      allow(Billing::Operations::Catalog::Push).to receive(:call)
        .and_return(push_result(products_created: 1))
      allow(Billing::Operations::MaterializePlans).to receive(:call)
        .and_return(materialize_result)
    end

    it 'shows DRY RUN banner' do
      output = capture_stdout { command.call(dry_run: true) }
      expect(output).to include('(DRY RUN)')
    end

    it 'skips pull step entirely' do
      expect(Billing::Operations::Catalog::Pull).not_to receive(:call)

      output = capture_stdout { command.call(dry_run: true) }
      expect(output).to include('Skipped (dry run)')
    end

    it 'does not prompt for push confirmation' do
      expect($stdin).not_to receive(:gets)

      capture_stdout { command.call(dry_run: true) }
    end

    it 'passes dry_run: true to materialize' do
      capture_stdout { command.call(dry_run: true) }

      expect(Billing::Operations::MaterializePlans).to have_received(:call)
        .with(hash_including(dry_run: true))
    end
  end

  describe 'progress rendering' do
    before do
      allow(Billing::Operations::Catalog::Push).to receive(:call)
        .and_return(push_result(no_changes: true))
      allow(Billing::Operations::Catalog::Pull).to receive(:call)
        .and_return(pull_result)
    end

    def stub_materialize_with_event(event)
      allow(Billing::Operations::MaterializePlans).to receive(:call) do |**, &blk|
        blk.call(event)
        materialize_result
      end
    end

    it 'renders per-org progress lines by default' do
      stub_materialize_with_event(
        Billing::Operations::MaterializePlansEvent.new(
          event: :materialized, org_extid: 'org_abc', planid: 'p1',
          entitlements_count: 5, cascade: nil, reason: nil,
        ),
      )

      output = capture_stdout { command.call(force: true) }
      expect(output).to include('Materialized: org_abc')
    end

    it 'suppresses per-org lines under --quiet' do
      stub_materialize_with_event(
        Billing::Operations::MaterializePlansEvent.new(
          event: :materialized, org_extid: 'org_abc', planid: 'p1',
          entitlements_count: 5, cascade: nil, reason: nil,
        ),
      )

      output = capture_stdout { command.call(force: true, quiet: true) }
      expect(output).not_to include('Materialized: org_abc')
    end

    it 'shows membership detail under --verbose' do
      stub_materialize_with_event(
        Billing::Operations::MaterializePlansEvent.new(
          event: :materialized, org_extid: 'org_abc', planid: 'p1',
          entitlements_count: 5,
          cascade: {
            success: 1, failed: 0, total: 1,
            details: [
              { objid: 'mem_111', role: 'owner', planid: 'p1', entitlements_count: 8, status: :ok, error: nil },
            ],
          },
          reason: nil,
        ),
      )

      output = capture_stdout { command.call(force: true, verbose: true) }
      expect(output).to include('mem_111')
      expect(output).to include('role=owner')
    end
  end
end

# apps/web/billing/spec/cli/orgs_validate_command_integration_spec.rb
#
# frozen_string_literal: true

# Integration spec for `bin/ots billing orgs validate`.
#
# Complements the mock-heavy unit spec
# (orgs_validate_command_spec.rb) by exercising the command end-to-end
# against real Redis and real Familia objects:
#
#   - Real Onetime::Customer and Onetime::Organization persistence
#   - Real Onetime::Organization.instances sorted-set iteration
#   - Real Billing::Plan.load_with_fallback resolution against the
#     Redis cache populated from spec/billing.test.yaml
#
# Uses the `:integration` symbol tag so the billing_spec_helper hooks
# run `flushdb` and `mock_billing_config!` between tests. The
# Plan.load stub from `stub_test_plan_catalog!` is reset to
# `and_call_original` so real plans persisted by ConfigLoader are
# visible to the command.
#
# Run: pnpm run test:rspec apps/web/billing/spec/cli/orgs_validate_command_integration_spec.rb

require 'json'

require_relative '../support/billing_spec_helper'
require 'onetime/cli'
require_relative '../../cli/orgs_validate_command'
require_relative '../../operations/catalog/config_loader'

RSpec.describe 'Billing Orgs Validate CLI (integration)', :integration do
  subject(:command) { Onetime::CLI::BillingOrgsValidateCommand.new }

  # The :integration before hook calls stub_test_plan_catalog! which
  # mocks Billing::Plan.load for test_plan_v1 and identity_plus_v1.
  # That defeats the point of an integration test, so reset to the real
  # implementation and let the data we persist below drive resolution.
  before do
    allow(command).to receive(:boot_application!)
    allow(Billing::Plan).to receive(:load).and_call_original

    # Load plans from spec/billing.test.yaml into Redis. This populates
    # the `instances` sorted set and gives us a real plan (identity_plus_v1)
    # that load_with_fallback can resolve via the Stripe-cache path.
    Billing::Operations::Catalog::ConfigLoader.load_all_from_config
  end

  def run_command(**kwargs)
    old_stdout = $stdout
    $stdout    = StringIO.new
    status     = nil
    begin
      command.call(**kwargs)
    rescue SystemExit => e
      status = e.status
    end
    [$stdout.string, status]
  ensure
    $stdout = old_stdout
  end

  # Build a real Customer + Organization in Redis with the requested
  # planid. Each call uses a unique email so multiple orgs/customers can
  # coexist without colliding with unique indexes.
  def create_org(planid:, display_name: 'Test Org', email_seed: nil, **extra)
    seed     = email_seed || SecureRandom.hex(4)
    email    = "orgs-validate-#{seed}@example.com"
    customer = Onetime::Customer.create!(email: email)
    org      = Onetime::Organization.create!(display_name, customer, email)
    org.planid = planid
    extra.each { |k, v| org.send("#{k}=", v) }
    org.save
    org
  end

  describe 'happy path: all orgs resolvable' do
    it 'exits 0 when every org has a planid that resolves via Redis cache' do
      # identity_plus_v1 is persisted to Redis by ConfigLoader above and
      # resolves through Billing::Plan.load (source: 'stripe').
      create_org(planid: 'identity_plus_v1', display_name: 'Acme Inc')

      output, status = run_command

      expect(status).to eq(0)
      expect(output).to include('Total orgs scanned:       1')
      expect(output).to include('Skipped (no planid):      0')
      expect(output).to include('Valid (Redis cache):      1')
      expect(output).to include('Invalid plan IDs:         0')
      expect(output).to include('All organizations have resolvable plan IDs.')
      expect(output).not_to include('INVALID PLAN IDS')
    end
  end

  describe 'invalid planid' do
    it 'exits 1 and reports the org under the invalid planid heading' do
      org = create_org(
        planid: 'definitely_not_a_real_plan_v99',
        display_name: 'Ghost Co',
      )

      output, status = run_command

      expect(status).to eq(1)
      expect(output).to include('Invalid plan IDs:         1')
      expect(output).to include('INVALID PLAN IDS')
      expect(output).to include('definitely_not_a_real_plan_v99 (1 org)')
      expect(output).to include(org.extid)
      expect(output).to include('Ghost Co')
      expect(output).to include('Resolution:')
    end
  end

  describe 'mixed orgs: valid + invalid + empty planid' do
    it 'reports correct counts for each bucket' do
      create_org(planid: 'identity_plus_v1', display_name: 'Valid Org', email_seed: 'valid')
      create_org(planid: 'ghost_plan_v1',    display_name: 'Invalid Org', email_seed: 'invalid')

      # Empty planid: create org then blank out the default 'free_v1'
      # assigned in Organization#init.
      empty_org        = create_org(planid: 'free_v1', display_name: 'Empty Org', email_seed: 'empty')
      empty_org.planid = ''
      empty_org.save

      output, status = run_command

      expect(status).to eq(1)
      expect(output).to include('Total orgs scanned:       3')
      expect(output).to include('Skipped (no planid):      1')
      expect(output).to include('Valid (Redis cache):      1')
      expect(output).to include('Invalid plan IDs:         1')
    end
  end

  describe 'cache miss with config fallback' do
    it 'counts an org whose planid only exists in billing.yaml as Valid (billing.yaml)' do
      # free_v1 is in spec/billing.test.yaml but is skipped by
      # ConfigLoader (no prices), so it is NOT persisted to Redis.
      # load_with_fallback should therefore miss the cache and hit
      # load_from_config, returning source: 'local_config'.
      config_plan = Billing::Plan.load_from_config('free_v1')

      if config_plan.nil?
        skip 'free_v1 not available via Billing::Config.load_plans in this environment'
      end

      # Sanity check: free_v1 must not be in the Redis cache for this
      # test to mean anything. ConfigLoader skips priceless plans so
      # this should hold, but guard against silent regressions.
      expect(Billing::Plan.load('free_v1')).to be_nil

      create_org(planid: 'free_v1', display_name: 'Config Fallback Org')

      output, status = run_command

      expect(status).to eq(0)
      expect(output).to include('Valid (billing.yaml):     1')
      expect(output).to include('Valid (Redis cache):      0')
      expect(output).to include('All organizations have resolvable plan IDs.')
    end
  end

  describe '--json output' do
    it 'emits a parseable JSON document matching the documented contract' do
      valid_org   = create_org(planid: 'identity_plus_v1', display_name: 'Valid Co', email_seed: 'json-valid')
      invalid_org = create_org(
        planid: 'ghost_v1',
        display_name: 'Ghost Co',
        email_seed: 'json-invalid',
        stripe_customer_id: 'cus_int_1',
        stripe_subscription_id: 'sub_int_1',
        subscription_status: 'canceled',
      )

      output, status = run_command(json: true)

      expect(status).to eq(1)

      # Suppresses the text report.
      expect(output).not_to include('Organization Plan ID Validation')
      expect(output).not_to include('Resolution:')

      parsed = JSON.parse(output)

      expect(parsed['stats']).to include(
        'total' => 2,
        'invalid' => 1,
        'valid_stripe' => 1,
        'skipped_no_planid' => 0,
      )

      expect(parsed['invalid_orgs'].size).to eq(1)
      expect(parsed['invalid_orgs'].first).to include(
        'extid' => invalid_org.extid,
        'planid' => 'ghost_v1',
        'display_name' => 'Ghost Co',
        'stripe_customer_id' => 'cus_int_1',
        'stripe_subscription_id' => 'sub_int_1',
        'subscription_status' => 'canceled',
      )

      # Make sure the valid org is NOT in the invalid list.
      expect(parsed['invalid_orgs'].map { |o| o['extid'] }).not_to include(valid_org.extid)

      expect(parsed['invalid_by_planid']).to have_key('ghost_v1')
      expect(parsed['invalid_by_planid']['ghost_v1'].size).to eq(1)
    end
  end
end

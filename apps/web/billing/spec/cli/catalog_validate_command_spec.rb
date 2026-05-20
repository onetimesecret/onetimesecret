# apps/web/billing/spec/cli/catalog_validate_command_spec.rb
#
# frozen_string_literal: true

# Specs for `bin/ots billing catalog validate`.
#
# Validates the billing catalog YAML against the Zod-generated JSON Schema
# at generated/schemas/config/billing.schema.json.
#
# These run under spec:fast (no :integration tag, no Stripe/VCR): the
# command performs local schema validation only and never calls Stripe.
#
# Run: pnpm run test:rspec apps/web/billing/spec/cli/catalog_validate_command_spec.rb

require_relative '../support/billing_spec_helper'
require 'tempfile'
require 'onetime/cli'
require_relative '../../cli/catalog_validate_command'

RSpec.describe 'Billing Catalog Validate CLI', :billing_cli do
  subject(:command) { Onetime::CLI::BillingCatalogValidateCommand.new }

  # The command calls `exit` to signal pass/fail. Capture stdout and the
  # resulting exit status.
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

  before do
    # OT is already booted by billing_spec_helper; avoid re-booting in-process.
    allow(command).to receive(:boot_application!)
  end

  describe 'generated schema' do
    it 'is committed at the path the command loads' do
      schema_path = File.join(Onetime::HOME, 'generated', 'schemas', 'config', 'billing.schema.json')
      expect(File.exist?(schema_path)).to be(true),
        "Expected generated schema at #{schema_path}. Run: pnpm run schemas:json:generate"
    end
  end

  describe '#call with a valid catalog' do
    # No config_path stub: ConfigResolver resolves the real test catalog
    # (apps/web/billing/spec/billing.test.yaml) under RACK_ENV=test.
    it 'passes validation against the current billing catalog' do
      output, status = run_command

      expect(output).to include('VALIDATION PASSED')
      expect(status).to eq(0)
    end
  end

  describe '#call with an invalid catalog' do
    let(:fixture) { Tempfile.new(['billing_invalid', '.yaml']) }

    before do
      allow(Billing::Config).to receive(:config_path).and_return(fixture.path)
      allow(Billing::Config).to receive(:config_exists?).and_return(true)
    end

    after do
      fixture.close
      fixture.unlink
    end

    def write_fixture(yaml)
      fixture.write(yaml)
      fixture.flush
    end

    it 'fails when a limit is negative beyond the -1 unlimited sentinel' do
      write_fixture(<<~YAML)
        schema_version: "1.0"
        app_identifier: "onetimesecret"
        entitlements:
          create_secrets:
            category: core
            description: Can create basic secrets
        plans:
          team_plus_v1:
            name: "Team Plus"
            tier: single_team
            entitlements:
              - create_secrets
            limits:
              organizations: -2
              members_per_team: 1
              custom_domains: 1
              secret_lifetime: 100
            prices:
              - interval: month
                amount: 100
      YAML

      output, status = run_command

      expect(output).to include('VALIDATION FAILED')
      expect(output).to include('Schema validation:')
      expect(status).to eq(1)
    end

    it 'fails when grandfathered_until is not an ISO date' do
      write_fixture(<<~YAML)
        schema_version: "1.0"
        app_identifier: "onetimesecret"
        entitlements:
          create_secrets:
            category: core
            description: Can create basic secrets
        plans:
          free_v1:
            name: "Free"
            tier: free
            grandfathered_until: "not-a-date"
            entitlements:
              - create_secrets
            limits:
              organizations: 1
              members_per_team: 1
              custom_domains: 1
              secret_lifetime: 100
            prices: []
      YAML

      output, status = run_command

      expect(output).to include('VALIDATION FAILED')
      expect(status).to eq(1)
    end

    it 'fails when plan ID does not match canonical format' do
      # Issue #3135: Plan IDs must match canonical pattern
      write_fixture(<<~YAML)
        schema_version: "1.0"
        app_identifier: "onetimesecret"
        entitlements:
          create_secrets:
            category: core
            description: Can create basic secrets
        plans:
          invalid_plan_format:
            name: "Invalid Plan"
            tier: single_account
            entitlements:
              - create_secrets
            limits:
              organizations: 1
              members_per_team: 1
              custom_domains: 1
              secret_lifetime: 100
            prices:
              - interval: month
                amount: 900
      YAML

      output, status = run_command

      expect(output).to include('VALIDATION FAILED')
      expect(output).to include('Schema validation:')
      expect(status).to eq(1)
    end

    it 'passes when plan ID matches canonical format' do
      write_fixture(<<~YAML)
        schema_version: "1.0"
        app_identifier: "onetimesecret"
        entitlements:
          create_secrets:
            category: core
            description: Can create basic secrets
        plans:
          identity_plus_v1:
            name: "Identity Plus"
            tier: single_account
            entitlements:
              - create_secrets
            limits:
              organizations: 1
              members_per_team: 1
              custom_domains: 1
              secret_lifetime: 100
            prices:
              - interval: month
                amount: 900
      YAML

      output, status = run_command

      expect(output).to include('VALIDATION PASSED')
      expect(status).to eq(0)
    end
  end
end

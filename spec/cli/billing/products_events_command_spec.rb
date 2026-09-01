# spec/cli/billing/products_events_command_spec.rb
#
# frozen_string_literal: true

# CLI adapter tests for `bin/ots billing products events`.
#
# Scoped to the operator-input contract: a negative --limit used to reach
# Array#first, which raises on a negative size, after the command had already
# spent a Stripe round trip. The guard runs ahead of stripe_configured?, so
# these need no Stripe key and no VCR cassette.
#
# Run: tests/lanes/run unit --only spec/cli/billing/products_events_command_spec.rb

require_relative '../cli_spec_helper'
# Also auto-discovered by lib/onetime/cli.rb's apps glob; required explicitly
# (like the sync_org peer spec) so this spec does not depend on the discovery
# cwd.
require_relative '../../../apps/web/billing/cli/products_events_command'

RSpec.describe 'Billing Products Events Command', type: :cli do
  describe '--limit validation' do
    it 'rejects a negative --limit before calling Stripe' do
      expect(Stripe::Product).not_to receive(:retrieve)

      output = run_cli_command_quietly('billing', 'products', 'events', 'prod_abc', '--limit', '-1')
      expect(output[:stdout]).to include('--limit must be a positive integer')
      expect(last_exit_code).to eq(1)
    end

    it 'rejects a zero --limit rather than showing nothing' do
      output = run_cli_command_quietly('billing', 'products', 'events', 'prod_abc', '--limit', '0')
      expect(output[:stdout]).to include('--limit must be a positive integer')
      expect(last_exit_code).to eq(1)
    end
  end
end

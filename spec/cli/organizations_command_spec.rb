# spec/cli/organizations_command_spec.rb
#
# frozen_string_literal: true

# CLI adapter tests for `bin/ots organizations …`.
#
# Scoped to the operator-input contract the command owns. The listing itself
# reads the live instances index and is exercised by the org specs; here only
# the --limit guard is asserted, because a negative value used to reach
# Array#take and abort the command with a backtrace.
#
# NOTE for later PRs: append `describe` blocks to this file rather than
# creating a sibling spec, so the whole `organizations` surface stays here.
#
# Run: tests/lanes/run unit --only spec/cli/organizations_command_spec.rb

require_relative 'cli_spec_helper'
# Also auto-discovered by lib/onetime/cli.rb's apps glob; required explicitly
# (like spec/cli/billing/sync_org_command_spec.rb) so this spec does not depend
# on the discovery cwd.
require_relative '../../apps/api/organizations/cli/list_command'

RSpec.describe 'Organizations Command', type: :cli do
  describe '--limit validation' do
    it 'rejects a negative --limit instead of crashing on take(-1)' do
      output = run_cli_command_quietly('organizations', '--list', '--limit', '-1')
      expect(output[:stdout]).to include('--limit must be a positive integer')
      expect(last_exit_code).to eq(1)
    end

    it 'rejects a zero --limit rather than listing nothing' do
      output = run_cli_command_quietly('organizations', '--list', '--limit', '0')
      expect(output[:stdout]).to include('--limit must be a positive integer')
      expect(last_exit_code).to eq(1)
    end
  end
end

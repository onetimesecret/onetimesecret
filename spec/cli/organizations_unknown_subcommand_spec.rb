# spec/cli/organizations_unknown_subcommand_spec.rb
#
# frozen_string_literal: true

# `organizations` is both a command and the parent of every org verb. dry-cli
# 1.4.1 (CommandRegistry#get) hands a token that names no child to the parent
# with the leftover words in `args:`. The parent must treat those as an
# unknown subcommand and exit 1, not print the usage and exit 0, so a typo or
# a retired verb in a script fails loudly.
#
# Run: tests/lanes/run unit --only spec/cli/organizations_unknown_subcommand_spec.rb

require_relative 'cli_spec_helper'
require 'onetime/cli/organizations_command'

RSpec.describe 'Organizations unknown subcommand', type: :cli do
  before do
    allow(Onetime::Organization).to receive(:instances).and_return(double('Instances', size: 3))
  end

  it 'still prints the usage and exits 0 with no subcommand' do
    output = run_cli_command_quietly('organizations')

    expect(last_exit_code).to eq(0)
    expect(output[:stdout]).to include('3 organizations')
    expect(output[:stderr]).not_to include('Unknown subcommand')
  end

  it 'exits 1 for the retired add-member verb and points at memberships add' do
    output = run_cli_command_quietly('organizations', 'add-member', 'on_org_ext', 'ur_cust_ext')

    expect(last_exit_code).to eq(1)
    expect(output[:stderr]).to include('Unknown subcommand: add-member')
    expect(output[:stderr]).to include('bin/ots memberships add ORG CUSTOMER [--role R] [--default]')
    expect(output[:stderr]).to include('bin/ots organizations show ORG')
    expect(output[:stdout]).not_to include('3 organizations')
  end

  it 'exits 1 for a misspelled verb through the `org` alias and suggests the verb' do
    output = run_cli_command_quietly('org', 'dcotor', 'on_org_ext')

    expect(last_exit_code).to eq(1)
    expect(output[:stderr]).to include('Unknown subcommand: dcotor')
    expect(output[:stderr]).to include('Did you mean `doctor`?')
  end

  it 'does not boot the application for an unknown subcommand' do
    expect(OT).not_to receive(:boot!)

    run_cli_command_quietly('organization', 'frobnicate')

    expect(last_exit_code).to eq(1)
  end

  # The old option-verbs. dry-cli rejects an option the parent does not
  # declare before `call` runs.
  %w[--list --show --check].each do |flag|
    it "exits 1 for the retired #{flag} option" do
      output = run_cli_command_quietly('organizations', flag)

      expect(last_exit_code).to eq(1)
      expect(output[:stderr]).to include('ERROR')
      expect(output[:stdout]).not_to include('3 organizations')
    end
  end
end

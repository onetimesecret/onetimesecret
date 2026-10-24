# spec/cli/parent_unknown_subcommand_spec.rb
#
# frozen_string_literal: true

# Every parent command that is also a command runs
# SubcommandGuard#reject_unknown_subcommand (lib/onetime/cli.rb) first. dry-cli
# 1.4.1 (CommandRegistry#get) hands such a parent a token that names no child,
# with the leftover words in `args:`; without the guard the parent prints its
# usage and exits 0. organizations has its own spec
# (organizations_unknown_subcommand_spec.rb); this one covers the rest.
#
# Run: tests/lanes/run unit --only spec/cli/parent_unknown_subcommand_spec.rb

require_relative 'cli_spec_helper'

RSpec.describe 'Parent command unknown subcommand', type: :cli do
  billing_loaded = Onetime::CLI.get(%w[billing]).found?

  before do
    allow(Onetime::Customer).to receive(:instances).and_return(double('Instances', size: 2))
    allow(Onetime::CustomDomain).to receive(:instances).and_return(double('Instances', size: 0))
    allow(Onetime::CustomDomain).to receive(:display_domain_index).and_return(double('Index', size: 0))
    allow(Onetime::Organization).to receive(:instances).and_return([])
    allow(Onetime::OrganizationMembership).to receive(:token_lookup).and_return(double('Lookup', size: 0))
  end

  # [parent path, unknown token, trailing words, suggestion or nil]
  unknown = [
    [%w[customers], 'purgee', %w[ur_cust_ext], 'purge'],
    [%w[customer], 'shwo', %w[ur_cust_ext], 'show'],
    [%w[memberships], 'remvoe', %w[on_org ur_cust], 'remove'],
    [%w[domains], 'frobnicate', %w[example.com], nil],
    [%w[organizations entitlement], 'grnat', %w[on_org ENT], 'grant'],
    [%w[memberships entitlement], 'revkoe', %w[on_org ur_cust ENT], 'revoke'],
    [%w[session], 'lsit', [], 'list'],
    [%w[scheduler], 'stauts', [], 'status'],
    [%w[billing], 'frobnicate', [], nil],
  ]

  unknown.each do |parent, token, rest, suggestion|
    argv = [*parent, token, *rest]

    it "exits 1 for `#{argv.join(' ')}` without booting" do
      skip 'billing CLI not registered in this lane' if argv.first == 'billing' && !billing_loaded
      expect(OT).not_to receive(:boot!)

      output = run_cli_command_quietly(*argv)

      expect(last_exit_code).to eq(1)
      expect(output[:stderr]).to include("Unknown subcommand: #{token}")
      expect(output[:stderr]).to include('Subcommands:')
      expect(output[:stderr]).to include("Did you mean `#{suggestion}`?") if suggestion
      expect(output[:stdout]).to be_empty
    end
  end

  # argv => text the usage prints on stdout
  usage = {
    %w[customers] => '2 customers',
    %w[memberships] => '0 active memberships',
    %w[domains] => '0 custom domains',
    %w[organizations entitlement] => 'bin/ots organizations entitlement show ORG',
    %w[memberships entitlement] => 'bin/ots memberships entitlement show ORG CUSTOMER',
    %w[session] => 'Session Inspector',
    %w[billing] => 'Billing Management Commands',
  }

  usage.each do |argv, marker|
    it "prints the usage and exits 0 for bare `#{argv.join(' ')}`" do
      skip 'billing CLI not registered in this lane' if argv.first == 'billing' && !billing_loaded

      output = run_cli_command_quietly(*argv)

      expect(last_exit_code).to eq(0)
      expect(output[:stdout]).to include(marker)
      expect(output[:stderr]).not_to include('Unknown subcommand')
    end
  end
end

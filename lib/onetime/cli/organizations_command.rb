# lib/onetime/cli/organizations_command.rb
#
# frozen_string_literal: true

# CLI command for managing organization records. Shows count and usage when
# invoked without a subcommand.
#
# `organizations` is the one parent for every organization verb. `organization`
# and `org` are aliases: dry-cli resolves an alias at every level of the
# command tree (Node#lookup is `children[token] || aliases[token]`), so
# `bin/ots org doctor X` reaches the `organizations doctor` child. Nothing may
# register a command under `org …` or `organization …` directly — that would
# create a real child node with the alias's name and shadow it.
#
# Usage:
#   bin/ots organizations                        # Show count and usage
#   bin/ots organizations show ORG               # Details, members, domains
#   bin/ots organizations doctor --all           # Check all organizations
#

require 'did_you_mean'

module Onetime
  module CLI
    class OrganizationsCommand < Command
      desc 'Manage organization records'

      # APPEND POINT — one line per new `organizations` verb, nothing else.
      #
      # Each PR that adds an `organizations` subcommand appends EXACTLY ONE
      # entry here (keep it grouped by verb, verbs alphabetical) so concurrent
      # lanes get a one-line diff instead of a conflict on a rewritten heredoc.
      # Pad the comment to the same column.
      USAGE_LINES = [
        '  bin/ots organizations create NAME --owner ID --apply  # Create an org owned by a customer',
        '  bin/ots organizations delete ORG              # Dry run: what a delete would take out',
        '  bin/ots organizations delete ORG --apply      # Permanently delete an org (guarded)',
        '  bin/ots organizations doctor ORG              # Check single org integrity',
        '  bin/ots organizations doctor --all            # Check all organizations',
        '  bin/ots organizations doctor --all --repair   # Auto-repair issues',
        '  bin/ots organizations doctor ORG --json       # JSON output',
        '  bin/ots organizations entitlement show ORG    # Plan / overrides / materialized + drift',
        '  bin/ots organizations entitlement grant ORG ENT --apply   # Add an override grant',
        '  bin/ots organizations entitlement revoke ORG ENT --apply  # Add an override revoke',
        '  bin/ots organizations entitlement clear ORG --apply   # Wipe ALL overrides (destructive)',
        '  bin/ots organizations list [--limit N]        # List organizations',
        '  bin/ots organizations list --owner EMAIL|--plan ID --run  # Filtered scan (dry run without --run)',
        '  bin/ots organizations list --verbose          # List with members and domains',
        '  bin/ots organizations reconcile ORG           # Dry run: the reconcile mode',
        '  bin/ots organizations reconcile ORG --apply   # Re-apply billing + entitlements',
        '  bin/ots organizations show ORG [--json]       # Details, billing, members, domains',
        '  bin/ots organizations transfer-ownership ORG NEW_OWNER --apply  # Hand an org to another member',
        '  bin/ots organizations unarchive ORG [--run]   # Restore an archived org',
      ].freeze

      # The ORG grammar every verb accepts (Org::Shared#resolve_org).
      IDENTIFIER_LINES = [
        'ORG = org extid, objid, Stripe customer id (cus_...), Stripe subscription id',
        '      (sub_...), or custom-domain hostname.',
        'Aliases: `bin/ots organization ...` and `bin/ots org ...` run the same verbs.',
        'Verbs that write are dry runs unless --apply (-y/--yes) is given; unarchive takes --run.',
        'Members: bin/ots memberships add|set-role|remove ORG CUSTOMER',
      ].freeze

      # The `organizations doctor` invariants. Doctor-specific; not an append
      # point for other verbs. Kept in step with OrgDoctorCommand#show_usage.
      INTEGRITY_CHECKS = [
        '  1. owner_id is set and points to an existing customer (CRITICAL)',
        '  2. owner_id customer is in members set (HIGH)',
        '  3. All members have backing customer objects (MEDIUM)',
        '  4. Membership role:owner matches owner_id (WARNING)',
        '  5. Organization has at least one member (WARNING)',
        '  6. class-level unique-index entries (CRITICAL/HIGH/MEDIUM)',
        '  7. display_name is not blank (WARNING)',
        '  --all also sweeps the unique indexes and the instances index for',
        '  entries no live organization backs (MEDIUM / LOW)',
      ].freeze

      # Verbs removed from `organizations`, with where they went. Read by
      # SubcommandGuard#reject_unknown_subcommand (lib/onetime/cli.rb).
      REMOVED_SUBCOMMANDS = {
        'add-member' => 'bin/ots memberships add ORG CUSTOMER [--role R] [--default] --apply',
      }.freeze

      # A token that names no child arrives in `args:`; see SubcommandGuard.
      def call(args: [], **)
        reject_unknown_subcommand(args)

        boot_application!

        puts format('%d organizations', Onetime::Organization.instances.size)
        puts
        print_usage
      end

      private

      def print_usage(io: $stdout)
        io.puts 'Usage:'
        USAGE_LINES.each { |line| io.puts line }
        io.puts
        IDENTIFIER_LINES.each { |line| io.puts line }
        io.puts
        io.puts 'Integrity checks (doctor):'
        INTEGRITY_CHECKS.each { |line| io.puts line }
      end

      # SubcommandGuard hook: the full usage, not just the child names.
      def unknown_subcommand_usage(io)
        print_usage(io: io)
      end
    end

    register 'organizations', OrganizationsCommand, aliases: %w[organization org]
  end
end

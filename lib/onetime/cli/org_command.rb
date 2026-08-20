# lib/onetime/cli/org_command.rb
#
# frozen_string_literal: true

# CLI command for managing organization records. Shows count and usage when
# invoked without a subcommand.
#
# Usage:
#   bin/ots org                                # Show count and usage
#   bin/ots org doctor EXTID                   # Check single org integrity
#   bin/ots org reconcile ORG --yes            # Re-apply billing + entitlements
#

module Onetime
  module CLI
    class OrgCommand < Command
      desc 'Manage organization records'

      # APPEND POINT — one line per new `org` verb, nothing else.
      #
      # Each PR that adds an `org` subcommand appends EXACTLY ONE entry here
      # (keep it grouped by verb, verbs alphabetical) so concurrent lanes get a
      # one-line diff instead of a conflict on a rewritten heredoc. Pad the
      # comment to the same column.
      USAGE_LINES = [
        '  bin/ots org create NAME --owner ID  # Create an org owned by a customer',
        '  bin/ots org delete ORG --yes        # Permanently delete an org (guarded)',
        '  bin/ots org doctor EXTID            # Check single org integrity',
        '  bin/ots org doctor --all            # Check all organizations',
        '  bin/ots org doctor --all --repair   # Auto-repair issues',
        '  bin/ots org doctor EXTID --json     # JSON output',
        '  bin/ots org entitlement show ORG    # Plan / overrides / materialized + drift',
        '  bin/ots org entitlement grant ORG ENT   # Add an override grant',
        '  bin/ots org entitlement revoke ORG ENT  # Add an override revoke',
        '  bin/ots org entitlement clear ORG   # Wipe ALL overrides (destructive)',
        '  bin/ots org reconcile ORG --dry-run # Preview the reconcile mode',
        '  bin/ots org reconcile ORG --yes     # Re-apply billing + entitlements',
        '  bin/ots org transfer-ownership ORG NEW_OWNER  # Hand an org to another member',
      ].freeze

      # The `org doctor` invariants. Doctor-specific; not an append point for
      # other verbs.
      INTEGRITY_CHECKS = [
        '  1. owner_id points to existing customer (CRITICAL)',
        '  2. owner_id customer is in members set (HIGH)',
        '  3. All members have backing customer objects (MEDIUM)',
        '  4. Membership role:owner matches owner_id (WARNING)',
        '  5. Organization has at least one member (WARNING)',
        '  6. class-level unique-index entries (CRITICAL/HIGH/MEDIUM)',
      ].freeze

      def call(**)
        boot_application!

        puts format('%d organizations', Onetime::Organization.instances.size)
        puts
        puts 'Usage:'
        USAGE_LINES.each { |line| puts line }
        puts
        puts 'Integrity checks:'
        INTEGRITY_CHECKS.each { |line| puts line }
      end
    end

    register 'org', OrgCommand, aliases: ['organization']
  end
end

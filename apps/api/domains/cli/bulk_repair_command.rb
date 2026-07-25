# apps/api/domains/cli/bulk_repair_command.rb
#
# frozen_string_literal: true

# DEPRECATED — `bin/ots domains bulk-repair` is retired. Use:
#
#   bin/ots domains doctor --all --repair
#
# The command is a shim that prints the replacement and exits non-zero. It is
# NOT a thin wrapper: the old behaviour is deliberately gone, because it was
# wrong in two ways that a wrapper would have preserved.
#
#   1. The scan compared `org.list_domains` (an array of CustomDomain OBJECTS)
#      against `domain.domainid` (a String), so the membership test was ALWAYS
#      false. Every org-owned domain in the system was reported as "mismatched"
#      and then "repaired" — the scan summary was meaningless.
#
#   2. The mutation loop recorded NO AdminAuditEvent. It walked every custom
#      domain in the install and mutated org collections with zero audit trail.
#
# `domains doctor --all --repair` already scans every domain, detects the same
# org.domains membership issue with a correct O(1) test, delegates the fix to
# Onetime::Operations::Domains::Repair (which owns the cross-org guard and the
# single `domain.repair` audit event), and additionally checks index integrity
# that bulk-repair knew nothing about. `domains orphaned` covers the orphan
# tally that was bulk-repair's only unique output.
#
# Orphaned domains still require a per-domain human decision:
#   bin/ots domains repair DOMAIN --org-id ORG

module Onetime
  module CLI
    # Deprecation shim for the retired `domains bulk-repair` verb.
    class DomainsBulkRepairCommand < Command
      desc 'DEPRECATED: use `domains doctor --all --repair`'

      # The old flags stay declared so an existing invocation reaches this
      # message instead of dying on an unknown option. They are ignored.
      option :dry_run,
        type: :boolean,
        default: false,
        desc: 'Ignored (deprecated)'

      option :force,
        type: :boolean,
        default: false,
        desc: 'Ignored (deprecated)'

      def call(**)
        # No boot_application! — there is nothing to do and nothing to load.
        warn 'ERROR: `domains bulk-repair` has been removed.'
        warn ''
        warn 'use: bin/ots domains doctor --all --repair'
        warn ''
        warn 'It scans every domain, applies the same org.domains membership repair'
        warn 'through the audited Operations::Domains::Repair path, and also checks'
        warn 'index integrity. The old command mis-detected every org-owned domain'
        warn 'and mutated without an audit trail.'
        warn ''
        warn 'Orphaned domains still need a per-domain decision:'
        warn '  bin/ots domains repair DOMAIN --org-id ORG'
        warn '  bin/ots domains orphaned            # list them'
        exit 1
      end
    end
  end
end

Onetime::CLI.register 'domains bulk-repair', Onetime::CLI::DomainsBulkRepairCommand

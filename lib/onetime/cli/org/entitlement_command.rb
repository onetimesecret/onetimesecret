# lib/onetime/cli/org/entitlement_command.rb
#
# frozen_string_literal: true

# Landing command + shared adapter helpers for the `bin/ots org entitlement …`
# group.
#
# Usage:
#   bin/ots org entitlement show  ORG
#   bin/ots org entitlement grant ORG ENTITLEMENT --yes
#   bin/ots org entitlement revoke ORG ENTITLEMENT --yes
#   bin/ots org entitlement clear ORG --yes
#
# The mutation + the admin audit event are performed by the shared
# Onetime::Operations::Org::EntitlementOverride op (the single implementation;
# the colonel ManageEntitlementOverride Logic class is the other adapter). These
# commands own only CLI concerns. The CLI runs outside the app autoloaders, so
# require the op explicitly.
require 'json'
require 'onetime/operations/org/entitlement_override'
# Org::Shared / Customers::Shared must exist before the `include`s below.
# Required here (not only from the lib/onetime/cli.rb manifest) so these files
# cannot be loaded in a broken order.
require_relative 'shared'
require_relative '../customers/shared'

module Onetime
  module CLI
    module Org
      # Behaviour common to `org entitlement grant|revoke|clear`. Kept in one
      # place so the three verbs cannot drift on confirmation, advisories,
      # rendering or exit codes — they differ ONLY in their arguments and their
      # prompt wording.
      module EntitlementSupport
        # Run the shared op and render it. May `exit`.
        #
        # @param organization [Onetime::Organization] already resolved
        # @param action [String] 'grant' | 'revoke' | 'clear'
        # @param entitlement [String, nil] nil for clear
        def execute_override(organization, action:, entitlement: nil, yes: false, dry_run: false, json: false)
          warn_advisories(organization, action: action, entitlement: entitlement)

          return unless confirm_override!(
            organization,
            action: action,
            entitlement: entitlement,
            yes: yes,
            dry_run: dry_run,
            json: json,
          )

          result = Onetime::Operations::Org::EntitlementOverride.new(
            org: organization,
            action: action,
            # Never fabricate a Customer for the shell (ADR-023) — the audit
            # trail records the shared CLI sentinel.
            actor: Customers::Shared::CLI_ACTOR,
            entitlement: entitlement,
            dry_run: dry_run,
          ).call

          OT.info "[cli-org-entitlement-#{action}] org=#{organization.extid} " \
                  "entitlement=#{entitlement || '-'} status=#{result.status} dry_run=#{result.dry_run}"

          json ? override_json(result) : override_text(result)
        end

        # Advisories go to STDERR, never stdout: `--json` must stay a pure,
        # parseable channel, and a terminal shows both. They are printed BEFORE
        # the confirmation prompt so an operator sees them while they can still
        # answer 'n'.
        def warn_advisories(organization, action:, entitlement:)
          warn_standalone(organization)
          return if action == 'clear'

          warn_unknown_entitlement(entitlement)
          warn_role_scope(entitlement) if action == 'grant'
        end

        # THE most important line this command prints. On a billing-disabled
        # install `Organization#entitlements` returns STANDALONE_ENTITLEMENTS
        # before it ever reaches the materialized path, so the override is
        # written and then ignored by every runtime check — while
        # `org entitlement show` (which reads the sets directly) still displays
        # it. Silent here means an operator concludes it worked.
        def warn_standalone(organization)
          return if organization.billing_enabled?

          warn_line('!! BILLING IS DISABLED ON THIS INSTALL !!')
          warn_line('Entitlement overrides are written but NEVER read: Organization#entitlements')
          warn_line('short-circuits to STANDALONE_ENTITLEMENTS (full access) when billing is off.')
          warn_line('This write is a DEAD LETTER at runtime — and `org entitlement show` will')
          warn_line('still display it, because it reads the override sets directly.')
        end

        def warn_unknown_entitlement(entitlement)
          return if Onetime::Operations::Org::EntitlementOverride.known_entitlement?(entitlement)

          warn_line("'#{entitlement}' is not in the billing catalog — check for a typo.")
          warn_line('Proceeding anyway: granting an entitlement that ships in a later catalog')
          warn_line('is supported and deliberately not blocked.')
        end

        def warn_role_scope(entitlement)
          warn_line("Org scope is not member scope: '#{entitlement}' only reaches a member whose")
          warn_line('role template contains it (materialize_for_role! intersects')
          warn_line('org.entitlements & ROLE_ENTITLEMENTS[role]).')
        end

        def warn_line(message)
          warn "WARNING: #{message}"
        end

        # @return [Boolean] true to proceed
        def confirm_override!(organization, action:, entitlement:, yes:, dry_run:, json:)
          return true if dry_run || yes

          # Never mutate production entitlement state from a scripted invocation
          # that did not say so.
          if json
            error_exit(
              "Refusing to #{action} entitlement overrides without --yes in --json mode",
              json: true,
            )
          end

          print "#{confirm_prompt(organization, action, entitlement)} [y/N] "
          response = $stdin.gets&.strip&.downcase
          return true if response == 'y'

          puts 'Aborted.'
          false
        end

        def confirm_prompt(organization, action, entitlement)
          case action
          when 'grant'  then "Grant '#{entitlement}' to #{org_label(organization)}?"
          when 'revoke' then "Revoke '#{entitlement}' from #{org_label(organization)}?"
          else "Clear ALL entitlement overrides (every grant AND revoke) on #{org_label(organization)}?"
          end
        end

        def override_text(result)
          case result.status
          when :invalid_action
            error_exit("Unknown action '#{result.action}'", json: false)
          when :missing_entitlement
            error_exit('Entitlement is required for grant/revoke', json: false)
          end

          puts 'DRY RUN — nothing was written' if result.dry_run
          puts "Organization: #{result.org_id}"
          puts "Action:       #{result.action}"
          puts "Entitlement:  #{result.entitlement || '(all overrides)'}"
          puts "Status:       #{result.status}"
          puts
          print_set('Grants', result.grants)
          print_set('Revokes', result.revokes)
          print_set(result.dry_run ? 'Effective (projected)' : 'Effective', result.effective)

          exit 1 unless override_ok?(result)
        end

        def print_set(label, values)
          list = Array(values).sort
          puts "#{label} (#{list.size}):"
          if list.empty?
            puts '  (none)'
          else
            list.each { |value| puts "  - #{value}" }
          end
          puts
        end

        def override_json(result)
          puts JSON.pretty_generate(
            status: result.status,
            org_id: result.org_id,
            action: result.action,
            entitlement: result.entitlement,
            effective: result.effective,
            grants: result.grants,
            revokes: result.revokes,
            standalone: result.standalone,
            dry_run: result.dry_run,
          )
          exit 1 unless override_ok?(result)
        end

        def override_ok?(result)
          Onetime::Operations::Org::EntitlementOverride::OK_STATUSES.include?(result.status)
        end
      end
    end

    # Landing command for the `org entitlement` group. Required so the group
    # node carries a command object: `org` is itself a registered command (not a
    # bare group), and dry-cli's help for a command enumerates its children by
    # `.description` — a nil intermediate node (a group with no command) crashes
    # `bin/ots org --help`. Registering this makes `org entitlement` a real,
    # describable node. Same shape as CustomersPlanCommand, the tested
    # precedent.
    class OrgEntitlementCommand < Command
      desc "Manage an organization's operator entitlement overrides"

      # One line per verb. `show` first: it is the read that makes the writes
      # legible, and an operator reaching this usage list is usually looking.
      USAGE_LINES = [
        '  bin/ots org entitlement show ORG            # Plan / grants / revokes / drift',
        '  bin/ots org entitlement grant ORG ENT       # Add an override grant',
        '  bin/ots org entitlement revoke ORG ENT      # Add an override revoke',
        '  bin/ots org entitlement clear ORG           # Wipe ALL overrides on the org',
      ].freeze

      def call(**)
        puts 'Usage:'
        USAGE_LINES.each { |line| puts line }
        puts
        puts 'Overrides survive plan changes and reconciles:'
        puts '  effective = plan_entitlements + grants - revokes'
        puts
        puts 'Overrides never expire. There is no TTL — an override stands until cleared.'
      end
    end

    register 'org entitlement', OrgEntitlementCommand
  end
end

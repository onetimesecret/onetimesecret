# lib/onetime/cli/memberships/entitlement_command.rb
#
# frozen_string_literal: true

# Landing command + shared adapter helpers for the
# `bin/ots memberships entitlement …` group (#3907, closing D19 of #3731).
#
# Usage:
#   bin/ots memberships entitlement show  ORG CUSTOMER
#   bin/ots memberships entitlement grant ORG CUSTOMER ENTITLEMENT --yes
#   bin/ots memberships entitlement revoke ORG CUSTOMER ENTITLEMENT --yes
#   bin/ots memberships entitlement clear ORG CUSTOMER --yes
#
# The mutation + the admin audit event are performed by the shared
# Onetime::Operations::Memberships::EntitlementOverride op (the single
# implementation; the colonel ManageMembershipEntitlementOverride Logic class
# is the other adapter). These commands own only CLI concerns. The CLI runs
# outside the app autoloaders, so require the op explicitly.
require 'json'
require 'onetime/operations/memberships/entitlement_override'
# Memberships::Shared / Customers::Shared must exist before the `include`s below.
# Required here (not only from the lib/onetime/cli.rb manifest) so these files
# cannot be loaded in a broken order.
require_relative 'shared'
require_relative '../customers/shared'

module Onetime
  module CLI
    module Memberships
      # Behaviour common to `memberships entitlement grant|revoke|clear`. Kept
      # in one place so the three verbs cannot drift on confirmation,
      # advisories, rendering or exit codes — they differ ONLY in their
      # arguments and their prompt wording. Deliberate sibling of
      # Org::EntitlementSupport; the advisories differ because membership
      # scope has DIFFERENT hazards (see warn_grant_scope / warn_standalone).
      module EntitlementSupport
        # Run the shared op and render it. May `exit`.
        #
        # @param organization [Onetime::Organization] already resolved
        # @param member [Onetime::Customer] already resolved
        # @param action [String] 'grant' | 'revoke' | 'clear'
        # @param entitlement [String, nil] nil for clear
        def execute_override(organization, member, action:, entitlement: nil, yes: false, dry_run: false, json: false)
          warn_advisories(organization, action: action, entitlement: entitlement)

          return unless confirm_override!(
            organization,
            member,
            action: action,
            entitlement: entitlement,
            yes: yes,
            dry_run: dry_run,
            json: json,
          )

          result = Onetime::Operations::Memberships::EntitlementOverride.new(
            org: organization,
            customer: member,
            action: action,
            # Never fabricate a Customer for the shell (ADR-023) — the audit
            # trail records the shared CLI sentinel.
            actor: Customers::Shared::CLI_ACTOR,
            entitlement: entitlement,
            dry_run: dry_run,
          ).call

          OT.info "[cli-memberships-entitlement-#{action}] org=#{organization.extid} " \
                  "member=#{member.extid} entitlement=#{entitlement || '-'} " \
                  "status=#{result.status} dry_run=#{result.dry_run}"

          json ? override_json(result) : override_text(result, member)
        end

        # Advisories go to STDERR, never stdout: `--json` must stay a pure,
        # parseable channel, and a terminal shows both. They are printed BEFORE
        # the confirmation prompt so an operator sees them while they can still
        # answer 'n'.
        def warn_advisories(organization, action:, entitlement:)
          warn_standalone(organization)
          return if action == 'clear'

          warn_unknown_entitlement(entitlement)
          warn_grant_scope(entitlement) if action == 'grant'
        end

        # Membership scope inverts the org-level dead-letter story: a
        # materialized membership answers can? from its materialized set
        # regardless of billing, so the write IS read at runtime. What changes
        # on a standalone install is the BASELINE — the plan set derives from
        # STANDALONE_ENTITLEMENTS ∩ role (already full role access), so a grant
        # mostly adds nothing while a revoke still bites.
        def warn_standalone(organization)
          return if organization.billing_enabled?

          warn_line('!! BILLING IS DISABLED ON THIS INSTALL !!')
          warn_line('The membership baseline derives from STANDALONE_ENTITLEMENTS ∩ role —')
          warn_line('already full role access. A grant mostly adds nothing here; a revoke')
          warn_line('still takes effect (membership reads have no standalone short-circuit).')
        end

        def warn_unknown_entitlement(entitlement)
          return if Onetime::Operations::Memberships::EntitlementOverride.known_entitlement?(entitlement)

          warn_line("'#{entitlement}' is not in the billing catalog — check for a typo.")
          warn_line('Proceeding anyway: granting an entitlement that ships in a later catalog')
          warn_line('is supported and deliberately not blocked.')
        end

        # The inverse of the org-level role-scope advisory: a MEMBERSHIP grant
        # is unioned on top of the plan set with NO intersection, so it reaches
        # can? directly — even outside the member's role template or the org's
        # plan — and survives re-materialization. Say so before the prompt.
        def warn_grant_scope(entitlement)
          warn_line("A membership grant is NOT bounded by the org's plan or the role template:")
          warn_line("'#{entitlement}' will reach this member's can? checks directly and")
          warn_line('survives role changes and re-materialization until cleared.')
        end

        def warn_line(message)
          warn "WARNING: #{message}"
        end

        # @return [Boolean] true to proceed
        def confirm_override!(organization, member, action:, entitlement:, yes:, dry_run:, json:)
          return true if dry_run || yes

          # Never mutate production entitlement state from a scripted invocation
          # that did not say so.
          if json
            error_exit(
              "Refusing to #{action} entitlement overrides without --yes in --json mode",
              json: true,
            )
          end

          print "#{confirm_prompt(organization, member, action, entitlement)} [y/N] "
          response = $stdin.gets&.strip&.downcase
          return true if response == 'y'

          puts 'Aborted.'
          false
        end

        def confirm_prompt(organization, member, action, entitlement)
          who = "#{member.obscure_email} in #{organization.extid}"
          case action
          when 'grant'  then "Grant '#{entitlement}' to #{who}?"
          when 'revoke' then "Revoke '#{entitlement}' from #{who}?"
          else "Clear ALL entitlement overrides (every grant AND revoke) on #{who}?"
          end
        end

        def override_text(result, member)
          case result.status
          when :invalid_action
            error_exit("Unknown action '#{result.action}'", json: false)
          when :missing_entitlement
            error_exit('Entitlement is required for grant/revoke', json: false)
          when :not_found
            error_exit("#{member.obscure_email} is not an active member of #{result.org_id}", json: false)
          end

          puts 'DRY RUN — nothing was written' if result.dry_run
          puts "Organization: #{result.org_id}"
          puts "Member:       #{result.member_id}"
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
            member_id: result.member_id,
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
          Onetime::Operations::Memberships::EntitlementOverride::OK_STATUSES.include?(result.status)
        end
      end
    end

    # Landing command for the `memberships entitlement` group. Required so the
    # group node carries a command object: `memberships` is itself a registered
    # command (not a bare group), and dry-cli's help for a command enumerates
    # its children by `.description` — a nil intermediate node (a group with no
    # command) crashes `bin/ots memberships --help`. Same shape as
    # OrgEntitlementCommand, the tested precedent (D16).
    class MembershipsEntitlementCommand < Command
      desc "Manage a member's operator entitlement overrides"

      # One line per verb. `show` first: it is the read that makes the writes
      # legible, and an operator reaching this usage list is usually looking.
      USAGE_LINES = [
        '  bin/ots memberships entitlement show ORG CUSTOMER            # Baseline / grants / revokes / drift',
        '  bin/ots memberships entitlement grant ORG CUSTOMER ENT       # Add an override grant',
        '  bin/ots memberships entitlement revoke ORG CUSTOMER ENT      # Add an override revoke',
        '  bin/ots memberships entitlement clear ORG CUSTOMER           # Wipe ALL overrides on the membership',
      ].freeze

      def call(**)
        puts 'Usage:'
        USAGE_LINES.each { |line| puts line }
        puts
        puts 'ORG = organization extid; CUSTOMER = email, extid, or Rodauth account id.'
        puts
        puts 'Overrides survive role changes, org plan changes and re-materialization:'
        puts '  effective = (org ∩ role template) + grants - revokes'
        puts
        puts 'Overrides never expire. There is no TTL — an override stands until cleared.'
      end
    end

    register 'memberships entitlement', MembershipsEntitlementCommand
  end
end

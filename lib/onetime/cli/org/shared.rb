# lib/onetime/cli/org/shared.rb
#
# frozen_string_literal: true

require 'json'

module Onetime
  module CLI
    # Shared resolution + rendering helpers for the `bin/ots organizations …`
    # commands (aliases `organization`, `org`). Every organizations command
    # includes this, and Memberships::Shared includes it too, so the CLI cannot
    # drift on how an ORG argument is resolved or how a failure is reported.
    #
    # ## Resolver contract — one ORG grammar for the whole CLI
    #
    # `resolve_org` dispatches on the SHAPE of the argument. The shapes are
    # disjoint by construction (an extid is `on` + base36, an objid is a UUID,
    # neither contains `_` or `.`), so the dispatch decides which lookup runs,
    # never which of two orgs wins:
    #
    #   cus_…            Stripe customer id      -> find_by_stripe_customer_id
    #   sub_…            Stripe subscription id  -> find_by_stripe_subscription_id
    #                    (both refuse an index entry naming an org that no
    #                    longer holds the id; see #org_holding)
    #   contains a `.`   custom-domain hostname  -> the domain's primary org
    #   anything else    org extid FIRST, objid fallback
    #
    # The last branch is `find_by_extid || Organization.load(objid)`, verbatim
    # what both colonel adapters do (`GetOrganizationDetail#load_organization`,
    # `ReconcileOrganization#load_organization`), so an identifier pasted from
    # the admin console resolves the same way in the shell. The other three
    # branches are a CLI-only superset: an operator at a shell often has the
    # Stripe id from a billing ticket or the hostname from a support ticket,
    # not the extid.
    #
    # ## Actor identity
    #
    # There is no org-local actor sentinel. CLI-initiated mutations are
    # attributed to {Onetime::CLI::Customers::Shared::CLI_ACTOR} (the string
    # `cli`) — never a fabricated Customer (ADR-023: real, not synthesized).
    module Org
      module Shared
        STRIPE_CUSTOMER_PREFIX     = 'cus_'
        STRIPE_SUBSCRIPTION_PREFIX = 'sub_'

        # Resolve an ORG argument to an Onetime::Organization.
        # Exits 1 on a miss — NEVER returns nil, so a caller cannot proceed
        # with a nil org.
        #
        # @param identifier [String] org extid (on…), objid, Stripe customer id
        #   (cus_…), Stripe subscription id (sub_…), or custom-domain hostname
        # @param json [Boolean] emit the failure as JSON rather than text
        # @return [Onetime::Organization]
        def resolve_org(identifier, json:)
          id = identifier.to_s.strip
          error_exit("Organization not found: #{identifier}", json: json) if id.empty?

          organization = lookup_org(id)
          error_exit("Organization not found: #{identifier}", json: json) unless organization

          organization
        end

        # Emit an error (JSON or text) and exit non-zero.
        def error_exit(message, json:)
          puts(json ? JSON.generate({ error: message }) : "Error: #{message}")
          exit 1
        end

        # Consistent operator-facing rendering of an org across org commands.
        # PUBLIC id only — never the objid.
        def org_label(org)
          "#{org.extid} (#{org.display_name})"
        end

        # Operator-facing member rows: the customer's PUBLIC id, the membership
        # role and status, and the obscured email. Never an objid. Same join as
        # the colonel GetOrganizationDetail#build_members: active memberships
        # keyed by customer objid, laid over list_members (which drops
        # members-set entries with no customer record behind them).
        #
        # @return [Array<Hash>] { extid:, role:, status:, email:, owner: }
        def member_rows(org)
          by_customer = Onetime::OrganizationMembership.active_for_org(org).to_h do |membership|
            [membership.customer_objid, membership]
          end

          org.list_members.map do |cust|
            membership = by_customer[cust.objid]
            {
              extid: cust.extid,
              role: membership&.role,
              status: membership&.status,
              email: cust.obscure_email,
              owner: cust.objid.to_s == org.owner_id.to_s,
            }
          end
        end

        # One fixed-width text line per member row (see #member_rows).
        def format_member_row(row, indent: '  ')
          format('%s%-28s %-8s %-8s %s', indent, row[:extid], row[:role] || '-', row[:status] || '-', row[:email])
        end

        private

        def lookup_org(id)
          if id.start_with?(STRIPE_CUSTOMER_PREFIX)
            org_holding(Onetime::Organization.find_by_stripe_customer_id(id), :stripe_customer_id, id)
          elsif id.start_with?(STRIPE_SUBSCRIPTION_PREFIX)
            org_holding(Onetime::Organization.find_by_stripe_subscription_id(id), :stripe_subscription_id, id)
          elsif id.include?('.')
            Onetime::CustomDomain.from_display_domain(id)&.primary_organization
          else
            Onetime::Organization.find_by_extid(id) || Onetime::Organization.load(id)
          end
        end

        # The org a Stripe-id index entry names, only while that org still
        # carries the id. The generated find_by_* finders load whatever the
        # index names without reading the field back, and a stale entry is a
        # real state (doctor check 6). Acting on it would aim `delete`,
        # `reconcile`, `entitlement clear` or `transfer-ownership` at an org
        # the operator did not name. Same refusal as
        # CustomDomain.record_for_display_domain on the hostname branch.
        def org_holding(org, field, value)
          return nil unless org
          return org if org.public_send(field).to_s == value

          OT.le "[org cli] Refused the #{field} index entry for #{value}: it names " \
                "#{org.extid}, which does not hold it (run bin/ots organizations doctor --all)"
          nil
        end
      end
    end
  end
end

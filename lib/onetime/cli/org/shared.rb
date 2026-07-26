# lib/onetime/cli/org/shared.rb
#
# frozen_string_literal: true

require 'json'

module Onetime
  module CLI
    # Shared resolution + rendering helpers for the `bin/ots org …` commands
    # (doctor / reconcile / …). Every org command includes this so the area
    # cannot drift on how an ORG argument is resolved or how a failure is
    # reported.
    #
    # ## Resolver contract — extid FIRST, objid fallback (decided once)
    #
    # `resolve_org` is `find_by_extid || Organization.load(objid)`. This matches
    # BOTH colonel adapters verbatim — `GetOrganizationDetail#load_organization`
    # and `ReconcileOrganization#load_organization` — so an operator can paste
    # the same identifier into the admin console and the shell.
    #
    # It DELIBERATELY differs from {Onetime::CLI::Memberships::Shared#resolve_org},
    # which is extid-only because the memberships CLI contract is documented as
    # `ORG = org extid`. That divergence is intentional, not drift: do not
    # "fix" either one to match the other.
    #
    # ## Actor identity
    #
    # There is no org-local actor sentinel. CLI-initiated mutations are
    # attributed to {Onetime::CLI::Customers::Shared::CLI_ACTOR} (the string
    # `cli`) — never a fabricated Customer (ADR-023: real, not synthesized).
    module Org
      module Shared
        # Resolve an ORG argument to an Onetime::Organization.
        # Exits 1 on a miss — NEVER returns nil, so a caller cannot proceed
        # with a nil org.
        #
        # @param identifier [String] org extid (on…) or objid
        # @param json [Boolean] emit the failure as JSON rather than text
        # @return [Onetime::Organization]
        def resolve_org(identifier, json:)
          id = identifier.to_s.strip
          error_exit("Organization not found: #{identifier}", json: json) if id.empty?

          organization = Onetime::Organization.find_by_extid(id) || Onetime::Organization.load(id)
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
      end
    end
  end
end

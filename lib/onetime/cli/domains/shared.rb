# lib/onetime/cli/domains/shared.rb
#
# frozen_string_literal: true

# Shared resolution + error helpers for the domains CLI commands that sit on
# top of the Operations layer (probe / repair). Mirrors
# Onetime::CLI::Memberships::Shared: one place for the identifier contracts and
# one place for "print an error and exit non-zero".
#
# This deliberately does NOT reuse Onetime::CLI::DomainsHelpers
# (apps/api/domains/cli/helpers.rb). That module's `load_domain_by_name` prints
# an error and returns nil, and every caller then does `return unless domain` —
# which exits 0 on a lookup failure and makes the commands unscriptable. The
# helpers module stays where it is for the nine legacy app commands that still
# include it.
require 'json'

module Onetime
  module CLI
    module Domains
      module Shared
        # Resolve a DOMAIN argument to an Onetime::CustomDomain.
        #
        # Precedence is display_domain -> extid -> objid, matching
        # DomainsHelpers#load_domain. display_domain MUST stay first: it is the
        # documented CLI input, and a display domain that happens to look like
        # an extid must still resolve as a display domain.
        #
        # Note the colonel adapters (ProbeDomain / RepairDomain) resolve by
        # extid ONLY. The CLI accepting a superset is intentional — an operator
        # at a shell has the hostname, not the extid.
        def resolve_domain(identifier, json:)
          value = identifier.to_s.strip

          domain   = Onetime::CustomDomain.load_by_display_domain(value)
          domain ||= Onetime::CustomDomain.find_by_extid(value)
          domain ||= Onetime::CustomDomain.find_by_identifier(value)

          error_exit("Domain not found: #{identifier}", json: json) unless domain
          domain
        end

        # Resolve an ORG argument to an Onetime::Organization by extid first
        # (the documented input), objid as a fallback. Same precedence as
        # `domains create --org` and the colonel RepairDomain resolver.
        def resolve_org(identifier, json:)
          value = identifier.to_s.strip

          organization = Onetime::Organization.find_by_extid(value) ||
                         Onetime::Organization.load(value)

          error_exit("Organization not found: #{identifier}", json: json) unless organization
          organization
        end

        # Emit an error (JSON or text) and exit non-zero.
        def error_exit(message, json:)
          puts(json ? JSON.generate({ error: message }) : "Error: #{message}")
          exit 1
        end
      end
    end
  end
end

# apps/web/auth/operations/customers/membership_snapshot.rb
#
# frozen_string_literal: true

module Auth
  module Operations
    module Customers
      # The OrganizationMembership registry grouped by organization, captured
      # ONCE for a bulk purge run and handed to every candidate's preflight.
      #
      # Shallow preflight discovery derives an organization's membership rows
      # from the organization's own `members` set, so an active row whose
      # customer fell out of that set is invisible and a workspace can read as
      # sole-owned when it is not. Deep discovery closes that gap by sweeping
      # the registry, but once per preflight, and a purge runs several
      # preflights per candidate — a thousand-account sweep would repeat the
      # sweep thousands of times. This snapshot is the one read the whole run
      # pays for.
      #
      # Active membership objids are composite and name their organization, so
      # grouping is a parse of the registry's sorted set with no per-row load.
      # Rows with a non-composite objid (staged invitations) are loaded once to
      # read `organization_objid`.
      #
      # The snapshot holds objids only. Consumers re-load each row when they
      # use it, so a row removed after the capture — including by an earlier
      # candidate of the same run — is skipped rather than reported as drift.
      # A row CREATED after the capture is outside it, the same residual the
      # `members`-derived path already accepts.
      class MembershipSnapshot
        COMPOSITE_OBJID = /\Aorganization:(?<org>[^:]+):customer:[^:]+:org_membership\z/

        # @return [MembershipSnapshot]
        def self.capture
          by_org = Hash.new { |hash, key| hash[key] = [] }

          Onetime::OrganizationMembership.instances.each do |raw|
            objid = raw.to_s
            next if objid.empty?

            org_id = if (match = COMPOSITE_OBJID.match(objid))
                       match[:org]
                     else
                       Onetime::OrganizationMembership.load(objid)&.organization_objid.to_s
                     end
            next if org_id.to_s.empty?

            by_org[org_id] << objid unless by_org[org_id].include?(objid)
          end

          new(by_org)
        end

        # @param by_org [Hash{String => Array<String>}] organization objid =>
        #   membership objids
        def initialize(by_org)
          @by_org = by_org.to_h { |org_id, objids| [org_id.to_s, objids.map(&:to_s).uniq.freeze] }.freeze
          freeze
        end

        # @param org_id [String]
        # @return [Array<String>] membership objids recorded for the organization
        def objids_for(org_id)
          @by_org.fetch(org_id.to_s, [])
        end

        # @return [Integer] rows captured
        def size
          @by_org.sum { |_org_id, objids| objids.size }
        end

        # @return [Integer] organizations with at least one row
        def organization_count
          @by_org.size
        end
      end
    end
  end
end

# frozen_string_literal: true

module Onetime
  module CLI
    class BackfillCapabilitiesCommand < Command
      desc 'Compare and backfill organization features and membership capabilities'
      option :run, type: :boolean, default: false, desc: 'Persist the new snapshots after comparison'
      option :org, type: :string, desc: 'Process one organization by public ID'
      option :check_rollback, type: :boolean, default: false, desc: 'Refuse rollback when an older server would apply different access'

      def call(run: false, org: nil, check_rollback: false, **)
        raise ArgumentError, '--check-rollback is read-only' if run && check_rollback

        boot_application!

        counts = { organizations: 0, memberships: 0, failures: 0 }
        if org
          organization = Onetime::Organization.find_by_extid(org)
          raise ArgumentError, "Unknown organization #{org}" unless organization

          compare_organization(organization, run, check_rollback, counts)
        else
          Onetime::Organization.instances.each do |id|
            organization = Onetime::Organization.load(id)
            compare_organization(organization, run, check_rollback, counts) if organization
          end
        end
        puts "#{run ? 'Backfill' : 'Comparison'}: #{counts[:organizations]} organizations, " \
             "#{counts[:memberships]} active memberships, #{counts[:failures]} failures"
        exit 1 if counts[:failures].positive?
      end

      private

      def compare_organization(org, persist, rollback, counts)
        features = org.entitlements.select { |name| Onetime::Authorization::Registry.feature?(name) }.uniq.sort
        # The preflight exercises what the old reader would return. Normal
        # backfill includes explicit overrides, even after an older worker
        # published a stale paid-plan snapshot.
        unless rollback
          grants  = org.entitlements_grants.to_a
          revokes = org.entitlements_revokes.to_a
          Onetime::Authorization::Registry.features.each do |name|
            case org.dbclient.hget(org.dbkey, "feature_override:#{name}")
            when '"grant"'  then features |= [name] if grants.include?(name) && !revokes.include?(name)
            when '"revoke"' then features -= [name] if revokes.include?(name)
            end
          end
        end
        actual   = org.plan_entitlements(persist: false)
        unless features.sort == actual.sort
          different = ((features | actual) - (features & actual)).sort
          raise Onetime::Problem, "Features differ from the legacy reader: #{different.join(', ')}"
        end
        org.plan_entitlements if persist
        counts[:organizations] += 1

        Onetime::OrganizationMembership.active_for_org(org).each do |membership|
          compare_membership(membership, persist, rollback)
          counts[:memberships] += 1
        end
      rescue StandardError => ex
        counts[:failures] += 1
        warn "#{org.extid}: #{ex.message}. Retry with --org #{org.extid}."
      end

      def compare_membership(membership, persist, rollback)
        known   = Onetime::Models::Features::MembershipCapabilities::LEGACY_CAPABILITIES
        current = membership.capability_state(persist: false)
        return unless current # Removed while the scan was running.

        extra = (current[1] | current[2]) - known
        if rollback && !extra.empty?
          raise Onetime::Problem, "Older servers cannot enforce #{extra.join(', ')} overrides on membership #{membership.objid}"
        end

        if rollback && membership.entitlements_materialized?
          mixed = membership.materialized_entitlements.to_a
          stale = ((current[1] - current[2] - mixed) | (current[2] & mixed)) & known
          unless stale.empty?
            raise Onetime::Problem, "Legacy membership snapshot differs for #{stale.join(', ')} on #{membership.objid}"
          end
        end

        role     = Onetime::OrganizationMembership::ROLE_CAPABILITIES.fetch(membership.role)
        expected = (role.to_a | membership.entitlements_grants.to_a) - membership.entitlements_revokes.to_a
        unless (expected & known).sort == (current.first & known).sort
          raise Onetime::Problem, "Existing capabilities differ for membership #{membership.objid}"
        end

        membership.materialize_capabilities! if persist
      end
    end

    register 'migrations backfill-capabilities', BackfillCapabilitiesCommand
  end
end

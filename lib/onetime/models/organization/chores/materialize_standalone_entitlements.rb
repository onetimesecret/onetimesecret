# lib/onetime/models/organization/chores/materialize_standalone_entitlements.rb
#
# frozen_string_literal: true

# Housekeeping chore: Backfill standalone-mode entitlement materialization
# for organizations created before Stage 2 Unit C wired
# `Organization.create!` to call `materialize_standalone_entitlements!`.
#
# Three branches:
#
#   1. billing_enabled?                              → log :info "Skipping",
#                                                      no-op (webhook owns this)
#   2. org already has materialized entitlements      → silent no-op
#                                                      (do not re-materialize:
#                                                      operator grants/revokes
#                                                      have already reconciled)
#   3. standalone mode AND not yet materialized       → call
#                                                      materialize_standalone_entitlements!,
#                                                      log :info "Materializing"
#
# Per ADR-012 §Standalone mode: when billing is disabled the
# `STANDALONE_ENTITLEMENTS` set is the canonical entitlement source. New
# orgs get this materialized at create time; this chore brings legacy
# orgs into the same shape so the runtime fallback at
# `WithPlanEntitlements#entitlements` can eventually be removed.
#
# The runtime fallback is intentionally retained until this chore has
# been run in deployed environments. Removal is a separate follow-up
# commit after backfill is verified.
#
# Run via HousekeepingJob:
#   HousekeepingJob.perform('Onetime::Organization', :materialize_standalone_entitlements)

module Onetime
  module Chores
    # Constants namespaced here (rather than at top level) so that other
    # chore files loaded via Dir.glob can use the same generic names
    # without "already initialized constant" warnings.
    module MaterializeStandaloneEntitlements
      # No constants needed yet — the logic is purely structural.
      # Reserved for future per-org overrides if any arise.
    end
  end
end

Onetime::Organization.chore :materialize_standalone_entitlements do |org|
  logger = Onetime.get_logger('Chores')

  # Branch 1: billing enabled → webhook handles materialization, skip.
  if org.billing_enabled?
    logger.info 'Skipping org: billing enabled (webhook owns materialization)',
      chore: :materialize_standalone_entitlements,
      org_extid: org.extid
    next
  end

  # Branch 2: already materialized → silent no-op. Re-running would clobber
  # any operator grants/revokes reconciliation that has already settled.
  next if org.entitlements_materialized?

  # Branch 3: standalone + not materialized → materialize now.
  org.materialize_standalone_entitlements!

  # Cascade to memberships so they're consistent with the org's new entitlements.
  # Without this, memberships remain stale and the runtime fallback can't be removed.
  org.rematerialize_all_memberships!

  entitlement_count = org.materialized_entitlements.size

  logger.info 'Materialized standalone entitlements',
    chore: :materialize_standalone_entitlements,
    org_extid: org.extid,
    entitlement_count: entitlement_count

  true
end

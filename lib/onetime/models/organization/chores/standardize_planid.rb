# lib/onetime/models/organization/chores/standardize_planid.rb
#
# frozen_string_literal: true

# Housekeeping chore: Normalize legacy organization.planid values to the
# current billing catalog.
#
# Three branches, all data-driven:
#
#   1. current ∈ CANONICAL_PLANIDS         → silent no-op
#   2. family  ∈ LEGACY_PLANID_MAP         → rewrite, log :info "Normalizing"
#   3. otherwise                           → log :info "Skipping unknown",
#                                            leave value alone
#
# `family` is `current` with any trailing legacy interval suffix removed
# (e.g. `_monthly`, `_v1_yearly`). This collapses interval-suffixed variants
# onto their base family without enumerating every permutation.
#
# Identity preservation: `'identity'` is intentionally kept as canonical.
# Pro-bono customers carry `customer.planid='identity'` and the
# `migrations migrate-probono-accounts` command (which operates on
# `customer.planid`, not `organization.planid`) is the authoritative path
# for those accounts. This chore deliberately does not touch them.
#
# Run via HousekeepingJob:
#   HousekeepingJob.perform('Onetime::Organization', :standardize_planid)

# Values already in the current catalog (or otherwise valid). Skipped silently.
CANONICAL_PLANIDS = %w[
  free_v1
  identity_plus_v1
  team_plus_v1
  legacy_plan_v1
  identity
].freeze

# Legacy planid base values → canonical replacement. Lookup is performed
# against the value after trailing interval suffixes have been stripped.
LEGACY_PLANID_MAP = {
  '' => 'free_v1',
  'free' => 'free_v1',
  'basic' => 'free_v1',
  'identity_plus' => 'identity_plus_v1',
  'team_plus' => 'team_plus_v1',
}.freeze

# Legacy interval suffix patterns: `_month`, `_year`, `_monthly`, `_yearly`,
# optionally preceded by `_v1`. Examples that strip:
#   identity_plus_v1_monthly → identity_plus
#   team_plus_yearly         → team_plus
#   free_month               → free
INTERVAL_SUFFIX = /_(v1_)?(month|year)(ly)?\z/

Onetime::Organization.chore :standardize_planid do |org|
  logger  = Onetime.get_logger('Chores')
  current = org.planid.to_s.strip

  next if CANONICAL_PLANIDS.include?(current)

  family    = current.sub(INTERVAL_SUFFIX, '')
  corrected = LEGACY_PLANID_MAP[family]

  unless corrected
    logger.info 'Skipping unknown planid',
      chore: :standardize_planid,
      org_extid: org.extid,
      planid: current
    next
  end

  logger.info 'Normalizing planid',
    chore: :standardize_planid,
    org_extid: org.extid,
    from: current,
    to: corrected

  org.planid! corrected
  true
end

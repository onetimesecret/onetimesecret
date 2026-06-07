# lib/onetime/models/organization/chores/standardize_owner_id.rb
#
# frozen_string_literal: true

# Housekeeping chore: Backfill `created_by` from `owner_id` on existing
# organizations.
#
# Three branches:
#
#   1. created_by already present AND equals owner_id  → silent no-op
#   2. created_by nil AND owner_id present             → copy owner_id → created_by,
#                                                        save, log :info "Backfilling"
#   3. both nil, OR they disagree                      → log :warn "Skipping inconsistent",
#                                                        leave values alone
#
# Per ADR-012, `created_by` is an immutable audit field set once at
# `Organization.create!`. New orgs get both fields set in lock-step; this
# chore brings legacy orgs (created before the field existed) into the
# same shape so downstream code can migrate `owner_id` reads to
# `created_by` over the deprecation window.
#
# This chore deliberately does not touch `owner_id`. `owner_id` is
# retained during the deprecation window; removal happens in a later
# stage (see ADR-012, Stage 2 Unit B/C).
#
# Run via HousekeepingJob:
#   HousekeepingJob.perform('Onetime::Organization', :standardize_owner_id)

module Onetime
  module Chores
    # Constants namespaced here (rather than at top level) so that other
    # chore files loaded via Dir.glob can use the same generic names
    # without "already initialized constant" warnings.
    module StandardizeOwnerId
      # No constants needed yet — the logic is purely structural.
      # Reserved for future per-org overrides if any arise.
    end
  end
end

Onetime::Organization.chore :standardize_owner_id do |org|
  logger     = Onetime.get_logger('Chores')
  owner_id   = org.owner_id.to_s.strip
  created_by = org.created_by.to_s.strip

  # Branch 1: already in sync (both set, equal) → silent no-op.
  next if !created_by.empty? && created_by == owner_id

  # Branch 3a: both empty → can't backfill, warn and skip.
  if owner_id.empty? && created_by.empty?
    logger.warn 'Skipping organization with no owner_id or created_by',
      chore: :standardize_owner_id,
      org_extid: org.extid
    next
  end

  # Branch 3b: both present but disagree → don't overwrite, warn.
  if !owner_id.empty? && !created_by.empty? && owner_id != created_by
    logger.warn 'Skipping inconsistent owner_id and created_by',
      chore: :standardize_owner_id,
      org_extid: org.extid,
      owner_id: owner_id,
      created_by: created_by
    next
  end

  # Branch 3c: created_by present but owner_id missing → unexpected; warn.
  # We don't backfill owner_id from created_by because owner_id is the
  # source of truth during the deprecation window.
  if owner_id.empty?
    logger.warn 'Skipping organization with created_by but no owner_id',
      chore: :standardize_owner_id,
      org_extid: org.extid,
      created_by: created_by
    next
  end

  # Branch 2: created_by missing, owner_id present → backfill.
  logger.info 'Backfilling created_by from owner_id',
    chore: :standardize_owner_id,
    org_extid: org.extid,
    owner_id: owner_id

  org.created_by = owner_id
  org.save
  true
end

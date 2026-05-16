# lib/onetime/models/organization/chores/standardize_planid.rb
#
# frozen_string_literal: true

# Housekeeping chore: Normalize legacy planid values to current billing catalog.
#
# Valid current values (from etc/billing.yaml):
#   - free_v1           (default free tier)
#   - identity_plus_v1  (paid individual)
#   - legacy_plan_v1    (grandfathered)
#
# Legacy values this chore handles:
#   - nil/empty → free_v1
#   - 'free'    → free_v1
#   - 'basic'   → free_v1
#
# Values left alone (handled by dedicated migrations or already valid):
#   - 'identity'        (pro-bono migration: migrate_probono_accounts_command.rb)
#   - '*_v1' suffixed   (already in current format)
#
# Run via HousekeepingJob:
#   HousekeepingJob.perform('Onetime::Organization', :standardize_planid)
#
Onetime::Organization.chore :standardize_planid do |org|
  logger  = Onetime.get_logger('Chores')
  current = org.planid.to_s.strip

  # Already valid v1 format - skip
  next if current.end_with?('_v1')

  # Map legacy values to current catalog
  corrected_value = case current
              when '', 'free', 'basic'
                'free_v1'
              when 'identity', 'identity_plus', 'identity_plus_v1_monthly', 'identity_plus_v1_yearly', 'identity_monthly', 'identity_yearly'
                'identity_plus_v1'
              else
                logger.info 'Skipping unknown planid',
                  chore: :standardize_planid,
                  org_extid: org.extid,
                  planid: current
                nil
              end

  next unless corrected_value

  logger.info 'Normalizing planid',
    chore: :standardize_planid,
    org_extid: org.extid,
    from: current,
    to: corrected_value

  # Use the fast writer to update the single field
  org.planid! corrected_value
  true
end

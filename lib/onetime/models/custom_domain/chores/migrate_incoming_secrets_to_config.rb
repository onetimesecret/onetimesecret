# lib/onetime/models/custom_domain/chores/migrate_incoming_secrets_to_config.rb
#
# frozen_string_literal: true

# Housekeeping chore: Copy legacy `incoming_secrets` JSON blob entries on
# CustomDomain into corresponding Onetime::CustomDomain::IncomingConfig
# Familia records.
#
# Background:
#   Prior to #3095, per-domain incoming-secrets recipients were stored as a
#   JSON blob in the CustomDomain `incoming_secrets` jsonkey and wrapped by
#   the (now-removed) IncomingSecretsConfig class. The newer IncomingConfig
#   Familia model is the canonical store. This chore bridges existing data
#   into the new model so the resolver — which no longer falls back to the
#   legacy blob — can find recipients for previously configured domains.
#
# Behaviour (all idempotent, all fail-soft):
#
#   1. domain has no legacy blob (nil/empty string)  → silent skip
#   2. blob is malformed JSON                        → log + skip, no raise
#   3. blob has no recipients (missing key / empty)  → log + skip
#   4. IncomingConfig already exists for the domain  → log + skip (no overwrite)
#   5. legacy recipients present, no IncomingConfig  → create record, log
#   6. IncomingConfig.create! raises Onetime::Problem → log + skip, no raise
#
# Unexpected exceptions are NOT swallowed here; they propagate to
# HousekeepingJob#run_chores_for which counts them as errors and continues.
#
# Run via the housekeeping CLI:
#   bin/ots housekeeping perform Onetime::CustomDomain migrate_incoming_secrets_to_config
#
# Remove this chore (and the `jsonkey :incoming_secrets` field declaration on
# CustomDomain) after telemetry confirms all production domains have an
# IncomingConfig record.

Onetime::CustomDomain.chore :migrate_incoming_secrets_to_config do |domain|
  logger     = Onetime.get_logger('Chores')
  chore_name = :migrate_incoming_secrets_to_config

  legacy_json = domain.incoming_secrets&.value
  next if legacy_json.to_s.empty?

  begin
    parsed = JSON.parse(legacy_json)
  rescue JSON::ParserError => ex
    logger.info 'Migration failed: corrupted legacy blob',
      chore: chore_name,
      domain_extid: domain.extid,
      error: ex.message
    next
  end

  legacy_recipients = parsed.is_a?(Hash) ? parsed['recipients'] : nil
  if !legacy_recipients.is_a?(Array) || legacy_recipients.empty?
    logger.info 'Skipping empty legacy blob',
      chore: chore_name,
      domain_extid: domain.extid
    next
  end

  existing = Onetime::CustomDomain::IncomingConfig.find_by_domain_id(domain.identifier)
  if existing
    logger.info 'Skipping (already migrated)',
      chore: chore_name,
      domain_extid: domain.extid
    next
  end

  begin
    Onetime::CustomDomain::IncomingConfig.create!(
      domain_id: domain.identifier,
      enabled: true,
      recipients: legacy_recipients,
    )
  rescue Onetime::Problem => ex
    logger.info 'Migration failed',
      chore: chore_name,
      domain_extid: domain.extid,
      error: ex.message
    next
  end

  logger.info 'Migrated incoming recipients',
    chore: chore_name,
    domain_extid: domain.extid,
    recipients_count: legacy_recipients.size

  true
end

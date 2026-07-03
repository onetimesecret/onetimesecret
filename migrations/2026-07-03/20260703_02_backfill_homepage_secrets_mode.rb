# migrations/2026-07-03/20260703_02_backfill_homepage_secrets_mode.rb
#
# frozen_string_literal: true

#
# Backfill the homepage secrets_mode field on existing custom domains.
#
# HomepageConfig gained a `secrets_mode` field ('create' | 'incoming') that
# selects which interactive experience an enabled homepage presents:
# the classic secret-creation form ('create', the historical behavior) or
# the incoming-secrets form ('incoming'). Records that pre-date the field
# have no stored value; the read path (HomepageConfig#secrets_mode_value)
# coerces nil/unknown to 'create', so legacy domains already behave
# correctly without this migration.
#
# This backfill persists the explicit 'create' default onto every existing
# HomepageConfig record so the stored data is self-describing: operators
# inspecting Redis (or future migrations iterating these records) see the
# actual mode rather than having to know the nil-means-create rule.
#
# Idempotent: records that already carry a recognised secrets_mode are
# skipped, so re-running touches nothing. The `updated` timestamp is NOT
# advanced: backfilling the equivalent-by-coercion default is not a
# semantic change, and bumping it would surface a fresh updated_at on
# every legacy domain's bootstrap/workspace payloads.
#
# Usage:
#   bin/ots migrate 20260703_02_backfill_homepage_secrets_mode           # Preview
#   bin/ots migrate --run 20260703_02_backfill_homepage_secrets_mode     # Execute
#
require 'familia/migration'

module Onetime
  module Migrations
    # Persist the explicit 'create' secrets_mode default onto HomepageConfig
    # records that pre-date the field.
    class BackfillHomepageSecretsMode < Familia::Migration::Base
      self.migration_id = '20260703_02_backfill_homepage_secrets_mode'
      self.description  = 'Backfill secrets_mode=create on existing custom domain homepage configs'
      self.dependencies = []

      def prepare
        @model_class  = Onetime::CustomDomain
        @config_class = Onetime::CustomDomain::HomepageConfig
      end

      # Migration is needed while any domain's HomepageConfig lacks a
      # recognised stored secrets_mode. Stable once applied: every processed
      # record carries 'create' or 'incoming' afterwards.
      def migration_needed?
        @model_class.instances.each do |domain_id|
          config = @config_class.find_by_domain_id(domain_id)
          next unless config

          return true unless mode_present?(config)
        rescue StandardError => ex
          # Surface the discovery error but keep scanning so one corrupt
          # record cannot mask a genuine pending migration.
          error "migration_needed? error for #{domain_id}: #{ex.message}"
        end

        false
      end

      # Progress reporting threshold: emit a running breakdown every N domains
      # processed, matching the step used by the other homepage-config
      # migrations so operator output stays consistent.
      PROGRESS_STEP = 250

      def migrate
        run_mode_banner

        total     = @model_class.instances.count
        processed = 0

        @model_class.instances.each do |domain_id|
          process_domain(domain_id)
        rescue StandardError => ex
          track_stat(:errors)
          error "Error processing domain #{domain_id}: #{ex.message}"
        ensure
          processed += 1
          report_progress(processed, total)
        end

        print_summary do |mode|
          @stats.each { |key, value| info "  #{key}: #{value}" }
          info ''
          info(mode == :dry_run ? 'Re-run with --run to apply changes.' : 'Homepage secrets_mode backfilled.')
        end

        true
      end

      private

      # A recognised stored value means the record post-dates the field (or a
      # prior run already backfilled it). Blank/unknown values still need the
      # explicit default persisted.
      def mode_present?(config)
        Onetime::CustomDomain::HomepageConfig::VALID_SECRETS_MODES.include?(config.secrets_mode.to_s)
      end

      def report_progress(processed, total)
        return unless total >= PROGRESS_STEP
        return unless (processed % PROGRESS_STEP).zero? || processed == total

        breakdown = @stats.map { |k, v| "#{k}=#{v}" }.join(', ')
        info "Progress: #{processed}/#{total} (#{breakdown})"
      end

      def process_domain(domain_id)
        config = @config_class.find_by_domain_id(domain_id)
        unless config
          # Post-#3023 every domain should carry a HomepageConfig; a missing
          # record means nothing to backfill (the read path already coerces).
          track_stat(:skipped_missing_config)
          return
        end

        if mode_present?(config)
          track_stat(:already_set)
          return
        end

        if dry_run?
          track_stat(:would_backfill)
          info "[DRY RUN] would set secrets_mode=create for #{domain_id} " \
               "(current=#{config.secrets_mode.inspect})"
          return
        end

        config.secrets_mode = Onetime::CustomDomain::HomepageConfig::DEFAULT_SECRETS_MODE
        # commit_fields (not save): save runs prepare_for_save, which stamps
        # `updated = Familia.now` unconditionally. Backfilling the
        # equivalent-by-coercion default is not a semantic change, so the
        # stored timestamp must survive; commit_fields writes the loaded
        # fields back verbatim plus the new secrets_mode.
        config.commit_fields

        track_stat(:backfilled)
        info "Backfilled secrets_mode=create for #{domain_id}"
      end
    end
  end
end

# Run directly
if __FILE__ == $0
  OT.boot! :cli
  exit(Onetime::Migrations::BackfillHomepageSecretsMode.cli_run)
end

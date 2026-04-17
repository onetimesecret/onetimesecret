# migrations/2026-04-17/20260417_01_backfill_homepage_config.rb
#
# frozen_string_literal: true

#
# Backfill CustomDomain::HomepageConfig from legacy BrandSettings
#
# The v0.24 -> v0.25 change moved `allow_public_homepage` from BrandSettings
# (a hashkey field on CustomDomain.brand) into a dedicated
# CustomDomain::HomepageConfig record without a release-time backfill.
# The UI serializer and API read HomepageConfig directly (no fallback in
# those paths), so domains that were toggled ON under v0.24 render as
# disabled under v0.25 until a HomepageConfig record exists.
#
# Production was mitigated manually via bin/console with equivalent logic;
# this migration encodes that mitigation for the release process itself and
# is safe to re-run (domains with an existing HomepageConfig are skipped).
#
# Usage:
#   bin/ots migrate 20260417_01_backfill_homepage_config           # Preview
#   bin/ots migrate --run 20260417_01_backfill_homepage_config     # Execute
#
# Refs: #3023
require 'familia/migration'

module Onetime
  module Migrations
    # Create HomepageConfig records for CustomDomains that only carry the
    # legacy BrandSettings#allow_public_homepage value.
    class BackfillHomepageConfig < Familia::Migration::Base
      self.migration_id = '20260417_01_backfill_homepage_config'
      self.description  = 'Backfill CustomDomain::HomepageConfig from legacy BrandSettings.allow_public_homepage'
      self.dependencies = []

      def prepare
        @model_class  = Onetime::CustomDomain
        @config_class = Onetime::CustomDomain::HomepageConfig
      end

      def migration_needed?
        @model_class.instances.each do |domain_id|
          next if @config_class.exists_for_domain?(domain_id)

          # Per #3023: any domain without a HomepageConfig record needs backfill,
          # regardless of the legacy brand_settings.allow_public_homepage value.
          # The legacy value only determines the enabled flag written during
          # migrate, not whether migration is needed. This ensures the legacy
          # fallback at CustomDomain#allow_public_homepage? can be removed in
          # a future release once every domain carries a real HomepageConfig.
          domain = @model_class.find_by_identifier(domain_id)
          return true if domain
        rescue StandardError => ex
          # Surface the discovery error but keep scanning so one corrupt
          # record cannot mask a genuine pending migration.
          error "migration_needed? error for #{domain_id}: #{ex.message}"
        end

        false
      end

      # Stat-key naming note
      #
      # Keys :would_migrate_true / :would_migrate_false / :migrated_true /
      # :migrated_false deliberately deviate from the 2025-07-27 convention of
      # past-tense action nouns (e.g. :backup_created, :symbols_converted,
      # :records_updated). The boolean split is retained for production
      # observability: operators can verify the true/false ratio matches
      # expectations, and if :migrated_true stays at zero across runs, the
      # legacy fallback at CustomDomain#allow_public_homepage? is provably
      # unused and safe to remove.
      def migrate
        run_mode_banner

        @model_class.instances.each do |domain_id|
          process_domain(domain_id)
        rescue StandardError => ex
          track_stat(:errors)
          error "Error processing domain #{domain_id}: #{ex.message}"
        end

        print_summary do |mode|
          @stats.each { |key, value| info "  #{key}: #{value}" }
          info ''
          info(mode == :dry_run ? 'Re-run with --run to apply changes.' : 'Backfill complete.')
        end

        true
      end

      private

      def process_domain(domain_id)
        if @config_class.exists_for_domain?(domain_id)
          track_stat(:skipped_existing)
          info "Skip (existing HomepageConfig): #{domain_id}"
          return
        end

        domain = @model_class.find_by_identifier(domain_id)
        unless domain
          track_stat(:skipped_missing_domain)
          info "Skip (domain not found): #{domain_id}"
          return
        end

        legacy_enabled = domain.brand_settings.allow_public_homepage?

        if dry_run?
          track_stat(legacy_enabled ? :would_migrate_true : :would_migrate_false)
          info "[DRY RUN] would upsert HomepageConfig(domain_id=#{domain_id}, enabled=#{legacy_enabled})"
        else
          @config_class.upsert(domain_id: domain_id, enabled: legacy_enabled)
          track_stat(legacy_enabled ? :migrated_true : :migrated_false)
          info "Upserted HomepageConfig(domain_id=#{domain_id}, enabled=#{legacy_enabled})"
        end
      end
    end
  end
end

# Run directly
if __FILE__ == $0
  OT.boot! :cli
  exit(Onetime::Migrations::BackfillHomepageConfig.cli_run)
end

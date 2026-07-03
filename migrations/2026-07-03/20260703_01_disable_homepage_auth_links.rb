# migrations/2026-07-03/20260703_01_disable_homepage_auth_links.rb
#
# frozen_string_literal: true

#
# Disable the homepage auth nav links (Create Account / Sign In) on all
# existing custom domains.
#
# The per-domain signup_enabled/signin_enabled toggles on
# CustomDomain::HomepageConfig originally defaulted to ON: the #3023 backfill
# and CustomDomain.create! both persisted a literal `true` into every record,
# and the model/serializer/frontend all read that value as "show the link".
# The result was that the Create Account and Sign In links appeared on every
# custom-domain homepage — confusing for recipients and employees who only
# ever arrive via a shared secret link.
#
# The default was flipped to OFF (conservative, mirroring
# SigninConfig/SignupConfig): new domains now hide the links until an operator
# opts in via PUT /homepage-config. But existing domains carry a persisted
# `true`, so a code-only default change cannot reach them — the stored value
# still wins at read time. This migration resets that persisted value.
#
# For every CustomDomain that has a HomepageConfig record, this flips
# signup_enabled/signin_enabled from true to false. A deliberate opt-in is
# indistinguishable from the historical default (both are a bare `true`), so
# all currently-enabled records are reset; operators re-enable the links per
# domain via the existing PUT /homepage-config endpoint afterwards.
#
# Idempotent: records already fully off (both flags false/nil) are skipped, so
# re-running touches nothing.
#
# Usage:
#   bin/ots migrate 20260703_01_disable_homepage_auth_links           # Preview
#   bin/ots migrate --run 20260703_01_disable_homepage_auth_links     # Execute
#
require 'familia/migration'

module Onetime
  module Migrations
    # Reset persisted HomepageConfig signup_enabled/signin_enabled to false so
    # the homepage auth nav links default to hidden on existing custom domains.
    class DisableHomepageAuthLinks < Familia::Migration::Base
      self.migration_id = '20260703_01_disable_homepage_auth_links'
      self.description  = 'Disable homepage Create Account / Sign In links on existing custom domains'
      self.dependencies = []

      def prepare
        @model_class  = Onetime::CustomDomain
        @config_class = Onetime::CustomDomain::HomepageConfig
      end

      # Migration is needed while any domain's HomepageConfig still reports an
      # enabled signup or signin link. Predicates are conservative (only a
      # literal boolean true reads as enabled), so this is stable once applied.
      def migration_needed?
        @model_class.instances.each do |domain_id|
          config = @config_class.find_by_domain_id(domain_id)
          next unless config

          return true if config.signup_enabled? || config.signin_enabled?
        rescue StandardError => ex
          # Surface the discovery error but keep scanning so one corrupt
          # record cannot mask a genuine pending migration.
          error "migration_needed? error for #{domain_id}: #{ex.message}"
        end

        false
      end

      # Progress reporting threshold: emit a running breakdown every N domains
      # processed. Matches the 250-domain step used by the #3023 backfill so
      # operator output stays consistent across the homepage-config migrations.
      PROGRESS_STEP = 250

      def migrate
        run_mode_banner

        # ZCARD on CustomDomain.instances — O(1), worth the one-time cost so
        # progress output can show current/total.
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
          info(mode == :dry_run ? 'Re-run with --run to apply changes.' : 'Homepage auth links disabled.')
        end

        true
      end

      private

      # Emit a periodic progress line with a running stat breakdown so
      # operators can watch long-running resets. Only logs at the step
      # boundary or the final iteration; stays silent below the threshold
      # to avoid noise on small datasets.
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
          # record means nothing to reset (the read path already fails closed).
          track_stat(:skipped_missing_config)
          return
        end

        # Already-off records (both flags false or nil) need no write — keeps
        # the migration idempotent and preserves their `updated` timestamp.
        unless config.signup_enabled? || config.signin_enabled?
          track_stat(:already_off)
          return
        end

        if dry_run?
          track_stat(:would_disable)
          info "[DRY RUN] would disable homepage auth links for #{domain_id} " \
               "(signup=#{config.signup_enabled?}, signin=#{config.signin_enabled?})"
          return
        end

        config.signup_enabled = false
        config.signin_enabled = false
        config.updated        = Familia.now.to_i
        config.save

        track_stat(:disabled)
        info "Disabled homepage auth links for #{domain_id}"
      end
    end
  end
end

# Run directly
if __FILE__ == $0
  OT.boot! :cli
  exit(Onetime::Migrations::DisableHomepageAuthLinks.cli_run)
end

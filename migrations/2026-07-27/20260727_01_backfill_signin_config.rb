# migrations/2026-07-27/20260727_01_backfill_signin_config.rb
#
# frozen_string_literal: true

#
# Backfill CustomDomain::SigninConfig for domains that predate v0.26
#
# CustomDomain::SigninConfig and the fail-closed custom-domain resolution
# (SigninConfig.resolve_signin_enabled_for_custom_domain) are new in v0.26.x.
# Under v0.25.11 the POST /signin runtime gate on custom domains followed the
# global AUTH_ENABLED/AUTH_SIGNIN settings; under v0.26.x a custom domain with
# no *enabled* SigninConfig record refuses sign-in entirely. The v0.25.11 ->
# v0.26.2 upgrade shipped no backfill, so every domain whose users signed in
# on-domain lost sign-in at upgrade (customer-visible as
# `web.login.signin_disabled_message`). Production was mitigated per-domain
# via bin/console; this migration encodes the grandfathering step for the
# release process itself.
#
# Field values (all four booleans true) are chosen to reproduce the exact
# pre-upgrade resolution, no more and no less. An *enabled* SigninConfig makes
# every field authoritative with no inheritance, so a bare
# `enabled: true, signin_enabled: true` would silently narrow the other
# surfaces relative to v0.25.11:
#
#   signin_enabled: true      -> resolve_signin_enabled returns
#                                `global && true` == global: the pre-upgrade
#                                follow-global behavior. The install-level
#                                kill switch still wins (AND semantics).
#   email_auth_enabled: true  -> resolve_email_auth_enabled returns global,
#                                as it did pre-upgrade. `false` would turn
#                                magic-link UI off wherever global is on.
#   sso_enabled: true         -> sso_permitted_for? stays permissive and
#                                defers to SsoConfig credentials, matching
#                                the no-record behavior. `false` on an
#                                enabled record is authoritative and would
#                                BREAK tenant SSO for domains with a working
#                                SsoConfig (tenant_sso_available_for? checks
#                                sso_permitted_for? first).
#   restrict_to: (unset)      -> no method restriction existed pre-upgrade.
#
# Nothing is force-enabled: every resolver ANDs with the global capability,
# so a globally-disabled method stays disabled.
#
# Scope: SigninConfig only. The other six per-domain config kinds need no
# deploy-time backfill — see the release notes / migration review for the
# per-kind rationale (homepage/api are bootstrapped at domain creation and
# covered by 20260417_01; incoming's absent-record semantics are unchanged
# since v0.25.11; signup's fail-closed flip is deliberate product intent per
# 20260703_01; sso/mailer absent means platform fallback by design).
#
# Timing caveat (run-once expectation): like 20260417_01 this migration is
# idempotent by absence (existing SigninConfig records are never touched) and
# is intended to run ONCE at upgrade time, when every existing domain
# predates v0.26 by definition. Unlike HomepageConfig/ApiConfig, domain
# creation does NOT bootstrap a SigninConfig record, so a LATE run would also
# flip domains created after the upgrade that legitimately carry the new
# fail-closed default. For late runs, bound the backfill explicitly:
#
#   SIGNIN_BACKFILL_CREATED_BEFORE=<epoch seconds | Time.parse-able string>
#
# Domains whose `created` timestamp is at or after the cutoff are skipped
# (counted as :skipped_created_after_cutoff). Unset (the default) means no
# cutoff, matching the 20260417_01 run-once stance.
#
# Usage (full-path form works regardless of which migrations/20* directory is
# newest — the bare-ID form only finds migrations in the latest directory):
#   bin/ots migrate migrations/2026-07-27/20260727_01_backfill_signin_config           # Preview
#   bin/ots migrate migrations/2026-07-27/20260727_01_backfill_signin_config --run     # Execute
#
# Refs: v0.25.11->v0.26.2 custom-domain sign-in regression (2026-07-27),
#       ADR-024 / ADR-030 (custom-domain auth resolution, fail-closed opt-in)
require 'time'
require 'familia/migration'

module Onetime
  module Migrations
    # Create enabled, follow-global SigninConfig records for CustomDomains
    # that predate the v0.26 fail-closed custom-domain sign-in default.
    class BackfillSigninConfig < Familia::Migration::Base
      self.migration_id = '20260727_01_backfill_signin_config'
      self.description  = 'Backfill enabled CustomDomain::SigninConfig for domains that predate the v0.26 fail-closed default'
      self.dependencies = []

      # Attribute set that reproduces v0.25.11 resolution exactly (see file
      # header). Symbol keys: consumed by SigninConfig.create! keyword logic
      # in pure Ruby, never serialized as-is.
      BACKFILL_ATTRS = {
        enabled: true,
        signin_enabled: true,
        email_auth_enabled: true,
        sso_enabled: true,
      }.freeze

      def prepare
        @model_class  = Onetime::CustomDomain
        @config_class = Onetime::CustomDomain::SigninConfig
        @cutoff_epoch = parse_cutoff!(ENV['SIGNIN_BACKFILL_CREATED_BEFORE'])
      end

      # Needed while any in-scope domain lacks a SigninConfig record.
      # Domains excluded by the cutoff do not count toward "needed".
      def migration_needed?
        @model_class.instances.each do |domain_id|
          next if @config_class.exists_for_domain?(domain_id)

          domain = @model_class.find_by_identifier(domain_id)
          next unless domain
          next if created_after_cutoff?(domain)

          return true
        rescue StandardError => ex
          # Surface the discovery error but keep scanning so one corrupt
          # record cannot mask a genuine pending migration.
          error "migration_needed? error for #{domain_id}: #{ex.message}"
        end

        false
      end

      # Progress reporting threshold: emit a running breakdown every N domains
      # processed. Matches the 250-domain step used by the earlier
      # custom-domain config migrations so operator output stays consistent.
      PROGRESS_STEP = 250

      def migrate
        run_mode_banner
        info "Cutoff: created < #{Time.at(@cutoff_epoch).utc.iso8601} (SIGNIN_BACKFILL_CREATED_BEFORE)" if @cutoff_epoch

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
          info(mode == :dry_run ? 'Re-run with --run to apply changes.' : 'Backfill complete.')
        end

        true
      end

      private

      # Parse the optional late-run cutoff. Fail fast and loud on an
      # unparseable value rather than silently backfilling everything.
      #
      # @param raw [String, nil] epoch seconds or a Time.parse-able string
      # @return [Integer, nil] epoch seconds, or nil when no cutoff is set
      def parse_cutoff!(raw)
        return nil if raw.to_s.strip.empty?

        return Integer(raw) if raw.match?(/\A\d+\z/)

        Time.parse(raw).to_i
      rescue ArgumentError => ex
        raise Onetime::Problem, "SIGNIN_BACKFILL_CREATED_BEFORE is not parseable (#{raw.inspect}): #{ex.message}"
      end

      # A missing/blank created timestamp reads as 0 and is always in scope:
      # a record too old to carry the field certainly predates v0.26.
      def created_after_cutoff?(domain)
        return false unless @cutoff_epoch

        domain.created.to_i >= @cutoff_epoch
      end

      # Emit a periodic progress line with a running stat breakdown so
      # operators can watch long-running backfills. Only logs at the step
      # boundary or the final iteration; stays silent below the threshold
      # to avoid noise on small datasets.
      def report_progress(processed, total)
        return unless total >= PROGRESS_STEP
        return unless (processed % PROGRESS_STEP).zero? || processed == total

        breakdown = @stats.map { |k, v| "#{k}=#{v}" }.join(', ')
        info "Progress: #{processed}/#{total} (#{breakdown})"
      end

      def process_domain(domain_id)
        if @config_class.exists_for_domain?(domain_id)
          track_stat(:skipped_existing)
          info "Skip (existing SigninConfig): #{domain_id}"
          return
        end

        domain = @model_class.find_by_identifier(domain_id)
        unless domain
          track_stat(:skipped_missing_domain)
          info "Skip (domain not found): #{domain_id}"
          return
        end

        if created_after_cutoff?(domain)
          track_stat(:skipped_created_after_cutoff)
          info "Skip (created after cutoff): #{domain_id} (#{domain.display_domain})"
          return
        end

        if dry_run?
          track_stat(:would_create)
          info "[DRY RUN] would create SigninConfig(domain_id=#{domain_id}, enabled=true, signin_enabled=true, " \
               "email_auth_enabled=true, sso_enabled=true) for #{domain.display_domain}"
          return
        end

        create_config(domain_id, domain)
      end

      # SigninConfig.create! is check-then-set (no WATCH), so a concurrent
      # writer (e.g. a self-serve PUT /signin-config) can land between our
      # exists? check and the create!. Treat that as skipped-existing — the
      # concurrent writer's explicit values win over the backfill default.
      def create_config(domain_id, domain)
        @config_class.create!(domain_id: domain_id, **BACKFILL_ATTRS)
        track_stat(:created)
        info "Created SigninConfig(domain_id=#{domain_id}) for #{domain.display_domain}"
      rescue Onetime::Problem
        raise unless @config_class.exists_for_domain?(domain_id)

        track_stat(:skipped_existing)
        info "Skip (created concurrently): #{domain_id}"
      end
    end
  end
end

# Run directly
if __FILE__ == $0
  OT.boot! :cli
  exit(Onetime::Migrations::BackfillSigninConfig.cli_run)
end

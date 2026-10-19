# migrations/2026-10-15/20261015_01_rename_ascii_display_domain_index.rb
#
# frozen_string_literal: true

#
# Rename the custom domain A-label index key
#
# The index that holds one entry per custom domain DNS name, keyed by the
# lower-case A-label form (v0.26.14, #4780), was declared as
# CustomDomain.canonical_display_domain_index and stored at
# custom_domain:canonical_display_domain_index. "Canonical" already names
# the install's own site host in this codebase (refuse_canonical_overlap!,
# DomainStrategy's :canonical), so the index is now ascii_display_domain_index
# at custom_domain:ascii_display_domain_index, and the commands, doctor
# findings and runbook call it the ASCII index.
#
# The application reads and writes the new key only. On an install that has
# the old key, until this migration runs, domains registered since v0.26.14
# have no entry under the new key: display_domain_id_for still finds them by
# the exact display_domain_index, but the creation gate and the doctor audit
# see an empty index, so a second registration of such a name in its other
# spelling is not refused. Run this with the application stopped, before
# starting the release that carries it.
#
# RENAMENX moves the key atomically and refuses to overwrite. When a
# destination already exists (a backfill or a registration ran on the new
# release before this migration), that rename is refused and both keys are
# reported: merge them by hand, or remove the destination and run the
# backfill again after the rename. The runbook's backup key
# (<old key>:before-backfill) is renamed the same way when present. The two
# renames are independent, so a refusal of one leaves the other where it
# landed; the summary says which keys moved, and a rerun after clearing the
# refused destination finishes the job. A refusal fails the run: migrate
# returns false (the runner does not record it as applied) and down raises
# (the runner would otherwise clear the applied mark whatever down returns).
#
# Usage:
#   bin/ots migrate migrations/2026-10-15/20261015_01_rename_ascii_display_domain_index.rb         # Preview
#   bin/ots migrate migrations/2026-10-15/20261015_01_rename_ascii_display_domain_index.rb --run   # Execute
#   bin/ots migrate --rollback 20261015_01_rename_ascii_display_domain_index --run                 # Rename back
#
# Refs: #4780 (the index), docs/runbooks/custom-domain-ascii-index-backfill.md
require 'familia/migration'

module Onetime
  module Migrations
    # Rename custom_domain:canonical_display_domain_index (and its runbook
    # backup) to custom_domain:ascii_display_domain_index.
    class RenameAsciiDisplayDomainIndex < Familia::Migration::Base
      self.migration_id = '20261015_01_rename_ascii_display_domain_index'
      self.description  = 'Rename custom_domain:canonical_display_domain_index to custom_domain:ascii_display_domain_index'
      self.dependencies = []

      # The runbook's rollback copy of the index.
      BACKUP_SUFFIX = ':before-backfill'

      def prepare
        index    = Onetime::CustomDomain.ascii_display_domain_index
        @client  = index.dbclient
        @new_key = index.dbkey
        @old_key = @new_key.sub('ascii_display_domain_index', 'canonical_display_domain_index')
        raise "unexpected index key #{@new_key.inspect}" if @old_key == @new_key
      end

      def migration_needed?
        key_pairs(@old_key, @new_key).any? { |from, _| @client.exists?(from) }
      end

      def migrate
        run_mode_banner
        ok = rename_all(@old_key, @new_key)
        summary(ok)
        ok
      end

      # The runner records a rollback whatever down returns, so a refused
      # rename raises to keep the migration marked applied for a retry.
      def down
        run_mode_banner
        ok = rename_all(@new_key, @old_key)
        summary(ok)
        return true if ok

        raise Familia::Migration::Errors::MigrationError, failure_message
      end

      private

      def key_pairs(from, to)
        [[from, to], ["#{from}#{BACKUP_SUFFIX}", "#{to}#{BACKUP_SUFFIX}"]]
      end

      # Each pair independently: a refused index rename does not stop the
      # backup rename, and the result is false when any pair was refused.
      def rename_all(from, to)
        key_pairs(from, to).map { |source, target| rename(source, target) }.all?
      end

      def rename(from, to)
        unless @client.exists?(from)
          info "#{from}: absent, nothing to rename"
          track_stat(:absent)
          return true
        end

        entries = @client.hlen(from)
        if @client.exists?(to)
          error "#{to} already exists (#{@client.hlen(to)} entries) and #{from} has #{entries}; " \
                'not renamed. Merge them by hand, or remove the target and run again.'
          track_stat(:refused)
          return false
        end

        if dry_run?
          info "[DRY RUN] RENAMENX #{from} -> #{to} (#{entries} entries)"
          track_stat(:would_rename)
          return true
        end

        if @client.renamenx(from, to)
          info "Renamed #{from} -> #{to} (#{entries} entries)"
          track_stat(:renamed)
          true
        else
          error "#{to} appeared before the rename; #{from} left in place"
          track_stat(:refused)
          false
        end
      end

      # The two renames are independent, so a refusal after a rename leaves
      # the keys half moved; say so rather than "nothing changed".
      def failure_message
        renamed = @stats[:renamed].to_i
        refused = @stats[:refused].to_i
        if renamed.positive?
          "#{renamed} rename(s) landed and #{refused} refused; see above. The renamed keys stay " \
            'renamed. Clear the refused destination, then run again to finish.'
        else
          "#{refused} rename(s) refused; see above. Nothing was changed."
        end
      end

      def summary(ok)
        print_summary do |mode|
          @stats.each { |key, value| info "  #{key}: #{value}" }
          info ''
          if !ok
            info failure_message
          elsif mode == :dry_run
            info 'Re-run with --run to rename.'
          else
            info 'Rename complete.'
          end
        end
      end
    end
  end
end

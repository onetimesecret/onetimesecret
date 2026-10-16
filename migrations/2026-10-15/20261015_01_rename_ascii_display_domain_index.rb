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
# RENAMENX moves the key atomically and refuses to overwrite. When the new
# key already exists (a backfill or a registration ran on the new release
# before this migration), both keys are reported and nothing is renamed:
# merge them by hand, or remove the new key and run the backfill again
# after the rename. The runbook's backup key (<old key>:before-backfill) is
# renamed the same way when present.
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

      def down
        run_mode_banner
        ok = rename_all(@new_key, @old_key)
        summary(ok)
        ok
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

      def summary(ok)
        print_summary do |mode|
          @stats.each { |key, value| info "  #{key}: #{value}" }
          info ''
          if !ok
            info 'A rename was refused; see above. Nothing else was changed.'
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

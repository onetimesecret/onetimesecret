# lib/onetime/operations/domains/canonical_index_audit.rb
#
# frozen_string_literal: true

# Domain-owned (app-scoped) diagnostic operation — see decision D3 in
# lib/onetime/operations/README.md. Lives alongside the incumbent domain ops in
# lib/onetime/operations, under the Domains:: namespace.

module Onetime
  module Operations
    module Domains
      # Compare every custom domain record with
      # CustomDomain.canonical_display_domain_index, the index that holds one
      # entry per DNS name (its lower-case A-label form) and that create! and
      # CustomDomain::IdentityGuard claim for new records.
      #
      # The index arrived after records already existed, and nothing entered
      # those records into it. This audit reports where the index and the
      # records disagree. {CanonicalIndexBackfill} acts on the result, and
      # `bin/ots domains doctor` reports it.
      #
      # READ-ONLY: no writes and no {Onetime::ColonelAuditEvent}.
      #
      # ## Categories
      #
      # One row per record:
      #
      #   :ok             the entry for the record's A-label names this record
      #   :missing        there is no entry for the record's A-label
      #   :collision      two or more records share the A-label; every record
      #                   in the group gets this category, whatever the entry says
      #   :conflict       the entry names a different record that exists
      #   :stale          the entry names a record that no longer exists
      #   :unconvertible  the record's name is blank or has no A-label form
      #
      # Plus one entry per index field that no record row accounts for (its
      # key is no record's A-label):
      #
      #   :stale          it names a record that no longer exists
      #   :conflict       it names a record whose own name maps elsewhere
      #
      # ## Enumeration
      #
      # Records are found by SCAN over `custom_domain:*:object`, the pattern
      # the maintenance jobs use, rather than the `instances` sorted set: SCAN
      # also finds records that are missing from `instances`, and `instances`
      # adds only members whose records are gone. SCAN does not block the
      # server, and records are loaded in pipelined batches.
      class CanonicalIndexAudit
        CATEGORIES = [:ok, :missing, :collision, :conflict, :stale, :unconvertible].freeze

        # Categories an operator has to resolve; the backfill never writes
        # them.
        ATTENTION_CATEGORIES = [:collision, :conflict].freeze

        SCAN_BATCH = 500

        # @!attribute category [r] Symbol, one of CATEGORIES
        # @!attribute canonical [r] String, nil — the A-label; nil when :unconvertible
        # @!attribute holder_id [r] String, nil — identifier the index entry names
        # @!attribute verified_confirmed_at [r] Integer, nil — epoch seconds of
        #   the last passing TXT check (DNS proof); ownership_verified alone may
        #   be an operator override
        Row = Data.define(
          :category,
          :domain_id,
          :extid,
          :display_domain,
          :canonical,
          :holder_id,
          :org_id,
          :verification_state,
          :ownership_verified,
          :verified_by_override,
          :verified_confirmed_at,
          :created,
          :detail,
        )

        # An index field that no record row accounts for.
        Entry = Data.define(:category, :canonical, :holder_id, :detail)

        # A record that exists but could not be loaded.
        Unreadable = Data.define(:domain_id, :message)

        Result = Data.define(:rows, :entries, :errors) do
          def count(category)
            rows.count { |row| row.category == category } + entries.count { |entry| entry.category == category }
          end

          def counts
            CATEGORIES.to_h { |category| [category, count(category)] }
          end

          def rows_in(category)
            rows.select { |row| row.category == category }
          end

          def entries_in(category)
            entries.select { |entry| entry.category == category }
          end

          # @return [Hash{String => Array<Row>}] A-label => records sharing it
          def collision_groups
            rows_in(:collision).group_by(&:canonical)
          end

          # Whether anything needs an operator: collisions, conflicts, or
          # records that could not be loaded.
          def attention?
            ATTENTION_CATEGORIES.any? { |category| count(category).positive? } || errors.any?
          end

          # Whether the index already agrees with every record.
          def clean?
            counts.except(:ok, :unconvertible).values.all?(&:zero?) && errors.empty?
          end
        end

        # @return [Result]
        def call
          records, errors = load_records
          holders         = index.hgetall
          rows            = classify_records(records, holders)
          entries         = classify_unmatched_entries(holders, rows, records)

          Result.new(rows: rows, entries: entries, errors: errors)
        end

        private

        def model
          Onetime::CustomDomain
        end

        def index
          model.canonical_display_domain_index
        end

        def client
          model.dbclient
        end

        # @return [Array(Hash{String => CustomDomain}, Array<Unreadable>)]
        def load_records
          records = {}
          errors  = []

          scan_identifiers.each_slice(SCAN_BATCH) do |batch|
            load_batch(batch).each do |identifier, outcome|
              if outcome.is_a?(Unreadable)
                errors << outcome
              elsif outcome
                records[identifier] = outcome
              end
            end
          end

          [records, errors]
        end

        def scan_identifiers
          prefix = "#{model.prefix}:"
          suffix = ":#{model.suffix}"
          ids    = []

          client.scan_each(match: "#{prefix}*#{suffix}", count: SCAN_BATCH) do |key|
            identifier = key.delete_prefix(prefix).delete_suffix(suffix)
            # Records' identifiers carry no delimiter; anything else under the
            # pattern belongs to a different key shape.
            ids << identifier unless identifier.empty? || identifier.include?(':')
          end

          ids.uniq.sort
        end

        # load_multi raises for the whole batch when one hash cannot be
        # deserialised, so a failed batch is retried one record at a time.
        def load_batch(batch)
          batch.zip(model.load_multi(batch))
        rescue StandardError => ex
          OT.le "[Domains::CanonicalIndexAudit] Batch load failed (#{ex.class}); loading one at a time"
          batch.map { |identifier| [identifier, load_one(identifier)] }
        end

        def load_one(identifier)
          model.find_by_identifier(identifier)
        rescue StandardError => ex
          Unreadable.new(domain_id: identifier, message: "#{ex.class}: #{ex.message}")
        end

        def canonical_for(display_domain)
          return nil if display_domain.to_s.empty?

          model.canonical_display_domain(display_domain)
        rescue Onetime::DomainValidation::AsciiHostname::ConversionError
          nil
        end

        def classify_records(records, holders)
          canonicals = records.transform_values { |record| canonical_for(record.display_domain) }
          groups     = canonicals.compact.group_by { |_id, canonical| canonical }.transform_values(&:size)

          rows = records.map do |identifier, record|
            canonical        = canonicals[identifier]
            holder           = canonical && holders[canonical]
            category, detail = categorize(identifier, canonical, holder, groups, records)
            build_row(identifier, record, category, canonical, holder, detail)
          end

          rows.sort_by { |row| [row.canonical.to_s, row.display_domain.to_s, row.domain_id.to_s] }
        end

        def categorize(identifier, canonical, holder, groups, records)
          return [:unconvertible, 'name is blank or has no A-label form'] if canonical.nil?

          shared = groups.fetch(canonical, 0)
          return [:collision, "#{shared} records share #{canonical}"] if shared > 1
          return [:missing, nil] if holder.nil?
          return [:ok, nil] if holder == identifier

          if records.key?(holder) || record_exists?(holder)
            [:conflict, "entry names #{holder}, #{describe_holder(records[holder])}"]
          else
            [:stale, "entry names #{holder}, which no longer exists"]
          end
        end

        def describe_holder(holder_record)
          return 'which exists but could not be loaded' unless holder_record

          "stored as #{holder_record.display_domain.to_s.inspect}"
        end

        # The identifier is the one from the record's key, not record.identifier:
        # a hash without an objid field would otherwise get a generated one (and
        # an extid derived from it).
        def build_row(identifier, record, category, canonical, holder, detail)
          Row.new(
            category: category,
            domain_id: identifier,
            extid: record.objid.to_s == identifier ? record.extid : nil,
            display_domain: record.display_domain,
            canonical: canonical,
            holder_id: holder,
            org_id: record.org_id.to_s.empty? ? nil : record.org_id,
            verification_state: record.verification_state,
            ownership_verified: record.ownership_verified ? true : false, # boolean_field native
            verified_by_override: record.verified_by_override ? true : false, # boolean_field native
            verified_confirmed_at: record.verified_confirmed_at,
            created: record.created,
            detail: detail,
          )
        end

        # Index fields keyed by a name that no record has.
        def classify_unmatched_entries(holders, rows, records)
          matched = rows.filter_map(&:canonical).to_set

          entries = holders.filter_map do |canonical, holder|
            next if matched.include?(canonical)

            if records.key?(holder) || record_exists?(holder)
              Entry.new(
                category: :conflict,
                canonical: canonical,
                holder_id: holder,
                detail: "no record is named #{canonical}; the entry names #{holder}, #{describe_holder(records[holder])}",
              )
            else
              Entry.new(
                category: :stale,
                canonical: canonical,
                holder_id: holder,
                detail: "no record is named #{canonical}; the entry names #{holder}, which no longer exists",
              )
            end
          end

          entries.sort_by(&:canonical)
        end

        def record_exists?(identifier)
          return false if identifier.to_s.empty?

          client.exists?(model.dbkey(identifier))
        end
      end
    end
  end
end

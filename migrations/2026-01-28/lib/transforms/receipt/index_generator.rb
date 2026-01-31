# migrations/2026-01-28/lib/transforms/receipt/index_generator.rb
#
# frozen_string_literal: true

module Migration
  module Transforms
    module Receipt
      # Generates index commands for Receipt records.
      #
      # Creates the following indexes:
      #   - receipt:instances (ZADD score=created member=objid)
      #   - receipt:expiration_timeline (ZADD score=expires_at member=objid)
      #   - receipt:objid_lookup (HSET objid -> "objid")
      #   - customer:{owner_id}:receipts (ZADD score=created member=objid)
      #   - organization:{org_id}:receipts (ZADD score=created member=objid)
      # NOTE: customdomain:{domain_id}:receipts is managed by Familia v2 at runtime
      #
      # Usage in Kiba job:
      #   transform Receipt::IndexGenerator, stats: stats
      #
      class IndexGenerator < IndexGeneratorBase
        def generate_indexes(record)
          commands = []
          objid = record[:objid]
          v2_fields = record[:v2_fields] || {}
          created = extract_created(record)

          # Owner/org/domain IDs are in v2_fields, not at record level
          owner_id = v2_fields['owner_id']
          org_id = v2_fields['org_id']
          domain_id = v2_fields['domain_id']

          # Instance index: receipt:instances (sorted set)
          commands << zadd('receipt:instances', created, objid)
          increment_stat(:receipt_instance_entries)

          # Expiration timeline: receipt:expiration_timeline
          add_expiration_index(commands, v2_fields, objid, created)

          # ObjID lookup: receipt:objid_lookup
          commands << hset('receipt:objid_lookup', objid, objid)
          increment_stat(:receipt_objid_lookups)

          # Customer receipts relationship
          if owner_id && !owner_id.empty? && owner_id != 'anon'
            commands << zadd("customer:#{owner_id}:receipts", created, objid)
            increment_stat(:customer_receipt_entries)
          else
            increment_stat(:anonymous_receipts)
          end

          # Organization receipts relationship
          if org_id && !org_id.empty?
            commands << zadd("organization:#{org_id}:receipts", created, objid)
            increment_stat(:org_receipt_entries)
          end

          # NOTE: customdomain:{domain_id}:receipts is NOT generated here.
          # This sorted_set is auto-managed by Familia v2's participates_in
          # mechanism at runtime. See Receipt.participates_in :CustomDomain, :receipts

          commands
        end

        private

        def add_expiration_index(commands, v2_fields, objid, created)
          # Calculate expiration from secret_ttl or lifespan
          secret_ttl = v2_fields['secret_ttl'] || v2_fields['lifespan']
          ttl = secret_ttl.to_i

          return unless ttl.positive? && created.positive?

          expires_at = created + ttl
          commands << zadd('receipt:expiration_timeline', expires_at, objid)
          increment_stat(:receipt_expiration_entries)
        end
      end
    end
  end
end

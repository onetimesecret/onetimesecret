# migrations/2026-01-28/lib/transforms/customer/index_generator.rb
#
# frozen_string_literal: true

module Migration
  module Transforms
    module Customer
      # Generates index commands for Customer records.
      #
      # Creates the following indexes:
      #   - customer:instances (ZADD score=created member=objid)
      #   - customer:email_index (HSET email -> "objid")
      #   - customer:extid_lookup (HSET extid -> "objid")
      #   - customer:objid_lookup (HSET objid -> "objid")
      #   - customer:role_index:{role} (SADD objid)
      #
      # Counter aggregation (secrets_created, etc.) is handled separately
      # in a post-processing step since it requires totaling across all records.
      #
      # Usage in Kiba job:
      #   transform Customer::IndexGenerator, stats: stats
      #
      class IndexGenerator < IndexGeneratorBase
        VALID_ROLES = %w[colonel customer anonymous recipient].freeze

        def generate_indexes(record)
          commands = []
          objid = record[:objid]
          extid = record[:extid]
          v2_fields = record[:v2_fields] || {}
          created = extract_created(record)

          # Instance index: customer:instances (sorted set)
          commands << zadd('customer:instances', created, objid)
          increment_stat(:customer_instance_entries)

          # Email lookup: customer:email_index
          email = v2_fields['email']
          if email && !email.empty?
            commands << hset('customer:email_index', email, objid)
            increment_stat(:customer_email_lookups)
          end

          # ExtID lookup: customer:extid_lookup
          if extid && !extid.empty?
            commands << hset('customer:extid_lookup', extid, objid)
            increment_stat(:customer_extid_lookups)
          end

          # ObjID lookup: customer:objid_lookup
          commands << hset('customer:objid_lookup', objid, objid)
          increment_stat(:customer_objid_lookups)

          # Role index: customer:role_index:{role}
          role = v2_fields['role']
          if role && VALID_ROLES.include?(role)
            commands << sadd("customer:role_index:#{role}", objid)
            increment_stat(:customer_role_entries)
          end

          commands
        end
      end
    end
  end
end

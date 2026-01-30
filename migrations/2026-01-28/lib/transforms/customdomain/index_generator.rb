# migrations/2026-01-28/lib/transforms/customdomain/index_generator.rb
#
# frozen_string_literal: true

module Migration
  module Transforms
    module Customdomain
      # Generates index commands for CustomDomain records.
      #
      # Creates the following indexes:
      #   - customdomain:instances (ZADD score=created member=objid)
      #   - customdomain:display_domain_index (HSET fqdn -> "objid")
      #   - customdomain:display_domains (HSET fqdn -> "objid") [compat]
      #   - customdomain:extid_lookup (HSET extid -> "objid")
      #   - customdomain:objid_lookup (HSET objid -> "objid")
      #   - customdomain:owners (HSET objid -> "org_id")
      #   - organization:{org_id}:domains (ZADD score=created member=objid)
      #
      # Usage in Kiba job:
      #   transform Customdomain::IndexGenerator, stats: stats
      #
      class IndexGenerator < IndexGeneratorBase
        def generate_indexes(record)
          commands = []
          objid = record[:objid]
          extid = record[:extid]
          org_id = record[:org_id]
          v2_fields = record[:v2_fields] || {}
          created = extract_created(record)

          # Instance index: customdomain:instances (sorted set)
          commands << zadd('customdomain:instances', created, objid)
          increment_stat(:domain_instance_entries)

          # Display domain lookups
          display_domain = v2_fields['display_domain'] || record[:display_domain]
          if display_domain && !display_domain.empty?
            commands << hset('customdomain:display_domain_index', display_domain, objid)
            # Compatibility alias
            commands << hset('customdomain:display_domains', display_domain, objid)
            increment_stat(:domain_display_lookups)
          end

          # ExtID lookup: customdomain:extid_lookup
          if extid && !extid.empty?
            commands << hset('customdomain:extid_lookup', extid, objid)
            increment_stat(:domain_extid_lookups)
          end

          # ObjID lookup: customdomain:objid_lookup
          commands << hset('customdomain:objid_lookup', objid, objid)
          increment_stat(:domain_objid_lookups)

          # Owner mapping: customdomain:owners (objid -> org_id)
          if org_id && !org_id.empty?
            commands << hset('customdomain:owners', objid, org_id)
            increment_stat(:domain_owner_mappings)

            # Organization participation: organization:{org_id}:domains
            commands << zadd("organization:#{org_id}:domains", created, objid)
            increment_stat(:org_domain_participations)
          end

          commands
        end
      end
    end
  end
end

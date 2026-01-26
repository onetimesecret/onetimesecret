# frozen_string_literal: true

require_relative 'base'

module IndexRebuilder
  # Builds Customer model indexes:
  # - customer:instances (zset: objid -> created)
  # - customer:email_index (hash: email -> objid)
  # - customer:extid_lookup (hash: extid -> objid)
  class CustomerIndexes < Base
    def build_all
      build_instances
      build_email_index
      build_extid_lookup
    end

    def build_instances
      build_instances_set('customer', 'customer')
    end

    def build_email_index
      puts '  Building customer:email_index...'

      index_key = 'customer:email_index'
      count     = 0

      scan_keys('customer:*:object') do |key|
        email = valkey.hget(key, 'email')
        objid = valkey.hget(key, 'objid')

        next if email.to_s.empty? || objid.to_s.empty?

        unless dry_run
          valkey.hset(index_key, email, objid)
        end
        count += 1
      end

      puts "    Added #{count} entries to #{index_key}"
      stats[:unique_indexes][:created] += count
    end

    def build_extid_lookup
      puts '  Building customer:extid_lookup...'

      lookup_key = 'customer:extid_lookup'
      count      = 0

      scan_keys('customer:*:object') do |key|
        objid = valkey.hget(key, 'objid')
        next if objid.to_s.empty?

        # Generate extid if not present
        extid = valkey.hget(key, 'extid')
        if extid.to_s.empty?
          extid = generate_extid(EXTID_PREFIXES[:customer], objid)
          valkey.hset(key, 'extid', extid) unless dry_run
        end

        unless dry_run
          valkey.hset(lookup_key, extid, objid)
        end
        count += 1
      end

      puts "    Added #{count} entries to #{lookup_key}"
      stats[:extid_lookups][:created] += count
    end
  end
end

# frozen_string_literal: true

require_relative 'base'

module IndexRebuilder
  # Builds CustomDomain model indexes:
  # - customdomain:instances (zset: domainid -> created)
  # - customdomain:display_domain_index (hash: display_domain -> domainid)
  # - customdomain:display_domains (hash: display_domain -> domainid, class hashkey)
  # - customdomain:owners (hash: domainid -> org_id)
  # - customdomain:{domainid}:receipts (zset: receipt_id -> created)
  class CustomdomainIndexes < Base
    def build_all
      build_instances
      build_display_domain_index
    end

    def build_class_hashkeys
      build_display_domains
      build_owners
    end

    def build_participation_sets
      build_receipts_sets
    end

    def build_instances
      build_instances_set('customdomain', 'customdomain')
    end

    def build_display_domain_index
      puts '  Building customdomain:display_domain_index...'

      index_key = 'customdomain:display_domain_index'
      count     = 0

      scan_keys('customdomain:*:object') do |key|
        display_domain = valkey.hget(key, 'display_domain')
        domainid       = key.split(':')[1] # Extract from key pattern

        next if display_domain.to_s.empty?

        unless dry_run
          valkey.hset(index_key, display_domain, domainid)
        end
        count += 1
      end

      puts "    Added #{count} entries to #{index_key}"
      stats[:unique_indexes][:created] += count
    end

    # Build customdomain:display_domains hash (display_domain -> domainid)
    # This is the class_hashkey used by CustomDomain.load_by_display_domain
    # Note: This is separate from display_domain_index (unique_index)
    def build_display_domains
      puts '  Building customdomain:display_domains...'

      hashkey = 'customdomain:display_domains'
      count   = 0

      scan_keys('customdomain:*:object') do |key|
        display_domain = valkey.hget(key, 'display_domain')
        domainid       = key.split(':')[1] # Extract from key pattern

        next if display_domain.to_s.empty?

        unless dry_run
          valkey.hset(hashkey, display_domain, domainid)
        end
        count += 1
      end

      puts "    Added #{count} entries to #{hashkey}"
      stats[:class_hashkeys][:created] += count
    end

    # Build customdomain:owners hash (domainid -> org_id)
    # Used for cascade delete operations (find domains when org is deleted)
    def build_owners
      puts '  Building customdomain:owners...'

      hashkey = 'customdomain:owners'
      count   = 0

      scan_keys('customdomain:*:object') do |key|
        domainid = key.split(':')[1] # Extract from key pattern
        org_id   = valkey.hget(key, 'org_id')

        next if org_id.to_s.empty?

        unless dry_run
          valkey.hset(hashkey, domainid, org_id)
        end
        count += 1
      end

      puts "    Added #{count} entries to #{hashkey}"
      stats[:class_hashkeys][:created] += count
    end

    def build_receipts_sets
      puts '  Building customdomain:{domainid}:receipts sets...'

      count = 0

      scan_keys('receipt:*:object') do |key|
        domain_id  = valkey.hget(key, 'domain_id')
        receipt_id = key.split(':')[1]
        created    = valkey.hget(key, 'created') || Time.now.to_f

        next if domain_id.to_s.empty?

        receipts_key = "customdomain:#{domain_id}:receipts"

        unless dry_run
          valkey.zadd(receipts_key, created.to_f, receipt_id)
        end
        count += 1
      end

      puts "    Added #{count} receipt entries to domain sets"
      stats[:participation_sets][:created] += count
    end
  end
end

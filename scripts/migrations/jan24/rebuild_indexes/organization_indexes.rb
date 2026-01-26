# frozen_string_literal: true

require_relative 'base'

module IndexRebuilder
  # Builds Organization model indexes:
  # - organization:instances (zset: objid -> created)
  # - organization:contact_email_index (hash: contact_email -> objid)
  # - organization:extid_lookup (hash: extid -> objid)
  # - organization:stripe_customer_id_index (hash: stripe_customer_id -> objid)
  # - organization:stripe_subscription_id_index (hash: stripe_subscription_id -> objid)
  # - organization:{objid}:members (zset: customer_objid -> joined_at)
  # - organization:{objid}:domains (zset: domain_id -> created)
  # - organization:{objid}:receipts (zset: receipt_id -> created)
  class OrganizationIndexes < Base
    def build_all
      build_instances
      build_contact_email_index
      build_extid_lookup
      build_stripe_customer_id_index
      build_stripe_subscription_id_index
    end

    def build_participation_sets
      build_members_sets
      build_domains_sets
      build_receipts_sets
    end

    def build_instances
      build_instances_set('organization', 'organization')
    end

    def build_contact_email_index
      puts '  Building organization:contact_email_index...'

      index_key = 'organization:contact_email_index'
      count     = 0

      scan_keys('organization:*:object') do |key|
        contact_email = valkey.hget(key, 'contact_email')
        objid         = valkey.hget(key, 'objid')

        next if contact_email.to_s.empty? || objid.to_s.empty?

        unless dry_run
          valkey.hset(index_key, contact_email, objid)
        end
        count += 1
      end

      puts "    Added #{count} entries to #{index_key}"
      stats[:unique_indexes][:created] += count
    end

    def build_extid_lookup
      puts '  Building organization:extid_lookup...'

      lookup_key = 'organization:extid_lookup'
      count      = 0

      scan_keys('organization:*:object') do |key|
        objid = valkey.hget(key, 'objid')
        next if objid.to_s.empty?

        # Generate extid if not present
        extid = valkey.hget(key, 'extid')
        if extid.to_s.empty?
          extid = generate_extid(EXTID_PREFIXES[:organization], objid)
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

    def build_stripe_customer_id_index
      puts '  Building organization:stripe_customer_id_index...'

      index_key = 'organization:stripe_customer_id_index'
      count     = 0

      scan_keys('organization:*:object') do |key|
        stripe_customer_id = valkey.hget(key, 'stripe_customer_id')
        objid              = valkey.hget(key, 'objid')

        next if stripe_customer_id.to_s.empty? || objid.to_s.empty?

        unless dry_run
          valkey.hset(index_key, stripe_customer_id, objid)
        end
        count += 1
      end

      puts "    Added #{count} entries to #{index_key}"
      stats[:stripe_indexes][:created] += count
    end

    def build_stripe_subscription_id_index
      puts '  Building organization:stripe_subscription_id_index...'

      index_key = 'organization:stripe_subscription_id_index'
      count     = 0

      scan_keys('organization:*:object') do |key|
        stripe_subscription_id = valkey.hget(key, 'stripe_subscription_id')
        objid                  = valkey.hget(key, 'objid')

        next if stripe_subscription_id.to_s.empty? || objid.to_s.empty?

        unless dry_run
          valkey.hset(index_key, stripe_subscription_id, objid)
        end
        count += 1
      end

      puts "    Added #{count} entries to #{index_key}"
      stats[:stripe_indexes][:created] += count
    end

    def build_members_sets
      puts '  Building organization:{objid}:members sets...'

      count = 0

      scan_keys('org_membership:*:object') do |key|
        membership = valkey.hgetall(key)

        org_objid      = membership['organization_objid']
        customer_objid = membership['customer_objid']
        joined_at      = membership['joined_at'] || Time.now.to_f

        next if org_objid.to_s.empty? || customer_objid.to_s.empty?

        members_key = "organization:#{org_objid}:members"

        unless dry_run
          valkey.zadd(members_key, joined_at.to_f, customer_objid)
        end
        count += 1
      end

      puts "    Added #{count} member entries"
      stats[:participation_sets][:created] += count
    end

    def build_domains_sets
      puts '  Building organization:{objid}:domains sets...'

      count = 0

      scan_keys('customdomain:*:object') do |key|
        org_id    = valkey.hget(key, 'org_id')
        domain_id = key.split(':')[1]
        created   = valkey.hget(key, 'created') || Time.now.to_f

        next if org_id.to_s.empty?

        domains_key = "organization:#{org_id}:domains"

        unless dry_run
          valkey.zadd(domains_key, created.to_f, domain_id)
        end
        count += 1
      end

      puts "    Added #{count} domain entries"
      stats[:participation_sets][:created] += count
    end

    def build_receipts_sets
      puts '  Building organization:{objid}:receipts sets...'

      count = 0

      scan_keys('receipt:*:object') do |key|
        org_id     = valkey.hget(key, 'org_id')
        receipt_id = key.split(':')[1]
        created    = valkey.hget(key, 'created') || Time.now.to_f

        next if org_id.to_s.empty?

        receipts_key = "organization:#{org_id}:receipts"

        unless dry_run
          valkey.zadd(receipts_key, created.to_f, receipt_id)
        end
        count += 1
      end

      puts "    Added #{count} receipt entries to organization sets"
      stats[:participation_sets][:created] += count
    end
  end
end

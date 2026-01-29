# frozen_string_literal: true

require 'digest'

module Migration
  module Transforms
    module Organization
      # Generates organization records from customer data.
      #
      # Organizations are NEW in V2 - one is created per Customer.
      # Uses deterministic UUID generation from customer objid to ensure
      # re-running the migration produces identical results.
      #
      # Input:  Customer record with objid, extid, v2_fields (or fields)
      # Output: Organization record with objid, extid, v2_fields
      #
      # Usage in Kiba job:
      #   transform Organization::Generator,
      #             stats: stats,
      #             migrated_at: job_started_at
      #
      class Generator < BaseTransform
        EXTID_PREFIX = 'on'

        attr_reader :migrated_at

        # @param migrated_at [Time, nil] Timestamp for migration tracking (default: now)
        # @param kwargs [Hash] Additional options passed to BaseTransform
        #
        def initialize(migrated_at: nil, **kwargs)
          super(**kwargs)
          @migrated_at = migrated_at || Time.now
          @uuid_generator = Shared::UuidV7Generator.new
        end

        # Generate organization record from customer.
        #
        # @param record [Hash] Customer record with objid and fields/v2_fields
        # @return [Hash] Organization record
        #
        def process(record)
          key = record[:key]

          # Only process customer :object records
          unless key&.end_with?(':object') && key&.start_with?('customer:')
            increment_stat(:skipped_non_customer_object)
            return nil
          end

          customer_objid = record[:objid]
          unless customer_objid && !customer_objid.empty?
            increment_stat(:skipped_no_objid)
            record[:generation_error] = 'Missing customer objid'
            return nil
          end

          # Extract customer fields (prefer v2_fields from Phase 1 output)
          customer_fields = extract_customer_fields(record)
          unless customer_fields
            increment_stat(:skipped_no_fields)
            record[:generation_error] = 'Missing customer fields'
            return nil
          end

          # Generate organization
          generate_organization(customer_objid, customer_fields, record)
        end

        private

        def extract_customer_fields(record)
          # After decode, data is in :fields (decoder always writes there)
          # v2_fields is only present before encode step
          record[:fields] || record[:v2_fields]
        end

        def generate_organization(customer_objid, customer_fields, customer_record)
          # Use customer's created timestamp for org (inherits creation time)
          created = extract_created_timestamp(customer_fields, customer_record)

          # Generate deterministic org_objid from customer_objid
          org_objid = generate_org_objid_from_customer(customer_objid, created)
          org_extid = @uuid_generator.derive_extid(org_objid, prefix: EXTID_PREFIX)

          # Extract fields from customer
          email = extract_email(customer_fields)
          stripe_customer_id = customer_fields['stripe_customer_id']
          stripe_subscription_id = customer_fields['stripe_subscription_id']
          stripe_checkout_email = customer_fields['stripe_checkout_email']
          planid = customer_fields['planid'] || 'free'

          # Track Stripe stats
          increment_stat(:stripe_customers) if stripe_customer_id&.start_with?('cus_')
          increment_stat(:stripe_subscriptions) if stripe_subscription_id&.start_with?('sub_')

          # Build organization fields
          v2_fields = build_org_fields(
            org_objid: org_objid,
            org_extid: org_extid,
            customer_objid: customer_objid,
            email: email,
            planid: planid,
            created: created,
            stripe_customer_id: stripe_customer_id,
            stripe_subscription_id: stripe_subscription_id,
            stripe_checkout_email: stripe_checkout_email,
            customer_fields: customer_fields,
            customer_record: customer_record
          )

          increment_stat(:organizations_generated)

          {
            key: "organization:#{org_objid}:object",
            type: 'hash',
            ttl_ms: -1, # Organizations don't expire
            db: customer_record[:db],
            objid: org_objid,
            extid: org_extid,
            owner_id: customer_objid,
            contact_email: email,
            created: created,
            v2_fields: v2_fields,
          }
        end

        def build_org_fields(org_objid:, org_extid:, customer_objid:, email:,
                             planid:, created:, stripe_customer_id:,
                             stripe_subscription_id:, stripe_checkout_email:,
                             customer_fields:, customer_record:)
          fields = {
            'objid' => org_objid,
            'extid' => org_extid,
            'display_name' => derive_display_name(email),
            'description' => nil,
            'owner_id' => customer_objid,
            'contact_email' => email,
            'billing_email' => email,
            'is_default' => 'true',
            'planid' => planid,
            'created' => created.to_s,
            'updated' => @migrated_at.to_f.to_s,

            # Billing fields from customer
            'stripe_customer_id' => stripe_customer_id,
            'stripe_subscription_id' => stripe_subscription_id,
            'stripe_checkout_email' => stripe_checkout_email,

            # Migration tracking
            'v1_identifier' => customer_record[:key],
            'v1_source_custid' => customer_fields['v1_custid'] || customer_fields['email'],
            'migration_status' => 'completed',
            'migrated_at' => @migrated_at.to_f.to_s,
          }

          # Remove nil values
          fields.compact
        end

        def extract_created_timestamp(customer_fields, customer_record)
          # Try record-level first, then fields
          ts = customer_record[:created] || customer_fields['created']
          ts ? ts.to_f.to_i : Time.now.to_i
        end

        def extract_email(customer_fields)
          customer_fields['email'] || customer_fields['v1_custid'] || customer_fields['custid']
        end

        # Generate deterministic org_objid from customer_objid and timestamp.
        #
        # Uses UUIDv7 format with:
        # - Timestamp from customer's created date (preserves chronological ordering)
        # - Deterministic "random" bits derived from customer_objid (reproducible)
        #
        def generate_org_objid_from_customer(customer_objid, created_timestamp)
          # Create deterministic seed from customer objid
          seed = Digest::SHA256.digest("organization:#{customer_objid}")

          # Use customer's created timestamp for UUIDv7 time component
          timestamp_ms = (created_timestamp.to_f * 1000).to_i

          # Encode timestamp as 48-bit hex (12 hex chars)
          hex = timestamp_ms.to_s(16).rjust(12, '0')

          # Use deterministic PRNG seeded from customer objid
          prng = Random.new(seed.unpack1('Q>'))
          rand_bytes = prng.bytes(10)
          rand_hex = rand_bytes.unpack1('H*')

          # Construct UUID v7 parts
          time_hi = hex[0, 8]
          time_mid = hex[8, 4]
          ver_rand = '7' + rand_hex[0, 3]
          variant = ((rand_hex[4, 2].to_i(16) & 0x3F) | 0x80).to_s(16).rjust(2, '0') + rand_hex[6, 2]
          node = rand_hex[8, 12]

          "#{time_hi}-#{time_mid}-#{ver_rand}-#{variant}-#{node}"
        end

        def derive_display_name(email)
          return 'Default Workspace' unless email && !email.empty?

          # Extract domain part for display name
          domain = email.split('@').last
          if domain
            domain.split('.').first.capitalize + "'s Workspace"
          else
            'Default Workspace'
          end
        end
      end
    end
  end
end

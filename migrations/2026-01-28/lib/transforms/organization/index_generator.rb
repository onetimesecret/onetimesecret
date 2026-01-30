# migrations/2026-01-28/lib/transforms/organization/index_generator.rb
#
# frozen_string_literal: true

module Migration
  module Transforms
    module Organization
      # Generates index commands for Organization records.
      #
      # Creates the following indexes:
      #   - organization:instances (ZADD score=created member=objid)
      #   - organization:contact_email_index (HSET email -> "objid")
      #   - organization:extid_lookup (HSET extid -> "objid")
      #   - organization:objid_lookup (HSET objid -> "objid")
      #   - organization:stripe_customer_id_index (HSET cus_xxx -> "objid")
      #   - organization:stripe_subscription_id_index (HSET sub_xxx -> "objid")
      #   - organization:stripe_checkout_email_index (HSET email -> "objid")
      #   - organization:{objid}:members (ZADD score=created member=owner_id)
      #   - customer:{owner_id}:participations (SADD "organization:{objid}:members")
      #
      # Usage in Kiba job:
      #   transform Organization::IndexGenerator, stats: stats
      #
      class IndexGenerator < IndexGeneratorBase
        def generate_indexes(record)
          commands = []
          objid = record[:objid]
          extid = record[:extid]
          owner_id = record[:owner_id]
          v2_fields = record[:v2_fields] || {}
          created = extract_created(record)

          # Instance index: organization:instances (sorted set)
          commands << zadd('organization:instances', created, objid)
          increment_stat(:org_instance_entries)

          # Contact email lookup: organization:contact_email_index
          contact_email = v2_fields['contact_email']
          if contact_email && !contact_email.empty?
            commands << hset('organization:contact_email_index', contact_email, objid)
            increment_stat(:org_email_lookups)
          end

          # ExtID lookup: organization:extid_lookup
          if extid && !extid.empty?
            commands << hset('organization:extid_lookup', extid, objid)
            increment_stat(:org_extid_lookups)
          end

          # ObjID lookup: organization:objid_lookup
          commands << hset('organization:objid_lookup', objid, objid)
          increment_stat(:org_objid_lookups)

          # Stripe indexes
          add_stripe_indexes(commands, v2_fields, objid)

          # Members relationship: organization:{org_objid}:members
          # Owner is first member, score = created timestamp
          if owner_id && !owner_id.empty?
            commands << zadd("organization:#{objid}:members", created, owner_id)
            increment_stat(:org_member_entries)

            # Customer participation: customer:{owner_id}:participations
            # Tracks which org member sets this customer belongs to
            commands << sadd("customer:#{owner_id}:participations", "organization:#{objid}:members")
            increment_stat(:customer_participations)
          end

          commands
        end

        private

        def add_stripe_indexes(commands, v2_fields, objid)
          # Stripe customer ID index
          stripe_customer_id = v2_fields['stripe_customer_id']
          if stripe_customer_id && stripe_customer_id.start_with?('cus_')
            commands << hset('organization:stripe_customer_id_index', stripe_customer_id, objid)
            increment_stat(:org_stripe_customer_indexes)
          end

          # Stripe subscription ID index
          stripe_subscription_id = v2_fields['stripe_subscription_id']
          if stripe_subscription_id && stripe_subscription_id.start_with?('sub_')
            commands << hset('organization:stripe_subscription_id_index', stripe_subscription_id, objid)
            increment_stat(:org_stripe_subscription_indexes)
          end

          # Stripe checkout email index
          stripe_checkout_email = v2_fields['stripe_checkout_email']
          if stripe_checkout_email && !stripe_checkout_email.empty?
            commands << hset('organization:stripe_checkout_email_index', stripe_checkout_email, objid)
            increment_stat(:org_stripe_email_indexes)
          end
        end
      end
    end
  end
end

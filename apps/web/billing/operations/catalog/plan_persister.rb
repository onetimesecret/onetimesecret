# apps/web/billing/operations/catalog/plan_persister.rb
#
# frozen_string_literal: true

module Billing
  module Operations
    module Catalog
      # Persistence helpers for Stripe-to-Redis plan synchronization.
      #
      # Handles:
      # - Upsert from Stripe data (create or update)
      # - Stale plan pruning (soft-delete)
      # - Cache rebuild (price_id lookup index)
      # - Sync timestamp updates
      #
      # @example Upsert a plan from Stripe data
      #   PlanPersister.upsert_from_stripe_data(plan_data)
      #
      # @example Prune plans not in current sync
      #   PlanPersister.prune_stale_plans(current_ids)
      #
      module PlanPersister
        extend self

        # Upsert single plan from Stripe data
        #
        # Creates a new plan if it doesn't exist, or updates an existing one.
        # This pattern avoids the empty catalog window that occurs with clear+rebuild.
        #
        # @param plan_data [Hash] Plan data from extract_plan_data or webhook payload
        # @return [Plan] The upserted plan instance
        # rubocop:disable Metrics/PerceivedComplexity
        def upsert_from_stripe_data(plan_data)
          plan_id = plan_data[:plan_id]

          # Load existing or create new - handle missing entries gracefully
          existing = begin
            loaded = Billing::Plan.load(plan_id)
            loaded if loaded&.exists?
          rescue Familia::NoIdentifier
            # Plan hash missing but instances entry persisted - treat as new
            nil
          end

          # Check for stale update (out-of-order webhook delivery)
          # Only skip if BOTH timestamps are valid (> 0) AND the Stripe product
          # is the same. When stripe_product_id differs (cross-region replacement),
          # bypass the stale check so the new product always wins.
          # NOTE: nil == nil is true in Ruby - plans without a stripe_product_id
          # (e.g., config-only plans created before this field existed) are treated
          # as "same product", so the stale check still applies. This is the correct
          # safe default, avoiding accidental overwrites when product provenance is
          # unknown.
          if existing && plan_data[:stripe_updated_at]
            same_product     = existing.stripe_product_id == plan_data[:stripe_product_id]
            incoming_updated = plan_data[:stripe_updated_at].to_i
            existing_updated = existing.stripe_updated_at.to_i

            if same_product && incoming_updated > 0 && existing_updated > 0 && incoming_updated <= existing_updated
              OT.ld "[PlanPersister] Skipping stale update for #{plan_id} " \
                    "(same_product: #{same_product}, incoming: #{incoming_updated}, existing: #{existing_updated})"
              return existing
            end
          end

          plan = existing || Billing::Plan.new(plan_id: plan_id)

          # Apply family-level scalar fields from plan_data
          plan.stripe_product_id  = plan_data[:stripe_product_id]
          plan.name               = plan_data[:name]
          plan.tier               = plan_data[:tier]
          plan.currency           = plan_data[:currency]
          plan.region             = plan_data[:region]
          plan.tenancy            = plan_data[:tenancy]
          plan.display_order      = plan_data[:display_order]
          plan.show_on_plans_page = plan_data[:show_on_plans_page]
          plan.description        = plan_data[:description]
          plan.plan_code          = plan_data[:plan_code]
          plan.is_popular         = plan_data[:is_popular]
          plan.plan_name_label    = plan_data[:plan_name_label]
          plan.includes_plan      = plan_data[:includes_plan]
          plan.active             = plan_data[:active]
          plan.last_synced_at     = Time.now.to_i.to_s

          # Store stripe_updated_at for future stale update comparison
          plan.stripe_updated_at  = plan_data[:stripe_updated_at] || Time.now.to_i.to_s

          # Save scalar fields before writing collections (sets, hashkeys)
          # which write directly to Redis and expect the parent to exist.
          unless plan.save
            OT.le "[PlanPersister] Save FAILED for plan: #{plan_id}",
              {
                existing: !existing.nil?,
                region: plan_data[:region],
                stripe_product_id: plan_data[:stripe_product_id],
              }
            return plan
          end

          # Populate collections after save (these write directly to Redis)
          plan.entitlements.clear
          plan_data[:entitlements]&.each { |ent| plan.entitlements.add(ent) }

          plan.features.clear
          plan_data[:features]&.each { |feat| plan.features.add(feat) }

          plan.limits.clear
          plan_data[:limits]&.each do |resource, value|
            key              = "#{resource}.max"
            val              = value == -1 ? 'unlimited' : value.to_s
            plan.limits[key] = val
          end

          # Merge prices into hashkey (interval => JSON price data)
          # For updates, merge new intervals with existing; for new plans, set all
          plan_data[:prices]&.each do |interval, price_data|
            plan.prices[interval.to_s] = price_data.to_json
          end

          # Clear memoization cache so prices_hash reflects new data
          plan.instance_variable_set(:@prices_hash, nil)

          # Store Stripe data snapshot for recovery
          if plan_data[:stripe_snapshot]
            plan.stripe_data_snapshot.value = plan_data[:stripe_snapshot].to_json
          end

          action = existing ? 'Updated' : 'Created'
          OT.ld "[PlanPersister] #{action} plan: #{plan_id}"

          plan
        end
        # rubocop:enable Metrics/PerceivedComplexity

        # Remove plans not in current Stripe catalog
        #
        # Uses soft-delete pattern - marks plans as inactive rather than destroying.
        # Handles missing entries gracefully by removing orphaned instances entries.
        #
        # @param current_plan_ids [Array<String>] Plan IDs currently in Stripe catalog
        # @return [Integer] Number of plans marked stale or cleaned up
        def prune_stale_plans(current_plan_ids)
          all_cached_ids = Billing::Plan.instances.to_a
          stale_ids      = all_cached_ids - current_plan_ids
          pruned_count   = 0

          stale_ids.each do |plan_id|
            plan = Billing::Plan.load(plan_id)

            if plan&.exists?
              # Plan exists in Redis - soft-delete by marking inactive
              plan.active         = 'false'
              plan.last_synced_at = Time.now.to_i.to_s
              unless plan.save
                OT.le "[PlanPersister] Save FAILED for stale plan: #{plan_id}",
                  {
                    active: plan.active,
                    last_synced_at: plan.last_synced_at,
                    region: plan.region,
                    stripe_product_id: plan.stripe_product_id,
                  }
              end
              OT.li "[PlanPersister] Marked stale: #{plan_id}"
              pruned_count       += 1
            else
              # Plan hash missing - just remove orphaned instances entry
              Billing::Plan.instances.remove(plan_id)
              OT.ld "[PlanPersister] Removed orphaned entry: #{plan_id}"
              pruned_count += 1
            end
          rescue Familia::NoIdentifier => _ex
            # Object missing but load returned something invalid - clean up instances
            Billing::Plan.instances.remove(plan_id)
            OT.ld "[PlanPersister] Cleaned orphan entry: #{plan_id}"
            pruned_count += 1
          rescue StandardError => ex
            # Always clean up orphan entry on unexpected errors to prevent stale references
            Billing::Plan.instances.remove(plan_id)
            OT.le '[PlanPersister] Error processing stale plan (cleaned orphan)',
              {
                plan_id: plan_id,
                error: ex.message,
              }
          end

          OT.li "[PlanPersister] Pruned #{pruned_count} stale plans" if pruned_count.positive?
          pruned_count
        end

        # Rebuild the price ID cache
        #
        # Called after plan refresh to ensure cache is up to date.
        #
        # @return [Hash<String, Plan>] Rebuilt cache
        def rebuild_stripe_price_id_cache
          Billing::Plan.rebuild_stripe_price_id_cache
        end

        # Update the global catalog sync timestamp
        #
        # Called after successful Stripe sync to record when the catalog
        # was last refreshed. Stores Familia.now (Float) with JSON serialization
        # to preserve type. TTL matches CATALOG_TTL so the staleness check
        # in BillingCatalog initializer automatically triggers re-sync.
        #
        def update_catalog_sync_timestamp
          Billing::Plan.catalog_synced_at.value = Familia.now
        end
      end
    end
  end
end

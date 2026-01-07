# apps/api/colonel/logic/colonel/list_organizations.rb
#
# frozen_string_literal: true

require_relative '../base'

module ColonelAPI
  module Logic
    module Colonel
      # Lists organizations with billing sync health detection.
      #
      # Sync health helps identify organizations with potentially stale planid
      # after plan changes made via Stripe Dashboard/CLI (bypassing webhook flow).
      #
      # Sync status values:
      #   synced - Consistent state (active sub + paid plan, OR no sub + free plan)
      #   potentially_stale - Inconsistent state requiring investigation
      #   unknown - Cannot determine (no billing data yet)
      #
      class ListOrganizations < ColonelAPI::Logic::Base
        attr_reader :organizations, :total_count, :page, :per_page, :total_pages, :status_filter, :sync_status_filter

        FREE_PLAN_IDS = %w[free free_v1].freeze

        def process_params
          @page               = (params['page'] || 1).to_i
          @per_page           = (params['per_page'] || 50).to_i
          @per_page           = 100 if @per_page > 100 # Max 100 per page
          @page               = 1 if @page < 1
          @status_filter      = params['status']      # subscription_status filter
          @sync_status_filter = params['sync_status'] # synced, potentially_stale, unknown
        end

        def raise_concerns
          verify_one_of_roles!(colonel: true)
        end

        def process
          # Get all organizations using efficient loading
          all_org_ids = Onetime::Organization.instances.to_a
          all_orgs    = Onetime::Organization.load_multi(all_org_ids).compact

          # Build org data with sync status
          org_data_list = all_orgs.map { |org| build_org_data(org) }

          # Apply filters
          org_data_list = apply_filters(org_data_list)

          @total_count = org_data_list.size
          @total_pages = (@total_count.to_f / @per_page).ceil

          # Sort by created timestamp (most recent first)
          org_data_list.sort_by! { |data| -(data[:created] || 0) }

          # Paginate
          start_idx      = (@page - 1) * @per_page
          end_idx        = start_idx + @per_page - 1
          @organizations = org_data_list[start_idx..end_idx] || []

          success_data
        end

        private

        def build_org_data(org)
          owner      = org.owner
          created_ts = org.created.to_i
          updated_ts = org.updated.to_i if org.updated

          {
            org_id: org.objid,
            extid: org.extid,
            display_name: org.display_name,
            contact_email: org.contact_email,
            owner_id: org.owner_id,
            owner_email: owner&.obscure_email,
            member_count: org.member_count,
            domain_count: org.domain_count,
            is_default: org.is_default.to_s == 'true',
            created: created_ts,
            created_human: format_timestamp(created_ts),
            updated: updated_ts,
            updated_human: format_timestamp(updated_ts),
            # Billing fields
            planid: org.planid,
            stripe_customer_id: org.stripe_customer_id,
            stripe_subscription_id: org.stripe_subscription_id,
            subscription_status: org.subscription_status,
            subscription_period_end: org.subscription_period_end,
            billing_email: org.billing_email,
            # Computed sync health
            sync_status: compute_sync_status(org),
            sync_status_reason: compute_sync_status_reason(org),
          }
        end

        def format_timestamp(ts)
          return nil unless ts && ts.positive?

          Time.at(ts).utc.strftime('%Y-%m-%d %H:%M UTC')
        end

        # Compute sync health status based on billing state consistency
        #
        # @param org [Onetime::Organization] Organization to check
        # @return [String] 'synced', 'potentially_stale', or 'unknown'
        def compute_sync_status(org)
          planid              = org.planid.to_s
          subscription_id     = org.stripe_subscription_id.to_s
          subscription_status = org.subscription_status.to_s

          # No billing data yet -> unknown
          if planid.empty? && subscription_id.empty?
            return 'unknown'
          end

          has_active_subscription = %w[active trialing].include?(subscription_status)
          has_paid_plan           = !planid.empty? && !FREE_PLAN_IDS.include?(planid)
          has_free_plan           = planid.empty? || FREE_PLAN_IDS.include?(planid)

          # Consistent states
          if has_active_subscription && has_paid_plan
            return 'synced'
          end

          if !has_active_subscription && has_free_plan && subscription_id.empty?
            return 'synced'
          end

          # Canceled subscription + free plan is consistent
          if subscription_status == 'canceled' && has_free_plan
            return 'synced'
          end

          # Inconsistent states
          if has_active_subscription && has_free_plan
            # Active subscription but still on free plan -> likely missed webhook
            return 'potentially_stale'
          end

          if !has_active_subscription && has_paid_plan && subscription_status != 'past_due'
            # No active subscription but still showing paid plan -> stale
            return 'potentially_stale'
          end

          # Past due with paid plan is expected (payment issue, not sync issue)
          if subscription_status == 'past_due' && has_paid_plan
            return 'synced'
          end

          # Default to unknown for edge cases
          'unknown'
        end

        # Provide human-readable reason for sync status
        #
        # @param org [Onetime::Organization] Organization to check
        # @return [String, nil] Reason for the sync status
        def compute_sync_status_reason(org)
          planid              = org.planid.to_s
          subscription_status = org.subscription_status.to_s

          has_active_subscription = %w[active trialing].include?(subscription_status)
          has_paid_plan           = !planid.empty? && !FREE_PLAN_IDS.include?(planid)
          has_free_plan           = planid.empty? || FREE_PLAN_IDS.include?(planid)

          if has_active_subscription && has_free_plan
            return 'Active subscription but planid is free - possible missed webhook'
          end

          if !has_active_subscription && has_paid_plan && subscription_status != 'past_due'
            return 'Paid plan but no active subscription - may need downgrade'
          end

          nil
        end

        def apply_filters(org_data_list)
          result = org_data_list

          # Filter by subscription status
          if status_filter && !status_filter.empty?
            result = result.select { |data| data[:subscription_status] == status_filter }
          end

          # Filter by sync status
          if sync_status_filter && !sync_status_filter.empty?
            result = result.select { |data| data[:sync_status] == sync_status_filter }
          end

          result
        end

        def success_data
          {
            record: {},
            details: {
              organizations: organizations,
              pagination: {
                page: page,
                per_page: per_page,
                total_count: total_count,
                total_pages: total_pages,
              },
              filters: {
                status: status_filter,
                sync_status: sync_status_filter,
              },
            },
          }
        end
      end
    end
  end
end

# apps/web/billing/cli/products_update_command.rb
#
# frozen_string_literal: true

require_relative 'helpers'

module Onetime
  module CLI
    # Update Stripe product metadata
    #
    # NOTE: This command updates existing products only.
    # Product deletion is intentionally not implemented to prevent accidental data loss.
    # To delete products, use the Stripe CLI: stripe products delete PRODUCT_ID
    class BillingProductsUpdateCommand < Command
      include BillingHelpers

      desc 'Update Stripe product metadata (delete via: stripe products delete PRODUCT_ID)'

      argument :product_id, required: true, desc: 'Product ID (e.g., prod_xxx)'

      option :interactive, type: :boolean, default: false,
        desc: 'Interactive mode - prompt for all fields'

      option :plan_id, type: :string, desc: 'Plan ID'
      option :tier, type: :string, desc: 'Tier'
      option :region, type: :string, desc: 'Region'
      option :tenancy, type: :string, desc: 'Tenancy'
      option :entitlements, type: :string, desc: 'Entitlements (comma-separated)'
      option :display_order, type: :string, desc: 'Display order (lower = earlier)'
      option :show_on_plans_page, type: :boolean, desc: 'Show on plans page'
      option :limit_teams, type: :string, desc: 'Limit teams (-1 for unlimited)'
      option :limit_members_per_team, type: :string, desc: 'Limit members per team (-1 for unlimited)'
      option :limit_custom_domains, type: :string, desc: 'Limit custom domains (-1 for unlimited)'
      option :limit_secret_lifetime, type: :string, desc: 'Limit secret lifetime (seconds)'
      option :add_marketing_feature, type: :string, desc: 'Add marketing feature'
      option :remove_marketing_feature, type: :string, desc: 'Remove marketing feature (by ID)'

      def call(product_id:, interactive: false, **options)
        boot_application!

        return unless stripe_configured?

        product = Stripe::Product.retrieve(product_id)
        puts "Current product: #{product.name}"
        puts 'Current metadata:'
        product.metadata.each { |k, v| puts "  #{k}: #{v}" }
        puts

        # Extract marketing feature operations from options
        add_feature    = options.delete(:add_marketing_feature)
        remove_feature = options.delete(:remove_marketing_feature)

        metadata = if interactive
          prompt_for_metadata
        else
          # Build metadata hash - preserve existing values, ensure all fields exist
          current_meta = product.metadata.to_h

          # Start with current metadata
          updated_meta = current_meta.dup

          # Ensure required fields exist, preserving current values
          updated_meta['app']                  = 'onetimesecret'
          updated_meta['created']            ||= Time.now.utc.iso8601
          updated_meta['display_order']      ||= '100'
          updated_meta['show_on_plans_page'] ||= 'true'

          # Override ONLY with explicitly provided options (don't blank out existing values)
          updated_meta['plan_id']                = options[:plan_id] if options[:plan_id]
          updated_meta['tier']                   = options[:tier] if options[:tier]
          updated_meta['region']                 = options[:region] if options[:region]
          updated_meta['tenancy']                = options[:tenancy] if options[:tenancy]
          updated_meta['entitlements']           = options[:entitlements] if options[:entitlements]
          updated_meta['display_order']          = options[:display_order] if options[:display_order]
          updated_meta['show_on_plans_page']     = options[:show_on_plans_page].to_s if options.key?(:show_on_plans_page)
          updated_meta['limit_teams']            = options[:limit_teams] if options[:limit_teams]
          updated_meta['limit_members_per_team'] = options[:limit_members_per_team] if options[:limit_members_per_team]
          updated_meta['limit_custom_domains']   = options[:limit_custom_domains] if options[:limit_custom_domains]
          updated_meta['limit_secret_lifetime']  = options[:limit_secret_lifetime] if options[:limit_secret_lifetime]

          updated_meta
        end

        puts 'Updating metadata:'
        metadata.each { |k, v| puts "  #{k}: #{v}" }

        print "\nProceed? (y/n): "
        return unless $stdin.gets.chomp.downcase == 'y'

        # Build update params
        update_params = { metadata: metadata }

        # Handle marketing features
        if add_feature || remove_feature
          current_features = product.marketing_features || []

          if add_feature
            # Add new feature
            current_features << { name: add_feature }
            puts "  Adding marketing feature: #{add_feature}"
          end

          if remove_feature
            # Remove feature by name (MarketingFeature is a hash-like object)
            current_features.reject! { |f| f['name'] == remove_feature }
            puts "  Removing marketing feature: #{remove_feature}"
          end

          update_params[:marketing_features] = current_features
        end

        updated = Stripe::Product.update(product_id, update_params)

        puts "\nProduct updated successfully"
        puts 'Updated metadata:'
        updated.metadata.each { |k, v| puts "  #{k}: #{v}" }

        if updated.marketing_features && updated.marketing_features.any?
          puts "\nMarketing features:"
          updated.marketing_features.each { |f| puts "  - #{f['name']}" }
        end
      rescue Stripe::StripeError => ex
        puts "Error updating product: #{ex.message}"
      end
    end
  end
end

Onetime::CLI.register 'billing products update', Onetime::CLI::BillingProductsUpdateCommand

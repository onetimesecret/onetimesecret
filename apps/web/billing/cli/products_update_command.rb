# apps/web/billing/cli/products_update_command.rb
#
# frozen_string_literal: true

require_relative 'helpers'

module Onetime
  module CLI
    # Update Stripe product metadata
    class BillingProductsUpdateCommand < Command
      include BillingHelpers

      desc 'Update Stripe product metadata'

      argument :product_id, required: true, desc: 'Product ID (e.g., prod_xxx)'

      option :interactive, type: :boolean, default: false,
        desc: 'Interactive mode - prompt for all fields'

      option :plan_id, type: :string, desc: 'Plan ID'
      option :tier, type: :string, desc: 'Tier'
      option :region, type: :string, desc: 'Region'
      option :tenancy, type: :string, desc: 'Tenancy'
      option :capabilities, type: :string, desc: 'Capabilities'
      option :add_marketing_feature, type: :string, desc: 'Add marketing feature'
      option :remove_marketing_feature, type: :string, desc: 'Remove marketing feature (by ID)'

      def call(product_id:, interactive: false, **options)
        boot_application!

        return unless stripe_configured?

        product = Stripe::Product.retrieve(product_id)
        puts "Current product: #{product.name}"
        puts "Current metadata:"
        product.metadata.each { |k, v| puts "  #{k}: #{v}" }
        puts

        # Extract marketing feature operations from options
        add_feature = options.delete(:add_marketing_feature)
        remove_feature = options.delete(:remove_marketing_feature)

        metadata = if interactive
          prompt_for_metadata
        else
          # Build complete metadata hash with all fields
          current_meta = product.metadata.to_h
          {
            'app' => 'onetimesecret',
            'plan_id' => options[:plan_id] || current_meta['plan_id'] || '',
            'tier' => options[:tier] || current_meta['tier'] || '',
            'region' => options[:region] || current_meta['region'] || '',
            'tenancy' => options[:tenancy] || current_meta['tenancy'] || '',
            'capabilities' => options[:capabilities] || current_meta['capabilities'] || '',
            'created' => current_meta['created'] || Time.now.utc.iso8601,
            'limit_teams' => current_meta['limit_teams'] || '',
            'limit_members_per_team' => current_meta['limit_members_per_team'] || '',
          }
        end

        puts "Updating metadata:"
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
            # Remove feature by ID
            current_features.reject! { |f| f.id == remove_feature }
            puts "  Removing marketing feature: #{remove_feature}"
          end

          update_params[:marketing_features] = current_features
        end

        updated = Stripe::Product.update(product_id, update_params)

        puts "\nProduct updated successfully"
        puts "Updated metadata:"
        updated.metadata.each { |k, v| puts "  #{k}: #{v}" }

        if updated.marketing_features && updated.marketing_features.any?
          puts "\nMarketing features:"
          updated.marketing_features.each { |f| puts "  - #{f.name} (#{f.id})" }
        end
      rescue Stripe::StripeError => e
        puts "Error updating product: #{e.message}"
      end
    end
  end
end

Onetime::CLI.register 'billing products update', Onetime::CLI::BillingProductsUpdateCommand

# apps/web/billing/cli/products_create_command.rb
#
# frozen_string_literal: true

require_relative 'helpers'

module Onetime
  module CLI
    # Create Stripe product
    class BillingProductsCreateCommand < Command
      include BillingHelpers

      desc 'Create a new Stripe product'

      argument :name, required: false, desc: 'Product name'

      option :interactive, type: :boolean, default: false,
        desc: 'Interactive mode - prompt for all fields'

      option :plan_id, type: :string, desc: 'Plan ID (optional, e.g., identity_v1)'
      option :tier, type: :string, desc: 'Tier (e.g., single_team)'
      option :region, type: :string, desc: 'Region (e.g., us-east)'
      option :tenancy, type: :string, desc: 'Tenancy (e.g., single, multi)'
      option :capabilities, type: :string, desc: 'Capabilities (comma-separated)'
      option :marketing_features, type: :string, desc: 'Marketing features (comma-separated)'

      def call(name: nil, interactive: false, **options)
        boot_application!

        return unless stripe_configured?

        if interactive || name.nil?
          print 'Product name: '
          name = $stdin.gets.chomp
        end

        if name.to_s.strip.empty?
          puts 'Error: Product name is required'
          return
        end

        metadata = if interactive
          prompt_for_metadata
        else
          # Build metadata with all fields, using empty strings for missing values
          {
            'app' => 'onetimesecret',
            'plan_id' => options[:plan_id] || '',
            'tier' => options[:tier] || '',
            'region' => options[:region] || 'global',
            'tenancy' => options[:tenancy] || '',
            'capabilities' => options[:capabilities] || '',
            'created' => Time.now.utc.iso8601,
            'limit_teams' => '',
            'limit_members_per_team' => '',
          }
        end

        puts "\nCreating product '#{name}' with metadata:"
        metadata.each { |k, v| puts "  #{k}: #{v}" }

        print "\nProceed? (y/n): "
        return unless $stdin.gets.chomp.downcase == 'y'

        # Build product creation params
        product_params = {
          name: name,
          metadata: metadata,
        }

        # Add marketing features if provided
        if options[:marketing_features]
          features                            = options[:marketing_features].split(',').map(&:strip)
          product_params[:marketing_features] = features.map { |f| { name: f } }
          puts "\nMarketing features:"
          features.each { |f| puts "  - #{f}" }
        end

        product = Stripe::Product.create(product_params)

        puts "\nProduct created successfully:"
        puts "  ID: #{product.id}"
        puts "  Name: #{product.name}"

        if product.marketing_features && product.marketing_features.any?
          puts "\nMarketing features:"
          product.marketing_features.each { |f| puts "  - #{f.name}" }
        end

        puts "\nNext steps:"
        puts "  bin/ots billing prices create --product #{product.id}"
      rescue Stripe::StripeError => ex
        puts "Error creating product: #{ex.message}"
      end
    end
  end
end

Onetime::CLI.register 'billing products create', Onetime::CLI::BillingProductsCreateCommand

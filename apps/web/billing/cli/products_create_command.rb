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

      option :plan_id, type: :string, desc: 'Plan ID (optional, e.g., identity_plus_v1)'
      option :tier, type: :string, desc: 'Tier (e.g., single_team)'
      option :region, type: :string, desc: 'Region (e.g., EU)'
      option :tenancy, type: :string, desc: 'Tenancy (e.g., single, multi)'
      option :capabilities, type: :string, desc: 'Capabilities (comma-separated)'
      option :marketing_features, type: :string, desc: 'Marketing features (comma-separated)'
      option :display_order, type: :string, desc: 'Display order (higher = earlier, default: 0)'
      option :show_on_plans_page, type: :boolean, default: true,
        desc: 'Show on plans page (default: true)'
      option :limit_teams, type: :string, desc: 'Limit teams (-1 for unlimited)'
      option :limit_members_per_team, type: :string, desc: 'Limit members per team (-1 for unlimited)'
      option :limit_custom_domains, type: :string, desc: 'Limit custom domains (-1 for unlimited)'
      option :limit_secret_lifetime, type: :string, desc: 'Limit secret lifetime (seconds)'
      option :limit_secrets_per_day, type: :string, desc: 'Limit secrets per day (-1 for unlimited)'
      option :force, type: :boolean, default: false,
        desc: 'Create duplicate product without checking for existing'

      option :yes, type: :boolean, default: false,
        desc: 'Skip confirmation prompts (for automation)'

      option :update, type: :boolean, default: false,
        desc: 'Update existing product if found (requires --yes for non-interactive)'

      def call(name: nil, interactive: false, force: false, yes: false, update: false, **options)
        boot_application!

        return unless stripe_configured?

        if interactive || name.nil?
          print 'Product name: '
          input = $stdin.gets
          name  = input&.chomp
        end

        if name.to_s.strip.empty?
          puts 'Error: Product name is required'
          return
        end

        metadata = if interactive
          prompt_for_metadata
        else
          # Build metadata with all fields, using empty strings for missing values
          base_metadata = {
            'app' => 'onetimesecret',
            'plan_id' => options[:plan_id] || '',
            'tier' => options[:tier] || '',
            'region' => options[:region] || 'global',
            'tenancy' => options[:tenancy] || '',
            'capabilities' => options[:capabilities] || '',
            'created' => Time.now.utc.iso8601,
            'display_order' => options[:display_order] || '0',
            'show_on_plans_page' => options[:show_on_plans_page].to_s,
          }

          # Add limit fields if provided
          base_metadata['limit_teams']            = options[:limit_teams] if options[:limit_teams]
          base_metadata['limit_members_per_team'] = options[:limit_members_per_team] if options[:limit_members_per_team]
          base_metadata['limit_custom_domains']   = options[:limit_custom_domains] if options[:limit_custom_domains]
          base_metadata['limit_secret_lifetime']  = options[:limit_secret_lifetime] if options[:limit_secret_lifetime]
          base_metadata['limit_secrets_per_day']  = options[:limit_secrets_per_day] if options[:limit_secrets_per_day]

          base_metadata
        end

        # Check for existing product with same plan_id (unless --force)
        unless force
          existing = find_existing_product(metadata['plan_id'])

          if existing
            handle_existing_product(existing, name, metadata, options)
            return
          end
        end

        puts "\nCreating product '#{name}' with metadata:"
        metadata.each { |k, v| puts "  #{k}: #{v}" }

        if options[:marketing_features]
          features = options[:marketing_features].split(',').map(&:strip)
          puts "\nMarketing features:"
          features.each { |f| puts "  - #{f}" }
        end

        # Skip confirmation if --yes flag is provided
        unless yes
          print "\nProceed? (y/n): "
          response = $stdin.gets
          return unless response&.chomp&.downcase == 'y'
        end

        create_product_with_metadata(name, metadata, options)
      end

      private

      # Find existing product by plan_id metadata
      def find_existing_product(plan_id)
        return nil if plan_id.to_s.strip.empty?

        Stripe::Product.list(active: true, limit: 100).data.find do |product|
          product.metadata['app'] == 'onetimesecret' &&
            product.metadata['plan_id'] == plan_id
        end
      rescue Stripe::StripeError => ex
        puts "Warning: Could not search for existing products: #{ex.message}"
        nil
      end

      # Handle case where product already exists
      def handle_existing_product(existing, name, metadata, options)
        puts "\n⚠️  Product already exists with plan_id: #{metadata['plan_id']}"
        puts "  Product ID: #{existing.id}"
        puts "  Name: #{existing.name}"
        puts "  Tier: #{existing.metadata['tier']}"
        puts "  Region: #{existing.metadata['region']}"

        if existing.metadata['capabilities']
          caps = existing.metadata['capabilities'].split(',').map(&:strip)
          puts "  Capabilities: #{caps.join(', ')}"
        end

        # Auto-update if --update flag provided (requires --yes for non-interactive)
        if options[:update]
          if options[:yes]
            puts "\n→ Auto-updating existing product (--update --yes)"
            update_existing_product(existing.id, name, metadata, options)
            return
          else
            puts "\n⚠️  Warning: --update requires --yes for non-interactive mode"
            puts 'Run with --yes --update to auto-update, or continue interactively below.'
            puts
          end
        end

        # Interactive mode - prompt user
        puts "\nWhat would you like to do?"
        puts '  1) Update existing product with new values'
        puts '  2) Create duplicate anyway (not recommended)'
        puts '  3) Cancel'

        print "\nChoice (1-3): "
        choice = $stdin.gets&.chomp

        case choice
        when '1'
          update_existing_product(existing.id, name, metadata, options)
        when '2'
          puts "\nCreating duplicate product (--force mode)..."
          create_product_with_metadata(name, metadata, options)
        when '3'
          puts "\nCancelled."
        else
          puts "\nInvalid choice. Cancelled."
        end
      end

      # Update existing product
      def update_existing_product(product_id, name, metadata, options)
        puts "\nUpdating product #{product_id}..."

        # Fetch current product to preserve existing metadata
        current_product = Stripe::Product.retrieve(product_id)

        # Merge new metadata with existing, preserving non-empty existing values
        merged_metadata = current_product.metadata.to_h.merge(metadata) do |_key, old_val, new_val|
          # Keep new value unless it's empty and old value exists
          (new_val.nil? || new_val.to_s.strip.empty?) && !old_val.to_s.strip.empty? ? old_val : new_val
        end

        update_params = {
          name: name,
          metadata: merged_metadata,
        }

        # Add marketing features if provided
        if options[:marketing_features]
          features                           = options[:marketing_features].split(',').map(&:strip)
          update_params[:marketing_features] = features.map { |f| { name: f } }
        end

        product = Stripe::Product.update(product_id, update_params)

        puts "\n✓ Product updated successfully:"
        puts "  ID: #{product.id}"
        puts "  Name: #{product.name}"

        puts "\nNext steps:"
        puts '  bin/ots billing sync  # Update Redis cache'
        puts "  bin/ots billing products show #{product.id}  # View details"
      rescue Stripe::StripeError => ex
        puts "Error updating product: #{ex.message}"
      end

      # Create product with given metadata (extracted for reuse)
      def create_product_with_metadata(name, metadata, options)
        product_params = {
          name: name,
          metadata: metadata,
        }

        if options[:marketing_features]
          features                            = options[:marketing_features].split(',').map(&:strip)
          product_params[:marketing_features] = features.map { |f| { name: f } }
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
        puts "  bin/ots billing prices create #{product.id} --amount=2900 --currency=usd --interval=month"

        product
      rescue Stripe::StripeError => ex
        puts "Error creating product: #{ex.message}"
        nil
      end
    end
  end
end

Onetime::CLI.register 'billing products create', Onetime::CLI::BillingProductsCreateCommand

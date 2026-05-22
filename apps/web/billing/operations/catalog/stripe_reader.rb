# apps/web/billing/operations/catalog/stripe_reader.rb
#
# frozen_string_literal: true

require_relative 'stripe_retry'

module Billing
  module Operations
    module Catalog
      # Consolidated Stripe data fetching for catalog operations.
      #
      # Single entry point for `Stripe::Product.list` and `Stripe::Price.list`
      # in the catalog sync path. Used by both Pull and Push operations.
      #
      # @example
      #   products = StripeReader.fetch_products(app_identifier: 'onetimesecret')
      #   prices   = StripeReader.fetch_prices(products)
      #
      module StripeReader
        extend self

        # Fetch products filtered by app_identifier and optional region.
        #
        # Products are keyed by a match_key built from metadata fields,
        # enabling correlation with YAML plan definitions.
        #
        # @param app_identifier [String] Value to match in product metadata['app']
        # @param region_filter [String, nil] Optional region to filter products
        # @param match_fields [Array<String>] Fields to build match keys from metadata
        # @param override_product_ids [Set<String>] Product IDs to include regardless of app match
        # @return [Hash<String, Stripe::Product>] Products keyed by match_key
        def fetch_products(app_identifier:, region_filter: nil, match_fields: ['plan_id'], override_product_ids: Set.new)
          products = {}

          StripeRetry.with_retry do
            Stripe::Product.list(active: true, limit: 100).auto_paging_each do |product|
              has_app_match      = product.metadata['app'] == app_identifier
              has_override_match = override_product_ids.include?(product.id)

              next unless has_app_match || has_override_match

              if region_filter && !has_override_match && !Billing::RegionNormalizer.match?(product.metadata['region'], region_filter)
                next
              end

              key = build_match_key_from_metadata(product.metadata, match_fields)

              if key
                products[key] = product
              elsif has_override_match
                products["__id__#{product.id}"] = product
              end
            end
          end

          products
        end

        # Fetch active prices for given products.
        #
        # @param products [Hash<String, Stripe::Product>] Products keyed by match_key
        # @return [Hash<String, Array<Stripe::Price>>] Prices grouped by match_key
        def fetch_prices(products)
          prices      = {}
          product_ids = products.values.map(&:id)

          return prices if product_ids.empty?

          StripeRetry.with_retry do
            Stripe::Price.list(active: true, limit: 100).auto_paging_each do |price|
              next unless product_ids.include?(price.product)

              match_key = products.find { |_k, p| p.id == price.product }&.first
              next unless match_key

              prices[match_key] ||= []
              prices[match_key] << price
            end
          end

          prices
        end

        private

        def build_match_key_from_metadata(metadata, match_fields)
          values = match_fields.map { |f| metadata[f]&.to_s }
          return nil if values.any?(&:nil?)

          values.join('|')
        end
      end
    end
  end
end

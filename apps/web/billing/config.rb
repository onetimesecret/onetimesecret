# apps/web/billing/config.rb
#
# frozen_string_literal: true

module Billing
  # Billing configuration and catalog management
  module Config
    # Get path to billing plans catalog
    #
    # @return [String] Absolute path to billing-plans.yaml
    def self.catalog_path
      File.join(Onetime::HOME, 'etc', 'billing-plans.yaml')
    end

    # Check if catalog file exists
    #
    # @return [Boolean]
    def self.catalog_exists?
      File.exist?(catalog_path)
    end
  end
end

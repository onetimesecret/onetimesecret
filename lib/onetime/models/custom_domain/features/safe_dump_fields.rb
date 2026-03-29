# lib/onetime/models/custom_domain/features/safe_dump_fields.rb
#
# frozen_string_literal: true

# Autoloaded extension file for Onetime::CustomDomain SafeDump configuration
# This file is automatically loaded when the SafeDump feature is enabled
module Onetime::CustomDomain::Features
  module SafeDump
    Onetime::CustomDomain.add_feature self, :safe_dump_fields

    def self.included(base)
      base.feature :safe_dump

      base.safe_dump_field :identifier, ->(obj) { obj.identifier }
      base.safe_dump_field :extid
      base.safe_dump_field :domainid
      base.safe_dump_field :display_domain
      base.safe_dump_field :custid
      base.safe_dump_field :base_domain
      base.safe_dump_field :subdomain
      base.safe_dump_field :trd
      base.safe_dump_field :tld
      base.safe_dump_field :sld
      base.safe_dump_field :is_apex, ->(obj) { obj.apex? }
      base.safe_dump_field :txt_validation_host
      base.safe_dump_field :txt_validation_value
      base.safe_dump_field :brand, ->(obj) { obj.brand_settings.to_h } # until we can call obj.brand.to_h
      # NOTE: We don't include brand images here b/c they create huge payloads
      # that we want to avoid unless we are actually going to use it.
      base.safe_dump_field :status
      base.safe_dump_field :vhost, ->(obj) { obj.parse_vhost }
      base.safe_dump_field :verified, ->(obj) { obj.verified.to_s == 'true' }
      base.safe_dump_field :created
      base.safe_dump_field :updated

      # SSO status fields - computed from DomainSsoConfig lookup
      # Single lookup for both fields to avoid N+1 pattern on domain lists
      base.safe_dump_field :sso_configured,
        ->(obj) {
          config = Onetime::DomainSsoConfig.find_by_domain_id(obj.identifier)
          obj.instance_variable_set(:@_sso_config_cache, config)
          !config.nil?
        }
      base.safe_dump_field :sso_enabled,
        ->(obj) {
          config = obj.instance_variable_get(:@_sso_config_cache) ||
                   Onetime::DomainSsoConfig.find_by_domain_id(obj.identifier)
          config&.enabled? || false
        }
    end
  end
end

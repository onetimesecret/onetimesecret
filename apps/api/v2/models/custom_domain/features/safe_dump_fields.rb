# apps/api/v2/models/custom_domain/features/safe_dump_fields.rb

# Autoloaded extension file for V2::CustomDomain SafeDump configuration
# This file is automatically loaded when the SafeDump feature is enabled
module V2::CustomDomain::Features
  module SafeDump

    V2::CustomDomain.add_feature self, :safe_dump_fields

    def self.included(base)

      base.feature :safe_dump

      base.safe_dump_field :identifier, ->(obj) { obj.identifier }
      base.safe_dump_field :domainid
      base.safe_dump_field :display_domain
      base.safe_dump_field :custid
      base.safe_dump_field :base_domain
      base.safe_dump_field :subdomain
      base.safe_dump_field :trd
      base.safe_dump_field :tld
      base.safe_dump_field :sld
      base.safe_dump_field :is_apex, ->(obj) { obj.apex? }
      base.safe_dump_field :_original_value
      base.safe_dump_field :txt_validation_host
      base.safe_dump_field :txt_validation_value
      base.safe_dump_field :brand, ->(obj) { obj.brand.hgetall }
      # NOTE: We don't include brand images here b/c they create huge payloads
      # that we want to avoid unless we are actually going to use it.
      base.safe_dump_field :status
      base.safe_dump_field :vhost, ->(obj) { obj.parse_vhost }
      base.safe_dump_field :verified
      base.safe_dump_field :created
      base.safe_dump_field :updated
    end
  end
end

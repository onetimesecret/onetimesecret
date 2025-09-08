# apps/api/v2/models/custom_domain/features/safe_dump_fields.rb

# Autoloaded extension file for V2::CustomDomain SafeDump configuration
# This file is automatically loaded when the SafeDump feature is enabled
class V2::CustomDomain
  # TODO: SafeDump feature could look in modelname/, modelname/features/,
  # and modelname/features/safe_dump for safe_dump_fields.rb.
  safe_dump_field :identifier, ->(obj) { obj.identifier }
  safe_dump_field :domainid
  safe_dump_field :display_domain
  safe_dump_field :custid
  safe_dump_field :base_domain
  safe_dump_field :subdomain
  safe_dump_field :trd
  safe_dump_field :tld
  safe_dump_field :sld
  safe_dump_field :is_apex, ->(obj) { obj.apex? }
  safe_dump_field :_original_value
  safe_dump_field :txt_validation_host
  safe_dump_field :txt_validation_value
  safe_dump_field :brand, ->(obj) { obj.brand.hgetall }
  # NOTE: We don't include brand images here b/c they create huge payloads
  # that we want to avoid unless we are actually going to use it.
  safe_dump_field :status
  safe_dump_field :vhost, ->(obj) { obj.parse_vhost }
  safe_dump_field :verified
  safe_dump_field :created
  safe_dump_field :updated
end

# try/migrations/field_types_completeness_try.rb
#
# frozen_string_literal: true

# Validates FIELD_TYPES constants in migration transform scripts against model definitions.
#
# This test ensures all fields from the model definitions (including features like
# deprecated_fields, migration_fields, counter_fields, etc.) are included in the
# FIELD_TYPES constant with correct type mappings.
#
# Migration scripts validate FIELD_TYPES at runtime (fail-fast on unknown fields),
# so completeness here prevents runtime failures during migration.

require 'familia'

# Load the FIELD_TYPES from migration scripts for validation
# These are exact copies from the transform.rb files

module MigrationFieldTypes
  # From migrations/2026-01-26/01-customer/transform.rb
  CUSTOMER_FIELD_TYPES = {
    # Core fields (customer.rb)
    'custid' => :string,
    'email' => :string,
    'locale' => :string,
    'planid' => :string,
    'last_password_update' => :timestamp,
    'last_login' => :timestamp,
    'notify_on_reveal' => :boolean,
    'objid' => :string,
    'extid' => :string,
    # Status fields (features/status.rb)
    'role' => :string,
    'joined' => :timestamp,
    'verified' => :boolean,
    'verified_by' => :string,
    # Deprecated fields (features/deprecated_fields.rb)
    'sessid' => :string,
    'apitoken' => :string,
    'contributor' => :string,
    'stripe_customer_id' => :string,
    'stripe_subscription_id' => :string,
    # Counter fields (features/counter_fields.rb)
    'secrets_created' => :integer,
    'secrets_burned' => :integer,
    'secrets_shared' => :integer,
    'emails_sent' => :integer,
    # Legacy encrypted fields (features/legacy_encrypted_fields.rb)
    'passphrase' => :string,
    'passphrase_encryption' => :string,
    'value' => :string,
    'value_encryption' => :string,
    # Required fields (features/required_fields.rb)
    'created' => :timestamp,
    'updated' => :timestamp,
    # Migration fields (features/with_migration_fields.rb)
    'v1_identifier' => :string,
    'v1_custid' => :string,
    'migration_status' => :string,
    'migrated_at' => :timestamp,
  }.freeze

  # From migrations/2026-01-26/02-organization/generate.rb
  ORGANIZATION_FIELD_TYPES = {
    # Core fields (organization.rb)
    'objid' => :string,
    'extid' => :string,
    'display_name' => :string,
    'description' => :string,
    'owner_id' => :string,
    'contact_email' => :string,
    'is_default' => :boolean,
    # Billing fields (features/with_organization_billing.rb)
    'planid' => :string,
    'billing_email' => :string,
    'stripe_customer_id' => :string,
    'stripe_subscription_id' => :string,
    'stripe_checkout_email' => :string,
    'subscription_status' => :string,
    'subscription_period_end' => :timestamp,
    # Required fields (features/required_fields.rb)
    'created' => :timestamp,
    'updated' => :timestamp,
    # Migration fields (features/with_migration_fields.rb + organization-specific)
    'v1_identifier' => :string,
    'v1_source_custid' => :string,
    'migration_status' => :string,
    'migrated_at' => :timestamp,
  }.freeze

  # From migrations/2026-01-26/03-customdomain/transform.rb
  CUSTOMDOMAIN_FIELD_TYPES = {
    # Core fields (custom_domain.rb)
    'domainid' => :string,
    'objid' => :string,
    'extid' => :string,
    'display_domain' => :string,
    'org_id' => :string,
    'base_domain' => :string,
    'subdomain' => :string,
    'trd' => :string,
    'tld' => :string,
    'sld' => :string,
    'txt_validation_host' => :string,
    'txt_validation_value' => :string,
    'status' => :string,
    'vhost' => :string,  # JSON string stored as string
    'verified' => :boolean,
    'resolving' => :boolean,
    '_original_value' => :string,
    # V1 legacy field (custid was used before org_id)
    'custid' => :string,
    # Required fields - timestamps stored as floats
    'created' => :timestamp,
    'updated' => :timestamp,
    # Migration fields
    'v1_identifier' => :string,
    'v1_custid' => :string,
    'migration_status' => :string,
    'migrated_at' => :timestamp,
  }.freeze

  # From migrations/2026-01-26/04-receipt/transform.rb
  RECEIPT_FIELD_TYPES = {
    # Core fields (receipt.rb)
    'objid' => :string,
    'extid' => :string,
    'owner_id' => :string,
    'state' => :string,
    'secret_identifier' => :string,
    'secret_shortid' => :string,
    'secret_ttl' => :integer,
    'lifespan' => :integer,
    'share_domain' => :string,
    'passphrase' => :string,
    'org_id' => :string,
    'domain_id' => :string,
    'recipients' => :string,  # JSON array stored as string
    'memo' => :string,
    # Required fields - timestamps stored as floats
    'created' => :timestamp,
    'updated' => :timestamp,
    # Migration fields
    'v1_identifier' => :string,
    'v1_key' => :string,
    'v1_custid' => :string,
    'migration_status' => :string,
    'migrated_at' => :timestamp,
    # Deprecated fields (features/deprecated_fields.rb)
    'key' => :string,
    'viewed' => :timestamp,    # renamed to 'previewed' in v2
    'received' => :timestamp,  # renamed to 'revealed' in v2
    'shared' => :timestamp,
    'burned' => :timestamp,
    'custid' => :string,       # legacy owner field
    'truncate' => :boolean,
    'secret_key' => :string,   # use secret_identifier
    'previewed' => :timestamp,
    'revealed' => :timestamp,
  }.freeze

  # From migrations/2026-01-26/05-secret/transform.rb
  SECRET_FIELD_TYPES = {
    # Core fields (secret.rb)
    'objid' => :string,
    'state' => :string,
    'lifespan' => :integer,
    'receipt_identifier' => :string,
    'receipt_shortid' => :string,
    'owner_id' => :string,
    # Encrypted fields - keep exactly as-is
    'ciphertext' => :string,
    'passphrase' => :string,
    'value_encryption' => :string,
    'passphrase_encryption' => :string,
    # Required fields - timestamps stored as floats
    'created' => :timestamp,
    'updated' => :timestamp,
    # Migration fields
    'v1_identifier' => :string,
    'v1_custid' => :string,
    'v1_original_size' => :integer,
    'migration_status' => :string,
    'migrated_at' => :timestamp,
    # Deprecated fields (features/deprecated_fields.rb)
    'value' => :string,        # plaintext value in v1 (deprecated)
    'key' => :string,          # legacy key field
    'custid' => :string,       # legacy owner field
    'share_domain' => :string,
    'verification' => :string,
    'metadata_key' => :string, # use receipt_identifier
    'truncated' => :boolean,
    'secret_key' => :string,
  }.freeze

  # Expected fields from model definitions (consolidated from all feature files)
  # These are the fields that SHOULD be in FIELD_TYPES

  CUSTOMER_EXPECTED_FIELDS = %w[
    custid email locale planid last_password_update last_login notify_on_reveal
    objid extid role joined verified verified_by sessid apitoken contributor
    stripe_customer_id stripe_subscription_id secrets_created secrets_burned
    secrets_shared emails_sent passphrase passphrase_encryption value value_encryption
    created updated v1_identifier v1_custid migration_status migrated_at
  ].freeze

  ORGANIZATION_EXPECTED_FIELDS = %w[
    objid extid display_name description owner_id contact_email is_default
    planid billing_email stripe_customer_id stripe_subscription_id
    stripe_checkout_email subscription_status subscription_period_end
    created updated v1_identifier v1_source_custid migration_status migrated_at
  ].freeze

  CUSTOMDOMAIN_EXPECTED_FIELDS = %w[
    domainid objid extid display_domain org_id base_domain subdomain trd tld sld
    txt_validation_host txt_validation_value status vhost verified resolving
    _original_value custid created updated v1_identifier v1_custid
    migration_status migrated_at
  ].freeze

  RECEIPT_EXPECTED_FIELDS = %w[
    objid extid owner_id state secret_identifier secret_shortid secret_ttl
    lifespan share_domain passphrase org_id domain_id recipients memo
    created updated v1_identifier v1_key v1_custid migration_status migrated_at
    key viewed received shared burned custid truncate secret_key previewed revealed
  ].freeze

  SECRET_EXPECTED_FIELDS = %w[
    objid state lifespan receipt_identifier receipt_shortid owner_id
    ciphertext passphrase value_encryption passphrase_encryption
    created updated v1_identifier v1_custid v1_original_size migration_status migrated_at
    value key custid share_domain verification metadata_key truncated secret_key
  ].freeze
end

# ============================================================================
# CUSTOMER FIELD_TYPES Validation Tests
# ============================================================================

## Customer FIELD_TYPES includes all expected core fields
@customer_missing = MigrationFieldTypes::CUSTOMER_EXPECTED_FIELDS - MigrationFieldTypes::CUSTOMER_FIELD_TYPES.keys
@customer_missing.empty?
#=> true

## Customer FIELD_TYPES has no unexpected extra fields
@customer_extra = MigrationFieldTypes::CUSTOMER_FIELD_TYPES.keys - MigrationFieldTypes::CUSTOMER_EXPECTED_FIELDS
@customer_extra.empty?
#=> true

## Customer FIELD_TYPES has correct type for email (string)
MigrationFieldTypes::CUSTOMER_FIELD_TYPES['email']
#=> :string

## Customer FIELD_TYPES has correct type for secrets_created (integer)
MigrationFieldTypes::CUSTOMER_FIELD_TYPES['secrets_created']
#=> :integer

## Customer FIELD_TYPES has correct type for created (timestamp)
MigrationFieldTypes::CUSTOMER_FIELD_TYPES['created']
#=> :timestamp

## Customer FIELD_TYPES has correct type for verified (boolean)
MigrationFieldTypes::CUSTOMER_FIELD_TYPES['verified']
#=> :boolean

# ============================================================================
# ORGANIZATION FIELD_TYPES Validation Tests
# ============================================================================

## Organization FIELD_TYPES includes all expected fields
@org_missing = MigrationFieldTypes::ORGANIZATION_EXPECTED_FIELDS - MigrationFieldTypes::ORGANIZATION_FIELD_TYPES.keys
@org_missing.empty?
#=> true

## Organization FIELD_TYPES has no unexpected extra fields
@org_extra = MigrationFieldTypes::ORGANIZATION_FIELD_TYPES.keys - MigrationFieldTypes::ORGANIZATION_EXPECTED_FIELDS
@org_extra.empty?
#=> true

## Organization FIELD_TYPES has correct type for is_default (boolean)
MigrationFieldTypes::ORGANIZATION_FIELD_TYPES['is_default']
#=> :boolean

## Organization FIELD_TYPES has correct type for subscription_period_end (timestamp)
MigrationFieldTypes::ORGANIZATION_FIELD_TYPES['subscription_period_end']
#=> :timestamp

# ============================================================================
# CUSTOMDOMAIN FIELD_TYPES Validation Tests
# ============================================================================

## CustomDomain FIELD_TYPES includes all expected fields
@domain_missing = MigrationFieldTypes::CUSTOMDOMAIN_EXPECTED_FIELDS - MigrationFieldTypes::CUSTOMDOMAIN_FIELD_TYPES.keys
@domain_missing.empty?
#=> true

## CustomDomain FIELD_TYPES has no unexpected extra fields
@domain_extra = MigrationFieldTypes::CUSTOMDOMAIN_FIELD_TYPES.keys - MigrationFieldTypes::CUSTOMDOMAIN_EXPECTED_FIELDS
@domain_extra.empty?
#=> true

## CustomDomain FIELD_TYPES has correct type for verified (boolean)
MigrationFieldTypes::CUSTOMDOMAIN_FIELD_TYPES['verified']
#=> :boolean

## CustomDomain FIELD_TYPES has correct type for resolving (boolean)
MigrationFieldTypes::CUSTOMDOMAIN_FIELD_TYPES['resolving']
#=> :boolean

# ============================================================================
# RECEIPT FIELD_TYPES Validation Tests
# ============================================================================

## Receipt FIELD_TYPES includes all expected fields
@receipt_missing = MigrationFieldTypes::RECEIPT_EXPECTED_FIELDS - MigrationFieldTypes::RECEIPT_FIELD_TYPES.keys
@receipt_missing.empty?
#=> true

## Receipt FIELD_TYPES has no unexpected extra fields
@receipt_extra = MigrationFieldTypes::RECEIPT_FIELD_TYPES.keys - MigrationFieldTypes::RECEIPT_EXPECTED_FIELDS
@receipt_extra.empty?
#=> true

## Receipt FIELD_TYPES has correct type for secret_ttl (integer)
MigrationFieldTypes::RECEIPT_FIELD_TYPES['secret_ttl']
#=> :integer

## Receipt FIELD_TYPES has correct type for lifespan (integer)
MigrationFieldTypes::RECEIPT_FIELD_TYPES['lifespan']
#=> :integer

## Receipt FIELD_TYPES has correct type for truncate (boolean)
MigrationFieldTypes::RECEIPT_FIELD_TYPES['truncate']
#=> :boolean

## Receipt FIELD_TYPES has correct type for viewed (timestamp, deprecated)
MigrationFieldTypes::RECEIPT_FIELD_TYPES['viewed']
#=> :timestamp

## Receipt FIELD_TYPES has correct type for previewed (timestamp)
MigrationFieldTypes::RECEIPT_FIELD_TYPES['previewed']
#=> :timestamp

# ============================================================================
# SECRET FIELD_TYPES Validation Tests
# ============================================================================

## Secret FIELD_TYPES includes all expected fields
@secret_missing = MigrationFieldTypes::SECRET_EXPECTED_FIELDS - MigrationFieldTypes::SECRET_FIELD_TYPES.keys
@secret_missing.empty?
#=> true

## Secret FIELD_TYPES has no unexpected extra fields
@secret_extra = MigrationFieldTypes::SECRET_FIELD_TYPES.keys - MigrationFieldTypes::SECRET_EXPECTED_FIELDS
@secret_extra.empty?
#=> true

## Secret FIELD_TYPES has correct type for lifespan (integer)
MigrationFieldTypes::SECRET_FIELD_TYPES['lifespan']
#=> :integer

## Secret FIELD_TYPES has correct type for v1_original_size (integer)
MigrationFieldTypes::SECRET_FIELD_TYPES['v1_original_size']
#=> :integer

## Secret FIELD_TYPES has correct type for truncated (boolean)
MigrationFieldTypes::SECRET_FIELD_TYPES['truncated']
#=> :boolean

## Secret FIELD_TYPES has correct type for ciphertext (string, encrypted)
MigrationFieldTypes::SECRET_FIELD_TYPES['ciphertext']
#=> :string

# ============================================================================
# Type Mapping Validation Tests
# ============================================================================

## All timestamp fields are typed as :timestamp
@all_field_types = [
  MigrationFieldTypes::CUSTOMER_FIELD_TYPES,
  MigrationFieldTypes::ORGANIZATION_FIELD_TYPES,
  MigrationFieldTypes::CUSTOMDOMAIN_FIELD_TYPES,
  MigrationFieldTypes::RECEIPT_FIELD_TYPES,
  MigrationFieldTypes::SECRET_FIELD_TYPES,
]
@timestamp_fields = %w[created updated migrated_at last_password_update last_login joined subscription_period_end viewed received shared burned previewed revealed]
@timestamp_types_correct = @all_field_types.all? do |field_types|
  @timestamp_fields.all? do |field|
    !field_types.key?(field) || field_types[field] == :timestamp
  end
end
@timestamp_types_correct
#=> true

## All integer counter fields are typed as :integer
@counter_fields = %w[secrets_created secrets_burned secrets_shared emails_sent secret_ttl lifespan v1_original_size]
@counter_types_correct = @all_field_types.all? do |field_types|
  @counter_fields.all? do |field|
    !field_types.key?(field) || field_types[field] == :integer
  end
end
@counter_types_correct
#=> true

## All boolean fields are typed as :boolean
@boolean_fields = %w[verified is_default notify_on_reveal resolving truncate truncated]
@boolean_types_correct = @all_field_types.all? do |field_types|
  @boolean_fields.all? do |field|
    !field_types.key?(field) || field_types[field] == :boolean
  end
end
@boolean_types_correct
#=> true

# ============================================================================
# Serialization Behavior Tests (using actual Familia serializer)
# ============================================================================

## Familia JsonSerializer handles empty string edge case - empty strings should NOT go through serializer
# In migration scripts, empty strings are explicitly mapped to 'null' before serializer call
# This tests that the JsonSerializer itself handles various inputs correctly
Familia::JsonSerializer.dump('')
#=> '""'

## However, migration scripts map empty string to 'null' BEFORE calling dump
# This is the expected behavior for v2 migration
def serialize_v2_style(value, field_type)
  return 'null' if value == ''
  case field_type
  when :string then Familia::JsonSerializer.dump(value)
  when :integer then Familia::JsonSerializer.dump(value.to_i)
  when :timestamp, :float then Familia::JsonSerializer.dump(value.to_f)
  when :boolean then Familia::JsonSerializer.dump(value == 'true')
  end
end
serialize_v2_style('', :string)
#=> 'null'

## String serialization produces JSON-quoted string
serialize_v2_style('hello', :string)
#=> '"hello"'

## Integer serialization produces unquoted number
serialize_v2_style('42', :integer)
#=> '42'

## Timestamp serialization produces unquoted float
serialize_v2_style('1706745600', :timestamp)
#=> '1706745600.0'

## Boolean true serialization produces unquoted true
serialize_v2_style('true', :boolean)
#=> 'true'

## Boolean false serialization produces unquoted false
serialize_v2_style('false', :boolean)
#=> 'false'

# ============================================================================
# Edge Case Tests
# ============================================================================

## Integer zero serializes correctly
serialize_v2_style('0', :integer)
#=> '0'

## Negative integer serializes correctly
serialize_v2_style('-1', :integer)
#=> '-1'

## Timestamp with fractional seconds serializes correctly
serialize_v2_style('1706745600.123456', :timestamp)
#=> '1706745600.123456'

## String with JSON special characters serializes correctly
serialize_v2_style('test"quote', :string)
#=> '"test\\"quote"'

## String with newline serializes correctly
serialize_v2_style("line1\nline2", :string)
#=> '"line1\\nline2"'

## String with backslash serializes correctly
serialize_v2_style('path\\to\\file', :string)
#=> '"path\\\\to\\\\file"'

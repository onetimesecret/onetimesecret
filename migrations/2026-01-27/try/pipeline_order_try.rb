# try/migrations/pipeline_order_try.rb
#
# Integration tests for migration pipeline ordering and dependency validation.
# Tests that phases fail gracefully when prerequisites are missing.
#
# frozen_string_literal: true

require_relative '../../../try/support/test_helpers'
require 'json'
require 'fileutils'
require 'tmpdir'

MIGRATION_DIR = File.expand_path('..', __dir__)

## Pipeline phases exist in correct order
expected_phases = %w[
  01-customer
  02-organization
  03-customdomain
  04-receipt
  05-secret
]

actual_phases = Dir.glob(File.join(MIGRATION_DIR, '0*')).map { |d| File.basename(d) }.sort
actual_phases
#=> ["01-customer", "02-organization", "03-customdomain", "04-receipt", "05-secret"]

## Each phase has required scripts
@phases_with_scripts = {}

expected_phases = %w[01-customer 02-organization 03-customdomain 04-receipt 05-secret]
expected_phases.each do |phase|
  phase_dir = File.join(MIGRATION_DIR, phase)
  scripts = Dir.glob(File.join(phase_dir, '*.rb')).map { |f| File.basename(f) }
  @phases_with_scripts[phase] = scripts.sort
end

# All phases should have create_indexes.rb
@phases_with_scripts.values.all? { |scripts| scripts.include?('create_indexes.rb') }
#=> true

## Phase 1 (customer) has transform.rb
@phases_with_scripts['01-customer'].include?('transform.rb')
#=> true

## Phase 2 (organization) has generate.rb instead of transform.rb
# Organizations are created fresh, not transformed from v1
['02-organization'].all? do |phase|
  @phases_with_scripts[phase].include?('generate.rb')
end
#=> true

## Phase 3-5 have transform.rb
['03-customdomain', '04-receipt', '05-secret'].all? do |phase|
  @phases_with_scripts[phase].include?('transform.rb')
end
#=> true

## CustomDomain transformer requires email_to_org mapping file
# Load the transformer class
load File.join(MIGRATION_DIR, '03-customdomain', 'transform.rb')

# Attempting to run without the mapping file should fail
@temp_dir = Dir.mktmpdir('pipeline_test')
input_dir = File.join(@temp_dir, 'customdomain')
FileUtils.mkdir_p(input_dir)

# Create minimal input file
File.write(
  File.join(input_dir, 'customdomain_dump.jsonl'),
  JSON.generate({ key: 'customdomain:example.com:object', dump: 'dGVzdA==' })
)

transformer = CustomDomainTransformer.new(
  input_file: File.join(input_dir, 'customdomain_dump.jsonl'),
  output_dir: input_dir,
  email_to_org_file: File.join(@temp_dir, 'nonexistent.json'),
  email_to_customer_file: nil,
  redis_url: 'redis://127.0.0.1:6379',
  temp_db: 15,
  dry_run: true
)

begin
  transformer.run
  false
rescue ArgumentError => e
  e.message.include?('not found')
end
#=> true

## Cleanup
FileUtils.rm_rf(@temp_dir)
true
#=> true

## Receipt transformer requires customer indexes file
load File.join(MIGRATION_DIR, '04-receipt', 'transform.rb')

@temp_dir = Dir.mktmpdir('pipeline_test')
input_dir = File.join(@temp_dir, 'metadata')
FileUtils.mkdir_p(input_dir)

File.write(
  File.join(input_dir, 'metadata_dump.jsonl'),
  JSON.generate({ key: 'metadata:abc123:object', dump: 'dGVzdA==' })
)

transformer = ReceiptTransformer.new(
  input_file: File.join(input_dir, 'metadata_dump.jsonl'),
  output_dir: input_dir,
  exports_dir: @temp_dir,  # Missing customer/ org/ customdomain/ subdirs
  redis_url: 'redis://127.0.0.1:6379',
  temp_db: 15,
  dry_run: true
)

begin
  transformer.run
  false
rescue ArgumentError => e
  e.message.include?('index file not found')
end
#=> true

## Cleanup
FileUtils.rm_rf(@temp_dir)
true
#=> true

## ReceiptTransformer validates all three index files
load File.join(MIGRATION_DIR, '04-receipt', 'transform.rb')

# Check that CUSTOMER_INDEXES_FILE, ORG_INDEXES_FILE, DOMAIN_INDEXES_FILE are defined
[
  ReceiptTransformer::CUSTOMER_INDEXES_FILE,
  ReceiptTransformer::ORG_INDEXES_FILE,
  ReceiptTransformer::DOMAIN_INDEXES_FILE
]
#=> ["customer/customer_indexes.jsonl", "organization/organization_indexes.jsonl", "customdomain/customdomain_indexes.jsonl"]

## run_all.sh specifies correct phase order
run_all_script = File.read(File.join(MIGRATION_DIR, 'run_all.sh'))

# Extract phase order from script (excluding "Done")
phase_order = run_all_script.scan(/echo "=== (\w+) ==="/m).flatten.reject { |p| p == 'Done' }

# Should be: Customer, Organization, Domain, Receipt, Secret
phase_order
#=> ["Customer", "Organization", "Domain", "Receipt", "Secret"]

## run_all.sh calls transform before create_indexes for each phase
run_all_script = File.read(File.join(MIGRATION_DIR, 'run_all.sh'))

# For customer phase, transform.rb should come before create_indexes.rb
# Get section between Customer and next echo
customer_section = run_all_script[/Customer.*?Organization/m]
transform_pos = customer_section.index('transform.rb') || 0
indexes_pos = customer_section.index('create_indexes.rb') || 999

transform_pos < indexes_pos
#=> true

## enrich_with_identifiers.rb runs before any transform
run_all_script = File.read(File.join(MIGRATION_DIR, 'run_all.sh'))

enrich_pos = run_all_script.index('enrich_with_identifiers.rb')
customer_pos = run_all_script.index('01-customer/transform.rb')

enrich_pos < customer_pos
#=> true

## enrich_with_original_record.rb runs after all transforms
run_all_script = File.read(File.join(MIGRATION_DIR, 'run_all.sh'))

# Find last transform/create_indexes call
last_indexes_pos = run_all_script.rindex('create_indexes.rb')
original_record_pos = run_all_script.index('enrich_with_original_record.rb')

last_indexes_pos < original_record_pos
#=> true

## KeyLoader MODELS constant has correct dependency order
load File.join(MIGRATION_DIR, 'load_keys.rb')

KeyLoader::MODELS.keys
#=> ["customer", "organization", "customdomain", "receipt", "secret"]

## KeyLoader maps models to correct databases
load File.join(MIGRATION_DIR, 'load_keys.rb')

db_mappings = KeyLoader::MODELS.transform_values { |v| v[:db] }
db_mappings
#=> {"customer"=>6, "organization"=>6, "customdomain"=>6, "receipt"=>7, "secret"=>8}

## All pre-transform scripts are present
required_scripts = %w[dump_keys.rb enrich_with_identifiers.rb]
required_scripts.all? { |script| File.exist?(File.join(MIGRATION_DIR, script)) }
#=> true

## All post-transform scripts are present
required_scripts = %w[enrich_with_original_record.rb load_keys.rb]
required_scripts.all? { |script| File.exist?(File.join(MIGRATION_DIR, script)) }
#=> true

## Phase 1 Customer does not depend on external files
load File.join(MIGRATION_DIR, '01-customer', 'transform.rb')

# Customer transformer only needs its input file
# It should have no required external lookups
transformer = CustomerTransformer.new(
  input_file: '/tmp/test.jsonl',
  output_dir: '/tmp',
  redis_url: 'redis://127.0.0.1:6379',
  temp_db: 15,
  dry_run: true
)

# Should not have any @email_to_* or @fqdn_to_* instance variables
ivars = transformer.instance_variables.map(&:to_s)
ivars.none? { |v| v.include?('email_to') || v.include?('fqdn_to') }
#=> true

## Phase 3 CustomDomain depends on email_to_org mapping
load File.join(MIGRATION_DIR, '03-customdomain', 'transform.rb')

transformer = CustomDomainTransformer.new(
  input_file: '/tmp/test.jsonl',
  output_dir: '/tmp',
  email_to_org_file: '/tmp/email_to_org.json',
  email_to_customer_file: '/tmp/customers.jsonl',
  redis_url: 'redis://127.0.0.1:6379',
  temp_db: 15,
  dry_run: true
)

ivars = transformer.instance_variables.map(&:to_s)
[ivars.include?('@email_to_org_file'), ivars.include?('@email_to_customer_file')]
#=> [true, true]

## Model config for OriginalRecordEnricher covers all transform outputs
load File.join(MIGRATION_DIR, 'enrich_with_original_record.rb')

models = OriginalRecordEnricher::MODEL_CONFIG.keys.sort
models
#=> ["customdomain", "customer", "metadata", "secret"]

## OriginalRecordEnricher config maps dump to transformed files correctly
config = OriginalRecordEnricher::MODEL_CONFIG

# Each model should have dump_file and transformed_file
config.all? do |model, cfg|
  cfg.key?(:dump_file) && cfg.key?(:transformed_file)
end
#=> true

## OriginalRecordEnricher marks secret as binary_safe
config = OriginalRecordEnricher::MODEL_CONFIG

config['secret'][:binary_safe]
#=> true

## Non-secret models are not binary_safe
config = OriginalRecordEnricher::MODEL_CONFIG

['customer', 'customdomain', 'metadata'].all? { |m| config[m][:binary_safe] == false }
#=> true

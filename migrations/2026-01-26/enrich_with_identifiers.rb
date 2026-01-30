#!/usr/bin/env ruby
# frozen_string_literal: true

# Enriches dump JSONL files with UUIDv7 objid and derived extid.
# Also performs key renames for V1→V2 migration.
#
# Reads dump files created by dump_keys.rb, generates identifiers for :object records,
# and outputs enriched JSONL files.
#
# Usage:
#   ruby scripts/migrations/jan24/enrich_with_identifiers.rb [OPTIONS]
#
# Options:
#   --input-dir=DIR    Input directory with dump files (default: results)
#   --output-dir=DIR   Output directory (default: results, overwrites in place)
#   --dry-run          Show what would be generated without writing
#
# Input: results/{model}/{model}_dump.jsonl
# Output: results/{model}/{model}_dump.jsonl (enriched with objid, extid)
#
# For :object records with 'created' field:
#   - objid: UUIDv7 generated from created timestamp
#   - extid: Derived from objid using model-specific prefix
#
# Key renames:
#   - customer:{id}:metadata → customer:{id}:receipts
#
# ExtID prefixes by model (ObjectIdentifier only):
#   - customer:     ur
#   - customdomain: cd
#   - organization: on (generated during org creation)
#
# Note: metadata (receipt) and secret use VerifiableIdentifier - no objid/extid

require 'json'
require 'securerandom'
require 'digest'
require 'fileutils'

class IdentifierEnricher
  # Model name -> extid prefix mapping
  # Only models with ObjectIdentifier get objid/extid
  # Metadata (receipt) and secret use VerifiableIdentifier (no objid/extid)
  EXTID_PREFIXES = {
    'customer' => 'ur',
    'customdomain' => 'cd',
    'organization' => 'on',
  }.freeze

  # Models that need identifier enrichment (ObjectIdentifier only)
  # NOTE: Organization is in EXTID_PREFIXES but not here because organizations
  # are created fresh during migration (one per customer), not imported from v1.
  MODELS_TO_ENRICH = %w[customer customdomain].freeze

  # Key rename patterns: old_suffix => new_suffix
  KEY_RENAMES = {
    ':metadata' => ':receipts',
  }.freeze

  def initialize(input_dir:, output_dir:, dry_run: false)
    @input_dir  = input_dir
    @output_dir = output_dir
    @dry_run    = dry_run

    @stats = Hash.new { |h, k| h[k] = { total: 0, enriched: 0, renamed: 0, skipped: 0, errors: [] } }
  end

  def run
    MODELS_TO_ENRICH.each do |model|
      process_model(model)
    end

    print_summary
    @stats
  end

  private

  def process_model(model)
    input_file = File.join(@input_dir, model, "#{model}_dump.jsonl")

    unless File.exist?(input_file)
      puts "Skipping #{model}: #{input_file} not found"
      return
    end

    puts "Processing #{model}..."

    if @dry_run
      dry_run_model(model, input_file)
    else
      enrich_model(model, input_file)
    end
  end

  def dry_run_model(model, input_file)
    stats = @stats[model]

    File.foreach(input_file) do |line|
      stats[:total] += 1
      record         = JSON.parse(line.chomp)

      if should_enrich?(record)
        stats[:enriched] += 1
      else
        stats[:skipped] += 1
      end
    rescue JSON::ParserError => ex
      stats[:errors] << { line: stats[:total], error: ex.message }
    end

    puts "  Would enrich #{stats[:enriched]} of #{stats[:total]} records"
  end

  def enrich_model(model, input_file)
    stats       = @stats[model]
    output_file = File.join(@output_dir, model, "#{model}_dump.jsonl")
    temp_file   = "#{output_file}.tmp"
    prefix      = EXTID_PREFIXES[model]

    FileUtils.mkdir_p(File.dirname(output_file))

    File.open(temp_file, 'w') do |out|
      File.foreach(input_file) do |line|
        stats[:total] += 1
        record         = JSON.parse(line.chomp)

        # Apply key renames
        if rename_key!(record)
          stats[:renamed] += 1
        end

        # Enrich with identifiers
        if should_enrich?(record)
          enrich_record!(record, prefix)
          stats[:enriched] += 1
        else
          stats[:skipped] += 1
        end

        out.puts(JSON.generate(record))
      rescue JSON::ParserError => ex
        stats[:errors] << { line: stats[:total], error: ex.message }
      end
    end

    # Atomic replace
    FileUtils.mv(temp_file, output_file)
    puts "  Enriched #{stats[:enriched]} of #{stats[:total]} records -> #{output_file}"
  end

  def rename_key!(record)
    key = record['key']
    return false unless key

    KEY_RENAMES.each do |old_suffix, new_suffix|
      if key.end_with?(old_suffix)
        record['key'] = key.sub(/#{Regexp.escape(old_suffix)}$/, new_suffix)
        return true
      end
    end

    false
  end

  def should_enrich?(record)
    # Only enrich :object records that have a created timestamp
    record['key']&.end_with?(':object') && record['created']&.positive?
  end

  def enrich_record!(record, prefix)
    created_timestamp = record['created']

    # Generate UUIDv7 from created timestamp
    objid = generate_uuid_v7_from(created_timestamp)

    # Derive extid from objid
    extid = derive_extid_from_uuid(objid, prefix: prefix)

    record['objid'] = objid
    record['extid'] = extid
  end

  # Generate UUID v7 from Unix timestamp (seconds)
  # Standalone implementation to avoid external dependencies
  #
  # Note: Records sharing the same second will have random (not deterministic)
  # sort order within that second. Sub-second precision not preserved.
  def generate_uuid_v7_from(timestamp_seconds)
    # Convert to milliseconds (UUID v7 uses 48-bit ms timestamp)
    timestamp_ms = (timestamp_seconds.to_f * 1000).to_i

    # Encode timestamp as 48-bit hex (12 hex chars)
    hex = timestamp_ms.to_s(16).rjust(12, '0')

    # Generate random parts
    random_bytes = SecureRandom.random_bytes(10)

    # Build UUID v7 format:
    # xxxxxxxx-xxxx-7xxx-yxxx-xxxxxxxxxxxx
    # where x = timestamp/random, 7 = version, y = variant (8-b)

    rand_hex = random_bytes.unpack1('H*')

    # Construct UUID parts per RFC 9562
    time_hi      = hex[0, 8]                                   # bits 0-31 of timestamp
    time_mid     = hex[8, 4]                                   # bits 32-47 of timestamp
    ver_rand     = '7' + rand_hex[0, 3]                        # version 7 + 12 random bits
    # variant: mask to 10xxxxxx per RFC 9562
    variant_byte = (rand_hex[3, 2].to_i(16) & 0x3F) | 0x80
    variant      = variant_byte.to_s(16).rjust(2, '0') + rand_hex[5, 2]

    node       = rand_hex[7, 12] # Uses indices 7-18

    "#{time_hi}-#{time_mid}-#{ver_rand}-#{variant}-#{node}"
  end

  # Derive external ID from UUID using deterministic hashing
  # Matches Familia v2.0.0-pre12 approach
  def derive_extid_from_uuid(uuid_string, prefix:)
    # Normalize UUID to hex (remove hyphens)
    normalized_hex = uuid_string.delete('-')

    # Create seed from the hex string
    seed = Digest::SHA256.digest(normalized_hex)

    # Initialize PRNG with the seed
    prng = Random.new(seed.unpack1('Q>'))

    # Generate 16 bytes of deterministic output
    random_bytes = prng.bytes(16)

    # Encode as base36 string (25 chars)
    external_part = random_bytes.unpack1('H*').to_i(16).to_s(36).rjust(25, '0')

    "#{prefix}#{external_part}"
  end

  def print_summary
    puts "\n=== Identifier Enrichment Summary ==="
    @stats.each do |model, stats|
      puts "#{model}:"
      puts "  Total records: #{stats[:total]}"
      puts "  Enriched:      #{stats[:enriched]}"
      puts "  Renamed:       #{stats[:renamed]}"
      puts "  Skipped:       #{stats[:skipped]}"
      next unless stats[:errors].any?

      puts "  Errors:        #{stats[:errors].size}"
      stats[:errors].first(5).each do |err|
        puts "    Line #{err[:line]}: #{err[:error]}"
      end
    end
  end
end

def parse_args(args)
  options = {
    input_dir: 'results',
    output_dir: 'results',
    dry_run: false,
  }

  args.each do |arg|
    case arg
    when /^--input-dir=(.+)$/
      options[:input_dir] = Regexp.last_match(1)
    when /^--output-dir=(.+)$/
      options[:output_dir] = Regexp.last_match(1)
    when '--dry-run'
      options[:dry_run] = true
    when '--help', '-h'
      puts <<~HELP
        Usage: ruby scripts/migrations/jan24/enrich_with_identifiers.rb [OPTIONS]

        Enriches dump JSONL files with UUIDv7 objid and derived extid.

        Options:
          --input-dir=DIR    Input directory (default: results)
          --output-dir=DIR   Output directory (default: results)
          --dry-run          Preview without writing
          --help             Show this help

        Input files (from dump_keys.rb):
          results/customer/customer_dump.jsonl
          results/customdomain/customdomain_dump.jsonl

        For each :object record with 'created' field, adds:
          - objid: UUIDv7 generated from created timestamp
          - extid: Derived from objid with model prefix

        ExtID prefixes (ObjectIdentifier models only):
          customer:     ur (e.g., ur0abc123...)
          customdomain: cd (e.g., cd0xyz789...)

        Note: metadata/receipts and secret use VerifiableIdentifier (no objid/extid)
      HELP
      exit 0
    else
      warn "Unknown option: #{arg}"
      exit 1
    end
  end

  options
end

if __FILE__ == $PROGRAM_NAME
  options = parse_args(ARGV)

  enricher = IdentifierEnricher.new(
    input_dir: options[:input_dir],
    output_dir: options[:output_dir],
    dry_run: options[:dry_run],
  )

  enricher.run
end

# scripts/diagnostics/check_raw_email_fields.rb
#
# Diagnostic script to scan all Customer records in Redis and identify
# fields stored as raw (non-JSON-serialized) strings.
#
# Usage from bin/console:
#   load 'scripts/diagnostics/check_raw_email_fields.rb'
#
# Or standalone:
#   bundle exec ruby scripts/diagnostics/check_raw_email_fields.rb
#
# frozen_string_literal: true

module Diagnostics
  module CheckRawEmailFields
    extend self

    # Checks whether a Redis hash field value looks properly JSON-serialized.
    #
    # In Familia v2, all values stored in Redis hashes should be valid JSON:
    #   - Strings: wrapped in double quotes, e.g. "\"hello\""
    #   - Integers: bare digits, e.g. "123"
    #   - Booleans: "true" or "false"
    #   - Null: "null"
    #   - Objects/Arrays: start with { or [
    #
    # A raw string like "delano@example.com" (no wrapping quotes) is NOT
    # valid JSON and indicates a serialization bypass.
    #
    def properly_serialized?(value)
      return true if value.nil? || value.empty?

      # Valid JSON literals
      return true if value == 'null'
      return true if %w[true false].include?(value)

      # JSON string: must start and end with double quote
      return true if value.start_with?('"') && value.end_with?('"')

      # JSON number (integer or float, possibly negative)
      return true if value.match?(/\A-?\d+(\.\d+)?\z/)

      # JSON object or array
      return true if value.start_with?('{', '[')

      false
    end

    def run(sample_limit: 10, verbose: false)
      redis   = OT::Customer.dbclient
      results = {
        total_customers: 0,
        raw_email_count: 0,
        other_raw_field_count: 0,
        raw_email_samples: [],
        other_raw_samples: [],
      }

      redis.scan_each(match: 'customer:*:object', count: 200) do |key|
        next unless redis.type(key) == 'hash'

        results[:total_customers] += 1
        $stderr.print "\rScanned #{results[:total_customers]} customers..." if (results[:total_customers] % 1000).zero?

        scan_record(redis.hgetall(key), key, sample_limit, verbose, results)
      end

      $stderr.print "\r" if results[:total_customers] >= 1000

      total_customers       = results[:total_customers]
      raw_email_count       = results[:raw_email_count]
      other_raw_field_count = results[:other_raw_field_count]
      raw_email_samples     = results[:raw_email_samples]
      other_raw_samples     = results[:other_raw_samples]

      # Report
      puts '=' * 60
      puts 'Customer Field Serialization Diagnostic'
      puts '=' * 60
      puts
      puts "Total customer records scanned: #{total_customers}"
      puts "Records with raw (non-JSON) email: #{raw_email_count}"
      puts "Other fields with raw values: #{other_raw_field_count}"
      puts

      if raw_email_samples.any?
        puts '-' * 60
        puts "Sample records with raw email (#{[raw_email_count, sample_limit].min} of #{raw_email_count}):"
        puts '-' * 60
        raw_email_samples.each_with_index do |sample, i|
          puts "  #{i + 1}. key: #{sample[:key]}"
          puts "     custid:   #{sample[:custid]}"
          puts "     stored:   #{sample[:email_stored]}"
          puts "     expected: #{sample[:email_expected]}"
          puts
        end
      else
        puts '(No raw email fields found)'
      end

      if verbose && other_raw_samples.any?
        puts '-' * 60
        puts 'Sample records with other raw fields:'
        puts '-' * 60
        other_raw_samples.each_with_index do |sample, i|
          puts "  #{i + 1}. key: #{sample[:key]}"
          puts "     field: #{sample[:field]}"
          puts "     value: #{sample[:value_stored]}"
          puts
        end
      end

      results
    end

    private

    def scan_record(fields, key, sample_limit, verbose, results)
      custid      = fields['custid'] || fields['objid'] || '(unknown)'
      email_value = fields['email']

      if email_value && !email_value.empty? && !properly_serialized?(email_value)
        results[:raw_email_count] += 1
        if results[:raw_email_samples].size < sample_limit
          results[:raw_email_samples] << {
            key: key,
            custid: custid,
            email_stored: email_value,
            email_expected: "\"#{email_value}\"",
          }
        end
      end

      fields.each do |field_name, value|
        next if field_name == 'email'
        next if value.nil? || value.empty?
        next if properly_serialized?(value)

        results[:other_raw_field_count] += 1
        next unless verbose && results[:other_raw_samples].size < sample_limit

        results[:other_raw_samples] << { key: key, field: field_name, value_stored: value[0..60] }
      end
    end
  end
end

# Auto-run when loaded
if __FILE__ == $PROGRAM_NAME || defined?(OT)
  Diagnostics::CheckRawEmailFields.run(verbose: true)
end

#!/usr/bin/env ruby
# frozen_string_literal: true

# tests/fixtures/validate_test_data.rb
#
# Validates the comprehensive test data structure and can be used
# to check if specific test cases would find bugs in the system.
#
# Usage:
#   ruby tests/fixtures/validate_test_data.rb
#   ruby tests/fixtures/validate_test_data.rb --category secret_creation_edge_cases
#   ruby tests/fixtures/validate_test_data.rb --id SEC-001

require 'json'
require 'optparse'

class TestDataValidator
  REQUIRED_FIELDS = %w[id name data assumption_violated what_breaks verification].freeze
  EXPECTED_CATEGORIES = %w[
    secret_creation_edge_cases
    customer_validation_bugs
    metadata_state_conflicts
    timing_attacks
    injection_attempts
    encryption_edge_cases
    ttl_boundary_violations
    multi_tenancy_issues
  ].freeze

  attr_reader :test_data, :errors, :warnings

  def initialize(filepath = 'tests/fixtures/comprehensive_test_data.json')
    @filepath = filepath
    @errors = []
    @warnings = []
    @test_data = nil
  end

  def load_and_validate
    load_json
    validate_structure
    validate_test_cases
    report_results
  end

  def validate_category(category_name)
    load_json
    return unless @test_data

    unless @test_data['test_cases'].key?(category_name)
      puts "❌ Category '#{category_name}' not found"
      puts "Available categories: #{@test_data['test_cases'].keys.join(', ')}"
      return
    end

    puts "\n📋 Validating category: #{category_name}\n"
    puts "=" * 60

    test_cases = @test_data['test_cases'][category_name]
    test_cases.each do |test_case|
      validate_single_test_case(test_case, category_name)
    end

    puts "\n✅ Category validation complete: #{test_cases.length} test cases"
  end

  def validate_test_id(test_id)
    load_json
    return unless @test_data

    found = false
    @test_data['test_cases'].each do |category, test_cases|
      test_case = test_cases.find { |tc| tc['id'] == test_id }
      next unless test_case

      found = true
      puts "\n🔍 Test Case: #{test_id}\n"
      puts "=" * 60
      puts "Category: #{category}"
      puts "Name: #{test_case['name']}"
      puts "\nData:"
      puts JSON.pretty_generate(test_case['data'])
      puts "\nAssumption Violated:"
      puts "  #{test_case['assumption_violated']}"
      puts "\nWhat Breaks:"
      puts "  #{test_case['what_breaks']}"
      puts "\nVerification:"
      puts "  #{test_case['verification']}"
      puts "=" * 60

      validate_single_test_case(test_case, category)
      break
    end

    puts "❌ Test case '#{test_id}' not found" unless found
  end

  private

  def load_json
    @test_data = JSON.parse(File.read(@filepath))
  rescue Errno::ENOENT
    @errors << "File not found: #{@filepath}"
  rescue JSON::ParserError => e
    @errors << "Invalid JSON: #{e.message}"
  end

  def validate_structure
    return unless @test_data

    # Validate top-level structure
    unless @test_data['meta']
      @errors << "Missing 'meta' section"
    end

    unless @test_data['test_cases']
      @errors << "Missing 'test_cases' section"
      return
    end

    # Validate all expected categories exist
    EXPECTED_CATEGORIES.each do |category|
      unless @test_data['test_cases'][category]
        @warnings << "Missing expected category: #{category}"
      end
    end
  end

  def validate_test_cases
    return unless @test_data && @test_data['test_cases']

    @test_data['test_cases'].each do |category, test_cases|
      unless test_cases.is_a?(Array)
        @errors << "Category '#{category}' is not an array"
        next
      end

      test_cases.each do |test_case|
        validate_single_test_case(test_case, category)
      end
    end
  end

  def validate_single_test_case(test_case, category)
    # Check required fields
    REQUIRED_FIELDS.each do |field|
      unless test_case[field]
        @errors << "[#{category}] Test case missing field '#{field}': #{test_case['id'] || 'unknown'}"
      end
    end

    # Validate ID format
    if test_case['id']
      unless test_case['id'].match?(/^[A-Z]+-\d{3}$/)
        @warnings << "[#{category}] Test ID format should be XXX-### (e.g., SEC-001): #{test_case['id']}"
      end
    end

    # Check for empty or too short descriptions
    if test_case['assumption_violated'] && test_case['assumption_violated'].length < 20
      @warnings << "[#{category}] Assumption description too short: #{test_case['id']}"
    end

    if test_case['what_breaks'] && test_case['what_breaks'].length < 50
      @warnings << "[#{category}] 'what_breaks' description too short: #{test_case['id']}"
    end

    # Check that data section is not empty
    if test_case['data'] && test_case['data'].empty?
      @errors << "[#{category}] Empty data section: #{test_case['id']}"
    end
  end

  def report_results
    puts "\n" + "=" * 60
    puts "Test Data Validation Report"
    puts "=" * 60

    if @errors.empty? && @warnings.empty?
      puts "\n✅ All validations passed!"
      print_statistics
    else
      if @errors.any?
        puts "\n❌ ERRORS (#{@errors.length}):"
        @errors.each { |error| puts "  - #{error}" }
      end

      if @warnings.any?
        puts "\n⚠️  WARNINGS (#{@warnings.length}):"
        @warnings.each { |warning| puts "  - #{warning}" }
      end

      print_statistics
    end

    exit(@errors.any? ? 1 : 0)
  end

  def print_statistics
    return unless @test_data && @test_data['test_cases']

    total_tests = 0
    category_counts = {}

    @test_data['test_cases'].each do |category, test_cases|
      count = test_cases.length
      category_counts[category] = count
      total_tests += count
    end

    puts "\n📊 Statistics:"
    puts "  Total test cases: #{total_tests}"
    puts "  Categories: #{category_counts.length}"
    puts "\n  Breakdown:"
    category_counts.sort_by { |_, count| -count }.each do |category, count|
      puts "    - #{category}: #{count} tests"
    end
  end
end

# CLI handling
options = {}
OptionParser.new do |opts|
  opts.banner = "Usage: validate_test_data.rb [options]"

  opts.on("-c", "--category CATEGORY", "Validate specific category") do |cat|
    options[:category] = cat
  end

  opts.on("-i", "--id TEST_ID", "Validate specific test ID") do |id|
    options[:id] = id
  end

  opts.on("-h", "--help", "Show this help message") do
    puts opts
    exit
  end
end.parse!

validator = TestDataValidator.new

if options[:category]
  validator.validate_category(options[:category])
elsif options[:id]
  validator.validate_test_id(options[:id])
else
  validator.load_and_validate
end

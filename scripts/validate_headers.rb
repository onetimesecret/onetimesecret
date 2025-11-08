#!/usr/bin/env ruby
# scripts/validate_headers.rb
#
# frozen_string_literal: true

# Validates that all Ruby, TypeScript, and Vue files have correct header format
#
# Usage:
#   ruby scripts/validate_headers.rb
#   ruby scripts/validate_headers.rb --fix
#
# Expected header formats:
#
# Ruby files:
#   # path/to/file.rb
#   #
#   # frozen_string_literal: true
#
# TypeScript files:
#   // path/to/file.ts
#
# Vue files:
#   <!-- path/to/file.vue -->
#

require 'pathname'

class HeaderValidator
  REPO_ROOT = Pathname.new(__dir__).parent.freeze

  def initialize(fix: false)
    @fix = fix
    @errors = []
  end

  def validate_all
    puts "Validating file headers..."
    puts "Fix mode: #{@fix ? 'ON' : 'OFF'}"
    puts

    validate_ruby_files
    validate_typescript_files
    validate_vue_files

    report_results
  end

  private

  def validate_ruby_files
    puts "Checking Ruby files..."

    Dir.glob("**/*.rb", base: REPO_ROOT).each do |file_path|
      next if skip_file?(file_path)

      full_path = REPO_ROOT / file_path
      validate_ruby_header(full_path, file_path)
    end
  end

  def validate_typescript_files
    puts "Checking TypeScript files..."

    Dir.glob("src/**/*.ts", base: REPO_ROOT).each do |file_path|
      next if skip_file?(file_path)

      full_path = REPO_ROOT / file_path
      validate_typescript_header(full_path, file_path)
    end
  end

  def validate_vue_files
    puts "Checking Vue files..."

    Dir.glob("src/**/*.vue", base: REPO_ROOT).each do |file_path|
      next if skip_file?(file_path)

      full_path = REPO_ROOT / file_path
      validate_vue_header(full_path, file_path)
    end
  end

  def validate_ruby_header(full_path, relative_path)
    lines = File.readlines(full_path)
    return if lines.empty?

    # Skip files with shebangs
    return if lines[0].start_with?('#!')

    # Expected header:
    # Line 1: # path/to/file.rb
    # Line 2: #
    # Line 3: # frozen_string_literal: true
    # Line 4: (blank)

    errors = []

    # Check line 1: filename comment
    unless lines[0]&.strip == "# #{relative_path}"
      errors << "Line 1: Expected '# #{relative_path}', got: #{lines[0]&.strip.inspect}"
    end

    # Check line 2: empty comment
    unless lines[1]&.strip == '#'
      errors << "Line 2: Expected '#', got: #{lines[1]&.strip.inspect}"
    end

    # Check line 3: frozen pragma
    unless lines[2]&.strip == '# frozen_string_literal: true'
      errors << "Line 3: Expected '# frozen_string_literal: true', got: #{lines[2]&.strip.inspect}"
    end

    # Check line 4: blank line
    unless lines[3]&.strip == ''
      errors << "Line 4: Expected blank line, got: #{lines[3]&.strip.inspect}"
    end

    if errors.any?
      @errors << { file: relative_path, issues: errors }
    end
  end

  def validate_typescript_header(full_path, relative_path)
    lines = File.readlines(full_path)
    return if lines.empty?

    # Expected header:
    # Line 1: // path/to/file.ts
    # Line 2: (blank)

    errors = []

    # Check line 1: filename comment
    unless lines[0]&.strip == "// #{relative_path}"
      errors << "Line 1: Expected '// #{relative_path}', got: #{lines[0]&.strip.inspect}"
    end

    # Check line 2: blank line
    unless lines[1]&.strip == ''
      errors << "Line 2: Expected blank line, got: #{lines[1]&.strip.inspect}"
    end

    if errors.any?
      @errors << { file: relative_path, issues: errors }
    end
  end

  def validate_vue_header(full_path, relative_path)
    lines = File.readlines(full_path)
    return if lines.empty?

    # Expected header:
    # Line 1: <!-- path/to/file.vue -->
    # Line 2: (blank)

    errors = []

    # Check line 1: filename comment
    unless lines[0]&.strip == "<!-- #{relative_path} -->"
      errors << "Line 1: Expected '<!-- #{relative_path} -->', got: #{lines[0]&.strip.inspect}"
    end

    # Check line 2: blank line
    unless lines[1]&.strip == ''
      errors << "Line 2: Expected blank line, got: #{lines[1]&.strip.inspect}"
    end

    if errors.any?
      @errors << { file: relative_path, issues: errors }
    end
  end

  def skip_file?(path)
    path.include?('node_modules/') ||
      path.include?('.git/') ||
      path.include?('vendor/') ||
      path.include?('tmp/')
  end

  def report_results
    puts
    puts "=" * 80

    if @errors.empty?
      puts "✓ All file headers are valid!"
      exit 0
    else
      puts "✗ Found #{@errors.size} files with invalid headers:"
      puts

      @errors.each do |error|
        puts "File: #{error[:file]}"
        error[:issues].each do |issue|
          puts "  - #{issue}"
        end
        puts
      end

      puts "=" * 80
      puts
      puts "To fix these issues, run: ruby #{__FILE__} --fix"
      exit 1
    end
  end
end

# Main execution
fix_mode = ARGV.include?('--fix')
validator = HeaderValidator.new(fix: fix_mode)
validator.validate_all

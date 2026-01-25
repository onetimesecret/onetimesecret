#!/usr/bin/env ruby
# scripts/validate_headers.rb
#
# frozen_string_literal: true

# Validates that all Ruby, TypeScript, and Vue files have correct header format
#
# Usage:
#   ruby scripts/validate_headers.rb
#   ruby scripts/validate_headers.rb --fix
#   ruby scripts/validate_headers.rb lib/onetime/
#   ruby scripts/validate_headers.rb --fix src/**/*.ts
#   ruby scripts/validate_headers.rb apps/ lib/onetime/*.rb
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

  def initialize(fix: false, paths: [])
    @fix         = fix
    @paths       = paths
    @errors      = []
    @fixed       = []
    @files_found = 0
  end

  def validate_all
    puts 'Validating file headers...'
    puts "Fix mode: #{@fix ? 'ON' : 'OFF'}"
    puts "Paths: #{@paths.empty? ? '(all)' : @paths.join(', ')}"
    puts

    validate_ruby_files
    validate_typescript_files
    validate_vue_files

    report_results
  end

  private

  def files_for_glob(pattern)
    if @paths.empty?
      Dir.glob(pattern, base: REPO_ROOT)
    else
      @paths.flat_map do |path|
        full_path = REPO_ROOT / path
        if full_path.directory?
          # Path is a directory - search within it
          Dir.glob(File.join(path, '**/*.{rb,ts,vue}'), base: REPO_ROOT)
             .select { |f| File.fnmatch?(pattern, f, File::FNM_PATHNAME) }
        else
          # Path is a glob or file pattern
          Dir.glob(path, base: REPO_ROOT)
             .select { |f| File.fnmatch?(pattern, f, File::FNM_PATHNAME) }
        end
      end.uniq
    end
  end

  def validate_ruby_files
    puts 'Checking Ruby files...'

    files_for_glob('**/*.rb').each do |file_path|
      next if skip_file?(file_path)

      full_path = REPO_ROOT / file_path
      next unless full_path.file?

      @files_found += 1
      validate_ruby_header(full_path, file_path)
    end
  end

  def validate_typescript_files
    puts 'Checking TypeScript files...'

    files_for_glob('src/**/*.ts').each do |file_path|
      next if skip_file?(file_path)

      full_path = REPO_ROOT / file_path
      next unless full_path.file?

      @files_found += 1
      validate_typescript_header(full_path, file_path)
    end
  end

  def validate_vue_files
    puts 'Checking Vue files...'

    files_for_glob('src/**/*.vue').each do |file_path|
      next if skip_file?(file_path)

      full_path = REPO_ROOT / file_path
      next unless full_path.file?

      @files_found += 1
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
      if @fix
        fix_ruby_header(full_path, relative_path, lines)
      else
        @errors << { file: relative_path, issues: errors }
      end
    end
  end

  def fix_ruby_header(full_path, relative_path, lines)
    # Find where original content starts (skip existing header attempts)
    content_start = find_ruby_content_start(lines)
    content = lines[content_start..].join

    new_header = "# #{relative_path}\n#\n# frozen_string_literal: true\n\n"
    File.write(full_path, new_header + content)
    @fixed << relative_path
  end

  def find_ruby_content_start(lines)
    # Skip lines that look like header comments or frozen_string_literal
    idx = 0
    while idx < lines.length
      line = lines[idx].strip
      break unless line.empty? ||
                   line == '#' ||
                   line.start_with?('# frozen_string_literal') ||
                   (line.start_with?('#') && !line.start_with?('##') && idx < 4)

      idx += 1
    end
    idx
  end

  def validate_typescript_header(full_path, relative_path)
    lines = File.readlines(full_path)
    return if lines.empty?

    # Skip files with shebangs (executable scripts)
    return if lines[0].start_with?('#!')

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
      if @fix
        fix_typescript_header(full_path, relative_path, lines)
      else
        @errors << { file: relative_path, issues: errors }
      end
    end
  end

  def fix_typescript_header(full_path, relative_path, lines)
    content_start = find_typescript_content_start(lines)
    content = lines[content_start..].join

    new_header = "// #{relative_path}\n\n"
    File.write(full_path, new_header + content)
    @fixed << relative_path
  end

  def find_typescript_content_start(lines)
    idx = 0
    while idx < lines.length
      line = lines[idx].strip
      # Skip empty lines and single-line path comments at the start
      break unless line.empty? || (line.start_with?('//') && idx == 0)

      idx += 1
    end
    idx
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
      if @fix
        fix_vue_header(full_path, relative_path, lines)
      else
        @errors << { file: relative_path, issues: errors }
      end
    end
  end

  def fix_vue_header(full_path, relative_path, lines)
    content_start = find_vue_content_start(lines)
    content = lines[content_start..].join

    new_header = "<!-- #{relative_path} -->\n\n"
    File.write(full_path, new_header + content)
    @fixed << relative_path
  end

  def find_vue_content_start(lines)
    idx = 0
    while idx < lines.length
      line = lines[idx].strip
      # Skip empty lines and HTML comment headers at the start
      break unless line.empty? || (line.start_with?('<!--') && line.end_with?('-->') && idx == 0)

      idx += 1
    end
    idx
  end

  def skip_file?(path)
    path.include?('node_modules/') ||
      path.include?('.git/') ||
      path.include?('vendor/') ||
      path.include?('tmp/')
  end

  def report_results
    puts
    puts '=' * 80

    if @fix && @fixed.any?
      puts "✓ Fixed #{@fixed.size} files:"
      @fixed.each { |f| puts "  - #{f}" }
      puts
      print_tally
      exit 0
    elsif @errors.empty?
      puts '✓ All file headers are valid!'
      puts
      print_tally
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

      puts '=' * 80
      puts
      print_tally
      puts
      puts "To fix these issues, run: ruby #{__FILE__} --fix"
      exit 1
    end
  end

  def print_tally
    compliant = @files_found - @errors.size - @fixed.size
    puts 'Summary:'
    puts "  Files scanned:     #{@files_found}"
    puts "  Compliant:         #{compliant}"
    puts "  Non-compliant:     #{@errors.size}" unless @fix
    puts "  Fixed:             #{@fixed.size}" if @fix
  end
end

# Main execution
fix_mode = ARGV.delete('--fix')
paths    = ARGV.dup
validator = HeaderValidator.new(fix: !!fix_mode, paths: paths)
validator.validate_all

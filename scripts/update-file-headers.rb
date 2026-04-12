#!/usr/bin/env ruby
# scripts/update-file-headers.rb
#
# frozen_string_literal: true

# Validates that all Ruby, Python, TypeScript, and Vue files have correct header format
#
# Usage:
#   ruby scripts/update-file-headers.rb
#   ruby scripts/update-file-headers.rb --fix
#   ruby scripts/update-file-headers.rb lib/onetime/
#   ruby scripts/update-file-headers.rb --fix src/**/*.ts
#   ruby scripts/update-file-headers.rb apps/ lib/onetime/*.rb
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
# Python files:
#   # path/to/file.py
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
    validate_python_files
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
          Dir.glob(File.join(path, '**/*.{rb,py,ts,vue}'), base: REPO_ROOT)
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

  def validate_python_files
    puts 'Checking Python files...'

    files_for_glob('**/*.py').each do |file_path|
      next if skip_file?(file_path)

      full_path = REPO_ROOT / file_path
      next unless full_path.file?

      @files_found += 1
      validate_python_header(full_path, file_path)
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

    # Shebang files have the header after the shebang line
    offset = lines[0].start_with?('#!') ? 1 : 0

    # Expected header (at offset):
    # # path/to/file.rb
    # #
    # # frozen_string_literal: true
    # (blank)

    errors = []

    unless lines[offset]&.strip == "# #{relative_path}"
      errors << "Line #{offset + 1}: Expected '# #{relative_path}', got: #{lines[offset]&.strip.inspect}"
    end

    unless lines[offset + 1]&.strip == '#'
      errors << "Line #{offset + 2}: Expected '#', got: #{lines[offset + 1]&.strip.inspect}"
    end

    unless lines[offset + 2]&.strip == '# frozen_string_literal: true'
      errors << "Line #{offset + 3}: Expected '# frozen_string_literal: true', got: #{lines[offset + 2]&.strip.inspect}"
    end

    unless lines[offset + 3]&.strip == ''
      errors << "Line #{offset + 4}: Expected blank line, got: #{lines[offset + 3]&.strip.inspect}"
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
    has_shebang = lines[0]&.start_with?('#!')
    content_start = find_ruby_content_start(lines, relative_path, has_shebang ? 1 : 0)
    content = lines[content_start..].join

    prefix = has_shebang ? lines[0] : ''
    new_header = "# #{relative_path}\n#\n# frozen_string_literal: true\n\n"
    File.write(full_path, prefix + new_header + content)
    @fixed << relative_path
  end

  # Only consume lines that are part of the existing file-path header:
  #   - the exact path-header line (`# <relative_path>`)
  #   - an immediately following `#` separator line
  #   - an immediately following `# frozen_string_literal: true`
  #   - a single trailing blank line
  # Any other leading comment (license, rubocop directive, author credit)
  # is preserved as content.
  def find_ruby_content_start(lines, relative_path, start = 0)
    idx = start
    header_line = "# #{relative_path}"

    if lines[idx]&.strip == header_line
      idx += 1
      idx += 1 if lines[idx]&.strip == '#'
      idx += 1 if lines[idx]&.strip == '# frozen_string_literal: true'
    end
    idx += 1 if lines[idx]&.strip == ''
    idx
  end

  def validate_python_header(full_path, relative_path)
    lines = File.readlines(full_path)
    return if lines.empty?

    offset = lines[0].start_with?('#!') ? 1 : 0

    # Expected header (at offset):
    # # path/to/file.py
    # (blank)

    errors = []

    unless lines[offset]&.strip == "# #{relative_path}"
      errors << "Line #{offset + 1}: Expected '# #{relative_path}', got: #{lines[offset]&.strip.inspect}"
    end

    unless lines[offset + 1]&.strip == ''
      errors << "Line #{offset + 2}: Expected blank line, got: #{lines[offset + 1]&.strip.inspect}"
    end

    if errors.any?
      if @fix
        fix_python_header(full_path, relative_path, lines)
      else
        @errors << { file: relative_path, issues: errors }
      end
    end
  end

  def fix_python_header(full_path, relative_path, lines)
    has_shebang = lines[0]&.start_with?('#!')
    content_start = find_python_content_start(lines, relative_path, has_shebang ? 1 : 0)
    content = lines[content_start..].join

    prefix = has_shebang ? lines[0] : ''
    new_header = "# #{relative_path}\n\n"
    File.write(full_path, prefix + new_header + content)
    @fixed << relative_path
  end

  # Only consume the exact file-path header line plus one trailing blank.
  # Preserves encoding cookies, license stubs, module docstrings.
  def find_python_content_start(lines, relative_path, start = 0)
    idx = start
    idx += 1 if lines[idx]&.strip == "# #{relative_path}"
    idx += 1 if lines[idx]&.strip == ''
    idx
  end

  def validate_typescript_header(full_path, relative_path)
    lines = File.readlines(full_path)
    return if lines.empty?

    offset = lines[0].start_with?('#!') ? 1 : 0

    # Expected header (at offset):
    # // path/to/file.ts
    # (blank)

    errors = []

    unless lines[offset]&.strip == "// #{relative_path}"
      errors << "Line #{offset + 1}: Expected '// #{relative_path}', got: #{lines[offset]&.strip.inspect}"
    end

    unless lines[offset + 1]&.strip == ''
      errors << "Line #{offset + 2}: Expected blank line, got: #{lines[offset + 1]&.strip.inspect}"
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
    has_shebang = lines[0]&.start_with?('#!')
    content_start = find_typescript_content_start(lines, has_shebang ? 1 : 0)
    content = lines[content_start..].join

    prefix = has_shebang ? lines[0] : ''
    new_header = "// #{relative_path}\n\n"
    File.write(full_path, prefix + new_header + content)
    @fixed << relative_path
  end

  def find_typescript_content_start(lines, start = 0)
    idx = start
    while idx < lines.length
      line = lines[idx].strip
      break unless line.empty? || (line.start_with?('//') && idx == start)

      idx += 1
    end
    idx
  end

  def validate_vue_header(full_path, relative_path)
    lines = File.readlines(full_path)
    return if lines.empty?

    offset = lines[0].start_with?('#!') ? 1 : 0

    # Expected header (at offset):
    # <!-- path/to/file.vue -->
    # (blank)

    errors = []

    unless lines[offset]&.strip == "<!-- #{relative_path} -->"
      errors << "Line #{offset + 1}: Expected '<!-- #{relative_path} -->', got: #{lines[offset]&.strip.inspect}"
    end

    unless lines[offset + 1]&.strip == ''
      errors << "Line #{offset + 2}: Expected blank line, got: #{lines[offset + 1]&.strip.inspect}"
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
    has_shebang = lines[0]&.start_with?('#!')
    content_start = find_vue_content_start(lines, has_shebang ? 1 : 0)
    content = lines[content_start..].join

    prefix = has_shebang ? lines[0] : ''
    new_header = "<!-- #{relative_path} -->\n\n"
    File.write(full_path, prefix + new_header + content)
    @fixed << relative_path
  end

  def find_vue_content_start(lines, start = 0)
    idx = start
    while idx < lines.length
      line = lines[idx].strip
      break unless line.empty? || (line.start_with?('<!--') && line.end_with?('-->') && idx == start)

      idx += 1
    end
    idx
  end

  def skip_file?(path)
    path.include?('node_modules/') ||
      path.include?('.git/') ||
      path.include?('vendor/') ||
      path.include?('tmp/') ||
      path.include?('__pycache__/') ||
      path.include?('.venv/')
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
